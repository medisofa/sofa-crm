/** Patient flow UI with fictional patients; no external services or clinical data. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1760,height:1100}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.clock.install({time:new Date('2026-11-10T14:00:00Z')});
 await page.route('**/*',async request=>{
  const u=new URL(request.request().url());if(u.hostname!=='127.0.0.1')return request.abort();
  if(u.pathname==='/preview.html')return request.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/services/claims.js')return request.fulfill({contentType:'text/javascript',body:`export async function captureProviders(){return [{id:'doctor-a',organization_id:'org-a',full_name:'Dra. de ejemplo A',organizations:{legal_name:'Consultorio de ejemplo Norte'}},{id:'doctor-b',organization_id:'org-b',full_name:'Dr. de ejemplo B',organizations:{legal_name:'Consultorio de ejemplo Sur'}}];}`});
  if(u.pathname==='/js/services/consultorio.js')return request.fulfill({contentType:'text/javascript',body:`export async function flowBoard(org,date){window.reads.push({org,date});if(window.failRefresh)throw Error('Fallo de prueba');return structuredClone(window.rows);}
export async function setAppointmentStatus(id,status){window.writes.push({kind:'status',id,status});const row=window.rows.find(r=>r.id===id);if(row){row.status=status;row.status_changed_at=new Date().toISOString();}return true;}
export async function callAppointmentIn(id,room){window.writes.push({kind:'call',id,room});const row=window.rows.find(r=>r.id===id);if(row){row.status='en_consulta';row.room=room;row.consult_started_at=new Date().toISOString();}return true;}`});
  if(u.pathname==='/js/utils/diag-log.js')return request.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  try{return request.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return request.fulfill({status:404,body:'Missing '+u.pathname});}
 });
 await page.goto('http://127.0.0.1:8895/preview.html');
 await page.evaluate(async()=>{
  window.reads=[];window.writes=[];window.failRefresh=false;
  window.rows=[
   {id:'scheduled',patient:'Dulce María de los Ángeles Rodríguez (ejemplo)',doctor:'Dra. de ejemplo A',type:'Control nutricional',time:'11:00',status:'programada'},
   {id:'confirmed',patient:'Carmen Altagracia Peña (ejemplo)',doctor:'Dra. de ejemplo A',type:'Control mensual',time:'10:00',status:'confirmada'},
   {id:'waiting',patient:'José Ramón Tavárez de la Cruz (ejemplo)',doctor:'Dra. de ejemplo A',type:'Evaluación nutricional inicial',time:'09:00',status:'en_espera',status_changed_at:'2026-11-10T13:40:00Z'},
   {id:'old-waiting',patient:'Paciente histórico de ejemplo',doctor:'Dr. de ejemplo B',type:'Consulta de seguimiento',time:'09:15',status:'en_espera',status_changed_at:'2024-01-01T13:40:00Z'},
   {id:'consulting',patient:'María Alexandra Fernández (ejemplo)',doctor:'Dr. de ejemplo B',type:'Consulta especializada',time:'09:30',status:'en_consulta',consult_started_at:'2026-11-10T13:50:00Z',room:'Sala de ejemplo 2'},
   {id:'attended',patient:'Rosanna Bautista Lora (ejemplo)',doctor:'Dra. de ejemplo A',type:'Consulta privada',time:'08:00',status:'atendida'}
  ];
  window.mod=await import('/js/modules/flujo-pacientes.js');window.ctx={role:'admin',viewAs:null};window.renderFlow=async next=>{Object.assign(ctx,next||{});await mod.render(document.querySelector('main'),ctx)};await renderFlow();
 });
 await page.locator('#fp-board .flow-card').first().waitFor();
 assert.equal(await page.locator('.flow-col').count(),5,'Cinco estados conservados');
 assert.equal(await page.locator('.flow-card').count(),6);
 assert.doesNotMatch(await page.locator('#fp-board').textContent(),/NaN|\d{4,}\s*min/,'Sin duraciones históricas gigantes');
 for(const id of ['fp-org','fp-date','fp-search'])assert.equal(await page.locator('label[for="'+id+'"]').count(),1,'Etiqueta visible '+id);
 const search=page.locator('#fp-search');await search.fill('Carmen');
 await page.waitForFunction(()=>document.querySelectorAll('.flow-card').length===1);
 assert.match(await page.locator('.flow-card').textContent(),/Carmen/);
 await page.clock.fastForward(26000);
 await page.waitForFunction(()=>reads.length>=2);
 assert.equal(await search.inputValue(),'Carmen','Actualización conserva búsqueda');
 assert.equal(await search.evaluate(el=>el===document.activeElement),true,'Actualización conserva foco');
 await search.fill('');await page.waitForFunction(()=>document.querySelectorAll('.flow-card').length===6);
 for(const width of [1760,1440,768,390,320]){
  await page.setViewportSize({width,height:1100});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin desbordamiento '+width);
  const geometry=await page.locator('[data-call="waiting"]').evaluate(button=>{const card=button.closest('.flow-card'),name=card.querySelector('.flow-patient');const b=button.getBoundingClientRect(),c=card.getBoundingClientRect(),n=name.getBoundingClientRect();return {buttonTop:b.top,nameBottom:n.bottom,nameWidth:n.width,cardWidth:c.width};});
  assert.ok(geometry.nameWidth>=geometry.cardWidth-42,'Nombre a ancho útil '+width+': '+JSON.stringify(geometry));
  assert.ok(geometry.buttonTop>=geometry.nameBottom,'Botón debajo del nombre '+width);
 }
 await page.setViewportSize({width:1760,height:1100});
 const cardsBeforeFailure=await page.locator('#fp-board').textContent();
 await page.evaluate(()=>{window.failRefresh=true});await page.locator('#fp-refresh').click();
 await page.waitForFunction(()=>document.querySelector('#fp-error').textContent.includes('Fallo de prueba'));
 assert.equal(await page.locator('#fp-board').textContent(),cardsBeforeFailure,'Un fallo de actualización conserva tarjetas');
 await page.evaluate(()=>{window.failRefresh=false});await page.locator('#fp-refresh').click();
 await page.waitForFunction(()=>!document.querySelector('#fp-error').textContent.trim());
 if(process.env.SOFA_FLOW_SCREENSHOTS){await mkdir('/workspace/artifacts/patient-flow',{recursive:true});await page.screenshot({path:'/workspace/artifacts/patient-flow/pantalla.png',fullPage:true});}
 await page.locator('[data-arrive="scheduled"]').click();await page.waitForFunction(()=>writes.some(w=>w.id==='scheduled'));
 assert.deepEqual(await page.evaluate(()=>writes.find(w=>w.id==='scheduled')),{kind:'status',id:'scheduled',status:'en_espera'});
 await page.locator('[data-call="waiting"]').click();await page.getByRole('dialog',{name:'Llamar a consulta',exact:true}).waitFor();
 await page.locator('#fp-room').fill('  Sala QA 3  ');
 const readsBeforeDialogRefresh=await page.evaluate(()=>reads.length);await page.clock.fastForward(26000);
 await page.waitForFunction(n=>reads.length>n,readsBeforeDialogRefresh);
 assert.equal(await page.locator('#fp-room').inputValue(),'  Sala QA 3  ','Refresco conserva sala escrita');
 assert.equal(await page.locator('#fp-room').evaluate(el=>el===document.activeElement),true,'Refresco conserva foco del diálogo');
 await page.getByRole('button',{name:'Llamar',exact:true}).click();
 await page.waitForFunction(()=>writes.some(w=>w.kind==='call'));
 assert.deepEqual(await page.evaluate(()=>writes.find(w=>w.kind==='call')),{kind:'call',id:'waiting',room:'Sala QA 3'});
 await page.waitForFunction(()=>!!document.querySelector('[data-back="consulting"]'));
 await page.locator('[data-back="consulting"]').click();await page.waitForFunction(()=>writes.some(w=>w.id==='consulting'));
 assert.deepEqual(await page.evaluate(()=>writes.find(w=>w.id==='consulting')),{kind:'status',id:'consulting',status:'en_espera'});
 await page.locator('#fp-date').fill('2026-10-01');await page.waitForFunction(()=>reads.at(-1).date==='2026-10-01');
 assert.doesNotMatch(await page.locator('#fp-board').textContent(),/\b\d+\s*min\b/,'Consulta histórica no usa duración actual');
 await page.locator('#fp-date').fill('2026-11-10');await page.waitForFunction(()=>reads.at(-1).date==='2026-11-10');
 await page.locator('#fp-org').selectOption('org-b');await page.waitForFunction(()=>reads.at(-1).org==='org-b');
 assert.equal(await page.locator('#fp-org').inputValue(),'org-b');
 const before=await page.evaluate(()=>writes.length);
 await page.evaluate(async()=>{await renderFlow({viewAs:{orgId:'org-a'}})});await page.locator('.flow-card').first().waitFor();
 assert.equal(await page.locator('[data-arrive],[data-call],[data-back]').count(),0,'Soporte sin botones de escritura');
 assert.equal(await page.evaluate(()=>writes.length),before);
 await page.evaluate(async()=>{await renderFlow({viewAs:null,role:'client'})});await page.locator('.flow-card').first().waitFor();assert.match(await page.locator('h2').first().textContent(),/Plan del día/);
 await page.setViewportSize({width:390,height:844});
 if(process.env.SOFA_FLOW_SCREENSHOTS){await page.screenshot({path:'/workspace/artifacts/patient-flow/movil.png',fullPage:true});await page.setViewportSize({width:1760,height:1100});await page.evaluate(()=>document.documentElement.dataset.theme='dark');await page.screenshot({path:'/workspace/artifacts/patient-flow/oscuro.png',fullPage:true});}
 assert.deepEqual(errors,[]);console.log('PASS: flujo de pacientes, nombres legibles, cinco estados, acciones exactas, filtros/foco estables, espera histórica, soporte y móvil.');
}finally{await browser.close();}
