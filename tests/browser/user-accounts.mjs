// Usage: SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/user-accounts.mjs
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const browser=await chromium.launch({executablePath:process.env.SOFA_CHROMIUM || '/usr/bin/chromium',args:['--no-sandbox']});
try {
const page=await browser.newPage({viewport:{width:1440,height:1000},timezoneId:'America/Santo_Domingo'});
const errors=[];let external=0;
page.on('pageerror',e=>errors.push(e.message));
await page.route('**/*',async route=>{
 const u=new URL(route.request().url());
 if(u.hostname!=='127.0.0.1'){external++;return route.abort();}
 if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>'});
 if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:'export const sb=()=>window.mockDB;'});
 try{return route.fulfill({body:await readFile(root+u.pathname),contentType:u.pathname.endsWith('.js')?'text/javascript':u.pathname.endsWith('.css')?'text/css':'text/plain'});}catch{return route.fulfill({status:404,body:'Missing'});}
});
await page.goto('http://127.0.0.1:8881/preview.html');
await page.evaluate(async()=>{
 const base={is_active:true,status:'activo',invited_at:'2026-10-01',last_sign_in_at:'2026-10-26T12:00:00-04:00'};
 const row=(user,role,org,extra={})=>({...base,user_id:user,email:user+'@example.test',full_name:user==='doctor-a'?'Dra. Ana Pérez':user,role_code:role,role_name:role,organization_id:org,organization:org,kind:org.startsWith('clinic')?'client':'operator',...extra});
 window.rows=[row('self','super_admin','operator'),row('doctor-a','client','clinic-a'),row('doctor-a','client','clinic-b'),row('doctor-a','client','clinic-a'),row('billing-b','billing','operator'),row('shared-c','billing','operator',{email:'shared@example.test'}),row('shared-d','billing','operator',{email:'shared@example.test'}),row('protected-e','client','clinic-a'),row('protected-e','super_admin','operator',{is_active:false,status:'desactivado'})];
 window.calls=[];window.failReadiness=false;window.failReport=false;
 window.mockDB={rpc(name,args){calls.push({name,args});
 if(name==='users_overview')return Promise.resolve({data:rows});
 if(name==='users_access_readiness')return Promise.resolve(failReadiness?{error:{message:'Readiness unavailable'}}:{data:rows.map(r=>({...r,readiness:'ready',email_confirmed:true,profile_active:true,membership_active:true}))});
 if(name==='users_roles_report')return Promise.resolve(failReport?{error:{message:'Report unavailable'}}:{data:[]});
 if(name==='log_export')return Promise.resolve({data:null});throw new Error('Unexpected RPC '+name);}};
 const {render}=await import('/js/modules/users.js');window.usersRender=render;window.ctx={role:'admin',session:{user:{id:'self'}},operatorId:'operator'};await render(document.querySelector('main'),ctx);
});
await page.getByText('6 de 6 cuentas · 8 accesos',{exact:true}).waitFor();
assert.equal(await page.locator('tbody>tr').count(),6);
await page.locator('tbody>tr').filter({hasText:'Dra. Ana Pérez'}).getByRole('button',{name:'Ver cuenta',exact:true}).click();
await page.locator('dialog.users-detail').waitFor();
assert.equal(await page.locator('dialog.users-detail .user-membership').count(),2);
await page.locator('dialog.users-detail').getByRole('button',{name:'Seguridad',exact:true}).click();
await page.locator('dialog.users-detail').getByRole('heading',{name:'Acciones de la cuenta',exact:true}).waitFor();
await page.locator('dialog.users-detail').getByRole('button',{name:'Cerrar',exact:true}).click();

const doctor=page.locator('tbody>tr').filter({hasText:'Dra. Ana Pérez'});
assert.equal(await doctor.locator('.user-membership').count(),2);assert.equal(await doctor.locator('[data-act="resend"]').count(),1);
assert.equal(await page.locator('tbody>tr').filter({hasText:'protected-e@example.test'}).locator('[data-act]').count(),0);
await doctor.locator('[data-act="validate"][data-org="clinic-b"]').click();await page.locator('dialog').waitFor();assert.match(await page.locator('dialog').innerText(),/clinic-b/);
await page.locator('dialog').getByRole('button',{name:'Cerrar',exact:true}).click();
await page.locator('#kinds [data-k="client"]').click();assert.equal(await page.locator('tbody>tr').count(),2);
await page.locator('#tabs [data-s="desactivado"]').click();assert.equal(await page.locator('tbody>tr').count(),0);
await page.locator('#tabs [data-s=""]').click();await page.locator('#kinds [data-k=""]').click();
await page.getByLabel('Buscar cuenta').fill('ana perez');assert.equal(await page.locator('tbody>tr').count(),1);await page.getByLabel('Buscar cuenta').fill('');
const pendingDownload=page.waitForEvent('download');await page.getByRole('button',{name:'Exportar revisión de accesos',exact:true}).click();
const csv=await readFile(await (await pendingDownload).path(),'utf8');assert.equal(csv.trim().split(/\r?\n/).length,7);
for(const theme of ['light','dark']){await page.evaluate(theme=>document.documentElement.dataset.theme=theme,theme);await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);}
const before=await page.evaluate(()=>calls.length);
await page.evaluate(()=>{const b=document.createElement('button');b.dataset.act='toggle';b.dataset.user='doctor-a';document.querySelector('#l').append(b);b.click();});
await page.waitForTimeout(30);assert.equal(await page.evaluate(()=>calls.length),before);
await page.evaluate(async()=>{window.rows=[{...rows.find(r=>r.user_id==='billing-b'),is_active:false,status:'desactivado'}];failReadiness=true;await usersRender(document.querySelector('main'),{...ctx,role:'super_admin'});});
await page.getByText('1 de 1 cuentas · 1 accesos',{exact:true}).waitFor();await page.locator('[data-act="validate"]').click();await page.locator('dialog').waitFor();
assert.equal(await page.locator('dialog').getByRole('button',{name:'Activar usuario',exact:true}).count(),0);assert.match(await page.locator('dialog').innerText(),/No disponible/);
await page.locator('dialog').getByRole('button',{name:'Cerrar',exact:true}).click();
await page.evaluate(()=>{failReadiness=false;failReport=true;});await page.locator('[data-act="validate"]').click();await page.locator('dialog').waitFor();
assert.equal(await page.locator('dialog').getByRole('button',{name:'Activar usuario',exact:true}).count(),0);assert.match(await page.locator('dialog').innerText(),/validación incompleta/);
await page.locator('dialog').getByRole('button',{name:'Cerrar',exact:true}).click();
const beforeDenied=await page.evaluate(()=>calls.length);await page.evaluate(async()=>usersRender(document.querySelector('main'),{...ctx,role:'client'}));assert.equal(await page.evaluate(()=>calls.length),beforeDenied);

// New correction view: explicit reason, identity confirmation, denied write, then atomic success.
await page.evaluate(async()=>{
 window.rows=[{user_id:'repair-user',email:'repair@example.test',full_name:'Cuenta propia de prueba',role_code:'client',role_name:'Médico',organization_id:'clinic-a',organization:'Consultorio de prueba',kind:'client',is_active:true,status:'activo'}];
 window.failReadiness=false;window.failReport=false;window.repairBlocked=false;window.repairReject=true;
 const original=mockDB.rpc;
 mockDB.rpc=(name,args)=>{
  if(name==='admin_user_repair_preview'){calls.push({name,args});return Promise.resolve({data:{user_id:args.p_user,client_org_id:args.p_org,email:'repair@example.test',current_role:'client',target_role:'admin',profile_active:true,expected:'token-test',can_repair:!repairBlocked,blockers:repairBlocked?['Cuenta enlazada a un médico.']:[]}});}
  if(name==='admin_repair_user_access'){calls.push({name,args});if(repairReject)return Promise.resolve({error:{message:'Los accesos cambiaron. Revise una nueva vista previa.'}});rows[0].is_active=false;rows[0].status='desactivado';rows.push({...rows[0],role_code:'admin',role_name:'Administrador SOFA',organization_id:'operator',organization:'Empresa SOFA',kind:'operator',is_active:true,status:'activo'});return Promise.resolve({data:{ok:true,audit_id:'audit-test',user_id:args.p_user,profile_active:true}});}
  return original(name,args);
 };
 await usersRender(document.querySelector('main'),{...ctx,role:'super_admin'});
});
await page.locator('[data-act="repair"]').waitFor();await page.locator('[data-act="repair"]').click();await page.locator('dialog').waitFor();
await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).click();
assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='admin_repair_user_access').length),0);
await page.getByLabel('Motivo de la corrección *').fill('Cuenta propia asociada a un cliente por error');
await page.getByLabel('Escribe el correo para confirmar *').fill('wrong@example.test');
await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).click();
assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='admin_repair_user_access').length),0);
await page.getByLabel('Escribe el correo para confirmar *').fill('repair@example.test');
await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).click();
assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='admin_repair_user_access').length),0);
await page.locator('dialog .err').getByText('Confirma el cambio solicitado.',{exact:true}).waitFor();
assert.equal(await page.locator('#repair-confirmed').getAttribute('aria-invalid'),'true');
await page.locator('dialog input[name="confirmed"]').check();
await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).click();
await page.locator('dialog .fd-msg').getByText(/Los accesos cambiaron/).waitFor();
assert.equal(await page.locator('dialog').count(),1);
await page.locator('dialog').getByRole('button',{name:'Cancelar',exact:true}).click();
await page.evaluate(()=>window.repairReject=false);
await page.locator('[data-act="repair"]').click();await page.locator('dialog').waitFor();
await page.getByLabel('Motivo de la corrección *').fill('Cuenta propia asociada a un cliente por error');
await page.getByLabel('Escribe el correo para confirmar *').fill('repair@example.test');await page.locator('dialog input[name="confirmed"]').check();
await page.screenshot({path:'/workspace/artifacts/sofa-reparacion-usuarios/vista-correccion.png',fullPage:true});
await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).click();
await page.getByText('1 de 1 cuentas · 2 accesos',{exact:true}).waitFor();
assert.equal(await page.locator('tbody>tr').count(),1);assert.ok(await page.getByText('Administrador SOFA',{exact:true}).count());
await page.evaluate(async()=>{window.rows[0].is_active=true;window.rows[0].status='activo';window.rows=rows.slice(0,1);window.repairBlocked=true;await usersRender(document.querySelector('main'),{...ctx,role:'super_admin'});});
await page.locator('[data-act="repair"]').waitFor();await page.locator('[data-act="repair"]').click();await page.locator('dialog').waitFor();
assert.equal(await page.locator('dialog').getByRole('button',{name:'Corregir y asignar Administrador',exact:true}).count(),0);
assert.match(await page.locator('dialog').innerText(),/Cuenta enlazada a un médico/);
await page.locator('dialog').getByRole('button',{name:'Cerrar',exact:true}).click();
await page.evaluate(()=>{
 const previous=mockDB.rpc;
 mockDB.rpc=(name,args)=>name==='admin_user_repair_preview' ? Promise.resolve({error:{code:'42501',message:'permission denied for function admin_user_repair_preview'}}) : previous(name,args);
});
await page.locator('[data-act="repair"]').click();
await page.getByText('No tienes permiso para esta acción.',{exact:true}).waitFor();
assert.equal(await page.locator('[data-act="repair"]').count(),1);
await page.evaluate(()=>{
 const previous=mockDB.rpc;
 mockDB.rpc=(name,args)=>name==='admin_user_repair_preview' ? Promise.resolve({error:{code:'PGRST202',message:'Could not find the function public.admin_user_repair_preview in the schema cache'}}) : previous(name,args);
});
const writesBeforeMissing=await page.evaluate(()=>calls.filter(c=>c.name==='admin_repair_user_access').length);
await page.locator('[data-act="repair"]').click();
await page.getByText('Corrección de asociaciones no habilitada',{exact:true}).waitFor();
assert.equal(await page.locator('[data-act="repair"]').count(),0);
assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='admin_repair_user_access').length),writesBeforeMissing);
assert.deepEqual(errors,[]);assert.equal(external,0);
assert.ok(await page.evaluate(()=>calls.every(c=>['users_overview','users_access_readiness','users_roles_report','log_export','admin_user_repair_preview','admin_repair_user_access'].includes(c.name))));
console.log('PASS: repair preview/confirmation/rejected write/success/blocked clinical account;  grouped accounts, exact access validation, combined filters, protected accounts, CSV, mobile/themes, rejected forged action, fail-closed activation, denied role. All RPC simulated; no real mutations or external requests.');
} finally {await browser.close();}
