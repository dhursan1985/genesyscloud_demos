#!/usr/bin/env python3
"""Simulador offline para tests de orquestación, NO un CLI ni una API de Genesys.
Los identificadores MOCK_* son exclusivamente fixtures locales.
"""
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if args[:1] == ['-p']:
    assert args[1] == 'TEST_PROFILE', 'Profile not propagated'
    args = args[2:]
mode = os.environ.get('MOCK_GC_MODE', '')
state_file = Path(os.environ['MOCK_GC_STATE'])
state = json.loads(state_file.read_text())
root = Path(__file__).resolve().parents[1]

def emit(value):
    print(json.dumps(value, ensure_ascii=False))
    sys.exit(0)

def fail():
    print('MOCK failure (no credentials)', file=sys.stderr)
    sys.exit(1)

def flag(name):
    return args[args.index(name)+1]

if '--help' in args:
    if mode == 'unsupported' and args[:3] == ['flows','datatables','create']:
        fail()
    print('Genesys Cloud CLI MOCK help --file --name --expand --showbrief --pageNumber --pageSize --autopaginate --libraryId')
    sys.exit(0)
if args == ['version']:
    print('MOCK VERSION: no installed Genesys version assertion')
    sys.exit(0)
if mode == 'auth-failure':
    fail()
if args == ['organizations','me','get']:
    emit({'id':'MOCK_ORG_ID','name':'MOCK organization'})
if args[:3] == ['flows','datatables','list']:
    table = state.get('table')
    entities = [table] if table else []
    if mode == 'duplicate' and table:
        entities.append(dict(table, id='MOCK_DUPLICATE_TABLE_ID'))
    if mode == 'pagination' and flag('--pageNumber') == '1':
        entities = [{'name':'MOCK_UNRELATED_'+str(i),'id':'MOCK_OTHER_'+str(i)} for i in range(100)]
    elif mode == 'pagination' and flag('--pageNumber') == '2':
        pass
    elif mode == 'pagination':
        entities = []
    emit({'entities':entities})
if args[:3] == ['flows','datatables','create']:
    assert mode != 'readonly', 'Unexpected mutation'
    table = json.loads(Path(flag('--file')).read_text(encoding='utf-8-sig'))
    table['id'] = 'MOCK_TABLE_ID'
    state['table'] = table
    state['mutations'] += 1
    state_file.write_text(json.dumps(state))
    emit(table)
if args[:3] == ['flows','datatables','get']:
    table = state.get('table')
    if not table:
        fail()
    if mode == 'schema-drift':
        table['schema']['properties']['key']['title'] = 'WRONG'
    emit(table)
if args[:4] == ['flows','datatables','rows','list']:
    emit({'entities':state['rows']})
if args[:4] == ['flows','datatables','rows','create']:
    assert mode != 'readonly', 'Unexpected mutation'
    row = json.loads(Path(flag('--file')).read_text(encoding='utf-8-sig'))
    assert all(r['key'] != row['key'] for r in state['rows']), 'Duplicate creation'
    state['rows'].append(row)
    state['mutations'] += 1
    state_file.write_text(json.dumps(state))
    emit(row)
if args[:4] == ['flows','datatables','rows','get']:
    rows = [r for r in state['rows'] if r['key'] == args[5]]
    if rows:
        emit(rows[0])
    fail()
if args[:3] == ['routing','queues','list']:
    queue = state.get('queue', {'id':'MOCK_QUEUE_ID','name':'Demo_Hermet10_EmailIN'})
    emit({'entities':[queue] if queue else []})
if args[:3] == ['routing','queues','create']:
    if mode == 'queue-create-failure': fail()
    body=json.loads(Path(flag('--file')).read_text(encoding='utf-8-sig'))
    body['id']='MOCK_QUEUE_ID';state['queue']=body;state['mutations']+=1
    state_file.write_text(json.dumps(state));emit(body)
if args[:3] == ['responsemanagement','libraries','list']:
    emit({'entities':state.get('libraries',[])})
if args[:3] == ['responsemanagement','libraries','create']:
    body=json.loads(Path(flag('--file')).read_text(encoding='utf-8-sig'))
    body['id']='MOCK_LIBRARY_ID';state.setdefault('libraries',[]).append(body);state['mutations']+=1
    state_file.write_text(json.dumps(state));emit(body)
if args[:3] == ['responsemanagement','responses','list']:
    emit({'entities':[r for r in state.get('responses',[]) if any(l['id']==flag('--libraryId') for l in r['libraries'])]})
if args[:3] == ['responsemanagement','responses','create']:
    body=json.loads(Path(flag('--file')).read_text(encoding='utf-8-sig'))
    assert body['libraries'][0]['id']=='MOCK_LIBRARY_ID'
    body['id']='MOCK_RESPONSE_ID';state.setdefault('responses',[]).append(body);state['mutations']+=1
    state_file.write_text(json.dumps(state));emit(body)
if args[:2] == ['flows','list']:
    emit({'entities':[{'id':'MOCK_FLOW_ID','name':'Hermet10_Demo_ConsultaPedido','type':'inboundemail'}]})
if args[:2] == ['flows','get']:
    emit({'id':'MOCK_FLOW_ID','name':'Hermet10_Demo_ConsultaPedido','type':'inboundemail'})
if args[:3] == ['scripts','published','list']:
    emit({'entities':[{'id':'MOCK_SCRIPT_ID','name':'SC_Consulta_Pedido'}]})
fail()
