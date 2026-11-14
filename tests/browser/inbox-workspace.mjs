/** Bandeja operativa con datos ficticios; sin lecturas ni escrituras en Supabase. */
import assert from 'node:assert/strict';
import {readFile}from'node:fs/promises';
const{chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><link rel="stylesheet" href="/css/workspace-inbox.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/modules/pending-digest.js')return route.fulfill({contentType:'text/javascript',body:`export async function mountPendingDigest(root){root.textContent='Resumen diario conservado';window.digestCalled=true;}`});
  if(u.pathname==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:`export const sb=()=>({rpc:async(name,args)=>{window.calls.push({name,args});if(name==='inbox_my'){if(window.failInbox)return {error:{message:'Fallo de lectura de prueba'}};return {data:{view:window.role==='billing'?'propia':'todo',totals:{total:3,overdue:1,overdue_amount:750,high:1,amount:2250,unassigned:1},counts:[{type:'captura_incompleta',label:'Capturas incompletas',total:1,overdue:1},{type:'lote_por_radicar',label:'Lotes por radicar',total:1,overdue:0},{type:'glosa_responder',label:'Glosas por responder',total:1,overdue:0}],tasks:window.tasks.filter(t=>!args.p_type||t.type===args.p_type),covering:[],my_absence:null,truncated:window.truncated}};}throw Error('RPC inesperada '+name);}});`});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8896/preview.html');
 await page.evaluate(async()=>{window.calls=[];window.role='admin';window.tasks=[
  {task_key:'captura:lot-a',type:'captura_incompleta',entity_id:'lot-a',organization_id:'org-a',type_label:'Captura incompleta',title:'Lote RAD-EJEMPLO-A · ARS de ejemplo',detail:'Falta autorización y documentación',client:'Cliente ficticio A',ars_name:'ARS de ejemplo',folio:'RAD-EJEMPLO-A',due_on:'2026-11-10',days_late:2,priority:'critica',amount:750,assignee:null,unassigned_reason:'sin_asignacion'},
  {task_key:'lot:lot-b',type:'lote_por_radicar',entity_id:'lot-b',organization_id:'org-b',type_label:'Lote por radicar',title:'Lote RAD-EJEMPLO-B',detail:'Preparar revisión antes de radicar',client:'Cliente ficticio B',due_on:'2026-11-12',days_late:0,priority:'alta',amount:750,assignee:'Responsable ficticio',assignee_id:'user-a'},
  {task_key:'glosa:glosa-a',type:'glosa_responder',entity_id:'glosa-a',organization_id:'org-a',type_label:'Glosa por responder',title:'Glosa GLO-EJEMPLO',detail:'Respuesta documental pendiente',client:'Cliente ficticio A',due_on:null,days_late:null,priority:'normal',amount:750,assignee:'Responsable ficticio',assignee_id:'user-a'}
 ];window.mod=await import('/js/modules/mi-bandeja.js');window.renderInbox=async(role='admin')=>{window.role=role;await mod.render(document.querySelector('main'),{role});};await renderInbox();});
 assert.equal(await page.locator('.iw-task').count(),3);
 assert.equal(await page.getByLabel('Secciones de la bandeja').getByRole('tab').count(),7,'Pestañas de supervisor conservadas');
 assert.match(await page.locator('.iw-task').first().textContent(),/Falta autorización/);
 assert.equal(await page.locator('.iw-task a[href="#/radicaciones/lot-a"]').count(),1);
 await page.getByRole('button',{name:'Vencidas',exact:true}).click();assert.equal(await page.locator('.iw-task').count(),1);
 await page.getByRole('button',{name:'Sin responsable',exact:true}).click();assert.equal(await page.locator('.iw-task').count(),1);
 await page.locator('#iw-clear').click();await page.locator('#iw-search').fill('GLO-EJEMPLO');assert.equal(await page.locator('.iw-task').count(),1);assert.match(await page.locator('.iw-task').textContent(),/Sin plazo informado/);
 assert.equal(await page.locator('.iw-task').getByRole('link',{name:/Preparar respuesta/}).getAttribute('href'),'#/glosas/glosa-a');
 await page.locator('#iw-search').fill('no coincide');assert.equal(await page.locator('.iw-task').count(),0);assert.match(await page.locator('#iw-task-list').textContent(),/No hay tareas con estos filtros/);
 await page.locator('#iw-clear').click();await page.locator('#iw-client').selectOption('org-b');assert.equal(await page.locator('.iw-task').count(),1);await page.locator('#iw-refresh').click();await page.waitForFunction(()=>document.querySelector('#iw-client')?.value==='org-b');assert.equal(await page.locator('.iw-task').count(),1,'Filtros conservados tras actualizar');
 await page.locator('#iw-clear').click();await page.locator('#iw-assignee').selectOption('user-a');assert.equal(await page.locator('.iw-task').count(),2);
 await page.locator('#iw-clear').click();await page.getByRole('button',{name:'Vencen hoy',exact:true}).click();assert.equal(await page.locator('.iw-task').count(),1,'Plazo nulo no se confunde con hoy');
 await page.locator('#iw-clear').click();await page.locator('[data-type="captura_incompleta"]').click();await page.waitForFunction(()=>document.querySelectorAll('.iw-task').length===1);assert.equal(await page.evaluate(()=>calls.at(-1).args.p_type),'captura_incompleta');
 await page.getByRole('tab',{name:'Resumen diario',exact:true}).click();await page.waitForFunction(()=>digestCalled);assert.match(await page.locator('[role="tabpanel"]').textContent(),/Resumen diario conservado/);
 await page.evaluate(()=>renderInbox('billing'));assert.equal(await page.getByRole('tab',{name:'Asignaciones',exact:true}).count(),0);assert.equal(await page.locator('#iw-assignee').count(),0);assert.equal(await page.getByRole('button',{name:'Sin responsable',exact:true}).count(),0);
 assert.equal(await page.locator('.iw-task a[href^="#/glosas"]').count(),0,'No enlazar módulos fuera del rol');
 for(const width of[1440,768,390,320]){await page.setViewportSize({width,height:1000});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin overflow '+width);}
 await page.evaluate(()=>{window.failInbox=true;});await page.locator('#iw-refresh').click();await page.getByRole('alert').waitFor();assert.match(await page.locator('main').textContent(),/Fallo de lectura/);
 assert.equal(await page.evaluate(()=>calls.some(c=>/save|set|delete|close/.test(c.name))),false,'Solo lecturas');assert.deepEqual(errors,[]);
 console.log('PASS: bandeja real por tareas, filtros y búsqueda local, plazo nulo, enlaces autorizados, pestañas/resumen, errores, móvil y sin escrituras.');
}finally{await browser.close();}
