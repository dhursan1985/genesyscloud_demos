"""Pruebas Linux/PowerShell 7 con simulador; no acreditan Windows ni acceso Genesys."""
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = os.environ.get('DEMO_PWSH') or shutil.which('pwsh')

@unittest.skipUnless(PWSH and os.name != 'nt', 'Requiere pwsh y mock POSIX; ejecutar los scripts reales en Windows.')
class CliScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state_file = Path(self.tmp.name)/'state.json'
        self.env = dict(os.environ, MOCK_GC_STATE=str(self.state_file), MOCK_GC_MODE='')
        self.env.update(XDG_CACHE_HOME=str(Path(self.tmp.name)/'cache'), XDG_CONFIG_HOME=str(Path(self.tmp.name)/'config'), XDG_DATA_HOME=str(Path(self.tmp.name)/'data'))
        self.write_state({'table':None,'rows':[],'mutations':0})

    def write_state(self, state):
        self.state_file.write_text(json.dumps(state))

    def state(self):
        return json.loads(self.state_file.read_text())

    def run_script(self, name, *extra, mode=''):
        env = dict(self.env, MOCK_GC_MODE=mode)
        return subprocess.run([PWSH, '-NoProfile','-File',str(ROOT/'scripts'/name),'-GcPath',str(ROOT/'tests/mock_gc.py'),'-Profile','TEST_PROFILE',*extra], env=env, text=True, capture_output=True, timeout=40)

    def seed(self, *extra, **kw):
        return self.run_script('seed-datatable.ps1','-ExpectedOrganizationId','MOCK_ORG_ID',*extra,**kw)

    def populate(self):
        table = json.loads((ROOT/'DT_Demo_Pedidos_Clientes.json').read_text())
        table['id'] = 'MOCK_TABLE_ID'
        with (ROOT/'DT_Demo_Pedidos_Clientes.csv').open(encoding='utf-8-sig',newline='') as f:
            rows = [dict(key=row['NumeroPedido'],**{k:v for k,v in row.items() if k!='NumeroPedido'}) for row in csv.DictReader(f)]
        self.write_state({'table':table,'rows':rows,'mutations':0})

    def test_help_version_and_auth(self):
        result = self.run_script('check-genesys-cli.ps1','-CheckAuth')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('MOCK_ORG_ID',result.stdout)

    def test_unsupported_cli_fails(self):
        self.assertNotEqual(self.run_script('check-genesys-cli.ps1',mode='unsupported').returncode,0)

    def test_auth_failure_fails(self):
        self.assertNotEqual(self.run_script('check-genesys-cli.ps1','-CheckAuth',mode='auth-failure').returncode,0)

    def test_plan_does_not_mutate(self):
        result = self.seed()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.state()['mutations'],0)

    def test_create_and_idempotent_repeat(self):
        first = self.seed('-Apply')
        self.assertEqual(first.returncode,0,first.stdout+first.stderr)
        self.assertEqual(self.state()['mutations'],16)
        second = self.seed('-Apply')
        self.assertEqual(second.returncode,0,second.stdout+second.stderr)
        self.assertEqual(self.state()['mutations'],16)

    def test_existing_row_not_overwritten(self):
        self.populate()
        state = self.state();state['rows'][0]['DescripcionIncidencia'] = 'MOCK_EXISTING_CHANGED';self.write_state(state)
        result = self.seed('-Apply')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.state()['mutations'],0)
        self.assertEqual(self.state()['rows'][0]['DescripcionIncidencia'],'MOCK_EXISTING_CHANGED')

    def test_org_mismatch_no_mutation(self):
        result = self.run_script('seed-datatable.ps1','-ExpectedOrganizationId','MOCK_WRONG_ORG','-Apply')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.state()['mutations'],0)

    def test_schema_drift_no_mutation(self):
        self.populate()
        self.assertNotEqual(self.seed('-Apply',mode='schema-drift').returncode,0)
        self.assertEqual(self.state()['mutations'],0)

    def test_ambiguous_names_rejected(self):
        self.populate()
        self.assertNotEqual(self.seed('-Apply',mode='duplicate').returncode,0)
        self.assertEqual(self.state()['mutations'],0)

    def test_resource_search_and_exports(self):
        self.populate()
        export = Path(self.tmp.name)/'exports'
        result = self.run_script('check-resources.ps1','-ExportDirectory',str(export))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(json.loads((export/'order.json').read_text())['key'],'2540721')
        self.assertEqual(self.state()['mutations'],0)

    def test_pagination_searches_next_page(self):
        self.populate()
        export = Path(self.tmp.name)/'exports'
        result = self.run_script('check-resources.ps1','-ExportDirectory',str(export),mode='pagination')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(len(json.loads((export/'table-search.json').read_text())),101)

class DeployScriptTests(unittest.TestCase):
    write_state=CliScriptTests.write_state
    state=CliScriptTests.state
    run_script=CliScriptTests.run_script
    @classmethod
    def setUpClass(cls):
        if not PWSH or os.name == 'nt': raise unittest.SkipTest('Requiere pwsh y mock POSIX')
    def setUp(self):
        CliScriptTests.setUp(self)
        state=self.state();state.update(queue=None,libraries=[],responses=[]);self.write_state(state)

    def deploy(self, deploy_mode='Plan', org='MOCK_ORG_ID', **kw):
        return self.run_script('deploy-genesys-demo.ps1','-ExpectedOrganizationId',org,'-Mode',deploy_mode,'-OutputDirectory',str(Path(self.tmp.name)/'reports'),**kw)

    def latest_report(self):
        return json.loads(sorted((Path(self.tmp.name)/'reports').glob('*/deployment-report.json'))[-1].read_text())

    def test_deploy_plan_no_mutations(self):
        result=self.deploy()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.state()['mutations'],0)
        self.assertEqual(self.latest_report()['status'],'plan-only-no-remote-writes')

    def test_deploy_apply_repeat_and_verify(self):
        first=self.deploy('Apply')
        self.assertEqual(first.returncode,2,first.stdout+first.stderr)
        self.assertEqual(self.state()['mutations'],19)
        self.assertFalse(self.latest_report()['functionalReadinessVerified'])
        second=self.deploy('Apply')
        self.assertEqual(second.returncode,2,second.stdout+second.stderr)
        self.assertEqual(self.state()['mutations'],19)
        verify=self.deploy('Verify')
        self.assertEqual(verify.returncode,0,verify.stdout+verify.stderr)
        self.assertFalse(self.latest_report()['functionalReadinessVerified'])
        self.assertEqual(self.state()['mutations'],19)

    def test_deploy_wrong_org_stops_before_write(self):
        result=self.deploy('Apply',org='MOCK_WRONG_ORG')
        self.assertEqual(result.returncode,1)
        self.assertEqual(self.state()['mutations'],0)
        self.assertEqual(self.latest_report()['failedStep'],'Autenticacion y organizacion')

    def test_deploy_resumes_partial_failure(self):
        result=self.deploy('Apply',mode='queue-create-failure')
        self.assertEqual(result.returncode,1,result.stdout+result.stderr)
        self.assertEqual(self.state()['mutations'],16)
        resumed=self.deploy('Apply')
        self.assertEqual(resumed.returncode,2,resumed.stdout+resumed.stderr)
        self.assertEqual(self.state()['mutations'],19)

if __name__ == '__main__':
    unittest.main()
