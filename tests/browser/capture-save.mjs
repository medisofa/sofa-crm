/**
 * Captura rápida: guardar de verdad. Usa los servicios reales (claims.js, calidad-dato.js, consultorio.js);
 * solo se simula Supabase. Protege la regresión del 11/11 (#146), cuando la pantalla enviaba nombres que el servicio no leía.
 */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const mocks={
  '/js/utils/diag-log.js':'export function logDiag(){}',
  '/js/modules/dossier-card.js':'export const dossierPill=()=>"";',
  '/js/modules/captura-camara.js':'export const initCamara=()=>({hayPendientes:()=>true,limpiar(){window.log.push("limpiar")},subirPendientes:async(c,o)=>{window.log.push("subir:"+c.id+":"+c.submission_id+":"+o);return {subidas:1,fallas:[]}}});',
  '/js/modules/capture-identifiers.js':'export const captureIdentifiers=()=>async()=>{};',
  '/js/services/dossier.js':'export const requiredDocsPreview=async()=>[];export const dossierStatus=async()=>({});',
  '/js/supabase.js':`
   const data={providers:[{id:'prov',full_name:'Médico QA',organization_id:'org'}],ars:[{id:'ars',code:'QA',name:'ARS QA',portal_url:'https://example.invalid/pss'}],
     appointments:{id:'cita1',provider_id:'prov',ars_id:'ars',appointment_date:'2026-11-20',patient_name:'Paciente Cita',member_number:'99887766',authorization_number:'AUT-C',patient_doc:''},v_claims:[]};
   const q=(t)=>{const p=new Proxy({},{get:(_,k)=>k==='then'?(ok)=>ok({data:data[t]??[],error:null}):()=>p});return p;};
   export const sb=()=>({from:q,rpc:async(name,args)=>{window.calls.push({name,args});
     if(name==='contracted_services')return {data:[{procedure_id:'proc',name:'Consulta QA',amount:1000,valid_from:'2026-01-01'}],error:null};
     if(name==='capture_claim_dx')return {data:{id:'linea',submission_id:'lote',folio:'REC-QA',status:'capturada'},error:null};
     if(name==='patient_lookup')return {data:[],error:null};
     return {data:null,error:null};}});`
 };
 await page.route('**/*',async route=>{const p=new URL(route.request().url()).pathname;
  if(p==='/')return route.fulfill({contentType:'text/html',body:'<main></main><div id="toasts"></div>'});
  return route.fulfill({contentType:p.endsWith('.css')?'text/css':'text/javascript',body:mocks[p]??await readFile(new URL(p.slice(1),root))});});
 await page.goto('http://127.0.0.1:8882/');
 const open=(ctx)=>page.evaluate(async(ctx)=>{window.calls=[];window.log=[];const m=await import('/js/modules/capture.js');await m.render(document.querySelector('main'),ctx);},ctx);

 // 1. Captura normal: todos los datos llegan al servidor, la foto sube antes de limpiar.
 await open({role:'capturer'});
 await page.locator('#c_srv option[value="proc"]').waitFor({state:'attached'});
 assert.notEqual(await page.locator('#c_date').inputValue(),'');           // la fecha viene prellenada
 assert.equal(await page.locator('#arsPortalBtn').count(),1);              // se conserva el botón del portal
 await page.locator('#c_pat').fill('Paciente QA');await page.locator('#c_nss').fill('123456789');await page.locator('#c_auth').fill('AUT-1');
 await page.locator('#c_dx').fill('I10');await page.locator('#c_amt').fill('1200');await page.locator('#d_reason').fill('Ajuste autorizado QA');
 await page.locator('#save').click();
 await page.waitForFunction(()=>window.log.includes('limpiar'));
 const a=await page.evaluate(()=>calls.find(c=>c.name==='capture_claim_dx').args);
 assert.deepEqual([a.p_provider,a.p_ars,a.p_procedure,a.p_patient_name,a.p_member,a.p_authorization,a.p_diagnosis,a.p_amount,a.p_discrepancy_reason,a.p_quantity,a.p_allow_duplicate],
   ['prov','ars','proc','Paciente QA','123456789','AUT-1','I10',1200,'Ajuste autorizado QA',1,false]);
 assert.ok(a.p_service_date);
 assert.deepEqual(await page.evaluate(()=>log.slice(0,2)),['subir:linea:lote:org','limpiar']);

 // 2. Desde la agenda: se prellena con la cita y al guardar la cita queda vinculada.
 await open({role:'capturer',arg:'cita-cita1'});
 await page.locator('#c_srv option[value="proc"]').waitFor({state:'attached'});
 assert.equal(await page.locator('#c_pat').inputValue(),'Paciente Cita');
 assert.equal(await page.locator('#c_nss').inputValue(),'99887766');
 await page.locator('#c_srv').selectOption('proc');
 await page.locator('#save').click();
 await page.waitForFunction(()=>location.hash==='#/hoy');
 assert.deepEqual(await page.evaluate(()=>calls.find(c=>c.name==='link_appointment_claim').args),{p_appointment:'cita1',p_line:'linea'});
 assert.deepEqual(errors,[]);
 console.log('PASS: captura guarda todos los datos, sube la foto, conserva el portal ARS y cierra la cita de la agenda');
}finally{await browser.close();}
