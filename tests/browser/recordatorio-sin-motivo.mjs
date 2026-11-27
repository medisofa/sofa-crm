// Usage: SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/recordatorio-sin-motivo.mjs
// El recordatorio de WhatsApp no lleva el motivo de la cita (puede revelar un dato de salud).
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const browser=await chromium.launch({executablePath:process.env.SOFA_CHROMIUM || '/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage({timezoneId:'America/Santo_Domingo'});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><meta charset="utf-8"><main class="page"></main>'});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB; export const supabase=null;'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:'export const captureProviders=async()=>[{id:"p1",full_name:"Dr. QA",organization_id:"o1"}]; export const activeArs=async()=>[];'});
  try{return route.fulfill({body:await readFile(root+u.pathname),contentType:'text/javascript'});}catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8881/preview.html');
 await page.evaluate(async()=>{
  const d=new Date();const today=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  const appt={id:'a1',appointment_date:today,appointment_time:'09:00:00',patient_name:'Paciente Ficticio',phone:'8095550000',payer_type:'privado',status:'programada',reason:'Motivo reservado'};
  window.opened=[];window.open=(u)=>{opened.push(u);};
  window.mockDB={rpc(n){return Promise.resolve({data:n==='day_summary'?{appointments:{},ars_claims:{count:0},private:{count:0},collected:{},unregistered:[]}:null,error:null});},
   from(t){const rows=t==='appointments'?[appt]:[];const q=new Proxy({},{get:(_,k)=>k==='then'?(ok,ko)=>Promise.resolve({data:rows,error:null}).then(ok,ko):()=>q});return q;}};
  await (await import('/js/modules/agenda.js')).render(document.querySelector('main'),{role:'client'});
 });
 await page.locator('[data-wa="a1"]').click();
 const msg=decodeURIComponent(await page.evaluate(()=>opened[0]));
 assert.match(msg,/le recordamos su cita con Dr\. QA/);assert.doesNotMatch(msg,/Motivo reservado/);
 assert.deepEqual(errors,[]);
 console.log('OK · recordatorio sin motivo');
} finally { await browser.close(); }
