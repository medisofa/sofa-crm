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
 await page.evaluate(async()=>{window.line={id:'line',submission_id:'sub',claim_status:'capturada',service_date:'2026-10-19',patient_name:'Paciente ficticio',member_number:'1234567',authorization_number:'AUT123',procedure_id:'proc',quantity:1,unit_amount:750,notes:'Notas originales'};window.sub={id:'sub',status:'borrador',period:'2026-10-01',ars_id:'ars',ars_name:'ARS ficticia',provider_id:'provider',organization_id:'org'};window.editCalls=[];const m=await import('/js/modules/claim.js');window.show=async(role='admin')=>m.render(document.querySelector('main'),{arg:'line',role,setTitle(){}});await show();});
 await page.getByRole('button',{name:'Editar servicio, cantidad y monto',exact:true}).click();
 await page.locator('dialog').waitFor();assert.equal(await page.locator('[name=unit_amount]').inputValue(),'750');
 await page.locator('[name=unit_amount]').fill('850');await page.getByRole('button',{name:'Cancelar',exact:true}).click();
 assert.equal(await page.evaluate(()=>line.unit_amount),750);
 await page.getByRole('button',{name:'Editar servicio, cantidad y monto',exact:true}).click();
 await page.locator('[name=unit_amount]').fill('850');await page.locator('[name=quantity]').fill('0');
 await page.getByRole('button',{name:'Guardar cambios',exact:true}).click();assert.equal(await page.locator('[name=quantity]').getAttribute('aria-invalid'),'true');
 await page.locator('[name=quantity]').fill('2');await page.evaluate(()=>failSave=true);
 await page.getByRole('button',{name:'Guardar cambios',exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await page.locator('[name=unit_amount]').inputValue(),'850');
 await page.evaluate(()=>failSave=false);await page.getByRole('button',{name:'Guardar cambios',exact:true}).click();await page.locator('dialog').waitFor({state:'detached'});
 await page.waitForFunction(()=>document.querySelector('main').textContent.includes('1,700'));
 assert.equal(await page.evaluate(()=>line.notes),'Notas originales');assert.equal(await page.evaluate(()=>line.id),'line');
 for(const status of ['radicada','pagada','validada']){await page.evaluate(async status=>{line.claim_status=status;await show();},status);assert.equal(await page.locator('[data-edit-claim]').count(),0);}
 await page.evaluate(async()=>{line.claim_status='capturada';sub.status='radicada';await show();});assert.equal(await page.locator('[data-edit-claim]').count(),0);
 await page.evaluate(async()=>{sub.status='borrador';await show('auditor');});assert.equal(await page.locator('[data-edit-claim]').count(),0);
 await page.evaluate(()=>show('client'));assert.equal(await page.locator('[data-edit-claim]').count(),2);
 assert.deepEqual(errors,[]);console.log('PASS: edición desde ficha con formulario existente, cancelación, validación, error sin pérdida, actualización y bloqueo por estado/rol');
}finally{await browser.close();}
