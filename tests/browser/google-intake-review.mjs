import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="dark"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/modules/contracts.js'&&!u.searchParams.has('v'))return route.fulfill({contentType:'text/javascript',body:'export const legacy=true;'});
  if(u.pathname==='/js/config.js')return route.fulfill({contentType:'text/javascript',body:'export const CONFIG={};'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB;'});
  if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  if(u.pathname==='/js/modules/clients.js')return route.fulfill({contentType:'text/javascript',body:'export const pager=()=>"";'});
  if(u.pathname==='/js/services/calidad-dato.js')return route.fulfill({contentType:'text/javascript',body:'export const cie10Suggestions=async()=>[];'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:`export const captureProviders=async()=>[{id:'p1',full_name:'Médico Prueba',organization_id:'org1'}];export const activeArs=async()=>[{id:'a1',name:'ARS Prueba'}];export const contractedServices=async()=>[{procedure_id:'proc1',name:'Consulta',amount:window.tariff}];export const listContracts=async()=>[];export const contractHistory=async()=>[];export const createContractTariff=async()=>{throw Error('Debe usar el guardado atómico')};export const setContractStatus=async()=>{};export const importContracts=async()=>{};export const searchCatalog=async()=>[];`});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  window.calls=[];window.commits={};window.tariff=850;window.auditFail=false;window.commitFail=false;window.loseReply=false;window.protect=false;
  window.mockDB={async rpc(name,args){calls.push({name,args:structuredClone(args)});
   if(name==='google_intake_drafts_v1'){
    window.testDrafts??={};const d=testDrafts[args.p_id];
    if(args.p_action==='list')return {data:{items:Object.entries(testDrafts).filter(([,r])=>!r.archived).map(([id,r])=>({id,source_name:r.payload.source_name,rows:r.payload.rows.length}))}};
    if(args.p_action==='legacy_list')return {data:{items:[]}};
    if(args.p_action==='latest')return {data:{draft:null}};
    if(args.p_action==='save'){const version=(d?.version||0)+1;testDrafts[args.p_id]={version,payload:structuredClone(args.p_payload)};return {data:{version,updated_at:new Date().toISOString()}};}
    if(args.p_action==='archive'){if(d)d.archived=true;return {data:{archived:true}};}
   }
   if(name==='log_google_intake_edit')return auditFail?{error:{message:'No se pudo registrar la bitácora',code:'23514'}}:{data:1};
   if(name==='global_patient_lookup')return {data:{match:'none'}};
   if(name==='google_intake_tariff_v1'){tariff=Number(args.p_data.amount);return {data:'tariff-new'};}
   if(name==='google_intake_review_v1'){
    const record=commits[args.p_record_id];
    if(args.p_action==='duplicates'&&window.waitDuplicates)await new Promise(resolve=>{window.releaseDup=resolve});
    if(args.p_action==='duplicates'&&window.failDuplicates)return {error:{message:'NetworkError'}};
    if(args.p_action==='duplicates')return record?{data:{duplicate:false,already_imported:true,result:record,removed:record.removed||false}}:{data:{duplicate:args.p_data.member==='EXIST',folios:args.p_data.member==='EXIST'?['F-existente']:[]}};
    if(args.p_action==='remove'){if(protect)return {error:{message:'La reclamación tiene pagos registrados',code:'23514'}};record.removed=true;return {data:{...record,removed:true}};}
    if(commitFail)return {error:{message:'No se pudo registrar la bitácora definitiva',code:'23514'}};
    const result=record||{id:'claim-'+Object.keys(commits).length,folio:'F-'+Object.keys(commits).length,amount:args.p_data.amount??tariff};commits[args.p_record_id]=result;
    if(loseReply){loseReply=false;return {error:{message:'No se recibió confirmación del servidor',code:'23514'}};}return {data:result};
   }throw Error('Unexpected '+name);
  }};
  window.intake=await import('/js/modules/google-intake.js');await intake.render(document.querySelector('main'),{role:'billing',session:{user:{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}}});
 });
 const header='Médico / Prestador *,ARS *,Fecha del servicio *,Paciente *,NSS / No. afiliado *,Servicio / Procedimiento *,No. autorización,Monto a reclamar,Cantidad\n';
 const row=(patient,member,auth,amount='',qty='1')=>`Médico Prueba,ARS Prueba,10/01/2026,${patient},${member},Consulta,${auth},${amount},${qty}\n`;
 const upload=async text=>{await page.locator('#gcsv').setInputFiles({name:'capturas.csv',mimeType:'text/csv',buffer:Buffer.from(text)});await page.locator('#validate').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled)};
 await upload(header+row('<script>Paciente uno</script>','111','AU1')+row('Paciente dos','222','AU2','750')+row('Repetida','111','AU3')+row('Existente','EXIST','AU4')+row('Paciente cinco','555','AU5','','2'));
 assert.equal(await page.locator('#import').isDisabled(),true);
 assert.equal(await page.locator('#preview tbody tr').count(),5);
 await page.locator('[data-review-filter="amount"]').click();
 assert.equal(await page.locator('#preview tbody tr').count(),1);
 assert.match(await page.locator('#preview').textContent(),/750/);
 await page.locator('[data-review-filter="duplicates"]').click();
 assert.equal(await page.locator('#preview tbody tr').count(),3);
 await page.locator('[data-review-filter="all"]').click();
 assert.equal(await page.locator('#preview tbody tr').count(),5);
 assert.equal(await page.locator('#preview script').count(),0);
 await page.getByText(/Ya existe en SoFa: F-existente/).waitFor();
 const idleColor=await page.locator('#duplicates').evaluate(e=>getComputedStyle(e).backgroundColor);
 await page.evaluate(()=>waitDuplicates=true);
 await page.locator('#duplicates').click();
 await page.waitForFunction(()=>document.querySelector('#duplicates').dataset.actionState==='running');
 assert.equal(await page.locator('#duplicates').getAttribute('aria-busy'),'true');
 await page.waitForFunction(color=>getComputedStyle(document.querySelector('#duplicates')).backgroundColor!==color,idleColor);
 assert.notEqual(await page.locator('#duplicates').evaluate(e=>getComputedStyle(e).backgroundColor),idleColor);
 assert.equal(await page.locator('#duplicates').evaluate(e=>getComputedStyle(e,'::before').animationName),'sofa-action-spin');
 assert.match(await page.locator('#gi-action-status').textContent(),/en proceso/);
 await page.evaluate(()=>{waitDuplicates=false;releaseDup()});
 await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.locator('#duplicates').getAttribute('data-action-state'),'warning');
 assert.equal(await page.locator('#duplicates').isEnabled(),true);
 assert.match(await page.locator('#gi-action-status').textContent(),/finalizada.*\d{1,2}:\d{2}:\d{2}.*Puede volver/);
 const duplicateCalls=await page.evaluate(()=>calls.filter(c=>c.name==='google_intake_review_v1'&&c.args.p_action==='duplicates').length);
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.ok(await page.evaluate(()=>calls.filter(c=>c.name==='google_intake_review_v1'&&c.args.p_action==='duplicates').length)>duplicateCalls);
 await page.evaluate(()=>failDuplicates=true);
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.locator('#duplicates').getAttribute('data-action-state'),'error');
 assert.equal(await page.locator('#duplicates').isEnabled(),true);
 await page.evaluate(()=>failDuplicates=false);
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);

 await page.evaluate(()=>auditFail=true);
 await page.locator('[data-exclude-row="4"]').click();
 await page.locator('#gi-action-reason').fill('Duplicada identificada en el archivo');
 await page.getByRole('button',{name:'Confirmar y registrar',exact:true}).click();
 await page.getByRole('alert').filter({hasText:'No se pudo registrar la bitácora'}).waitFor();
 assert.equal(await page.locator('[data-restore-row="4"]').count(),0);
 await page.evaluate(()=>auditFail=false);
 await page.getByRole('button',{name:'Confirmar y registrar',exact:true}).click();
 await page.waitForFunction(()=>!!document.querySelector('[data-restore-row="4"]'));
 await page.locator('[data-edit-row="3"]').click();
 await page.locator('dialog [name="service"]').selectOption('proc1');
 await page.locator('dialog [name="discrepancy_reason"]').fill('Acuerdo individual aprobado para esta consulta');
 await page.getByRole('button',{name:'Guardar corrección',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('dialog'));
 assert.match(await page.locator('#preview tbody tr').nth(1).textContent(),/750/);
 await page.locator('#approve').click();await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.locator('#approve').getAttribute('data-action-state'),'cancelled');
 assert.equal(await page.locator('#approve').isEnabled(),true);
 await page.locator('#approve').click();await page.getByRole('button',{name:'Aprobar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#import').disabled);
 assert.match(await page.locator('#summary').textContent(),/3 aprobada/);
 // Revalidating unchanged source and tariff must preserve recorded approvals.
 await page.locator('#validate').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.match(await page.locator('#summary').textContent(),/3 aprobada/);
 await page.evaluate(()=>commitFail=true);
 await page.locator('#import').click();await page.getByRole('button',{name:'Confirmar e importar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.evaluate(()=>Object.keys(commits).length),0);
 await page.evaluate(()=>{commitFail=false;loseReply=true});
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 await page.locator('#approve').click();await page.getByRole('button',{name:'Aprobar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#import').disabled);
 await page.locator('#import').click();await page.getByRole('button',{name:'Confirmar e importar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.evaluate(()=>Object.keys(commits).length),3);
 const payloads=await page.evaluate(()=>calls.filter(c=>c.name==='google_intake_review_v1'&&c.args.p_action==='commit').map(c=>c.args.p_data));
 assert.ok(payloads.some(p=>p.amount===750&&p.discrepancy_reason.length>=10));
 assert.ok(payloads.some(p=>p.amount===null&&p.quantity===2));
 assert.equal(await page.locator('[data-remove-row]').count(),3);
 await page.evaluate(()=>protect=true);
 await page.locator('[data-remove-row]').first().click();await page.locator('#gi-action-reason').fill('Registro equivocado durante la carga');
 await page.getByRole('button',{name:'Confirmar y registrar',exact:true}).click();
 await page.getByRole('alert').filter({hasText:'pagos registrados'}).waitFor();
 await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 await page.evaluate(()=>protect=false);
 await page.locator('[data-remove-row]').first().click();await page.locator('#gi-action-reason').fill('Registro equivocado durante la carga');await page.getByRole('button',{name:'Confirmar y registrar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('dialog'));
 await upload(header+row('Paciente nuevo','777','AU7'));
 await page.locator('[data-tariff-row]').click();
 await page.locator('#k_m').fill('900');await page.locator('#k_f').fill('2026-01-01');
 await page.getByRole('button',{name:'Registrar',exact:true}).click();
 assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='google_intake_tariff_v1').length),0);
 await page.locator('#k_n').fill('Nueva vigencia contractual autorizada');await page.getByRole('button',{name:'Registrar',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('dialog'));
 assert.equal(await page.evaluate(()=>tariff),900);assert.equal(await page.locator('#import').isDisabled(),true);
 await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 await page.evaluate(async()=>{await intake.render(document.querySelector('main'),{role:'operations',session:{user:{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}}});});
 await upload(header+'\n'+row('Operaciones','999','AU9','750'));
 assert.equal(await page.locator('[data-edit-row="3"]').count(),1);
 assert.equal(await page.locator('[data-tariff-row]').count(),0);
 await page.getByText(/El ajuste de monto requiere autorización/).waitFor();

 await upload(header+row('Paciente sin médico','900','AU900').replace('Médico Prueba','Médico desconocido'));
 assert.equal(await page.locator('#duplicates').getAttribute('data-action-state'),null);
 await page.locator('#duplicates').click();await page.waitForFunction(()=>!document.querySelector('#gcsv').disabled);
 assert.equal(await page.locator('#duplicates').getAttribute('data-action-state'),'warning');
 assert.match(await page.locator('#gi-action-status').textContent(),/0 fila\(s\) comprobadas.*1 sin comprobar/);
 assert.equal(await page.locator('#duplicates').isEnabled(),true);
 assert.deepEqual(errors,[]);
 console.log('PASS: feedback en proceso/finalización/hora, repetición, errores y filas no comprobables; revisión obligatoria, edición con motivo, exclusión, duplicadas del archivo/SoFa, aprobación, monto real, bitácora fallida, recuperación de respuesta perdida, eliminación protegida, nueva vigencia autorizada y móvil.');
}finally{await browser.close();}
