import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{const page=await browser.newPage(),errors=[];page.setDefaultTimeout(8000);page.on('pageerror',e=>errors.push(e.message));
await page.route('**/*',async route=>{const p=new URL(route.request().url()).pathname;
const mock={
'/':'<main></main>',
'/js/utils/diag-log.js':'export function logDiag(){}',
'/js/modules/submission-dialogs.js':'export const lineDialog=async()=>{},importDialog=async()=>{},checklistDialog=async()=>{},radicarDialog=async()=>{},overrideDialog=async()=>{},commentDialog=async()=>{};',
'/js/services/finance.js':'export const listGlosas=async()=>({data:[]}),submissionPayments=async()=>[];',
'/js/services/dossier.js':'export const getDelivery=async()=>null,markSubmissionSent=async()=>{};',
'/js/services/documents.js':'export const listDocuments=async()=>[],uploadDocument=async()=>{},openDocument=async()=>{},deleteDocument=async()=>{},fileProblem=()=>null,sizeLabel=()=>"",safeName=s=>s;',
'/js/services/camera.js':'export const procesarFoto=async()=>{},subirCaptura=async()=>{},sha256=async()=>{};',
'/js/services/iter18.js':'export const rpc=async()=>structuredClone(window.dossier),supabase={};',
'/js/services/submissions.js':`export const getSubmission=async()=>({...window.sub}),listLines=async()=>[],lineChecklist=async()=>[],requirements=async()=>[],documentTypes=async()=>[],lineChecks=async()=>[],transitionsFrom=async()=>[],statusHistory=async()=>[],profileNames=async()=>({}),organizationContact=async()=>null;
export const validateSubmission=async()=>({items:[],passed:0,total:0,critical_ok:true}),changeStatus=async()=>{},deleteSubmission=async()=>{},deleteLine=async()=>{};
export async function updateSubmission(id,v){window.updates.push(v);Object.assign(window.sub,v);}`, 
'/js/services/claims.js':`export const getFiscal=async()=>({...window.sub,organizations:{}}),fiscalCheck=async()=>null,saveFiscal=async()=>{window.fiscalSaves++},authorizeFiscalDifference=async()=>{},submissionLineAllocations=async()=>[],submissionFamily=async()=>null,submissionClaimMoney=async()=>[],claimDuplicateCandidates=async()=>[],reviewClaimDuplicate=async()=>{};
export async function setSubmissionEcf(id,v){window.ecfSaves.push(v);Object.assign(window.sub,{ncf:v.ncf,ecf_security_code:v.code,ecf_signed_on:v.signed,ecf_dgii_status:v.status});return true;}
export const getClaim=async()=>window.dossierClaim;`
};if(p in mock)return route.fulfill({contentType:p==='/'?'text/html':'text/javascript',body:mock[p]});try{return route.fulfill({contentType:'text/javascript',body:await readFile(new URL(p.slice(1),root))});}catch{return route.fulfill({status:404});}});
await page.goto('http://127.0.0.1:8881/');
await page.evaluate(async()=>{window.sub={id:'s',folio:'RAD-QA',organization_id:'o',ars_id:'a',ars_name:'ARS ficticia',status:'borrador',display_status:'borrador',provider_code_status:'codificado',period:'2026-10-01',notes:'Original',docs_pct:0,lines:0};window.updates=[];window.ecfSaves=[];window.fiscalSaves=0;const m=await import('/js/modules/submission.js');window.show=role=>m.render(document.querySelector('main'),{arg:'s',role,setTitle(){}});await show('admin');});
await page.locator('#ncf').waitFor();await page.locator('#ncf').fill('E310000000001');await page.locator('#invd').fill('2026-11-05');await page.locator('#nts').fill('Notas conservadas');
await page.getByRole('button',{name:'Guardar factura',exact:true}).click();assert.equal(await page.evaluate(()=>updates.length),0);assert.equal(await page.locator('#ncf').getAttribute('aria-invalid'),'true');
await page.locator('[data-register-ecf]').click();await page.locator('dialog').waitFor();assert.equal(await page.locator('dialog [name=ncf]').inputValue(),'E310000000001');
// Correct length: E31 plus 10 digits; keep all metadata in the controlled RPC.
await page.locator('dialog [name=ncf]').fill('E310000000001');await page.locator('dialog [name=code]').fill('ABC123');await page.locator('dialog [name=signed]').fill('2026-11-05');
await page.getByRole('button',{name:'Guardar e-CF',exact:true}).click();await page.locator('dialog').waitFor({state:'detached'});
await page.waitForFunction(()=>document.querySelector('#ncf').value==='E310000000001',null,{timeout:8000});assert.equal(await page.locator('#nts').inputValue(),'Notas conservadas');assert.equal(await page.locator('#invd').inputValue(),'2026-11-05');
await page.getByRole('button',{name:'Guardar factura',exact:true}).click();await page.waitForFunction(()=>updates.length===1);assert.equal(await page.evaluate(()=>sub.notes),'Notas conservadas');
await page.locator('[data-invoice-focus]').click();assert.equal(await page.locator('#ncf').evaluate(el=>el===document.activeElement),true);assert.equal(await page.evaluate(()=>location.hash),'');
await page.evaluate(()=>show('billing'));assert.equal(await page.locator('#fiscForm').count(),0);assert.equal(await page.locator('#ecfBtn').count(),0);
await page.evaluate(async()=>{window.dossier={organization_id:'o',submission_id:'s',ars:null,submission_folio:null};window.dossierClaim={organization_id:'o',submission_id:'s',ars_id:'a',ars_name:'ARS recuperada',submission_folio:'RAD-QA'};window.detailService=await import('/js/services/expediente.js');});
assert.equal(await page.evaluate(async()=>(await detailService.detalleExpediente('line')).ars),'ARS recuperada');
await page.evaluate(()=>dossierClaim.organization_id='otra');assert.equal(await page.evaluate(async()=>(await detailService.detalleExpediente('line')).ars),null);
assert.deepEqual(errors,[]);console.log('PASS: e-NCF por RPC controlada, datos pendientes conservados, guardar fecha/notas, enlace local, permisos fiscales y recuperación segura de ARS');
}finally{await browser.close();}
