import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>({});'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:`export async function captureProviders(){return [{organization_id:'org-a',organizations:{legal_name:'Consultorio A'}},{organization_id:'org-b',organizations:{legal_name:'Consultorio B'}}]}`});
  if(u.pathname==='/js/services/consultorio.js')return route.fulfill({contentType:'text/javascript',body:`export async function flowBoard(org,date){window.reads.push({org,date});if(window.failRead)throw Error('NetworkError');return window.rows;} export async function setAppointmentStatus(id,status){window.writes.push({id,status});window.rows=window.rows.map(r=>r.id===id?{...r,status}:r);} export async function callAppointmentIn(){throw Error('No se espera en esta prueba');}`});
  if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  window.reads=[];window.writes=[];window.rows=['programada','confirmada','en_espera','en_consulta','atendida','cancelada'].map((status,i)=>({id:String(i),status,patient:i===0?'<script>sin ejecutar</script>':'Paciente '+i,doctor:'Médico',time:'08:00'}));
  window.flow=await import('/js/modules/flujo-pacientes.js');await flow.render(document.querySelector('main'),{role:'client'});
 });
 assert.equal(await page.locator('.flow-col').count(),5);
 assert.deepEqual(await page.locator('.flow-col h3').allTextContents(),['Agendados 1','Confirmados 1','En sala 1','En consulta 1','Atendidos 1']);
 assert.equal(await page.locator('.flow-card').count(),5);
 assert.equal(await page.locator('main script').count(),0);
 assert.match(await page.locator('h2').textContent(),/Plan del día/);
 assert.equal(await page.locator('[data-arrive]').count(),2);
 await page.locator('[data-arrive="1"]').click();
 await page.waitForFunction(()=>document.querySelectorAll('.flow-col')[1].querySelector('.pill').textContent==='0');
 assert.deepEqual(await page.evaluate(()=>writes),[{id:'1',status:'en_espera'}]);
 await page.locator('#fp-org').selectOption('org-b');
 await page.waitForFunction(()=>reads.at(-1).org==='org-b');
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 await page.evaluate(()=>{window.failRead=true;document.querySelector('#fp-date').dispatchEvent(new Event('change'));});
 await page.getByText(/No se pudo conectar con el servidor/).waitFor();
 await page.evaluate(()=>{location.hash='#/seguimiento-hoy'});
 await page.evaluate(async()=>{window.followup=await import('/js/modules/seguimiento-hoy.js');await followup.render(document.querySelector('main'),{role:'client'});});
 assert.equal(await page.locator('main a').count(),5);
 assert.equal(await page.locator('main input,main textarea').count(),0);
 await page.getByText('Próximas funciones · En construcción',{exact:true}).waitFor();
 await page.evaluate(async()=>followup.render(document.querySelector('main'),{role:'billing'}));
 assert.equal(await page.locator('main a').count(),0);
 await page.getByRole('alert').waitFor();
 assert.deepEqual(errors,[]);
 console.log('PASS: cinco estados exclusivos, transiciones existentes, consultorio, XSS, móvil, fallo de red, seguimiento y denegación por rol.');
}finally{await browser.close();}
