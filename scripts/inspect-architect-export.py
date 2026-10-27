"""Inspección offline de un export codificado; no es el validador de Genesys.
No modifica el original ni genera un .i3InboundEmailFlow.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote

REQUIRED_VARIABLES = set('orderNumber lookupFound customerCode customerName customerEmail customerPhone reference supplierOrder expectedDeliveryDate deliveryDate shippingType deliveryNote shippingLot shippingArea status incidentType incidentDescription'.split())

def inspect_export(path):
    raw = Path(path).read_bytes()
    decoded = base64.b64decode(raw, validate=True).decode('utf-8')
    document = json.loads(unquote(decoded))
    sequences = document.get('flowSequenceItemList', [])
    actions = {a['id']: a for s in sequences for a in s.get('actionList', [])}
    initial = next((s for s in sequences if s.get('id') == document.get('initialSequence')), {})
    def references(value):
        if isinstance(value, dict):
            return set().union(*(references(v) for k, v in value.items() if k != 'id'))
        if isinstance(value, list):
            return set().union(*(references(v) for v in value))
        return {value} if isinstance(value, str) and value in actions else set()
    reached = set()
    pending = [initial.get('startAction')]
    while pending:
        action_id = pending.pop()
        if action_id in actions and action_id not in reached:
            reached.add(action_id)
            pending.extend(references(actions[action_id]) - reached)
    variables = {v.get('name') for v in document.get('variables', [])}
    used = set(re.findall(r'Flow\.([A-Za-z][A-Za-z0-9_]*)', json.dumps(document)))
    findings = []
    for action in actions.values():
        if action.get('__type') == 'SetParticipantDataAction' and not action.get('participantData'):
            findings.append({'action':action['name'],'issue':'participantData vacio; esta accion no extrae ni asigna Flow.orderNumber'})
        if action.get('__type') == 'DecisionAction' and not action.get('conditions'):
            findings.append({'action':action['name'],'issue':'conditions vacio; solo hay defaultAction en este documento'})
        expression = action.get('keyExpression', {})
        if expression.get('config', {}).get('lit', {}).get('text') == 'Flow.orderNumber':
            findings.append({'action':action['name'],'issue':'config.lit contiene Flow.orderNumber como literal; no acredita una expresion de variable'})
        if action.get('__type') == 'DataTableLookupAction':
            findings.append({'action':action['name'],'issue':'No constan mapeos de columnas ni ramas Found/Not Found/Failure; solo nextAction'})
    report = {
        'scope':'Inspeccion estructural local; NO certifica importacion, esquema privado ni ejecucion de Architect',
        'sourceFile':Path(path).name,
        'sha256':hashlib.sha256(raw).hexdigest(),
        'encoding':'Base64 de texto JSON codificado por porcentajes',
        'name':document.get('name'),
        'type':document.get('type'),
        'language':document.get('defaultLanguage'),
        'actionCount':len(actions),
        'reachableActionCount':len(reached),
        'unreachableActions':[{'name':a['name'],'type':a.get('__type')} for k,a in actions.items() if k not in reached],
        'missingRequiredFlowVariables':sorted(REQUIRED_VARIABLES - variables),
        'undeclaredReferencedFlowVariables':sorted(used - variables),
        'screenPopActionCount':sum('screenpop' in a.get('__type','').lower() for a in actions.values()),
        'findings':findings,
        'importabilityVerified':False,
    }
    return document, report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export_file', type=Path)
    parser.add_argument('--output-directory', type=Path)
    args = parser.parse_args()
    document, report = inspect_export(args.export_file)
    if args.output_directory:
        args.output_directory.mkdir(parents=True, exist_ok=True)
        # Estos JSON son vistas de inspeccion, no sustitutos del fichero importable.
        for name, content in [('flujo_recibido_decodificado.NO_IMPORTAR.json',document),('diagnostico_flujo.json',report)]:
            target = args.output_directory/name
            if target.exists():
                raise FileExistsError(f'No se sobrescribe {target}; elegir otro directorio')
            target.write_text(json.dumps(content, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()
