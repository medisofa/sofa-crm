/** Tarifario: datos ficticios, sin conexión a Supabase ni cambios de datos reales. */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
const fakeClaims=`
export async function listContracts(args={}){
 window.reads.push(structuredClone(args));let rows=window.tariffs;
 if(args.providerId)rows=rows.filter(r=>r.provider_id===args.providerId);
 if(args.arsId)rows=rows.filter(r=>r.ars_id===args.arsId);
 if(args.status)rows=rows.filter(r=>r.status===args.status);
 if(args.onlyCurrent)rows=rows.filter(r=>r.is_current);
 if(args.q)rows=rows.filter(r=>[r.service_name,r.internal_code,r.contract_ref].join(' ').toLowerCase().includes(args.q.toLowerCase()));
 return {data:structuredClone(rows),count:rows.length};
}
export async function contractHistory(provider,ars,procedure,plan=null){window.historyReads.push({provider,ars,procedure,plan});return structuredClone(window.tariffHistory.filter(row=>(row.plan_id||null)===(plan||null)));}
export async function createContractTariff(args){window.creates.push(structuredClone(args));return {id:'created'};}
export async function setContractStatus(id,status,notes){window.statusWrites.push({id,status,notes});return {id};}
export async function importContracts(rows,commit){window.imports.push({rows,commit});return {errors:[],valid:rows.length,imported:commit?rows.length:0,rows:[]};}
export async function captureProviders(){return [{id:'doctor-a',full_name:'Dra. de prueba A'},{id:'doctor-b',full_name:'Dr. de prueba B'}];}
export async function activeArs(){return [{id:'ars-a',name:'ARS de prueba A'},{id:'ars-b',name:'ARS de prueba B'}];}
export async function searchCatalog(){return [{id:'procedure',name:'CONSULTA AMBULATORIA',internal_code:'SOFA-P07',simon:'2467',cups:null},{id:'other-procedure',name:'CONSULTA ESPECIALIZADA',internal_code:'OTRA'}];}
`;
try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.clock.install({time:new Date('2026-11-10T14:00:00Z')});
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="dark"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:fakeClaims});
  if(u.pathname==='/js/modules/clients.js')return route.fulfill({contentType:'text/javascript',body:'export const pager=()=>"";'});
  if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:`export const sb=()=>({rpc:async(name,args)=>{window.rpcs.push({name,args:structuredClone(args)});if(name==='change_contract_tariff_price'){const row=window.tariffs.find(r=>r.id===args.p_tariff);window.savedBefore=structuredClone(row);window.tariffHistory.push({id:row.id,plan_id:row.plan_id||null,amount:row.amount,currency:'DOP',valid_from:row.valid_from,valid_to:args.p_effective,status:'vigente',claims:row.claims});row.amount=args.p_amount;row.valid_from=args.p_effective;return {data:{id:'replacement'}};}return {data:null};}});`});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return route.fulfill({status:404,body:'Missing '+u.pathname});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  window.reads=[];window.rpcs=[];window.creates=[];window.statusWrites=[];window.imports=[];window.historyReads=[];
  const base={provider_name:'Dra. de prueba A',client_name:'Consultorio de prueba',ars_name:'ARS de prueba A',service_name:'CONSULTA AMBULATORIA',internal_code:'SOFA-P07',ars_service_code:'2467',simon:'2467',cups:null,currency:'DOP',valid_from:'2026-10-01',valid_to:null,is_current:true,contract_ref:'CONTRATO-QA',source:'Prueba',claims:3,provider_id:'doctor-a',ars_id:'ars-a',procedure_id:'procedure',status:'vigente',plan_id:null,plan_name:null};
  window.tariffs=[{...base,id:'general',amount:750},{...base,id:'plan',amount:950,plan_id:'plan-specific',plan_name:'Plan de prueba'},{...base,id:'other',amount:1200,service_name:'CONSULTA ESPECIALIZADA',internal_code:'OTRA',provider_name:'Dr. de prueba B',provider_id:'doctor-b',ars_name:'ARS de prueba B',ars_id:'ars-b',procedure_id:'other-procedure'}];
  window.tariffHistory=[{id:'plan-history',plan_id:'plan-specific',amount:950,currency:'DOP',valid_from:'2026-09-01',valid_to:'2026-10-01',status:'vigente',claims:2}];window.mod=await import('/js/modules/contracts.js');window.ctx={role:'admin',viewAs:null};window.renderTariffs=async next=>{Object.assign(ctx,next||{});await mod.render(document.querySelector('main'),ctx);};await renderTariffs();
 });
 await page.waitForFunction(()=>document.querySelectorAll('[data-change]').length===3);
 for(const id of ['q','cp','ca','cs']){const label=page.locator('label[for="'+id+'"]');assert.ok(await label.count(),'Filtro con etiqueta '+id);assert.equal(await label.evaluate(el=>el.classList.contains('sr-only')),false,'Etiqueta visible '+id);}
 if(process.env.SOFA_TARIFF_SCREENSHOTS)await page.screenshot({path:'/tmp/tariff-workspace-desktop.png',fullPage:true});
 assert.equal(await page.locator('#cur').isChecked(),true);assert.equal(await page.locator('main script').count(),0);
 await page.locator('#cp').selectOption('doctor-a');await page.waitForFunction(()=>document.querySelectorAll('[data-change]').length===2);
 await page.locator('#ca').selectOption('ars-a');await page.waitForFunction(()=>reads.at(-1).arsId==='ars-a');assert.match(await page.locator('#tariff-summary').textContent(),/2/);
 for(const width of [1440,390,320]){await page.setViewportSize({width,height:1050});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin desbordamiento '+width);if(width===390&&process.env.SOFA_TARIFF_SCREENSHOTS)await page.screenshot({path:'/tmp/tariff-workspace-mobile.png',fullPage:true});}
 await page.setViewportSize({width:1440,height:1050});
 await page.locator('#q').fill('ESPECIALIZADA');await page.clock.fastForward(400);await page.waitForFunction(()=>document.querySelectorAll('[data-change]').length===0);await page.locator('#clear-filters').click();await page.waitForFunction(()=>document.querySelectorAll('[data-change]').length===3);assert.equal(await page.locator('#q').inputValue(),'');assert.equal(await page.locator('#cp').inputValue(),'');assert.equal(await page.locator('#ca').inputValue(),'');
 await page.locator('[data-change="general"]').click();await page.getByRole('dialog',{name:'Cambiar precio',exact:true}).waitFor();
 assert.equal(Number(await page.locator('#te_amount').inputValue()),750);
 await page.locator('#te_amount').fill('0');await page.locator('#te_effective').fill('2026-11-10');await page.locator('#te_reason').fill('Ajuste administrativo documentado');await page.locator('dialog button[type="submit"]').click();assert.equal(await page.evaluate(()=>rpcs.length),0,'Precio cero bloqueado');
 await page.locator('#te_amount').fill('800');await page.locator('#te_reason').fill('corto');await page.locator('dialog button[type="submit"]').click();assert.equal(await page.evaluate(()=>rpcs.length),0,'Motivo corto bloqueado');
 await page.locator('#te_reason').fill('Ajuste administrativo documentado');await page.locator('#te_effective').fill('');await page.locator('dialog button[type="submit"]').click();assert.equal(await page.evaluate(()=>rpcs.length),0,'Fecha obligatoria');
 await page.locator('#te_effective').fill('2026-11-10');await page.locator('dialog button[type="submit"]').click();await page.waitForFunction(()=>!document.querySelector('dialog'));
 const mutation=await page.evaluate(()=>rpcs.find(r=>r.name==='change_contract_tariff_price'));assert.deepEqual(mutation.args,{p_tariff:'general',p_amount:800,p_effective:'2026-11-10',p_reason:'Ajuste administrativo documentado'});
 assert.equal(await page.evaluate(()=>tariffs.find(r=>r.id==='plan').amount),950,'Cambiar tarifa general no envía otro plan');assert.equal(await page.evaluate(()=>tariffs.find(r=>r.id==='other').amount),1200,'No cambia otros servicios');assert.equal(await page.evaluate(()=>creates.length+statusWrites.length+imports.length),0,'Edición no usa importación ni UPDATE de estado');
 await page.locator('[data-change="general"]').click();assert.equal(Number(await page.locator('#te_amount').inputValue()),800,'Edición posterior conserva el precio actual');await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 await page.locator('[data-details="general"]').click();await page.locator('[data-hist="general"]').click();await page.getByRole('dialog').waitFor();await page.waitForFunction(()=>historyReads.length===1);assert.match(await page.getByRole('dialog').textContent(),/750/);assert.match(await page.getByRole('dialog').textContent(),/conservan|historial|vigencia/i);await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 assert.equal(await page.evaluate(()=>historyReads[0].plan),null,'Historial general pide plan general');await page.locator('[data-details="plan"]').click();await page.locator('[data-hist="plan"]').click();await page.waitForFunction(()=>historyReads.length===2);assert.equal(await page.evaluate(()=>historyReads[1].plan),'plan-specific');assert.match(await page.getByRole('dialog').textContent(),/950/);assert.doesNotMatch(await page.getByRole('dialog').textContent(),/750/);await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 await page.evaluate(async()=>{window.parserResult=mod.parseContractRows('Médico;ARS;Servicio;Tarifa;Desde\nDra QA;ARS QA;SOFA-P07;750;10/11/2026');});assert.equal(await page.evaluate(()=>parserResult[0].tarifa),'750');assert.equal(await page.evaluate(()=>parserResult[0].servicio),'SOFA-P07');
 const before=await page.evaluate(()=>rpcs.length+creates.length+statusWrites.length+imports.length);
 await page.evaluate(async()=>{await renderTariffs({viewAs:{orgId:'org'}});});await page.waitForFunction(()=>document.querySelector('tbody'));
 assert.equal(await page.locator('[data-change],[data-st],#new,#imp').count(),0,'Soporte sin acciones mutantes');assert.equal(await page.locator('[data-hist]').count()>0,true,'Historial permanece accesible');assert.equal(await page.evaluate(()=>rpcs.length+creates.length+statusWrites.length+imports.length),before);
 await page.evaluate(async()=>{await renderTariffs({role:'client',viewAs:null});});await page.waitForFunction(()=>document.querySelector('tbody'));assert.equal(await page.locator('[data-change],[data-st],#new,#imp').count(),0,'Cliente sin permiso no edita tarifa contractual');
 assert.deepEqual(errors,[]);console.log('PASS: filtros visibles, edición por tarifa exacta y motivo/fecha, planes independientes, historial, parser de importación, soporte readonly y móvil');
}finally{await browser.close();}
