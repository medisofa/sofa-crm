/** Lote y reclamaciones ficticios. Fuentes fallidas no se presentan como controles aprobados. */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}}),errors=[];page.setDefaultTimeout(8000);page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const url=new URL(route.request().url()),path=url.pathname;if(url.hostname!=='127.0.0.1')return route.abort();
  const mocks={
   '/':'<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/components.css"><link rel="stylesheet" href="/css/app.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main>',
   '/js/utils/diag-log.js':'export function logDiag(){}',
   '/js/modules/submission-dialogs.js':'export const lineDialog=async()=>{},importDialog=async()=>{},checklistDialog=async()=>{},radicarDialog=async()=>{},overrideDialog=async()=>{},commentDialog=async()=>{};',
   '/js/services/finance.js':`export async function listGlosas(){if(window.fail.glosas)throw Error('Glosas sin respuesta');return {data:[]};}export async function submissionPayments(){if(window.fail.pays)throw Error('Pagos sin respuesta');return [];}`,
   '/js/services/dossier.js':'export const getDelivery=async()=>null,markSubmissionSent=async()=>{};',
   '/js/services/documents.js':`export async function listDocuments(){if(window.fail.docs)throw Error('Documentos sin respuesta');return [];}export const uploadDocument=async()=>{},openDocument=async()=>{},deleteDocument=async()=>{},fileProblem=()=>null,sizeLabel=()=>'',safeName=s=>s;`,
   '/js/services/submissions.js':`export const getSubmission=async()=>({...window.sub}),listLines=async()=>window.lines,requirements=async()=>[],documentTypes=async()=>[],transitionsFrom=async()=>[{to_code:'lista_para_radicar',allowed_roles:['admin'],requires_validation:true}],statusHistory=async()=>[],profileNames=async()=>({}),organizationContact=async()=>null,deleteSubmission=async()=>{},deleteLine=async()=>{};
export async function lineChecklist(){if(window.fail.lineChecklist)throw Error('Checklist sin respuesta');return [{service_line_id:'line-a',required:0,pct:100}];}export async function lineChecks(){if(window.fail.checks)throw Error('Checks sin respuesta');return [];}
export async function validateSubmission(){if(window.fail.validation)throw Error('Validación sin respuesta');return {items:[],passed:0,total:0,critical_ok:true};}export async function changeStatus(){window.moves++;}export const updateSubmission=async()=>{};`,
   '/js/services/claims.js':`export async function getFiscal(){if(window.fail.fiscal)throw Error('Factura sin respuesta');return {...window.sub,organizations:{}};}export async function fiscalCheck(){if(window.fail.fiscalCheck)throw Error('Control fiscal sin respuesta');if(window.nullFiscalCheck)return null;if(window.nullFiscalOk)return {registered:true,ok:null,matches:false,excepted:null,mode:'bloquear',total:750,fiscal_amount:700,difference:50};return {registered:true,ok:true,matches:true,total:750,fiscal_amount:750,difference:0};}export const saveFiscal=async()=>{},authorizeFiscalDifference=async()=>{},submissionFamily=async()=>null,reviewClaimDuplicate=async()=>{};
export async function submissionLineAllocations(){if(window.fail.distribution)throw Error('Reparto sin respuesta');return [];}export async function submissionClaimMoney(){if(window.fail.claimMoney)throw Error('Importes sin respuesta');return [];}
export async function claimDuplicateCandidates(){if(window.fail.duplicates)throw Error('Duplicados sin respuesta');return window.pairs;}`
  };
  if(path in mocks)return route.fulfill({contentType:path==='/'?'text/html':'text/javascript',body:mocks[path]});
  try{return route.fulfill({contentType:path.endsWith('.css')?'text/css':'text/javascript',body:await readFile(new URL(path.slice(1),root))});}catch{return route.fulfill({status:404,body:'Missing'});}
 });
 await page.goto('http://127.0.0.1:8897/');
 await page.evaluate(async()=>{
  window.fail={validation:true,fiscal:true,fiscalCheck:true,lineChecklist:true,checks:true,docs:true,duplicates:true,pays:true,glosas:true,distribution:true,claimMoney:true};window.moves=0;window.nullFiscalCheck=false;
  window.sub={id:'lot-a',folio:'RAD-EJEMPLO',organization_id:'org-a',ars_id:'ars-a',ars_name:'ARS de ejemplo',status:'radicada',display_status:'radicada',provider_code_status:'codificado',period:'2026-10-01',submitted_on:'2026-10-30',notes:'Original',docs_pct:100,lines:1,claimed:750,paid:0,balance:750};
  window.lines=[{id:'line-a',claim_folio:'REC-EJEMPLO-A',patient_name:'Paciente de ejemplo',member_number:'FICTICIO-001',authorization_number:null,service_date:'2026-10-20',quantity:1,unit_amount:750,amount:750,claim_status:'capturada'}];
  window.pairs=[{line_id:'line-a',other_line_id:'line-b',folio:'REC-EJEMPLO-A',other_folio:'REC-EJEMPLO-B',patient_name:'Paciente de ejemplo',matched_fields:['NSS','Fecha servicio'],review_decision:'duplicado_confirmado',blocks_radicacion:true,resolution_request_status:'pendiente'}];
  const module=await import('/js/modules/submission.js');window.show=()=>module.render(document.querySelector('main'),{arg:'lot-a',role:'admin',setTitle(){}});await show();
 });
 await page.locator('#submission-quality').waitFor();
 assert.ok(await page.locator('[data-quality-state="unchecked"]').count()>=8,'Errores de fuentes visibles');
 assert.equal(await page.locator('#duplicateCard .pill.ok').count(),0,'No falso verde de duplicados');
 assert.match(await page.locator('#submission-validation').textContent(),/No comprobada/);
 assert.doesNotMatch(await page.locator('#submission-validation').textContent(),/100% completo/,'Cobertura no afirmada si falta checklist');
 assert.match(await page.locator('#fisc').textContent(),/No comprobada/);
 assert.equal(await page.getByText('Sin pagos todavía.',{exact:true}).count(),0,'Fallo de pagos no es ausencia de pagos');
 await page.locator('[data-to="lista_para_radicar"]').click();assert.equal(await page.evaluate(()=>moves),0,'No avanzar con fuentes no comprobadas');
 await page.evaluate(()=>{window.fail={};});await page.locator('#submission-quality [data-quality-refresh]').click();
 await page.waitForFunction(()=>document.querySelectorAll('[data-quality-state="unchecked"]').length===0);
 const panel=page.locator('#submission-quality');
 assert.match(await panel.textContent(),/Duplicado confirmado pendiente de gestión/);
 assert.match(await panel.textContent(),/solicitud de exclusión pendiente/);
 assert.equal(await panel.locator('[data-quality-state="blocked"]').count(),1,'Solo bloqueo derivado del par devuelto por servidor');
 assert.equal(await panel.locator('[data-quality-state="warning"]').count(),1,'Autorización ausente no impone regla universal nueva');
 assert.equal(await panel.locator('a[href="#/reclamaciones/line-a"]').count(),1,'Acción a reclamación precisa');
 await page.evaluate(async()=>{sub.status='borrador';sub.display_status='borrador';sub.submitted_on=null;pairs=[];window.nullFiscalCheck=true;await show();});
 await page.locator('#ncf').waitFor();
 assert.match(await page.locator('#fisc').textContent(),/No comprobada/,'Respuesta fiscal nula tampoco equivale a verificación');
 await page.locator('[data-to="lista_para_radicar"]').click();assert.equal(await page.evaluate(()=>moves),0);
 await page.evaluate(()=>{window.nullFiscalCheck=false;window.nullFiscalOk=true;});await page.locator('#submission-quality [data-quality-refresh]').click();
 await page.waitForFunction(()=>document.querySelectorAll('[data-quality-state="unchecked"]').length===0);
 assert.match(await page.locator('#submission-quality').textContent(),/Diferencia en la factura fiscal/,'ok nulo con respuesta fiscal válida es diferencia, no fallo de consulta');
 assert.match(await page.locator('#fisc').textContent(),/Diferencia: radicación bloqueada/);
 assert.equal(await page.locator('#fisc .pill.ok').count(),0,'Diferencia conocida no presenta verde');
 await page.evaluate(()=>{window.nullFiscalOk=false;});
 await page.locator('#ncf').fill('B0100000999');await page.locator('#nts').fill('Borrador fiscal conservado');await page.locator('#fi_n').fill('F-EDITANDO');
 await page.evaluate(()=>{window.nullFiscalCheck=false;});await page.locator('#submission-quality [data-quality-refresh]').click();
 await page.waitForFunction(()=>document.querySelectorAll('[data-quality-state="unchecked"]').length===0);
 assert.equal(await page.locator('#ncf').inputValue(),'B0100000999');assert.equal(await page.locator('#nts').inputValue(),'Borrador fiscal conservado');assert.equal(await page.locator('#fi_n').inputValue(),'F-EDITANDO');
 await page.locator('[data-to="lista_para_radicar"]').click();await page.waitForFunction(()=>moves===1);
 for(const width of [1440,768,390,320]){await page.setViewportSize({width,height:1000});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Sin overflow '+width);}
 assert.deepEqual(errors,[]);console.log('PASS control de calidad: alcance por caso/par/lote, fuentes no comprobadas, fiscal nulo, pagos sin falso cero, bloqueo seguro, reconsulta y formularios conservados, móvil.');
}finally{await browser.close();}
