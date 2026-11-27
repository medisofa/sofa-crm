// Usage: SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/horas-usuarios.mjs
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const browser=await chromium.launch({executablePath:process.env.SOFA_CHROMIUM || '/usr/bin/chromium',args:['--no-sandbox']});
try {
const page=await browser.newPage({viewport:{width:1280,height:900},timezoneId:'America/Santo_Domingo'});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.route('**/*',async route=>{
 const u=new URL(route.request().url());
 if(u.hostname!=='127.0.0.1')return route.abort();
 if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>'});
 if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB;'});
 try{return route.fulfill({body:await readFile(root+u.pathname),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404,body:'Missing'});}
});
await page.goto('http://127.0.0.1:8881/preview.html');
await page.evaluate(async()=>{
 const base={week_start:'2026-11-23',days:3,last_at:'2026-11-27T10:00:00-04:00'};
 window.calls=[];window.fail=false;
 window.mockDB={rpc(name,args){calls.push({name,args});
  if(name==='usage_ping')return Promise.resolve({data:null});
  if(fail)return Promise.resolve({error:{message:'Reporte no disponible'}});
  return Promise.resolve({data:{since:'2026-11-27',rows:[
   {...base,user_id:'a',name:'Facturación QA',is_sofa:true,roles:'Facturación',connected_minutes:605,active_minutes:421,filed:2},
   {...base,user_id:'b',name:'Médico QA',is_sofa:false,roles:'Médico',connected_minutes:30,active_minutes:12,filed:0},
   {...base,user_id:'c',name:'Sin conexión QA',is_sofa:true,roles:'Asistente',week_start:null,days:0,last_at:null,connected_minutes:0,active_minutes:0,filed:0}]}});}};
 const mod=await import('/js/modules/horas-usuarios.js');window.screen_=mod;
 await mod.render(document.querySelector('main'),{role:'admin'});
});
await page.getByText('Facturación QA').waitFor();
const text=async()=>page.locator('main').innerText();
assert.match(await text(),/7 h 01 min/);assert.match(await text(),/10 h 05 min/);assert.match(await text(),/Sin conexión QA/);assert.doesNotMatch(await text(),/Médico QA/);
await page.getByLabel('Usuarios').selectOption('otros');assert.match(await text(),/Médico QA/);assert.doesNotMatch(await text(),/Facturación QA/);
await page.getByLabel('Usuarios').selectOption('');
const dl=page.waitForEvent('download');await page.getByRole('button',{name:'⬇ CSV'}).click();
assert.equal((await readFile(await (await dl).path(),'utf8')).trim().split(/\r?\n/).length,4);
await page.getByLabel('Período').selectOption('12');
await page.waitForFunction(()=>calls.filter(c=>c.name==='usage_hours_report').length===2);
assert.deepEqual(await page.evaluate(()=>screen_.period(4,new Date(2026,10,27))),{from:'2026-11-02',to:'2026-11-27'});
await page.screenshot({path:'/tmp/horas.png'});
await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
// Otros roles: ni se consulta.
const before=await page.evaluate(()=>calls.length);
for(const role of ['billing','client','assistant','auditor']){await page.evaluate(r=>screen_.render(document.querySelector('main'),{role:r}),role);assert.match(await text(),/Solo la Administración/);}
assert.equal(await page.evaluate(()=>calls.length),before);
await page.evaluate(async()=>{fail=true;await screen_.render(document.querySelector('main'),{role:'super_admin'});});
assert.match(await text(),/Reporte no disponible|no/i);
// Latido: un aviso al arrancar, no se duplica, «activo» al inicio y los errores no se propagan.
await page.evaluate(async()=>{const {startUsageHeartbeat}=await import('/js/utils/usage-heartbeat.js');window.beats=[];
 const ping=(a)=>{beats.push(a);return Promise.reject(new Error('sin red'));};startUsageHeartbeat({ping,everyMs:50});startUsageHeartbeat({ping,everyMs:50});});
await page.waitForTimeout(180);
const beats=await page.evaluate(()=>beats);assert.ok(beats.length>=2&&beats.length<=5,String(beats.length));assert.equal(beats[0],true);
const {canSee}=await import(root+'js/utils/permissions.js');
for(const r of ['super_admin','admin'])assert.equal(canSee('horas-usuarios',r),true);
for(const r of ['billing','assistant','client','auditor','glosas','secretaria','asistente'])assert.equal(canSee('horas-usuarios',r),false,r);
// Usuarios: botón de director de clínica.
await page.evaluate(async()=>{
 const base={is_active:true,status:'activo',invited_at:'2026-10-01',last_sign_in_at:'2026-10-26T12:00:00-04:00'};
 const rows=[{...base,user_id:'doc',email:'doc@example.test',full_name:'Dra. QA',role_code:'client',role_name:'Médico',organization_id:'clinic-a',organization:'Centro QA',kind:'client'}];
 window.directors=[];window.calls=[];
 window.mockDB={rpc(name,args){calls.push({name,args});
   if(name==='set_clinic_director'){directors=args.p_on?[{user_id:args.p_user,organization_id:args.p_org}]:[];return Promise.resolve({data:null});}
   if(name==='users_overview')return Promise.resolve({data:rows});return Promise.resolve({data:[]});},
  from(){const q={select:()=>q,eq:()=>q,then:(ok,ko)=>Promise.resolve({data:directors}).then(ok,ko)};return q;}};
 const {render}=await import('/js/modules/users.js');window.usersRender=render;
 document.querySelector('main').replaceChildren();await render(document.querySelector('main'),{role:'admin',session:{user:{id:'self'}},operatorId:'operator'});
});
await page.setViewportSize({width:1280,height:900});
await page.locator('tbody>tr').getByRole('button',{name:'Ver cuenta',exact:true}).click();
await page.locator('dialog.users-detail').getByRole('button',{name:'Marcar director de clínica'}).click();
await page.getByRole('button',{name:'Cancelar'}).click();
assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='set_clinic_director').length),0);
await page.locator('tbody>tr').getByRole('button',{name:'Ver cuenta',exact:true}).click();
await page.locator('dialog.users-detail').getByRole('button',{name:'Marcar director de clínica'}).click();
await page.getByRole('button',{name:'Marcar director',exact:true}).click();
await page.getByText('Director · ve a todos los médicos').first().waitFor({state:'attached'});
assert.deepEqual(await page.evaluate(()=>calls.find(c=>c.name==='set_clinic_director').args),{p_org:'clinic-a',p_user:'doc',p_on:true});
assert.deepEqual(errors,[]);
console.log('OK · horas-usuarios, latido y director de clínica');
} finally { await browser.close(); }
