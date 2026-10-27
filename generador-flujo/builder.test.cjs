'use strict';
// Simulación local del grafo. No valida el motor real ni la importación de Genesys.
const test=require('node:test');
const assert=require('node:assert/strict');
const {buildFlow,FIELDS}=require('./builder.cjs');
const fs=require('node:fs');
const path=require('node:path');
const CONFIG={flowName:'Hermet10_Demo_ConsultaPedido',dataTableName:'DT_Demo_Pedidos_Clientes',queueName:'Demo_Hermet10_EmailIN',fallbackQueueName:'Demo_Hermet10_EmailIN',scriptName:'SC_Consulta_Pedido',bodyExpression:'Email.Message.body',senderExpression:'ToString(Email.Message.from)'};
const INPUTS=[...FIELDS,'orderNumber','lookupFound','incidentIndicator','senderEmail','contactReason','escalationReason'];
function fakeSDK(missingColumn,missingInput) {
  const nodes=[];const states=[];
  function container(){return {actions:[],get actionCount(){return this.actions.length;},deleteAction(a){this.actions=this.actions.filter(x=>x!==a);}};}
  function named(names){const map=new Map(names.map(name=>[name,{name,value:{setVariable(v){this.variable=v;},setExpressionFromVariable(v){this.input=v;}}}]));return {getNamedValueByName:n=>map.get(n),map};}
  function action(parent,kind,name) {const a={kind,name,outputs:{}};parent.actions.push(a);nodes.push(a);return a;}
  function withOutputs(a,names){for(const name of names) a['output'+name]=a.outputs[name]=container();return a;}
  const A={
    addActionUpdateData(p,n){const a=action(p,'update',n);a.addUpdateDataStatement=(t,v,e)=>{a.variable=v;a.expression=e;};return a;},
    addActionDecision(p,n,e){const a=withOutputs(action(p,'decision',n),['Yes','No']);a.expression=e;return a;},
    addActionChangeState(p,n,state){const a=action(p,'change',n);a.target=state;return a;},
    addActionLoop(p,n,index,count){const a=withOutputs(action(p,'loop',n),['Loop']);a.index=index;a.count=count;return a;},
    addActionLoopExit(p,n){return action(p,'exit',n);},
    addActionLoopNext(p,n){return action(p,'next',n);},
    addActionDataTableLookup(p,n){const a=withOutputs(action(p,'lookup',n),['Found','NotFound','Failure']);a.setDataTableByNameAsync=async name=>{a.table=name;};a.lookupValue={setExpressionFromVariable(v){a.keyVariable=v;}};a.dataTableOutputsFound=named(FIELDS.slice(1).filter(n=>n!==missingColumn));return a;},
    addActionSendAutoReply(p,n){const a=withOutputs(action(p,'reply',n),['Success','Failure']);a.setMessageBodyVariable=v=>{a.bodyVariable=v;};return a;},
    addActionDisconnect(p,n){return action(p,'disconnect',n);},
    addActionSetScreenPop(p,n){const a=action(p,'pop',n);a.setScriptByNameAsync=async name=>{a.script=name;};a.scriptInputs=named(INPUTS.filter(n=>n!==missingInput));return a;},
    addActionTransferToAcd(p,n){const a=withOutputs(action(p,'transfer',n),['Failure']);a.setLiteralByQueueNameAsync=async name=>{a.queue=name;};return a;}
  };
  const flow={states,startUpObject:null,addVariable:(name,dataType)=>({name,dataType})};
  function state(name){const c=container();c.name=name;states.push(c);return c;}
  flow.startUpObject=state('Initial');
  const sdk={factories:{archFactoryActions:A,archFactoryStates:{addState:(f,name)=>state(name)},archFactoryFlows:{createFlowInboundEmailAsync:async(n,d,l,callback)=>callback(flow)}},dataTypes:{ArchDataTypes:{getFlowDataTypes:()=>Object.fromEntries(['String','Boolean','Integer'].map(n=>[n,{name:n,isCollection:false}]))}},languages:{archLanguages:{getByLanguageTag:t=>t}},enums:{archEnums:{SEND_AUTO_REPLY_MODES:{replyToSender:'replyToSender'}}}};
  return {sdk,nodes,flow};
}
function simulate(flow,body,options={}) {
  const Flow={};const Email={Message:{body,from:options.sender||'carlos.martinez.demo@ejemplo.com'}};
  const sent=[];const popped=[];const transfers=[];
  const functions={IsNotSet:v=>v==null,ToString:v=>String(v),Lower:v=>v.toLowerCase(),Length:v=>v.length,Trim:v=>v.trim(),Substring:(v,start,length)=>{if(start<0||length<0||start+length>v.length)throw Error('Substring fuera de rango');return v.slice(start,start+length);},FindString:(v,s)=>v.indexOf(s),Replace:(v,a,b)=>v.split(a).join(b)};
  function evaluate(e){return Function('Flow','Email',...Object.keys(functions),`return (${e.replace(/\bor\b/g,'||').replace(/\band\b/g,'&&')})`)(Flow,Email,...Object.values(functions));}
  function exec(c) {
    for(const a of c.actions){let result;
      if(a.kind==='update')Flow[a.variable.name]=evaluate(a.expression);
      else if(a.kind==='decision')result=exec(evaluate(a.expression)?a.outputYes:a.outputNo);
      else if(a.kind==='loop'){
        for(let i=0;i<Number(a.count);i++){
          Flow[a.index.name]=i;const r=exec(a.outputLoop);
          if(r?.type==='exit')break;
          if(r?.type==='next')continue;
          if(r){result=r;break;}
        }
      } else if(a.kind==='exit'||a.kind==='next'||a.kind==='disconnect')return {type:a.kind};
      else if(a.kind==='change')return {type:'change',state:a.target};
      else if(a.kind==='lookup'){
        if(options.lookupFailure)result=exec(a.outputFailure);
        else if(Flow[a.keyVariable.name]==='2540721'){
          for(const [name,named]of a.dataTableOutputsFound.map)Flow[named.value.variable.name]=options.row?.[name]??({CodigoCliente:'10065',TipologiaIncidencia:'Falta de Material',Referencia:'80822416',DescripcionIncidencia:'falta tapa interior de 155 la viuda'}[name]||'');
          result=exec(a.outputFound);
        } else result=exec(a.outputNotFound);
      } else if(a.kind==='reply'){
        if(options.replyFailure)result=exec(a.outputFailure);
        else {sent.push(Flow[a.bodyVariable.name]);result=exec(a.outputSuccess);}
      } else if(a.kind==='pop'){
        popped.push(Object.fromEntries([...a.scriptInputs.map].map(([name,n])=>[name,Flow[n.value.input.name]])));
      } else if(a.kind==='transfer'){
        transfers.push(a.queue);
        if(options.transferFailure)result=exec(a.outputFailure);else return {type:'transferred'};
      }
      if(result)return result;
    }
  }
  let current=flow.startUpObject;
  for(let i=0;i<20;i++){
    const r=exec(current);
    if(r?.type==='change'){current=r.state;continue;}
    return {Flow,sent,popped,transfers,outcome:r?.type};
  }
  throw Error('Bucle de estados');
}

test('API pública: métodos y enums existen en el paquete oficial fijado',()=>{
  const sdk=require('purecloud-flow-scripting-api-sdk-javascript');
  for(const name of Object.keys(fakeSDK().sdk.factories.archFactoryActions))assert.equal(typeof sdk.factories.archFactoryActions[name],'function',name);
  assert.equal(sdk.enums.archEnums.FLOW_FORMAT_TYPES.architect,'architect');
  assert.equal(typeof sdk.dataTypes.ArchDataTypes.getFlowDataTypes,'function');
  assert.equal(typeof sdk.factories.archFactoryFlows.createFlowInboundEmailAsync,'function');
});
test('cuatro patrones y cuerpo completo: lookup y respuesta nativos',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);
  assert.equal(f.nodes.filter(a=>a.kind==='lookup').length,1);
  for(const body of ['Pedido: 2540721','Pedido 2540721','número de pedido 2540721','numero de pedido 2540721',fs.readFileSync(path.join(__dirname,'../tests/email_cuerpo.txt'),'utf8')]){
    const r=simulate(f.flow,body);assert.equal(r.Flow.orderNumber,'2540721');assert.equal(r.Flow.lookupFound,true);assert.equal(r.sent.length,1);assert.match(r.sent[0],/10065/);assert.equal(r.outcome,'disconnect');assert.equal(r.transfers.length,0);
  }
});
test('no encontrado envía aviso y escala con 43 inputs',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);const r=simulate(f.flow,'Pedido 9999999');
  assert.equal(r.Flow.lookupFound,false);assert.equal(r.sent.length,1);assert.match(r.sent[0],/No hemos podido localizar/);assert.equal(r.outcome,'transferred');assert.equal(Object.keys(r.popped[0]).length,43);assert.equal(r.popped[0].orderNumber,'9999999');
});
test('sin número solicita dato; sin lookup ni transferencia',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);const r=simulate(f.flow,'Buenos días');assert.equal(r.sent.length,1);assert.match(r.sent[0],/necesitamos/);assert.equal(r.outcome,'disconnect');assert.equal(r.transfers.length,0);
});
test('petición de agente escala con datos Excel sin campos ficticios',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);
  const r=simulate(f.flow,'Pedido 2540721 necesito agente');
  assert.equal(r.outcome,'transferred');assert.equal(r.sent.length,0);
  assert.equal(r.popped[0].CodigoCliente,'10065');assert.equal(r.popped[0].NumeroPedido,'2540721');
  assert.equal('customerName' in r.popped[0],false);
});
test('patrones inválidos, duplicados y ambiguos',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);
  for(const body of ['despedido 2540721','Pedido 25407210','Pedido 2540721abc','Pedido ABC2540721'])assert.equal(simulate(f.flow,body).Flow.orderNumber,'');
  assert.equal(simulate(f.flow,'Pedido 2540721; Pedido 2540721').outcome,'disconnect');
  const amb=simulate(f.flow,'Pedido 2540721; Pedido 2540722');assert.equal(amb.outcome,'transferred');assert.equal(amb.Flow.ambiguous,true);
});
test('fallos de lookup y autorrespuesta escalan; transferencia reintenta una vez',async()=>{
  const f=fakeSDK();await buildFlow(f.sdk,CONFIG);
  for(const options of [{lookupFailure:true},{replyFailure:true}])assert.equal(simulate(f.flow,'Pedido 2540721',options).outcome,'transferred');
  const failed=simulate(f.flow,'Pedido 9999999',{transferFailure:true});assert.equal(failed.transfers.length,2);assert.equal(failed.outcome,'disconnect');
});
test('faltan columna o input: aborta, no produce fichero',async()=>{
  for(const f of [fakeSDK('CodigoCliente'),fakeSDK(undefined,'orderNumber')])await assert.rejects(buildFlow(f.sdk,CONFIG),/requerida|input/);
});
