"""Pruebas de fidelidad al Excel, consolidación y Script de solo lectura."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
from reference_extractor import extract_order

ROOT=Path(__file__).resolve().parents[1]
FIELDS=json.loads((ROOT/'data-table-fields.json').read_text())
spec=importlib.util.spec_from_file_location('consolidate_excel',ROOT/'scripts/consolidate-excel.py')
excel=importlib.util.module_from_spec(spec)
spec.loader.exec_module(excel)

def read_csv(path):
    with path.open(encoding='utf-8-sig',newline='') as file:return list(csv.DictReader(file))

class DeliveryTests(unittest.TestCase):
    def test_requested_patterns(self):
        for text in ['Pedido: 2540721','Pedido 2540721','número de pedido 2540721','numero de pedido 2540721',"Pedido número 2540721",(ROOT/'tests/email_cuerpo.txt').read_text()]:
            with self.subTest(text=text):self.assertEqual(extract_order(text),('2540721',False))

    def test_parser_boundaries_and_ambiguity(self):
        for text in [None,'','despedido 2540721','Pedido 25407210','Pedido 2540721abc']:
            self.assertEqual(extract_order(text),('',False))
        self.assertEqual(extract_order('Pedido 2540721; Pedido 2540721'),('2540721',False))
        self.assertEqual(extract_order('Pedido 2540721; Pedido 2540722'),('2540721',True))
        self.assertTrue(extract_order('x'*16001)[1])

    def test_source_excel_and_raw_csv_exact(self):
        source=ROOT/'datos/TablaVerdadHermet10.xlsx'
        manifest=json.loads((ROOT/'datos/source-manifest.json').read_text())
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),manifest['sha256'])
        columns,rows=excel.load_rows(source)
        self.assertEqual(columns,FIELDS)
        self.assertEqual(len(columns),37)
        self.assertEqual(len(rows),90)
        self.assertEqual(read_csv(ROOT/'datos/TablaVerdadHermet10_original.csv'),rows)
        # Los espacios y NULL literal no deben perderse por normalizaciones.
        self.assertEqual(rows[0]['ShippingAreaCode'],'ARAG ')
        self.assertEqual(rows[0]['WorkOrder'],'NULL')

    def test_consolidation_preserves_all_distinct_values(self):
        columns,original=excel.load_rows(ROOT/'datos/TablaVerdadHermet10.xlsx')
        rows=read_csv(ROOT/'DT_Demo_Pedidos_Clientes.csv')
        self.assertEqual(rows,excel.consolidate(columns,original))
        self.assertEqual(len(rows),15)
        self.assertEqual(len({r['NumeroPedido'] for r in rows}),15)
        main=next(r for r in rows if r['NumeroPedido']=='2540721')
        self.assertEqual(main['orden'],'1 | 2')
        self.assertEqual(main['CodigoCliente'],'10065')
        self.assertEqual(main['FechaEntrega'],'2025-10-03 00:00:00.000')
        self.assertEqual(main['RealDeliveryDate'],'2025-10-06 07:05:13.197')
        self.assertEqual(main['DescripcionIncidencia'],'falta tapa interior de 155 la viuda')

    def test_schema_exact_columns_and_unique_key(self):
        definition=json.loads((ROOT/'DT_Demo_Pedidos_Clientes.json').read_text())
        schema=definition['schema']
        self.assertEqual(schema['properties']['key'],{'type':'string','title':'NumeroPedido'})
        self.assertEqual(schema['required'],['key'])
        self.assertEqual([p['title'] for p in schema['properties'].values()],FIELDS)
        self.assertEqual(set(schema['properties']),set(FIELDS)-{'NumeroPedido'}|{'key'})
        self.assertTrue(all(p['type']=='string' for p in schema['properties'].values()))
        for invented in ['customerName','customerEmail','customerPhone','status','orderNumber']:
            self.assertNotIn(invented,schema['properties'])

    def test_readonly_inputs_and_no_data_actions(self):
        mapping=json.loads((ROOT/'script-inputs.json').read_text())
        self.assertEqual(len(mapping),43)
        self.assertEqual(len({m['name'] for m in mapping}),43)
        self.assertEqual([m['name'] for m in mapping[:37]],FIELDS)
        for m in mapping:
            self.assertTrue(m['input']);self.assertFalse(m['output']);self.assertTrue(m['readOnly'])
            self.assertEqual(m['architect'],'Flow.'+m['name'])
        self.assertFalse(list(ROOT.glob('DA_Update*.json')))
        flow=json.loads((ROOT/'flow-spec.json').read_text())
        self.assertEqual(flow['lookup']['action'],'Data Table Lookup')
        self.assertFalse(flow['lookup']['usesDataAction'])
        self.assertTrue(flow['agentScript']['readOnly'])
        self.assertEqual(flow['agentScript']['dataActions'],[])
        self.assertEqual(flow['agentScript']['editableFields'],[])

    def test_queue_consistency(self):
        for file in ['config.demo.json','generador-flujo/config.example.json']:
            config=json.loads((ROOT/file).read_text())
            self.assertEqual(config['queueName'],'Demo_Hermet10_EmailIN')
        flow=json.loads((ROOT/'flow-spec.json').read_text())
        self.assertEqual(flow['escalation']['queueName'],'Demo_Hermet10_EmailIN')

    def test_response_only_uses_existing_columns(self):
        text=(ROOT/'respuestas/Encontrado.txt').read_text()
        variables=re.findall(r'\{\{Flow\.(\w+)\}\}',text)
        self.assertTrue(variables)
        self.assertTrue(set(variables).issubset(set(FIELDS)))
        expression=(ROOT/'respuestas/Encontrado.architect-expression.txt').read_text()
        for name in variables:self.assertIn('Flow.'+name,expression)
        self.assertNotIn('{{',expression)
        self.assertNotIn('Estado:',text)
        self.assertNotIn('customerName',text)

    def test_all_json_valid(self):
        files=[p for p in ROOT.rglob('*.json') if not any(x in p.parts for x in ['exports','.local','.git','node_modules'])]
        for p in files:
            with self.subTest(path=str(p)):json.loads(p.read_text(encoding='utf-8-sig'))

if __name__=='__main__':unittest.main()
