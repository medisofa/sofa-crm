/** Inicio clínico: consultas acotadas, soporte sin escrituras, permisos y distribución. Datos ficticios. */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
const fakeBackend=`
function query(table){
 const spec={table,filters:[],orders:[],columns:null,options:null,limit:null};
 const q={select(columns,options){spec.columns=columns;spec.options=options;return q;},eq(k,v){spec.filters.push(['eq',k,v]);return q;},neq(k,v){spec.filters.push(['neq',k,v]);return q;},in(k,v){spec.filters.push(['in',k,v]);return q;},order(k,v){spec.orders.push([k,v]);return q;},limit(v){spec.limit=v;return q;},
 then(resolve,reject){window.reads.push(structuredClone(spec));let rows=window.fixture.appointments;
  for(const [op,k,v] of spec.filters){rows=rows.filter(r=>op==='eq'?r[k]===v:op==='neq'?r[k]!==v:v.includes(r[k]));}
  const failed=window.fixture.failAgenda&&!spec.options?.head || window.fixture.failStatus&&spec.filters.some(f=>f[1]==='status'&&f[2]===window.fixture.failStatus);
  if(failed)return Promise.resolve({data:null,count:null,error:{message:'NetworkError: prueba controlada'}}).then(resolve,reject);
  rows=[...rows].sort((a,b)=>(a.appointment_time||'99').localeCompare(b.appointment_time||'99')||a.id.localeCompare(b.id));
  return Promise.resolve({data:spec.options?.head?null:rows.slice(0,spec.limit||rows.length),count:rows.length,error:null}).then(resolve,reject);
 }};return q;
}
export const sb=()=>({from:query,rpc:async(name,args)=>{window.rpcs.push({name,args});if(name.startsWith('set_'))window.writes.push({name,args});return {data:name==='my_dashboard'?window.fixture.admin:name==='my_dashboard_view'?'ejecutivo':true,error:null};}});`;
try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.clock.install({time:new Date('2026-11-10T02:30:00Z')});
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="dark"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page" id="main"></main></html>'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:fakeBackend});
  if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'image/png'});}catch{return route.fulfill({status:404,body:'Missing '+u.pathname});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  window.reads=[];window.rpcs=[];window.writes=[];
  const statuses=['programada','confirmada','en_espera','en_consulta','atendida','cancelada'];
  window.fixture={appointments:statuses.map((status,i)=>({id:'appt-'+i,organization_id:'org-clinic',appointment_date:'2026-11-09',appointment_time:String(8+i).padStart(2,'0')+':00',patient_name:i===0?'<script>Paciente ficticio</script>':'Paciente ficticio '+i,status,provider_id:'doctor',providers:{full_name:'Dra. Ejemplo'},payer_type:i%2===0?'ars':'privado',authorization_number:i===0?null:'AUT-'+i,eligibility_status:i===2?'no_verificada':'verificada'})),admin:{sections:[{code:'direccion',title:'Administración',kpis:[{code:'cartera_ars',label:'Cartera ARS ficticia',value:750,unit:'RD$',level:'normal'},{code:'clientes_activos',label:'Clientes activos',value:3,level:'normal'}],shortcuts:['agenda']}]}};
  fixture.appointments.push({id:'foreign',organization_id:'org-foreign',appointment_date:'2026-11-09',appointment_time:'07:00',patient_name:'NO DEBE MOSTRARSE',status:'programada',provider_id:'other'});
  window.ctx={role:'client',profile:{full_name:'Dra. Ejemplo'},membership:{organization_id:'org-clinic',organization:'Consultorio ficticio'},viewAs:null};
  window.dashboard=await import('/js/modules/dashboard-rol.js');window.clinicalService=await import('/js/services/clinical-dashboard.js');
  window.renderTest=async(next={})=>{Object.assign(ctx,next);await dashboard.render(document.querySelector('main'),ctx);};
  await renderTest();
 });
 assert.equal(await page.locator('.clinical-home').count(),1);
 assert.equal(await page.evaluate(()=>clinicalService.clinicalDay(new Date('2026-11-10T02:30:00Z'))),'2026-11-09');
 assert.equal(await page.evaluate(()=>rpcs.some(r=>r.name==='my_dashboard')),false,'Médico no consulta dashboard staff');
 assert.equal(await page.getByText('NO DEBE MOSTRARSE',{exact:true}).count(),0);
 assert.equal(await page.locator('main script').count(),0);
 const reads=await page.evaluate(()=>reads);assert.ok(reads.length>=5);
 for(const q of reads){assert.equal(q.table,'appointments');assert.ok(q.filters.some(f=>f[1]==='organization_id'&&f[2]==='org-clinic'));assert.ok(q.filters.some(f=>f[1]==='appointment_date'&&f[2]==='2026-11-09'));}
 assert.ok(reads.some(q=>q.limit===8&&!q.options?.head),'Agenda limitada a ocho filas');
 assert.ok(reads.some(q=>q.filters.some(f=>f[0]==='in'&&f[1]==='status')),'Query next filtra por status programada/confirmada/en_espera');
 assert.equal(await page.locator('.clinical-row').count(),5,'Canceladas excluidas');
 assert.equal(await page.locator('.clinical-next').count(),1,'Tarjeta de siguiente cita visible');
 assert.equal(await page.locator('.clinical-home').evaluate(el=>el.textContent.includes('Clientes activos')),false);
 async function linksAllowed(){assert.equal(await page.evaluate(async()=>{const {canSee}=await import('/js/utils/permissions.js');return [...document.querySelectorAll('main a[href^="#/"]')].every(a=>canSee(a.getAttribute('href').slice(2).split('/')[0],ctx.role));}),true,'Todos los enlaces respetan canSee');}
 await linksAllowed();
 const allModules=page.locator('.clinical-modules summary');assert.equal(await allModules.count(),1);await allModules.focus();await page.keyboard.press('Space');assert.equal(await page.locator('.clinical-modules').getAttribute('open'),'');await page.keyboard.press('Space');assert.equal(await page.locator('.clinical-modules').getAttribute('open'),null);
 for(const width of [1440,390,320]){await page.setViewportSize({width,height:1000});if(process.env.SOFA_SCREENSHOT_DIR&&width!==320)await page.screenshot({path:process.env.SOFA_SCREENSHOT_DIR+'/sofa-clinical-'+(width===1440?'desktop':'mobile')+'.png',fullPage:true});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin overflow a '+width);}
 await page.setViewportSize({width:1440,height:1100});
 await page.evaluate(async()=>{reads=[];rpcs=[];writes=[];await renderTest({viewAs:{orgId:'org-clinic',orgName:'Consultorio ficticio',role:'client'}});});
 assert.equal(await page.locator('.clinical-home').count(),1);assert.deepEqual(await page.evaluate(()=>writes),[]);assert.equal(await page.evaluate(()=>rpcs.some(r=>r.name==='my_dashboard')),false);
 for(const role of ['capturer','asistente']){
  await page.evaluate(async role=>{reads=[];rpcs=[];await renderTest({role,viewAs:{orgId:'org-clinic',orgName:'Consultorio ficticio',targetName:'Usuario de prueba',role}});},role);
  assert.equal(await page.evaluate(()=>reads.length),0,'Soporte '+role+' no simula asignaciones');
  assert.equal(await page.evaluate(()=>rpcs.length),0);assert.match(await page.locator('main').textContent(),/soporte|asignaci|vista/i);await linksAllowed();
 }
 await page.evaluate(async()=>{reads=[];rpcs=[];await renderTest({role:'client',viewAs:{orgId:'org-clinic',orgName:'Consultorio ficticio',targetName:'Médico individual',role:'client'}});});
 assert.equal(await page.evaluate(()=>reads.length),0,'Soporte de un médico individual no usa permisos amplios');
 await page.evaluate(async()=>{reads=[];window.noOrgResult=await clinicalService.loadClinicalDashboard({role:'client',membership:{}});});
 assert.equal(await page.evaluate(()=>reads.length),0,'Sin consultorio no consulta agenda global');assert.ok(await page.evaluate(()=>noOrgResult.unavailable));
 await page.evaluate(async()=>{fixture.appointments=[];await renderTest({role:'client',viewAs:null});});
 assert.equal(await page.locator('.clinical-row').count(),0);assert.match(await page.locator('.clinical-agenda').textContent(),/sin citas|no hay citas|no tienes citas/i);
 await page.evaluate(async()=>{fixture.failAgenda=true;await renderTest();});
 assert.match(await page.locator('.clinical-agenda').textContent(),/no se pudo|no pudimos|no disponible|error|conexión/i);
 await page.evaluate(async()=>{fixture.failAgenda=false;fixture.failStatus='en_espera';window.failedMetrics=await clinicalService.loadClinicalDashboard(ctx);});
 assert.equal(await page.evaluate(()=>failedMetrics.metrics.waiting),null,'Fallo de lectura no se presenta como cero');
 await page.evaluate(async()=>{fixture.failStatus=null;reads=[];rpcs=[];await renderTest({role:'admin',viewAs:null});});
 assert.match(await page.locator('main').textContent(),/Cartera ARS ficticia/);assert.equal(await page.locator('.clinical-home').count(),0);assert.ok(await page.evaluate(()=>rpcs.some(r=>r.name==='my_dashboard')));await linksAllowed();
 const toggle=page.locator('.dash-viewbar-toggle');await toggle.focus();await page.keyboard.press('Space');assert.equal(await toggle.getAttribute('aria-expanded'),'true');assert.equal(await toggle.evaluate(el=>el===document.activeElement),true,'Foco conservado al abrir selector');
 const next=page.locator('.dash-view-btn[aria-pressed="false"]').first();await next.focus();await page.keyboard.press('Enter');await page.waitForFunction(()=>document.querySelector('.dash-viewbar-toggle')?.getAttribute('aria-expanded')==='false');assert.equal(await toggle.evaluate(el=>el===document.activeElement),true,'Foco vuelve al selector al elegir vista');
 assert.ok(await page.evaluate(()=>writes.some(w=>w.name==='set_my_dashboard_view')));
 // pickNext y coverageAlert
 const pickResult=await page.evaluate(()=>{
  const {pickNext,coverageAlert,clinicalClock}=clinicalService;
  const now=new Date('2026-11-09T14:00:00-04:00');
  const rows=[{id:'1',appointment_time:'09:00',status:'programada',payer_type:'ars',authorization_number:null},{id:'2',appointment_time:'10:30',status:'confirmada',payer_type:'privado'},{id:'3',appointment_time:'11:00',status:'programada',payer_type:'ars',authorization_number:'AUT-123',eligibility_status:'no_verificada'}];
  const next=pickNext(rows,now);
  return {nextId:next?.id,clock:clinicalClock(now),alertNoAuth:coverageAlert(rows[0]),alertPrivado:coverageAlert(rows[1]),alertNoVerif:coverageAlert(rows[2]),alertNull:coverageAlert(null)};
 });
 assert.equal(pickResult.nextId,'1','pickNext devuelve la primera cita aún pendiente');
 assert.equal(pickResult.clock,'14:00');
 assert.equal(pickResult.alertNoAuth.tone,'bad','Falta autorización → tono bad');
 assert.equal(pickResult.alertPrivado,null,'Privado sin alerta');
 assert.equal(pickResult.alertNoVerif.tone,'warn','No verificada → tono warn');
 assert.equal(pickResult.alertNull,null);
 // pickNext: todas pasadas devuelve la primera
 const pickAllPast=await page.evaluate(()=>{
  const {pickNext}=clinicalService;
  const rows=[{id:'a',appointment_time:'07:00',status:'programada'},{id:'b',appointment_time:'08:00',status:'confirmada'}];
  return pickNext(rows,new Date('2026-11-09T18:00:00-04:00'))?.id;
 });
 assert.equal(pickAllPast,'a','Todas pasadas → primera');
 // alert con autorización completa
 const alertOk=await page.evaluate(()=>clinicalService.coverageAlert({payer_type:'ars',authorization_number:'AUT-999',eligibility_status:'verificada'}));
 assert.equal(alertOk,null,'ARS con autorización y verificada → sin alerta');
 assert.deepEqual(errors,[]);console.log('PASS: inicio clínico acotado por organización y fecha RD, soporte sin escrituras ni asignaciones simuladas, permisos, móvil, vacíos, fallos, admin, selector con teclado, siguiente cita y alertas de cobertura.');
}finally{await browser.close();}
