/** Synthetic banking desk; no external network or real payment data. */
import assert from 'node:assert/strict';
import {readFile,mkdir}from'node:fs/promises';
const{chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1500,height:1120},locale:'es-DO'});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',()=>{throw Error('Native prompt must not be used');});
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();const path=u.pathname;
  if(path==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><link rel="stylesheet" href="/css/reconciliation-workspace.css"><main class="page"></main></html>'});
  if(path==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>({rpc:async(name,args)=>{try{return {data:await window.mockRpc(name,args)}}catch(e){return {error:{message:e.message}}}}});'});
  if(path==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  if(path==='/js/services/reconciliation-workspace.js')return route.fulfill({contentType:'text/javascript',body:`export async function bankWorkspaceClaims(args){window.workspaceReads.push(args);if(window.claimFailure)throw Error('No se pudo leer aplicaciones');return [{line_id:'line-a',folio:'REC-EJEMPLO-001',submission_id:'sub-a',submission_folio:'RAD-EJEMPLO-001',authorization_number:'00123456789',service_name:'Consulta de ejemplo',claimed:750,applied:500,balance:250}];}`});
  try{return route.fulfill({body:await readFile(new URL(path.slice(1),root)),contentType:path.endsWith('.css')?'text/css':path.endsWith('.js')?'text/javascript':'text/plain'});}catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8897/');
 await page.evaluate(async()=>{
  window.calls=[];window.workspaceReads=[];window.writes=[];window.failMatch=false;
  window.movements=[
   {id:'dep-a',date:'2026-11-09',description:'Depósito de ejemplo A',reference:'REF-EJEMPLO-001',amount:1500,ars:'ARS de ejemplo',ars_guess:'ars-a',status:'sin_conciliar',candidates:[{payment_id:'pay-a',folio:'PAG-EJEMPLO-001',ars:'ARS de ejemplo',paid_on:'2026-11-09',amount:1500,reference:'REF-EJEMPLO-001'}]},
   {id:'dep-b',date:'2026-11-08',description:'Depósito de ejemplo B',reference:'REF-EJEMPLO-002',amount:1450,ars:'ARS de ejemplo',ars_guess:'ars-a',status:'sin_conciliar',candidates:[{payment_id:'pay-b',folio:'PAG-EJEMPLO-002',ars:'ARS de ejemplo',paid_on:'2026-11-09',amount:1500}]},
   {id:'dep-c',date:'2026-11-07',description:'Depósito conciliado ejemplo',reference:'REF-EJEMPLO-003',amount:750,ars:'ARS de ejemplo',status:'conciliado',payment:{id:'pay-c',folio:'PAG-EJEMPLO-003',ars:'ARS de ejemplo',paid_on:'2026-11-07',amount:750},difference:0}
  ];
  window.mockRpc=async(name,args)=>{
   calls.push({name,args});
   if(name==='bank_overview')return [{organization_id:'org-a',client:'Consultorio de ejemplo',pending:2},{organization_id:'org-b',client:'Otro consultorio de ejemplo',pending:0}];
   if(name==='bank_reconciliation')return {summary:{deposits:3,deposits_amount:3700,matched:1,matched_amount:750,pending:2,pending_amount:2950,differences:0},movements:structuredClone(movements),payments_without_deposit:[],partial:[{id:'sub-a',folio:'RAD-EJEMPLO-001',ars:'ARS de ejemplo',submitted_on:'2026-10-01',claimed:1500,paid:500,glosa_accepted:0,balance:1000,pct:33.33}],unpaid_overdue:[],statements:[],payment_term_days:30};
   if(name==='ars_catalog')return [{id:'ars-a',name:'ARS de ejemplo'}];
   if(name==='bank_open_submissions')return [{id:'sub-a',folio:'RAD-EJEMPLO-001',submitted_on:'2026-10-01',provider:'Médico de ejemplo',balance:2000}];
   if(name==='bank_import'){if(args.p_commit)writes.push({name,args});return {errors:[],deposits:1,withdrawals_skipped:0,duplicates:0,rows:[{date:'2026-11-10',description:'Depósito CSV ficticio',reference:'REF-CSV',amount:750,ars:'ARS de ejemplo'}],auto_matched:0};}
   if(name==='bank_match'){if(failMatch)throw Error('No se pudo asociar');const m=movements.find(x=>x.id===args.p_movement),p=m.candidates.find(x=>x.payment_id===args.p_payment);writes.push({name,args});m.status='conciliado';m.payment={...p,id:p.payment_id};m.difference=m.amount-p.amount;m.note=args.p_note;return true;}
   if(name==='bank_unmatch'){writes.push({name,args});movements.find(x=>x.id===args.p_movement).status='sin_conciliar';return true;}
   if(name==='bank_ignore'){writes.push({name,args});const m=movements.find(x=>x.id===args.p_movement);m.status='no_ars';m.note=args.p_reason;return true;}
   if(name==='bank_register_payment'){writes.push({name,args});const m=movements.find(x=>x.id===args.p_movement);m.status='conciliado';m.payment={id:'pay-new',folio:'PAG-EJEMPLO-NUEVO',amount:m.amount,paid_on:m.date,ars:'ARS de ejemplo'};return true;}
   throw Error('Unexpected RPC '+name);
  };
  window.mod=await import('/js/modules/conciliacion.js');window.show=async(role='admin',viewAs=null)=>mod.render(document.querySelector('main'),{role,viewAs});await show();
 });
 assert.equal(await page.getByRole('heading',{name:'Mesa de conciliación',exact:true}).count(),1);
 assert.equal(await page.locator('#bk-payment').inputValue(),'','Pago no preseleccionado');
 await page.locator('#bk-payment').selectOption('pay-a');await page.waitForFunction(()=>workspaceReads.some(x=>x.paymentId==='pay-a'));
 assert.equal(await page.evaluate(()=>writes.length),0);
 assert.match(await page.locator('.rw-review').textContent(),/Depósito − pago/);
 assert.equal(await page.locator('.rw-review .rw-data-card dt').count(),10,'Datos de comparación renderizados como nodos');
 assert.doesNotMatch(await page.locator('.rw-review').textContent(),/\[object HTML/);
 assert.match(await page.locator('.rw-review .rw-data-card').first().textContent(),/REF-EJEMPLO-001/);
 await page.locator('#bk-confirm-match').click();await page.getByRole('dialog',{name:'Confirmar asociación bancaria',exact:true}).waitFor();
 await page.getByRole('button',{name:'Cancelar',exact:true}).click();assert.equal(await page.evaluate(()=>writes.length),0);
 await page.locator('#bk-query').fill('REF-EJEMPLO-002');assert.equal(await page.locator('[data-movement]').count(),1);await page.locator('#bk-query').fill('');
 await page.locator('[data-movement="dep-b"]').click();await page.locator('#bk-payment').selectOption('pay-b');
 await page.locator('#bk-confirm-match').click();await page.locator('#bk-difference-note').fill('corto');await page.getByRole('button',{name:'Confirmar asociación',exact:true}).click();assert.equal(await page.locator('#bk-difference-note').getAttribute('aria-invalid'),'true');
 await page.locator('#bk-difference-note').fill('Retención documentada de ejemplo.');await page.evaluate(()=>failMatch=true);await page.getByRole('button',{name:'Confirmar asociación',exact:true}).click();await page.getByRole('dialog').getByRole('alert').waitFor();assert.equal(await page.locator('#bk-difference-note').inputValue(),'Retención documentada de ejemplo.');
 await page.evaluate(()=>failMatch=false);await page.getByRole('button',{name:'Confirmar asociación',exact:true}).click();await page.getByRole('dialog').waitFor({state:'detached'});await page.waitForFunction(()=>writes.length===1);
 assert.deepEqual(await page.evaluate(()=>writes[0]),{name:'bank_match',args:{p_movement:'dep-b',p_payment:'pay-b',p_note:'Retención documentada de ejemplo.'}});
 await page.getByRole('button',{name:'Deshacer asociación',exact:true}).click();await page.getByRole('dialog',{name:'Deshacer conciliación',exact:true}).getByRole('button',{name:'Deshacer',exact:true}).click();await page.waitForFunction(()=>writes.length===2);assert.equal(await page.evaluate(()=>writes[1].name),'bank_unmatch');
 await page.locator('#bk-authorization-search').fill('00123456789');await page.locator('#bk-search-authorization').click();await page.waitForFunction(()=>workspaceReads.some(x=>x.search==='00123456789'&&x.paymentId===null));
 await page.locator('#bk-claims a[href="#/reclamaciones/line-a"]').waitFor();assert.equal(await page.evaluate(()=>writes.length),2,'Buscar autorización no asocia pagos');
 if(process.env.SOFA_RECONCILIATION_SCREENSHOTS){await mkdir('/workspace/artifacts/reconciliation-workspace',{recursive:true});await page.screenshot({path:'/workspace/artifacts/reconciliation-workspace/mesa.png',fullPage:true});}
 for(const width of[1500,1000,768,390,320]){await page.setViewportSize({width,height:1000});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Sin overflow '+width);}
 await page.setViewportSize({width:1500,height:1120});
 await page.locator('[data-movement="dep-a"]').click();await page.getByRole('button',{name:'Registrar el pago de la ARS',exact:true}).click();await page.getByRole('button',{name:'Registrar y conciliar',exact:true}).waitFor();await page.getByRole('button',{name:'Registrar y conciliar',exact:true}).click();await page.getByRole('dialog',{name:'Registrar pago y conciliar',exact:true}).getByRole('button',{name:'Registrar y conciliar',exact:true}).click();await page.waitForFunction(()=>writes.some(x=>x.name==='bank_register_payment'));
 assert.deepEqual(await page.evaluate(()=>writes.find(x=>x.name==='bank_register_payment').args),{p_movement:'dep-a',p_ars:'ars-a',p_allocations:[{submission_id:'sub-a',amount:1500}]});
 await page.locator('[data-movement="dep-b"]').click();await page.getByRole('button',{name:'No es de ARS',exact:true}).click();await page.locator('#bk-ignore-reason').fill('Depósito privado identificado.');await page.getByRole('button',{name:'Confirmar clasificación',exact:true}).click();await page.waitForFunction(()=>writes.some(x=>x.name==='bank_ignore'));
 await page.locator('.rw-upload>summary').click();await page.locator('#bk-bank').fill('Banco de ejemplo');await page.locator('#bk-file').setInputFiles({name:'estado-ejemplo.csv',mimeType:'text/csv',buffer:Buffer.from('Fecha,Descripción,Referencia,Monto\n10/11/2026,Depósito CSV ficticio,REF-CSV,750\n')});await page.getByRole('button',{name:'Revisar el archivo',exact:true}).click();await page.getByRole('button',{name:/Confirmar: guardar 1/}).waitFor();assert.equal(await page.evaluate(()=>writes.some(x=>x.name==='bank_import')),false);await page.getByRole('button',{name:/Confirmar: guardar 1/}).click();await page.waitForFunction(()=>writes.some(x=>x.name==='bank_import'));
 const beforeSupport=await page.evaluate(()=>writes.length);await page.evaluate(()=>show('admin',{orgId:'org-a'}));assert.equal(await page.getByRole('button',{name:'Deshacer asociación',exact:true}).count(),0);assert.equal(await page.locator('.rw-upload').count(),0);assert.equal(await page.getByRole('button',{name:'Registrar el pago de la ARS',exact:true}).count(),0);assert.equal(await page.evaluate(()=>writes.length),beforeSupport);
 assert.deepEqual(errors,[]);console.log('PASS conciliación: comparación explícita, motivo/confirmación, error recuperable, búsqueda autorización readonly, aplicación separada, registrar/deshacer/noARS/importación conservados, soporte y móvil.');
}finally{await browser.close();}
