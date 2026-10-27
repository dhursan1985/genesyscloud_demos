'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
function run(config){
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'hermet-runner-'));
  try{
    const file=path.join(temp,'config.json');
    if(config)fs.writeFileSync(file,JSON.stringify({...config,outputDirectory:'output'}));
    const env={...process.env};
    for(const key of ['GENESYSCLOUD_ACCESS_TOKEN','GENESYSCLOUD_OAUTHCLIENT_ID','GENESYSCLOUD_OAUTHCLIENT_SECRET'])delete env[key];
    const result=spawnSync(process.execPath,[path.join(__dirname,'generate.cjs'),file],{env,encoding:'utf8'});
    assert.equal(fs.existsSync(path.join(temp,'output')),false);
    return result;
  }finally{fs.rmSync(temp,{recursive:true,force:true});}
}
test('sin config: falla antes de conectar o producir archivo',()=>{const r=run();assert.equal(r.status,1);assert.match(r.stderr,/config.example/);});
test('marcadores pendientes: falla sin conectar ni exportar',()=>{const r=run(JSON.parse(fs.readFileSync(path.join(__dirname,'config.example.json'),'utf8')));assert.equal(r.status,1);assert.match(r.stderr,/Configure location/);});
test('sin credenciales: falla sin fingir un archivo importable',()=>{const c=JSON.parse(fs.readFileSync(path.join(__dirname,'config.example.json'),'utf8'));c.location='prod_eu_west_1';c.expectedOrganizationId='MOCK_ORG_ID';const r=run(c);assert.equal(r.status,1);assert.match(r.stderr,/No hay autenticacion/);});
