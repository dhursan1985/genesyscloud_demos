"""Pruebas offline del inspector; no validan el importador de Genesys."""
import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('inspect_export', ROOT/'scripts/inspect-architect-export.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class InspectorTests(unittest.TestCase):
    def inspect_fixture(self):
        data = json.loads((ROOT/'revision_adjuntos/flujo_recibido_decodificado.NO_IMPORTAR.json').read_text())
        # Se reenvuelve solo para un fixture temporal, nunca como entrega importable.
        raw = base64.b64encode(quote(json.dumps(data)).encode())
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'input.fixture';path.write_bytes(raw)
            document, report = module.inspect_export(path)
            self.assertEqual(path.read_bytes(),raw)
            return document,report

    def test_decodes_without_modifying_input(self):
        document, report = self.inspect_fixture()
        self.assertEqual(document['name'],'Hermet10_Demo_ConsultaPedido')
        self.assertFalse(report['importabilityVerified'])

    def test_unreachable_response(self):
        _, report=self.inspect_fixture()
        self.assertEqual(report['actionCount'],6)
        self.assertEqual(report['reachableActionCount'],5)
        self.assertEqual(report['unreachableActions'][0]['name'],'Enviar respuesta automática')

    def test_missing_variables_and_screen_pop(self):
        _, report=self.inspect_fixture()
        self.assertEqual(report['missingRequiredFlowVariables'],['customerPhone','incidentType','supplierOrder'])
        self.assertEqual(report['screenPopActionCount'],0)

    def test_reports_empty_assignments_literal_and_decision(self):
        _, report=self.inspect_fixture()
        self.assertEqual(len(report['findings']),4)
        self.assertTrue(any('conditions vacio' in x['issue'] for x in report['findings']))

if __name__=='__main__':
    unittest.main()
