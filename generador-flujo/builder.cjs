'use strict';
const fs = require('node:fs');
const path = require('node:path');

const FIELDS = require('../data-table-fields.json');
const STRING_VARS = [...FIELDS, 'orderNumber', 'rawBody','bodyLower','remaining','afterKeyword','candidate','firstOrder','currentChar','senderEmail','contactReason','escalationReason','responseBody'];
const BOOL_VARS = ['lookupFound','needsAgent','incidentIndicator','ambiguous'];
const INT_VARS = ['position','keywordIndex','digitIndex'];

/** Construye un flujo NUEVO en memoria usando solo las fábricas públicas del SDK.
 * No llama a save/checkIn/createFlow/publish ni inventa su serialización.
 */
async function buildFlow(sdk, config) {
  const A = sdk.factories.archFactoryActions;
  const S = sdk.factories.archFactoryStates;
  let flow;
  await sdk.factories.archFactoryFlows.createFlowInboundEmailAsync(
    config.flowName, 'Consulta de pedidos por email: lookup nativo, autorrespuesta y escalado',
    sdk.languages.archLanguages.getByLanguageTag('es-ES'), created => { flow = created; }
  );
  if (!flow) throw new Error('El SDK no devolvió el flujo nuevo en memoria.');
  // El SDK obtiene los tipos válidos del motor conectado, no de un esquema privado.
  const types = Object.values(sdk.dataTypes.ArchDataTypes.getFlowDataTypes(flow));
  function type(name) {
    const found = types.find(t => t.name.toLowerCase() === name.toLowerCase() && !t.isCollection);
    if (!found) throw new Error(`Tipo Architect no disponible: ${name}`);
    return found;
  }
  const vars = {};
  for (const [names,t] of [[STRING_VARS,'String'],[BOOL_VARS,'Boolean'],[INT_VARS,'Integer']]) {
    for (const name of names) vars[name] = flow.addVariable(name,type(t));
  }
  const start = flow.startUpObject;
  if (!start) throw new Error('No hay estado inicial en el flujo nuevo.');
  for (const action of [...start.actions]) start.deleteAction(action);
  start.name = 'Leer y extraer pedido';
  const lookupState = S.addState(flow,'Consultar Data Table');
  const escalation = S.addState(flow,'Escalar a agente');
  const noNumber = S.addState(flow,'Solicitar numero de pedido');
  const q = JSON.stringify;
  function set(container,name,expression) {
    const action = A.addActionUpdateData(container,`Asignar ${name}`);
    // Una asignación por acción: no depender del orden de evaluación de un grupo.
    action.addUpdateDataStatement(vars[name].dataType,vars[name],expression);
    return action;
  }
  function decision(container,name,expression) { return A.addActionDecision(container,name,expression); }
  function jump(container,state) { return A.addActionChangeState(container,`Ir a ${state.name}`,state); }
  function escalate(container,reason) {
    set(container,'escalationReason',q(reason)); jump(container,escalation);
  }
  function prefix(container,prefixText) {
    const guard = decision(container,`Longitud para prefijo ${prefixText}`,`Length(Flow.afterKeyword) >= ${prefixText.length}`);
    return decision(guard.outputYes,`Prefijo ${prefixText}`,`Substring(Flow.afterKeyword, 0, ${prefixText.length}) == ${q(prefixText)}`).outputYes;
  }
  const alpha = q('abcdefghijklmnopqrstuvwxyzáéíóúüñ0123456789');
  const isWord = char => `FindString(${alpha}, ${char}) >= 0`;
  const init = { ...Object.fromEntries(STRING_VARS.map(n=>[n,'""'])), ...Object.fromEntries(BOOL_VARS.map(n=>[n,'false'])), ...Object.fromEntries(INT_VARS.map(n=>[n,'0'])) };
  for (const [name,expression] of Object.entries(init)) set(start,name,expression);
  set(start,'contactReason',q('Consulta de estado de pedido por email'));
  const missingBody = decision(start,'Cuerpo no disponible',`IsNotSet(${config.bodyExpression})`);
  jump(missingBody.outputYes,noNumber);
  set(start,'rawBody',config.bodyExpression);
  set(start,'senderEmail',config.senderExpression);
  const tooLong = decision(start,'Limite de longitud de demo','Length(Flow.rawBody) > 16000');
  escalate(tooLong.outputYes,'Cuerpo supera limite de demo');
  set(start,'bodyLower','Lower(Flow.rawBody)');
  for (const [old,replacement] of [['\r',' '],['\n',' '],['\t',' '],['ú','u']]) {
    set(start,'bodyLower',`Replace(Flow.bodyLower, ${q(old)}, ${q(replacement)})`);
  }
  set(start,'remaining','Flow.bodyLower');
  set(start,'needsAgent',`FindString(Flow.bodyLower, "agente") >= 0 or FindString(Flow.bodyLower, "asistencia") >= 0 or FindString(Flow.bodyLower, "hablar con una persona") >= 0`);
  const outer = A.addActionLoop(start,'Buscar hasta diez menciones',vars.keywordIndex,'10');
  const loop = outer.outputLoop;
  set(loop,'position','FindString(Flow.remaining, "pedido")');
  const exhausted = decision(loop,'Sin mas menciones','Flow.position < 0');
  A.addActionLoopExit(exhausted.outputYes,'Fin de busqueda');
  const previous = decision(loop,'Existe caracter anterior','Flow.position > 0');
  const partialWord = decision(previous.outputYes,'Evitar palabra parcial',isWord('Substring(Flow.remaining, Flow.position - 1, 1)'));
  set(partialWord.outputYes,'remaining','Trim(Substring(Flow.remaining, Flow.position + 6, Length(Flow.remaining) - Flow.position - 6))');
  A.addActionLoopNext(partialWord.outputYes,'Siguiente mencion');
  set(loop,'afterKeyword','Trim(Substring(Flow.remaining, Flow.position + 6, Length(Flow.remaining) - Flow.position - 6))');
  set(loop,'remaining','Flow.afterKeyword');
  set(prefix(loop,':'),'afterKeyword','Trim(Substring(Flow.afterKeyword, 1, Length(Flow.afterKeyword) - 1))');
  set(prefix(loop,'numero '),'afterKeyword','Trim(Substring(Flow.afterKeyword, 7, Length(Flow.afterKeyword) - 7))');
  set(prefix(loop,':'),'afterKeyword','Trim(Substring(Flow.afterKeyword, 1, Length(Flow.afterKeyword) - 1))');
  set(loop,'candidate','""');
  const digits = A.addActionLoop(loop,'Leer hasta ocho cifras',vars.digitIndex,'8');
  const end = decision(digits.outputLoop,'Fin del texto','Flow.digitIndex >= Length(Flow.afterKeyword)');
  A.addActionLoopExit(end.outputYes,'Terminar cifras');
  set(digits.outputLoop,'currentChar','Substring(Flow.afterKeyword, Flow.digitIndex, 1)');
  const nonDigit = decision(digits.outputLoop,'No es cifra','FindString("0123456789", Flow.currentChar) < 0');
  A.addActionLoopExit(nonDigit.outputYes,'Fin de cifras');
  set(digits.outputLoop,'candidate','Flow.candidate + Flow.currentChar');
  const wrongLength = decision(loop,'Exigir siete cifras','Length(Flow.candidate) != 7');
  A.addActionLoopNext(wrongLength.outputYes,'Descartar longitud');
  const following = decision(loop,'Existe caracter posterior','Length(Flow.afterKeyword) > 7');
  const joinedWord = decision(following.outputYes,'Descartar sufijo de palabra',isWord('Substring(Flow.afterKeyword, 7, 1)'));
  A.addActionLoopNext(joinedWord.outputYes,'Descartar sufijo');
  const first = decision(loop,'Primer pedido','Flow.firstOrder == ""');
  set(first.outputYes,'firstOrder','Flow.candidate');
  const different = decision(loop,'Pedido diferente','Flow.firstOrder != Flow.candidate');
  set(different.outputYes,'ambiguous','true');
  const remaining = decision(start,'Limite de menciones agotado','FindString(Flow.remaining, "pedido") >= 0');
  set(remaining.outputYes,'ambiguous','true');
  set(start,'orderNumber','Flow.firstOrder');
  const ambiguous = decision(start,'Resultado ambiguo','Flow.ambiguous');
  escalate(ambiguous.outputYes,'Varios pedidos o limite de extraccion');
  const empty = decision(start,'No se detecta numero','Flow.orderNumber == ""');
  const helpWithoutOrder = decision(empty.outputYes,'Pide agente sin numero','Flow.needsAgent');
  escalate(helpWithoutOrder.outputYes,'Solicita asistencia sin numero de pedido');
  jump(helpWithoutOrder.outputNo,noNumber);
  jump(start,lookupState);

  // Lookup exclusivamente nativo, con binding de salidas a variables del flujo.
  const lookup = A.addActionDataTableLookup(lookupState,'Data Table Lookup - pedido');
  await lookup.setDataTableByNameAsync(config.dataTableName);
  lookup.lookupValue.setExpressionFromVariable(vars.orderNumber);
  for (const name of FIELDS.slice(1)) {
    const output = lookup.dataTableOutputsFound?.getNamedValueByName(name);
    if (!output) throw new Error(`La tabla no devuelve la columna requerida ${name}`);
    output.value.setVariable(vars[name]);
  }
  set(lookup.outputFound,'lookupFound','true');
  set(lookup.outputFound,'NumeroPedido','Flow.orderNumber');
  set(lookup.outputFound,'incidentIndicator','Flow.TipologiaIncidencia != "NULL" and Length(Trim(Flow.TipologiaIncidencia)) > 0');
  // El Excel no contiene email/nombre/telefono del cliente: no se inventan ni se comparan.
  const help = decision(lookup.outputFound,'Requiere asistencia','Flow.needsAgent');
  escalate(help.outputYes,'El cliente solicita asistencia');
  async function reply(container,file,finish) {
    const expression = fs.readFileSync(path.join(__dirname,'..','respuestas',`${file}.architect-expression.txt`),'utf8').trim();
    set(container,'responseBody',expression);
    const action = A.addActionSendAutoReply(container,`Autorrespuesta ${file}`);
    action.replyMode = sdk.enums.archEnums.SEND_AUTO_REPLY_MODES.replyToSender;
    action.setMessageBodyVariable(vars.responseBody);
    if (finish === 'disconnect') A.addActionDisconnect(action.outputSuccess,'Fin de email');
    else jump(action.outputSuccess,escalation);
    escalate(action.outputFailure,'Fallo de autorrespuesta');
  }
  await reply(lookup.outputFound,'Encontrado','disconnect');
  set(lookup.outputNotFound,'lookupFound','false');
  set(lookup.outputNotFound,'escalationReason',q('Pedido no encontrado'));
  await reply(lookup.outputNotFound,'NoEncontrado','escalate');
  set(lookup.outputFailure,'lookupFound','false');
  escalate(lookup.outputFailure,'Fallo tecnico de Data Table Lookup');
  await reply(noNumber,'SinNumero','disconnect');

  // Script publicado real y sus inputs. Sin UUID ficticios ni atributos que finjan un Screen Pop.
  const pop = A.addActionSetScreenPop(escalation,'Abrir Script de pedido');
  await pop.setScriptByNameAsync(config.scriptName);
  for (const name of [...FIELDS,'orderNumber','lookupFound','incidentIndicator','senderEmail','contactReason','escalationReason']) {
    const input = pop.scriptInputs?.getNamedValueByName(name);
    if (!input) throw new Error(`El Script publicado no expone el input ${name}`);
    input.value.setExpressionFromVariable(vars[name]);
  }
  const transfer = A.addActionTransferToAcd(escalation,'Transferir a cola de pedidos');
  await transfer.setLiteralByQueueNameAsync(config.queueName);
  const retry = A.addActionTransferToAcd(transfer.outputFailure,'Un reintento de transferencia');
  await retry.setLiteralByQueueNameAsync(config.fallbackQueueName || config.queueName);
  A.addActionDisconnect(retry.outputFailure,'Transferencia fallida: requiere revision operativa');
  return flow;
}
module.exports = { buildFlow, FIELDS };
