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
 window.calls=[];window.rejectWrite=true;
 window.account={user_id:'target',email:'test@example.test',full_name:'Cuenta de prueba',memberships:[{organization_id:'sofa',role_code:'billing',role_name:'Facturación',organization:'SOFA'},{organization_id:'clinic',role_code:'client',role_name:'Médico',organization:'Consultorio de prueba'}]};
 window.mockDB={rpc:async(name,args)=>{calls.push({name,args});if(name==='admin_access_revoke_preview')return {data:{user_id:'target',accesses:args.p_orgs.map(organization_id=>({organization_id,role_code:account.memberships.find(m=>m.organization_id===organization_id).role_code})),expected:'version',can_revoke:true,blockers:[]}};if(rejectWrite)return {error:{message:'Los accesos cambiaron; revisa nuevamente.'}};return {data:{ok:true,audit_id:'audit-test',user_id:'target'}};}};
 const {revokeSelectedAccesses}=await import('/js/modules/user-access-revoke.js');
 window.launch=()=>revokeSelectedAccesses(account,{role:'super_admin',session:{user:{id:'actor'}}},async()=>window.reloaded=true);
 window.launch();
});
await page.getByRole('button',{name:'Revisar selección',exact:true}).click();
await page.getByText('Selecciona al menos un acceso.',{exact:true}).waitFor();
assert.equal(await page.evaluate(()=>calls.length),0);
await page.screenshot({path:'/workspace/artifacts/sofa-reparacion-usuarios/seleccionar-accesos-checkbox.png',fullPage:true});
await page.locator('[name="access_1"]').check();
await page.getByRole('button',{name:'Revisar selección',exact:true}).click();
await page.getByRole('button',{name:'Revocar accesos seleccionados',exact:true}).waitFor();
assert.deepEqual(await page.evaluate(()=>calls[0].args.p_orgs),['clinic']);
await page.getByRole('button',{name:'Revocar accesos seleccionados',exact:true}).click();
assert.equal(await page.evaluate(()=>calls.length),1);
await page.locator('#revoke-reason').fill('Acceso de consultorio asignado por error');
await page.locator('#revoke-confirm').check();
await page.screenshot({path:'/workspace/artifacts/sofa-reparacion-usuarios/revocar-checkbox-propuesta.png',fullPage:true});
await page.getByRole('button',{name:'Revocar accesos seleccionados',exact:true}).click();
await page.locator('.fd-msg').getByText(/Los accesos cambiaron/).waitFor();
assert.equal(await page.locator('dialog').count(),1);
await page.evaluate(()=>rejectWrite=false);
await page.getByRole('button',{name:'Revocar accesos seleccionados',exact:true}).click();
await page.waitForFunction(()=>window.reloaded===true);
assert.deepEqual(await page.evaluate(()=>calls.at(-1).args.p_orgs),['clinic']);
await page.evaluate(()=>{
 const old=mockDB.rpc;
 mockDB.rpc=async(name,args)=>{
  const r=await old(name,args);
  if(name==='admin_access_revoke_preview')r.data.accesses[0].role_code='admin';
  return r;
 };
 window.launch();
});
await page.locator('[name="access_1"]').check();
await page.getByRole('button',{name:'Revisar selección',exact:true}).click();
await page.locator('.fd-msg').getByText(/Un rol cambió/).waitFor();
assert.equal(await page.getByRole('button',{name:'Revocar accesos seleccionados',exact:true}).count(),0);
for(const theme of ['light','dark']){
 await page.evaluate(t=>document.documentElement.dataset.theme=t,theme);
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
}
assert.deepEqual(errors,[]);assert.equal(external,0);
console.log('PASS: selección obligatoria, alcance exacto, motivo y confirmación, fallo conserva formulario, éxito recarga. RPC simuladas.');
}finally{await browser.close();}
