import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const p=new URL(route.request().url()).pathname;
  const mocks={
   '/':'<main></main>',
   '/js/modules/dossier-card.js':'export function renderDossier(){}',
   '/js/services/claim-agent-runner.js':'export async function runClaimPreaudit(){return {checks:[]};}',
   '/js/utils/diag-log.js':'export function logDiag(){}',
   '/js/services/claim-authorization.js':`export async function adminSetClaimAuthorization(v){window.authCalls.push(v);if(window.failAuth)throw Error('No se pudo guardar la autorización');if(window.line.authorization_number!==v.expectedNumber)throw Error('La autorización cambió desde que abrió la ficha. Recargue para revisar el valor actual.');window.line.authorization_number=v.number;return {id:v.lineId,authorization_number:v.number,changed:true};}`,
   '/js/services/catalog.js':'export async function listArs(){return [];}',
   '/js/services/claims.js':`export async function getClaim(){return {...window.line,folio:'REC-QA',service_name:'Consulta',claimed:window.line.quantity*window.line.unit_amount,provider_name:'Médico ficticio',ars_name:'ARS ficticia',contracted:true,tariff_amount:850};}
    export const claimHistory=async()=>[],claimAudits=async()=>[],claimDiscrepancies=async()=>[],claimChecks=async()=>null,claimLocations=async()=>[],claimTransitions=async()=>[],claimPaymentLines=async()=>[],claimGlosaItems=async()=>[],claimTimeline=async()=>[],claimResubmissions=async()=>[];
    export const recheckContract=async()=>{},resubmitClaims=async()=>{};`,
   '/js/services/submissions.js':`export const profileNames=async()=>({}),getSubmission=async()=>window.sub,getLine=async()=>({...window.line});
    export const newSubmission=async()=>{},activeProviders=async()=>[],providerCodes=async()=>[],importLines=async()=>{},setLineCheck=async()=>{},addLine=async()=>{};
    export async function procedureOptions(){return {procs:[{id:'proc',description:'Consulta',internal_code:'P01'}],tariffs:[{procedure_id:'proc',amount:850,valid_during:'[2026-01-01,)'}]};}
    export const lookupTariff=async()=>({amount:850,scope:'contractual'}),checkDuplicate=async()=>[];
    export async function updateLine(id,v){window.editCalls.push({id,...v});if(window.failSave)throw new Error('No se pudo guardar');Object.assign(window.line,v,{unit_amount:Number(v.unit_amount),quantity:Number(v.quantity)});return {id};}`
  };
  if(p in mocks)return route.fulfill({contentType:p==='/'?'text/html':'text/javascript',body:mocks[p]});
  try{return route.fulfill({contentType:'text/javascript',body:await readFile(new URL(p.slice(1),root))});}catch{return route.fulfill({status:404,body:'missing'});}
 });
 await page.goto('http://127.0.0.1:8881/');
 await page.evaluate(async()=>{window.line={id:'line',submission_id:'sub',claim_status:'capturada',service_date:'2026-10-19',patient_name:'Paciente ficticio',member_number:'1234567',authorization_number:'AUT123',procedure_id:'proc',quantity:1,unit_amount:750,notes:'Notas originales'};window.sub={id:'sub',status:'borrador',period:'2026-10-01',ars_id:'ars',ars_name:'ARS ficticia',provider_id:'provider',organization_id:'org'};window.editCalls=[];const m=await import('/js/modules/claim.js');window.show=async(role='admin',viewAs=null)=>m.render(document.querySelector('main'),{arg:'line',role,viewAs,setTitle(){}});await show();});

 await page.evaluate(async()=>{window.authCalls=[];window.line.authorization_number=null;window.line.claim_status='radicada';window.sub.status='radicada';await show();});
 assert.equal(await page.locator('[data-edit-claim]').count(),0,'No abrir edición financiera postradicación');
 await page.getByRole('button',{name:'Registrar autorización',exact:true}).click();
 await page.locator('#ca-number').fill('00123456789');await page.locator('#ca-reason').fill('corto');
 await page.getByRole('button',{name:'Guardar autorización',exact:true}).click();assert.equal(await page.locator('#ca-reason').getAttribute('aria-invalid'),'true');
 await page.locator('#ca-reason').fill('Autorización recibida de la ARS después de cargar.');await page.evaluate(()=>window.failAuth=true);
 await page.getByRole('button',{name:'Guardar autorización',exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await page.locator('#ca-number').inputValue(),'00123456789');
 await page.evaluate(()=>window.failAuth=false);await page.getByRole('button',{name:'Guardar autorización',exact:true}).click();await page.getByRole('dialog').waitFor({state:'detached'});
 await page.waitForFunction(()=>document.querySelector('main').textContent.includes('00123456789'));
 assert.equal(await page.evaluate(()=>line.claim_status),'radicada');assert.equal(await page.evaluate(()=>line.unit_amount),750);
 const last=await page.evaluate(()=>authCalls.at(-1));assert.deepEqual(last,{lineId:'line',number:'00123456789',reason:'Autorización recibida de la ARS después de cargar.',expectedNumber:null});
 for(const state of ['capturada','validada','lista_para_radicar','radicada','en_proceso_ars','pago_parcial','pagada','cerrada']){
  await page.evaluate(async state=>{line.claim_status=state;await show('admin');},state);assert.equal(await page.locator('#editAuthorization').count(),1);
  await page.evaluate(()=>show('super_admin'));assert.equal(await page.locator('#editAuthorization').count(),1);
 }
 await page.getByRole('button',{name:'Corregir autorización',exact:true}).click();await page.locator('#ca-number').fill('009999');await page.locator('#ca-reason').fill('Corregir referencia de la ARS.');
 await page.evaluate(()=>window.line.authorization_number='CAMBIO-CONCURRENTE');
 await page.getByRole('button',{name:'Guardar autorización',exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await page.locator('#ca-number').inputValue(),'009999');assert.equal(await page.evaluate(()=>line.authorization_number),'CAMBIO-CONCURRENTE');await page.keyboard.press('Escape');
 for(const role of ['billing','operations','auditor','client','capturer']){await page.evaluate(role=>show(role),role);assert.equal(await page.locator('#editAuthorization').count(),0,'Perfil restringido '+role);}
 await page.evaluate(()=>show('super_admin',{orgId:'org'}));assert.equal(await page.locator('#editAuthorization').count(),0,'Soporte readonly');
 await page.evaluate(async()=>{await show('admin');});
 await page.getByRole('button',{name:'Corregir autorización',exact:true}).click();
 for(const width of [390,320]){await page.setViewportSize({width,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Sin overflow '+width);}
 assert.deepEqual(errors,[]);console.log('PASS: autorización administrativa en estados cargados/radicados/pagados; motivo, error sin pérdida, ceros iniciales, concurrencia, roles y soporte; no edición financiera.');
}finally{await browser.close();}
