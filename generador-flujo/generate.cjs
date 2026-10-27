'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { buildFlow } = require('./builder.cjs');

async function main() {
  const configPath = path.resolve(process.argv[2] || path.join(__dirname,'config.local.json'));
  if (!fs.existsSync(configPath)) throw new Error('Copie config.example.json a config.local.json y configure location/organizacion.');
  const config = JSON.parse(fs.readFileSync(configPath,'utf8'));
  for (const field of ['location','expectedOrganizationId','flowName','dataTableName','queueName','scriptName','bodyExpression','senderExpression','outputDirectory']) {
    if (typeof config[field] !== 'string' || !config[field].trim() || config[field].includes('REEMPLAZAR')) throw new Error(`Configure ${field}`);
  }
  if (/[\\/:*?"<>|]/.test(config.flowName) || config.flowName === '.' || config.flowName === '..') throw new Error('Nombre de flujo no valido para un fichero Windows.');
  const token = process.env.GENESYSCLOUD_ACCESS_TOKEN;
  const clientId = process.env.GENESYSCLOUD_OAUTHCLIENT_ID;
  const secret = process.env.GENESYSCLOUD_OAUTHCLIENT_SECRET;
  if (!token && !(clientId && secret)) throw new Error('No hay autenticacion utilizable. Proporcione un token o el binding OAuth existente mediante variables de entorno; no escriba secretos en JSON ni en el chat.');
  const sdk = require('purecloud-flow-scripting-api-sdk-javascript');
  if (!Object.values(sdk.enums.archEnums.LOCATIONS).includes(config.location) || ['dev','test'].includes(config.location)) throw new Error('location debe ser una region de produccion admitida por el SDK.');
  const session = sdk.environment.archSession;
  session.endTerminatesProcess = false;
  let generated = false;
  const outputDir = path.resolve(path.dirname(configPath),config.outputDirectory);
  const finalFile = path.join(outputDir,config.flowName+'.i3InboundEmailFlow');
  if (fs.existsSync(finalFile)) throw new Error('El archivo de destino ya existe. Conservelo o cambie outputDirectory; no se sobrescribe.');
  const run = async current => {
    if (!current.orgInfo || current.orgInfo.id !== config.expectedOrganizationId) throw new Error('La organizacion autenticada no coincide con la configurada.');
    const flow = await buildFlow(sdk,config);
    const validation = await flow.validateAsync();
    fs.mkdirSync(outputDir,{recursive:true});
    fs.writeFileSync(path.join(outputDir,'validation.txt'),validation.getSummaryStr(true),'utf8');
    if (validation.hasErrors || !validation.hasNoErrors) throw new Error('El motor Architect devuelve errores. Consulte validation.txt; no se entrega un .i3InboundEmailFlow.');
    // Exporta el serializador oficial y comprueba su reimportacion EN MEMORIA.
    const staging = fs.mkdtempSync(path.join(outputDir,'.staging-'));
    try {
      const exported = await flow.exportToDirAsync(staging,undefined,sdk.enums.archEnums.FLOW_FORMAT_TYPES.architect,config.flowName);
      let check;
      await sdk.factories.archFactoryFlows.createFlowInboundEmailAsync(config.flowName,'Verificacion en memoria',sdk.languages.archLanguages.getByLanguageTag('es-ES'),created=>{check=created;});
      if (!check) throw new Error('No se pudo preparar la comprobacion de importacion.');
      await check.importFromFileAsync(exported);
      const checked = await check.validateAsync();
      fs.writeFileSync(path.join(outputDir,'roundtrip-validation.txt'),checked.getSummaryStr(true),'utf8');
      if (checked.hasErrors || !checked.hasNoErrors) throw new Error('La reimportacion en memoria tiene errores; no se entrega un flujo como validado.');
      fs.copyFileSync(exported,finalFile,fs.constants.COPYFILE_EXCL);
      generated = true;
      console.log(`Archivo generado por el SDK oficial: ${finalFile}`);
      console.log('Importelo manualmente en Architect y ejecute Validate antes de publicar. No se ha guardado ni publicado un flujo en la organizacion.');
    } finally { fs.rmSync(staging,{recursive:true,force:true}); }
  };
  const options={cacheEnabled:true,captureNetworkDiagnosticsOnFailure:false,logNetworkDiagnosticsOnFailure:false};
  if (token) await session.startWithAuthToken(config.location,run,token,undefined,config.tokenIsClientCredentials !== false,options);
  else await session.startWithClientIdAndSecret(config.location,run,clientId,secret,undefined,true,options);
  if (!generated || session.endExitCode !== 0) throw new Error('La sesion no termino con un flujo exportado y comprobado. Revise region, permisos, recursos y errores anteriores.');
}
main().catch(error=>{
  // No volcar objetos de sesion, respuestas HTTP ni credenciales.
  console.error(error instanceof Error ? error.message : 'Fallo al generar el flujo.');
  process.exitCode=1;
});
