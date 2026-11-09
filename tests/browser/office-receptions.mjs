import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[]; page.setDefaultTimeout(8000);
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const p=new URL(route.request().url()).pathname;
  const mock={
   '/':'<main class="page"></main>',
   '/js/utils/diag-log.js':'export function logDiag() {}',
   '/js/services/claims.js':`export async function activeArs(){return [{id:'ars',name:'ARS ficticia'}];} export async function captureProviders(){return [{id:'provider',full_name:'Médico ficticio',organization_id:'org'}];}`,
   '/js/services/office-receptions.js':`
    export const officeReceptionRoles=['super_admin','admin','operations','billing','assistant'];
    export async function receptionClients(){return [{id:'org',legal_name:'Cliente ficticio'}];}
    export async function listOfficeReceptions(){return {data:window.receipt?[window.receipt]:[],count:window.receipt?1:0};}
    export async function createOfficeReception(id,v){window.saveCalls.push({id,v});if(window.validationFailure)throw {code:'23514',message:'Revise el detalle'};window.receipt={...v,id,folio:'ROF-QA-001',status:'recibida',organizations:{legal_name:'Cliente ficticio'},office_reception_lines:v.lines.map((l,i)=>({...l,id:'item'+i,ars:{name:'ARS ficticia'}})),links:[]};if(window.saveTimeout){window.saveTimeout=false;throw new Error('Respuesta no confirmada');}return id;}
    export async function getOfficeReception(){return structuredClone(window.receipt);}
    export async function assignOfficeClaim(item,claim,remove){window.assignCalls.push({item,claim,remove});if(remove)window.receipt.links=window.receipt.links.filter(l=>l.service_line_id!==claim);else window.receipt.links.push({service_line_id:claim,reception_line_id:item,service_lines:{claim_folio:'REC-QA',patient_name:'Paciente ficticio',service_name_snapshot:'Consulta',amount:100}});}
    export async function cancelOfficeReception(id,reason){window.receipt.status='anulada';window.receipt.cancelled_reason=reason;window.receipt.links=[];}
    export async function receptionCandidates(){return {data:[{id:'claim',folio:'REC-QA',patient_name:'Paciente ficticio',service_name:'Consulta',service_date:'2026-09-28',claimed:100}],count:1};}
    export async function uploadReceptionFile(r,f){if(window.fileFailure)throw new Error('No se pudo subir');window.uploads.push(f.name);}
    export async function receptionFiles(){return window.uploads.map(name=>({name:'00000000-0000-0000-0000-000000000000-'+name}));}
    export async function receptionFileUrl(){return 'https://example.test/private-signed';}`
  };
  if(p in mock)return route.fulfill({contentType:p==='/'?'text/html':'text/javascript',body:mock[p]});
  try{return route.fulfill({contentType:p.endsWith('.css')?'text/css':'text/javascript',body:await readFile(new URL(p.slice(1),root))});}catch{return route.fulfill({status:404,body:'missing'});}
 });
 await page.goto('http://127.0.0.1:8881/');
 for (const sheet of ['variables.css','components.css','app.css']) await page.addStyleTag({content:await readFile(new URL('css/'+sheet,root),'utf8')});
 await page.evaluate(async()=>{window.saveCalls=[];window.assignCalls=[];window.uploads=[];const m=await import('/js/modules/office-receptions.js');window.officeRender=m.render;window.show=async(arg,role='admin')=>officeRender(document.querySelector('main'),{arg,role,profile:{full_name:'Recepción QA'}});await show('oficina');});
 await page.getByText('No hay recepciones para este cliente.',{exact:false}).waitFor();
 await page.evaluate(()=>show('oficina/nueva'));
 await page.locator('#of-org').selectOption('org');await page.locator('#of-provider').selectOption('provider');
 await page.locator('#of-delivered').fill('Mensajero ficticio');
 await page.locator('[data-ars]').selectOption('ars');await page.locator('[data-service]').fill('Consulta');
 await page.locator('[data-count]').fill('1');await page.locator('[data-amount]').fill('100');
 await page.getByRole('button',{name:'+ Agregar línea'}).click();assert.equal(await page.locator('[data-office-line]').count(),2);
 await page.getByRole('button',{name:'Eliminar línea 2'}).click();
 await page.evaluate(()=>window.validationFailure=true);
 await page.getByRole('button',{name:'Guardar y abrir acuse'}).click();await page.getByText('Revise el detalle',{exact:true}).waitFor();
 assert.equal(await page.locator('#of-delivered').isDisabled(),false);
 await page.evaluate(()=>{window.validationFailure=false;window.saveTimeout=true;});
 await page.getByRole('button',{name:'Guardar y abrir acuse'}).click();await page.getByText('Ocurrió un error: Respuesta no confirmada',{exact:true}).waitFor();
 assert.equal(await page.locator('#of-delivered').isDisabled(),true);
 await page.getByRole('button',{name:'Guardar y abrir acuse'}).click();
 await page.waitForFunction(()=>location.hash.includes(window.receipt.id));
 const calls=await page.evaluate(()=>saveCalls);assert.equal(calls[1].id,calls[2].id);assert.deepEqual(calls[1].v,calls[2].v);
 await page.evaluate(()=>show('oficina/'+receipt.id));
 await page.getByRole('button',{name:'Descargar acuse en imagen'}).waitFor();
 const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Descargar acuse en imagen'}).click();const download=await downloadPromise;assert.equal(download.suggestedFilename(),'ROF-QA-001.png');
 await page.getByRole('button',{name:'Vincular reclamaciones capturadas'}).click();
 await page.locator('[data-assign]').waitFor();await page.locator('[data-assign]').click();
 await page.waitForFunction(()=>window.receipt.links.length===1);
 await page.getByRole('button',{name:'Cerrar',exact:true}).click();
 await page.locator('.pill').filter({hasText:'Conciliada'}).first().waitFor();
 assert.equal(await page.locator('.office-linked a').textContent(),'REC-QA');
 await page.getByRole('button',{name:'Desvincular',exact:true}).click();await page.waitForFunction(()=>receipt.links.length===0);
 await page.locator('#office-files').setInputFiles({name:'evidencia.png',mimeType:'image/png',buffer:Buffer.from('ficticio')});
 await page.getByText('Archivos guardados.',{exact:true}).waitFor();assert.deepEqual(await page.evaluate(()=>uploads),['evidencia.png']);
 await page.getByRole('button',{name:'Anular recepción',exact:true}).click();await page.locator('#office-cancel-reason').fill('Entrega registrada por error');
 await page.getByRole('dialog').getByRole('button',{name:'Anular recepción',exact:true}).click();await page.getByText('Anulada',{exact:true}).waitFor();
 assert.equal(await page.locator('[data-link]').count(),0);
 await page.evaluate(()=>show('oficina/'+receipt.id,'client'));assert.equal(await page.locator('#office-files').count(),0);assert.equal(await page.locator('[data-cancel-reception]').count(),0);
 await page.evaluate(()=>show('oficina/nueva','client'));await page.getByText('Su perfil solo puede consultar recepciones.',{exact:false}).waitFor();
 await page.evaluate(()=>show('oficina/nueva'));
 await page.setViewportSize({width:375,height:812});
 assert.equal(await page.locator('.office-line-fields').evaluate(el=>getComputedStyle(el).gridTemplateColumns.split(' ').length),1);
 await page.setViewportSize({width:1440,height:1000});
 if(process.env.SOFA_SCREENSHOT) await page.screenshot({path:process.env.SOFA_SCREENSHOT,fullPage:true});
 assert.deepEqual(errors,[]);
 console.log('PASS: receipt form, validation, idempotent timeout retry, PNG, claim reconciliation, evidence, cancellation, readonly roles and mobile');
}finally{await browser.close();}
