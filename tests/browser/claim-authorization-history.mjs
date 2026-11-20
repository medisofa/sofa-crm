/** History and correction UI with fictional records; no database connection. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async r=>{
  const u=new URL(r.request().url());if(u.hostname!=='127.0.0.1')return r.abort();
  if(u.pathname==='/')return r.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><button id="open">Abrir gestión</button></html>'});
  if(u.pathname==='/js/services/claim-authorization.js')return r.fulfill({contentType:'text/javascript',body:`export async function adminSetClaimAuthorization(v){window.writes.push(v);return {changed:true};}export async function listClaimAuthorizationHistory(id){window.reads.push(id);if(window.failHistory)throw Error('Fallo de prueba');return window.historyRows;}`});
  if(u.pathname==='/js/utils/diag-log.js')return r.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  try{return r.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return r.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8897/');
 await page.evaluate(async()=>{window.mod=await import('/js/modules/claim-authorization.js');window.claim={id:'qa-line',folio:'REC-EJEMPLO-001',patient_name:'Paciente ficticio',authorization_number:'001122'};window.reads=[];window.writes=[];window.failHistory=false;window.historyRows=[{changed_at:'2026-11-11T10:00:00Z',actor_name:'Administradora ficticia',old_number:null,new_number:'001122',reason:'Autorización recibida después de la carga.'}];});
 // No default consent: reviewing a change is not saving it.
 await page.evaluate(()=>{window.mod.editClaimAuthorization(window.claim,{role:'admin'});});
 await page.locator('#ca-number').fill('009988');await page.locator('#ca-reason').fill('Corrección según documento de la ARS.');
 assert.equal(await page.locator('#ca-after').textContent(),'009988');
 await page.getByRole('button',{name:'Revisar cambio',exact:true}).click();
 const confirmation=page.getByRole('dialog',{name:'Confirmar cambio de autorización',exact:true});
 assert.match(await confirmation.textContent(),/Antes: 001122/);assert.match(await confirmation.textContent(),/Después: 009988/);
 await confirmation.getByRole('button',{name:'Cancelar',exact:true}).click();
 assert.equal(await page.locator('#ca-number').inputValue(),'009988');assert.equal(await page.locator('#ca-reason').inputValue(),'Corrección según documento de la ARS.');assert.equal(await page.evaluate(()=>writes.length),0);
 await page.keyboard.press('Escape');await page.getByRole('dialog').waitFor({state:'detached'});
 // History is a scoped, read-only query and escapes all values.
 await page.locator('#open').focus();
 await page.evaluate(()=>{window.mod.showClaimAuthorizationHistory(window.claim,{role:'admin'});});
 await page.locator('.ca-history-entry').waitFor();
 assert.deepEqual(await page.evaluate(()=>reads),['qa-line']);assert.match(await page.locator('.ca-history-entry').textContent(),/Sin registrar/);assert.match(await page.locator('.ca-history-entry').textContent(),/001122/);
 await page.evaluate(()=>{window.historyRows[0].reason='<img src=x onerror="window.xss=true">';});await page.getByRole('button',{name:'Actualizar historial',exact:true}).click();
 assert.equal(await page.locator('.ca-history-entry img').count(),0);assert.equal(await page.evaluate(()=>!!window.xss),false);
 await page.evaluate(()=>window.failHistory=true);await page.getByRole('button',{name:'Actualizar historial',exact:true}).click();await page.getByRole('alert').waitFor();
 await page.evaluate(()=>{window.failHistory=false;window.historyRows=[];});await page.getByRole('button',{name:'Actualizar historial',exact:true}).click();await page.getByText('Sin correcciones administrativas de autorización registradas para esta reclamación.',{exact:true}).waitFor();
 await page.evaluate(()=>{window.historyRows=[{changed_at:'2026-11-11T10:00:00Z',actor_name:'Administradora ficticia',old_number:'001122',new_number:'009988',reason:'Corrección según documento de la ARS.'}];});await page.getByRole('button',{name:'Actualizar historial',exact:true}).click();await page.locator('.ca-history-entry').waitFor();
 if(process.env.SOFA_AUTH_SCREENSHOTS){await mkdir('/workspace/artifacts/claim-authorization',{recursive:true});await page.screenshot({path:'/workspace/artifacts/claim-authorization/historial.png',fullPage:true});}
 for(const width of [390,320]){await page.setViewportSize({width,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert.ok(await page.getByRole('dialog').evaluate(e=>e.getBoundingClientRect().width<=innerWidth));}
 await page.getByRole('button',{name:'Cerrar',exact:true}).click();assert.equal(await page.locator('#open').evaluate(e=>e===document.activeElement),true);
 const count=await page.evaluate(()=>reads.length);
 for(const options of[{role:'billing'},{role:'client'},{role:'admin',viewAs:{orgId:'qa'}}]){
  const message=await page.evaluate(async options=>{try{await mod.showClaimAuthorizationHistory(claim,options);return null;}catch(e){return e.message;}},options);assert.match(message,/Administración o Super Admin/);
 }
 assert.equal(await page.evaluate(()=>reads.length),count,'No consultar historial sin permiso');assert.equal(await page.evaluate(()=>writes.length),0);
 assert.deepEqual(errors,[]);console.log('PASS: comparación antes/después, confirmación cancelable sin pérdida, historial readonly, error/reintento, escape XSS, roles/soporte y móvil.');
}finally{await browser.close();}
