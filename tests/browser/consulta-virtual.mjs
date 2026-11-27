// Usage: SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/consulta-virtual.mjs
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const browser=await chromium.launch({executablePath:process.env.SOFA_CHROMIUM || '/usr/bin/chromium',args:['--no-sandbox']});
try {
const page=await browser.newPage({viewport:{width:1440,height:1000},timezoneId:'America/Santo_Domingo'});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.route('**/*',async route=>{
 const u=new URL(route.request().url());
 if(u.hostname!=='127.0.0.1')return route.abort();
 if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta charset="utf-8"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><main class="page"></main></html>'});
 if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB; export const supabase=null;'});
 if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:'export const captureProviders=async()=>[{id:"p1",full_name:"Dr. QA",organization_id:"o1"}]; export const activeArs=async()=>[];'});
 try{return route.fulfill({body:await readFile(root+u.pathname),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404,body:'Missing'});}
});
await page.goto('http://127.0.0.1:8881/preview.html');
await page.evaluate(async()=>{
 const d=new Date();const today=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
 const appt={id:'a1',appointment_time:'09:00:00',time:'09:00',date:today,duration_min:30,patient_name:'Paciente Virtual',phone:'8095550000',payer_type:'privado',status:'programada',modality:'virtual',virtual_link:'https://meet.example.com/qa'};
 window.calls=[];window.opened=[];window.open=(u)=>{opened.push(u);};
 window.mockDB={
  rpc(name,args){calls.push({name,args});
   const data=name==='day_summary'?{appointments:{total:1,atendida:0,no_asistio:0,pendiente:1},ars_claims:{count:0,claimed:0},private:{count:0,billed:0,pending:0},collected:{total:0},unregistered:[]}
    :name==='agenda_week'?{schedule:[{weekday:((d.getDay()+6)%7)+1,start:'08:00',end:'12:00',slot_min:30}],appointments:[appt],busy:[]}
    :name==='my_agenda_scopes'?{centers_by_provider:{p1:[{id:'c1',name:'Centro QA'}]},reception:[]}:'nuevo';
   return Promise.resolve({data,error:null});},
  from(table){const rows=table==='appointments'?[appt]:[];const q=new Proxy({},{get:(_,k)=>k==='then'?(ok,ko)=>Promise.resolve({data:rows,error:null}).then(ok,ko):()=>q});return q;}};
 window.day=await import('/js/modules/agenda.js');window.week=await import('/js/modules/agenda-semana.js');
 await day.render(document.querySelector('main'),{role:'client'});
});
const saves=()=>page.evaluate(()=>calls.filter(c=>c.name==='save_appointment_modality').map(c=>c.args));
await page.getByRole('link',{name:'Entrar a la consulta virtual'}).waitFor();
await page.locator('[data-wa="a1"]').click();
assert.match(decodeURIComponent(await page.evaluate(()=>opened[0])),/consulta virtual; conéctese aquí: https:\/\/meet\.example\.com\/qa/);
// Nueva cita presencial: enlace deshabilitado y no se envía.
await page.locator('#ag_new').click();
assert.equal(await page.locator('#vv_l').isDisabled(),true);
await page.locator('#ap_n').fill('Paciente Nuevo');await page.locator('#ap_pay').selectOption('privado');
await page.locator('#ap_pay').selectOption('ars');
await page.locator('#vv_m').selectOption('virtual');
assert.equal(await page.locator('#ap_pay').inputValue(),'privado');
assert.equal(await page.locator('#ap_pay option[value="ars"]').isDisabled(),true);
assert.equal(await page.locator('#ap_ars').isDisabled(),true);
await page.locator('#vv_l').fill('http://inseguro.example.com');
await page.getByRole('button',{name:'Guardar',exact:true}).click();await page.waitForTimeout(200);
assert.equal((await saves()).length,0);
await page.locator('#vv_l').fill('https://meet.example.com/nueva');
await page.getByRole('button',{name:'Guardar',exact:true}).click();
await page.waitForFunction(()=>calls.some(c=>c.name==='save_appointment_modality'));
let s=(await saves())[0];assert.equal(s.p_modality,'virtual');assert.equal(s.p_link,'https://meet.example.com/nueva');assert.equal(s.p_payer,'privado');assert.equal(s.p_ars,null);
// Editar conserva la modalidad.
await page.locator('[data-appt="a1"] summary').click();await page.locator('[data-edit="a1"]').click();
assert.equal(await page.locator('#vv_m').inputValue(),'virtual');assert.equal(await page.locator('#vv_l').inputValue(),'https://meet.example.com/qa');
await page.locator('#vv_m').selectOption('presencial');
await page.locator('dialog #ap_pay').selectOption('privado');
await page.getByRole('button',{name:'Guardar',exact:true}).click();
await page.waitForFunction(()=>calls.filter(c=>c.name==='save_appointment_modality').length===2);
s=(await saves())[1];assert.equal(s.p_modality,'presencial');assert.equal(s.p_link,null);
await page.screenshot({path:'/tmp/dia.png'});
// Volver a presencial devuelve la forma de pago que había, y el aviso explica el cambio.
await page.locator('#ag_new').click();
assert.equal(await page.locator('dialog #ap_pay').inputValue(),'ars');assert.equal(await page.locator('#vv_note').isVisible(),false);
await page.locator('#vv_m').selectOption('virtual');
assert.equal(await page.locator('dialog #ap_pay').inputValue(),'privado');assert.equal(await page.locator('#vv_note').isVisible(),true);
await page.locator('#vv_m').selectOption('presencial');
assert.equal(await page.locator('dialog #ap_pay').inputValue(),'ars');assert.equal(await page.locator('#vv_note').isVisible(),false);
assert.equal(await page.locator('dialog #ap_ars').isDisabled(),false);
await page.keyboard.press('Escape');
// Semana
await page.evaluate(async()=>{const m=document.createElement('main');m.className='page';document.querySelector('main').replaceWith(m);await week.render(m,{role:'client'});});
await page.locator('.wk-ap').getByRole('link',{name:'Virtual ↗'}).waitFor();
assert.match(await page.locator('.wk-ap').innerText(),/Virtual/);
// Visible de verdad: dentro del alto de la tarjeta de 30 minutos, no recortado.
assert.equal(await page.evaluate(()=>{const c=document.querySelector('.wk-ap'),a=c.querySelector('a'),r=a.getBoundingClientRect(),k=c.getBoundingClientRect();return r.bottom<=k.bottom&&r.right<=k.right;}),true);
await page.screenshot({path:'/tmp/semana.png'});
await page.locator('.wk-free').first().click();
await page.locator('#na_n').fill('Paciente Semana');await page.locator('#vv_m').selectOption('virtual');
await page.getByRole('button',{name:'Agendar',exact:true}).click();
await page.waitForFunction(()=>calls.filter(c=>c.name==='save_appointment_modality').length===3);
s=(await saves())[2];assert.equal(s.p_modality,'virtual');assert.equal(s.p_link,null);
assert.deepEqual(errors,[]);
console.log('OK · consulta virtual en agenda del día y semana');
} finally { await browser.close(); }
