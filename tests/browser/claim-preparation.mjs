/** Preparing submissions with synthetic records; no network or writes to real services. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/preview.html')return route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="es" data-theme="light"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><link rel="stylesheet" href="/css/claim-preparation.css"><main class="page"></main></html>'});
  if(u.pathname==='/js/services/claims.js')return route.fulfill({contentType:'text/javascript',body:`export const captureProviders=async()=>[{id:'doctor-a',full_name:'Dra. de ejemplo A'}],activeArs=async()=>[{id:'ars-a',name:'ARS de ejemplo A'}];export async function listClaims(args){window.claimReads.push(args);if(window.failClaims)throw Error('No se pudo comprobar');return {data:structuredClone(window.claims),count:2000};}`});
  if(u.pathname==='/js/services/dossier.js')return route.fulfill({contentType:'text/javascript',body:`export async function preradBatches(args){window.lotReads.push(args);if(window.failLots)throw Error('Consulta de lotes falló');return structuredClone(window.batches.filter(b=>!args.readyOnly||(b.claims_ready&&b.fiscal_ok)));}`});
  if(u.pathname==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return route.fulfill({status:404,body:'Missing '+u.pathname});}
 });
 await page.goto('http://127.0.0.1:8898/preview.html');
 await page.evaluate(async()=>{
  window.claimReads=[];window.lotReads=[];window.failClaims=false;window.failLots=false;
  const base={period:'2026-11-01',status:'borrador',provider_name:'Dra. de ejemplo A',ars_name:'ARS de ejemplo A',claimed:1500,claims:2,validated:0,dossier_ok:1,fiscal_amount:null,fiscal_ok:false,claims_ready:false,in_clinic:0,in_review:1,inconsistent:0};
  window.batches=[{...base,submission_id:'lot-a',folio:'RAD-EJEMPLO-001'},{...base,submission_id:'lot-b',folio:'RAD-EJEMPLO-002',claims:1,validated:1,dossier_ok:1,fiscal_amount:750,fiscal_ok:true,claims_ready:true,in_review:0,claimed:750},{...base,submission_id:'lot-conflict',folio:'RAD-EJEMPLO-003',claims:1,validated:1,dossier_ok:0,fiscal_amount:750,fiscal_ok:true,claims_ready:true,in_review:0}];
  const line={provider_name:'Dra. de ejemplo A',ars_name:'ARS de ejemplo A',service_name:'Consulta ambulatoria',service_date:'2026-11-10',claimed:750,contracted:true,dossier_ok:true,dossier_missing:0,authorization_number:'AUT-EJEMPLO',claim_status:'capturada',submission_id:'lot-a',submission_folio:'RAD-EJEMPLO-001'};
  window.claims=[{...line,id:'a',folio:'REC-EJEMPLO-001',patient_name:'Paciente de ejemplo A',authorization_number:null,dossier_ok:false,dossier_missing:1},{...line,id:'b',folio:'REC-EJEMPLO-002',patient_name:'Paciente de ejemplo B',contracted:false,discrepancy_status:'pendiente'},{...line,id:'c',folio:'REC-EJEMPLO-003',patient_name:'Paciente de ejemplo C',submission_id:'lot-b',submission_folio:'RAD-EJEMPLO-002',claim_status:'lista_para_radicar'},{...line,id:'outside',folio:'REC-FUERA',patient_name:'No mostrar fuera de los lotes',submission_id:'other-lot'}];
  window.mod=await import('/js/modules/prerad.js');await mod.render(document.querySelector('main'),{role:'admin'});
 });
 await page.locator('.cp-table tbody tr').first().waitFor();
 assert.equal(await page.locator('.cp-table tbody tr').count(),3,'Solo reclamaciones de los lotes consultados');
 assert.doesNotMatch(await page.locator('main').textContent(),/No mostrar fuera de los lotes/);
 assert.equal(await page.evaluate(()=>claimReads.length),1);assert.equal(await page.evaluate(()=>lotReads.length),1);
 assert.deepEqual(await page.evaluate(()=>claimReads[0]),{providerId:'',arsId:'',realOnly:false,page:0,size:1000});
 assert.match(await page.locator('#cp-scope').textContent(),/Vista parcial/);
 assert.equal(await page.locator('label[for="pp"]').count(),1);assert.equal(await page.locator('label[for="pa"]').count(),1);
 assert.equal(await page.locator('.cp-table a[href="#/reclamaciones/a"]').count(),2);
 await page.locator('#cp-cause').selectOption('autorizacion');assert.equal(await page.locator('.cp-table tbody tr').count(),1);assert.match(await page.locator('.cp-table').textContent(),/Verificar autorización o excepción/);
 const readCount=await page.evaluate(()=>claimReads.length);await page.locator('#cp-search').fill('EJEMPLO-001');assert.equal(await page.evaluate(()=>claimReads.length),readCount,'Filtros locales sin N+1');
 await page.locator('#cp-clear').click();await page.waitForFunction(()=>claimReads.length===2);await page.waitForFunction(()=>document.querySelectorAll('.cp-table tbody tr').length===3);
 await page.locator('#pp').selectOption('doctor-a');await page.waitForFunction(()=>claimReads.at(-1).providerId==='doctor-a');
 await page.locator('#pa').selectOption('ars-a');await page.waitForFunction(()=>claimReads.at(-1).arsId==='ars-a');
 await page.locator('[data-view="batches"]').click();assert.equal(await page.locator('.cp-batch').count(),3);
 assert.match(await page.locator('.cp-batch').filter({hasText:'RAD-EJEMPLO-003'}).textContent(),/expediente incompleto/);
 assert.doesNotMatch(await page.locator('.cp-batch').filter({hasText:'RAD-EJEMPLO-003'}).locator('header .pill').textContent(),/Lista/,'Flags inconsistentes no se presentan como listos');
 assert.match(await page.locator('.cp-batch').filter({hasText:'RAD-EJEMPLO-002'}).locator('header .pill').textContent(),/Preparación completa · comprobar lote/,'Resumen no sustituye validación final');
 assert.equal(await page.locator('#cp-cause').isDisabled(),true);
 await page.locator('#ready').check();await page.waitForFunction(()=>lotReads.at(-1).readyOnly===true);await page.waitForFunction(()=>document.querySelectorAll('.cp-batch').length===2);
 await page.evaluate(()=>window.failLots=true);await page.locator('#cp-refresh').click();await page.locator('#cp-retry').waitFor();assert.equal(await page.locator('.cp-batch').count(),2,'Error conserva resultados previos');assert.match(await page.locator('#cp-scope').textContent(),/No se pudo actualizar/);
 await page.evaluate(()=>window.failLots=false);await page.locator('#cp-retry').click();await page.waitForFunction(()=>!document.querySelector('#cp-retry'));
 await page.locator('#cp-clear').click();await page.waitForFunction(()=>document.querySelectorAll('.cp-batch').length===3);await page.locator('[data-view="claims"]').click();
 for(const width of[1440,768,390,320]){await page.setViewportSize({width,height:1100});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Sin overflow '+width);}
 await page.setViewportSize({width:1440,height:1100});
 if(process.env.SOFA_PREPARATION_SCREENSHOTS){await mkdir('/workspace/artifacts/claim-preparation',{recursive:true});await page.screenshot({path:'/workspace/artifacts/claim-preparation/pantalla.png',fullPage:true});await page.setViewportSize({width:390,height:844});await page.screenshot({path:'/workspace/artifacts/claim-preparation/movil.png',fullPage:true});}
 assert.deepEqual(errors,[]);console.log('PASS preparación: causas verificadas, cruce por lote, muestra explícita, filtros, sin N+1, error/reintento, flags contradictorios y móvil.');
}finally{await browser.close();}
