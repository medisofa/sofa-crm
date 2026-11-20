/** Confirmed duplicate review stays blocked until a separate authorized resolution; fictional records only. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];
 page.on('pageerror',error=>errors.push(error.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();
  const mocks={
   '/':'<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>',
   '/js/modules/opening-history.js':'export const OPENING_ROLES=[];export function mountOpeningHistoryPicker(){}',
   '/js/modules/clients.js':'export const pager=()=>"";',
   '/js/utils/diag-log.js':'export function logDiag(){}',
   '/js/supabase.js':'export const sb=()=>({});',
   '/js/services/claims.js':`
    export async function listClaims(args){return {data:args.size===1000?[{id:'line-a'}]:[],count:0};}
    export async function claimCounts(){return [];}
    export async function claimLocations(){return [];}
    export async function claimTransitions(){return [];}
    export async function captureProviders(){return [];}
    export async function activeArs(){return [];}
    export async function claimDuplicateCandidates(){window.candidateChecks++;return [structuredClone(window.duplicate)];}
    export async function reviewClaimDuplicate(){window.reviewWrites++;}
    export async function requestClaimDuplicateExclusion(input){window.requestWrites.push(structuredClone(input));if(window.failRequest)throw Error('No se pudo solicitar');window.requests=[{id:'request-demo',status:'pendiente',keep_line:input.keepLine,exclude_line:input.keepLine===input.lineA?input.lineB:input.lineA,line_a:input.lineA,line_b:input.lineB,reason:input.reason,created_at:'2026-11-10T15:00:00Z'}];return {id:'request-demo',status:'pendiente'};}
    export async function listClaimDuplicateResolutionRequests(lineA,lineB){window.requestReads.push({lineA,lineB});if(window.failRequestRead)throw Error('No se pudo consultar');return structuredClone(window.requests);}
   `
  };
  if(u.pathname in mocks)return route.fulfill({contentType:u.pathname==='/'?'text/html':'text/javascript',body:mocks[u.pathname]});
  try{return route.fulfill({body:await readFile(new URL(u.pathname.slice(1),root)),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});}catch{return route.fulfill({status:404,body:'Missing '+u.pathname});}
 });
 await page.goto('http://127.0.0.1:8898/');
 await page.evaluate(async()=>{
  window.candidateChecks=0;window.reviewWrites=0;window.requestWrites=[];window.requestReads=[];window.requests=[];window.refreshes=0;
  window.duplicate={line_id:'line-a',other_line_id:'line-b',folio:'REC-EJEMPLO-001',other_folio:'REC-EJEMPLO-002',patient_name:'Paciente de ejemplo',member_number:'NSS-FICTICIO',service_date:'2026-09-28',authorization_date:'2026-09-28',authorization_number:'AUT-DEMO',other_authorization_number:'AUT-DEMO',service_name:'Consulta de ejemplo',other_service_name:'Consulta de ejemplo',matched_fields:['NSS','Fecha servicio','Fecha autorización','Autorización','Servicio'],risk:'critico',blocks_radicacion:true,review_decision:'duplicado_confirmado',suggested_solution:'Conserve la correcta y retire la duplicada.'};
  window.claimsModule=await import('/js/modules/claims.js');await claimsModule.render(document.querySelector('main'),{role:'admin'});
 });
 await page.locator('#coreDup .dup-group').waitFor();
 const core=page.locator('#coreDup');
 assert.match(await core.textContent(),/duplicado confirmado/i);
 assert.match(await core.textContent(),/bloquea radicación|pendiente de resol/i);
 assert.equal(await core.locator('.pill.ok').filter({hasText:/duplicado confirmado/i}).count(),0,'Revisión bloqueante no se presenta verde');
 await page.evaluate(async()=>{window.resolver=await import('/js/modules/duplicate-resolution.js');window.openResolution=(ctx={})=>resolver.resolveDuplicateDialog(duplicate,{role:'admin',viewAs:null,onRefresh:async()=>{window.refreshes++;window.lastCandidates=await(await import('/js/services/claims.js')).claimDuplicateCandidates();},...ctx});window.openResolution();});
 await page.getByRole('dialog').waitFor();
 // Remaining dialog assertions bind to the stable labels agreed with the UI implementation.
 const dialog=page.getByRole('dialog').first();
 assert.equal(await page.locator('#dr-action').inputValue(),'','Acción sin predeterminar');
 await page.locator('#dr-action').selectOption('corregir');
 assert.equal(await page.locator('#dr-correction a[href="#/reclamaciones/line-a"]').count(),1);
 assert.equal(await page.locator('#dr-correction a[href="#/reclamaciones/line-b"]').count(),1);
 assert.equal(await page.evaluate(()=>requestWrites.length),0,'Mostrar opciones de corrección no solicita ni modifica');
 await page.locator('#dr-action').selectOption('excluir');
 assert.equal(await page.locator('#dr-keep').inputValue(),'','Ninguna reclamación se conserva por defecto');
 await page.getByRole('button',{name:'Solicitar exclusión',exact:true}).click();
 assert.equal(await page.locator('#dr-keep').getAttribute('aria-invalid'),'true');
 assert.equal(await page.evaluate(()=>requestWrites.length),0);
 await page.locator('#dr-keep').selectOption('line-b');
 await page.locator('#dr-reason').fill('corto');
 await page.getByRole('button',{name:'Solicitar exclusión',exact:true}).click();
 assert.equal(await page.locator('#dr-reason').getAttribute('aria-invalid'),'true');
 assert.equal(await page.evaluate(()=>requestWrites.length),0);
 const reason='Conservar la reclamación correcta y revisar la duplicada.';
 await page.locator('#dr-reason').fill(reason);
 await page.getByRole('button',{name:'Solicitar exclusión',exact:true}).click();
 const confirmation=page.getByRole('dialog',{name:'Confirmar solicitud de exclusión',exact:true});await confirmation.waitFor();
 assert.match(await confirmation.textContent(),/REC-EJEMPLO-002/,'Confirmación muestra reclamación conservada');
 assert.match(await confirmation.textContent(),/REC-EJEMPLO-001/,'Confirmación muestra candidata a excluir');
 await confirmation.getByRole('button',{name:'Cancelar',exact:true}).click();
 assert.equal(await page.evaluate(()=>requestWrites.length),0,'Cancelar confirmación no escribe');
 await page.getByRole('button',{name:'Solicitar exclusión',exact:true}).click();
 await page.getByRole('dialog',{name:'Confirmar solicitud de exclusión',exact:true}).getByRole('button',{name:'Registrar solicitud',exact:true}).click();
 await page.waitForFunction(()=>requestWrites.length===1);
 assert.deepEqual(await page.evaluate(()=>requestWrites[0]),{lineA:'line-a',lineB:'line-b',keepLine:'line-b',reason});
 await page.waitForFunction(()=>refreshes>=1);
 assert.equal(await page.evaluate(()=>duplicate.blocks_radicacion),true,'La solicitud no desbloquea el par');
 assert.equal(await page.evaluate(()=>reviewWrites),0,'La solicitud no altera la decisión de revisión');
 assert.equal(await page.evaluate(()=>lastCandidates[0].blocks_radicacion),true,'Reconsulta sigue bloqueando');
 await page.getByRole('dialog').waitFor({state:'detached'});
 await page.evaluate(()=>{window.openResolution();});await page.getByRole('dialog').waitFor();
 assert.equal(await page.locator('#dr-action option[value="excluir"]').isDisabled(),true,'Solicitud pendiente impide duplicar solicitudes');
 assert.match(await page.getByRole('dialog').textContent(),/Pendiente de gestión/);
 for(const width of [390,320]){
  await page.setViewportSize({width,height:844});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin desbordamiento móvil');
  const dialog=page.getByRole('dialog');
  assert.ok(await dialog.evaluate(el=>el.getBoundingClientRect().width<=innerWidth),'Diálogo dentro del ancho móvil');
  await page.locator('#dr-action').selectOption('corregir');
  await page.locator('#dr-correction a').first().scrollIntoViewIfNeeded();
  assert.equal(await page.locator('#dr-correction a').first().isVisible(),true,'Enlaces alcanzables en móvil');
 }
 await page.setViewportSize({width:1440,height:1000});
 // Screenshots contain only synthetic records.
 if(process.env.SOFA_DUPLICATE_SCREENSHOTS){await mkdir('/workspace/artifacts/duplicate-resolution',{recursive:true});await page.screenshot({path:'/workspace/artifacts/duplicate-resolution/solicitud.png',fullPage:true});}
 await page.locator('#dr-recheck').click();await page.waitForFunction(()=>refreshes>=2);
 assert.equal(await page.evaluate(()=>lastCandidates[0].blocks_radicacion),true);
 await page.keyboard.press('Escape');await page.getByRole('dialog').waitFor({state:'detached'});
 const writesBefore=await page.evaluate(()=>requestWrites.length);
 await page.evaluate(()=>{window.requests=[];window.openResolution({viewAs:{orgId:'org-demo'}});});
 if(await page.getByRole('dialog').count()){
  assert.equal(await page.locator('#dr-action option[value="excluir"]').isDisabled(),true,'Soporte no puede elegir exclusión');
  assert.equal(await page.locator('button[type=submit]:enabled').filter({hasText:'Solicitar exclusión'}).count(),0);
  await page.keyboard.press('Escape');
 }
 assert.equal(await page.evaluate(()=>requestWrites.length),writesBefore,'Soporte no solicita exclusión');
 assert.deepEqual(errors,[]);
 console.log('PASS: duplicado confirmado permanece bloqueante; selección explícita, motivo, confirmación, solicitud exacta sin borrado/desbloqueo, corrección, reconsulta y soporte.');
}finally{await browser.close();}
