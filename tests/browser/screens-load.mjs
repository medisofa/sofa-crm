/**
 * Glosas, Reportes y la ficha de Habilitación abren y muestran datos. Usa los servicios reales; solo se simula Supabase.
 * Protege la regresión de imports con nombres viejos (#163 / #137) y el error de sintaxis de habilitation-case.js (#157).
 */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
const mocks={
 '/js/config.js':'export const CONFIG={PAGE_SIZE:25,SUPABASE_URL:"",SUPABASE_ANON_KEY:""};',
 '/js/utils/diag-log.js':'export function logDiag(){}',
 '/js/supabase.js':`
  const item={id:'it1',area:'1. Área QA',requirement:'Requisito QA',is_critical:true,status:'amarillo',notes:null,due_on:'2026-12-01',document_id:null,client_submitted_at:'2026-11-01T10:00:00Z',client_note:'nota QA',client_storage_path:'clients/o/i/a.pdf',client_file_name:'a.pdf',habilitation_requirements:{code:'QA-1',evidence_hint:'foto'}};
  const tables={
   ars:[{id:'ars1',code:'QA',name:'ARS QA'}],
   v_glosa_pareto:[{reason_name:'Motivo QA',ars_id:'ars1',ars_name:'ARS QA',amount:500}],
   v_ars_reconciliation:[{ars_id:'ars1',ars:'ARS QA',radicado:10000,pagado:0,glosa_aceptada:0,saldo:10000}],
   v_glosas:[{id:'g1',glosa_folio:'GLO-QA',folio:'RAD-QA',period:'2026-10-01',provider_name:'Dr. QA',client_name:'Cliente QA',ars_name:'ARS QA',main_reason:'Motivo QA',items:1,amount:500,in_dispute:500,status:'pendiente',appeal_deadline:'2026-12-01',days_left:5}],
   v_habilitation_cases:{id:'caso1',folio:'HAB-QA',establishment_name:'Consultorio QA',establishment_type:'Consultorio',case_kind:'apertura',stage:'correccion',ready_pct:50,verde:1,amarillo:1,rojo:0,pendiente:0,no_aplica:0,items_applicable:2,critical_open:1,fee_amount:0,organization_id:'org',operator_id:'op',renewal_seq:1},
   habilitation_items:[item],
   v_submissions:[{id:'s1',folio:'RAD-QA',client_name:'Cliente QA',provider_name:'Dr. QA',ars_name:'ARS QA',period:'2026-10-01',display_status:'radicada',lines:2,claimed:1000,paid:0,glosado:0,balance:1000}],
   v_fee_summary:[{client_name:'Cliente QA',rules:'5 %',accrued:100,uninvoiced:100,invoiced:0,collected:0,organization_id:'org'}],
   sofa_real_client_organizations:[{id:'org',legal_name:'Cliente QA'}]};
  const rpcs={
   glosa_summary_kpis:[{total_amount:500,total_in_dispute:500,total_recovered:0,total_accepted:0,total_count:1,soon_count:1,sla15_count:1,sla15_amount:500}],
   bi_events_by_month_kind:[],bi_events_by_ars_kind:[{ars_id:'ars1',kind:'radicado',total:10000}],bi_collection_days_by_ars:[{ars_id:'ars1',sum_days:60,cnt:2}],
   bi_open_balance_by_ars:[{ars_id:'ars1',ars_name:'ARS QA',total_balance:10000}],
   bi_open_balance_by_client:[{cliente:'Cliente QA',radicaciones:1,radicado:10000,pagado:0,disputa:0,saldo:10000,vencido:0}],
   bi_service_mix_agg:[{internal_code:'C-1',description:'Consulta QA',total_lines:2,total_quantity:2,total_amount:2000}],
   bi_glosa_pareto_agg:[{reason_name:'Motivo QA',category:'Admin',servicios:1,glosado:500,aceptado:0,recuperado:0}]};
  const q=(data)=>{let one=false;const p=new Proxy({},{get:(_,k)=>k==='then'?(ok)=>ok({data:one?(Array.isArray(data)?data[0]??null:data):data,count:Array.isArray(data)?data.length:0,error:null}):()=>{if(k==='maybeSingle'||k==='single')one=true;return p;}});return p;};
  export const sb=()=>({from:(t)=>q(tables[t]??[]),rpc:(n)=>{window.rpcs.push(n);return q(rpcs[n]??[]);},storage:{from:()=>({})},auth:{getUser:async()=>({data:{user:null}})}});`
};
async function open(modulo,ctx){
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 await page.route('**/*',async route=>{const p=new URL(route.request().url()).pathname;
  if(p==='/')return route.fulfill({contentType:'text/html',body:'<main></main><div id="toasts"></div>'});
  if(p==='/favicon.ico')return route.fulfill({body:''});
  return route.fulfill({contentType:p.endsWith('.css')?'text/css':'text/javascript',body:mocks[p]??await readFile(new URL(p.slice(1),root))});});
 await page.goto('http://127.0.0.1:8883/');
 await page.evaluate(async([modulo,ctx])=>{window.rpcs=[];const m=await import(modulo);await m.render(document.querySelector('main'),{...ctx,setTitle(){}});},[modulo,ctx]);
 return {page,errors};
}
const fails=[];
async function check(name,fn){try{await fn();console.log('PASS:',name);}catch(e){fails.push(name);console.log('FAIL:',name,'—',e.message.split('\n')[0]);}}
try{
 await check('Glosas: indicadores, motivos, tasa por ARS y bandeja',async()=>{
  const {page,errors}=await open('/js/modules/glosas.js',{role:'super_admin'});
  await page.locator('#par').getByText('Motivo QA').waitFor({timeout:5000});
  await page.locator('#rate').getByText('ARS QA').waitFor({timeout:5000});
  assert.match(await page.locator('#rate').innerText(),/5%/);
  await page.locator('#l').getByText('GLO-QA').waitFor({timeout:5000});
  assert.deepEqual(errors,[]);await page.close();});
 await check('Reportes: los 7 reportes muestran filas',async()=>{
  const {page,errors}=await open('/js/modules/reports.js',{role:'super_admin'});
  const esperado={mensual:'Total',ars:'ARS QA',cartera:'Cliente QA',glosas:'Motivo QA',servicios:'Consulta QA',radicaciones:'RAD-QA',honorarios:'Cliente QA'};
  for(const [key,texto] of Object.entries(esperado)){
   await page.locator('#rep').selectOption(key);
   await page.waitForFunction(([t,titulo])=>{const o=document.querySelector('#out');return o.querySelector('h2')?.textContent===titulo&&o.querySelector('tbody')?.textContent.includes(t);},
     [texto,await page.locator(`#rep option[value="${key}"]`).textContent()],{timeout:5000});
  }
  const [popup]=await Promise.all([page.waitForEvent('popup'),page.locator('#print').click()]);
  await popup.locator('table').waitFor({timeout:5000});
  assert.deepEqual(errors,[]);await page.close();});
 await check('Reportes: el médico (client) abre sin reportes internos',async()=>{
  const {page,errors}=await open('/js/modules/reports.js',{role:'client'});
  await page.locator('#out tbody').waitFor({timeout:5000});
  assert.equal(await page.locator('#rep option[value="cartera"]').count(),0);
  assert.deepEqual(errors,[]);await page.close();});
 for(const role of ['super_admin','client'])await check(`Habilitación: ficha del caso (${role})`,async()=>{
  const {page,errors}=await open('/js/modules/habilitation-case.js',{role,arg:'caso1'});
  await page.getByText('Requisito QA').first().waitFor({timeout:5000});
  assert.equal(await page.locator('.hab-item').count(),1);
  assert.deepEqual(errors,[]);await page.close();});
}finally{await browser.close();}
assert.deepEqual(fails,[],'Pantallas que fallan: '+fails.join(' | '));
