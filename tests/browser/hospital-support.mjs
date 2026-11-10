/** Hospitalización en soporte: médicos explícitos, reportes de lectura y sin RPC mine. */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');
const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try {
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const p=new URL(route.request().url()).pathname;
  if(p==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><main></main>'});
  if(p==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:`export const sb=()=>({rpc:async(name,args)=>{window.calls.push({name,args});if(name==='hospital_centers_mine')return {data:{soy_medico:true,centros:[]}};if(name==='hospital_report_list')return {data:[]};if(name!=='hospital_support_context')throw new Error('Unexpected RPC '+name);if(args.p_org!=='org-client')throw new Error('Wrong organization');if(window.fail)return {error:{message:'Acceso de soporte vencido'}};const provider=args.p_provider|| (window.single?'p1':null);const report=args.p_report?{id:args.p_report,provider_id:provider,patient_name:'Paciente ficticio',centro:'Centro ficticio',status:'borrador',total:850,puede_editar:true,lineas:[{service_date:'2026-11-09',servicio:'Servicio de prueba',quantity:1,unit_amount:850,amount:850}]}:null;if(window.defer&&args.p_report)await new Promise(resolve=>window.resolveDetail=resolve);return {data:{providers:window.single?[{id:'p1',full_name:'Médico A'}]:[{id:'p1',full_name:'Médico A'},{id:'p2',full_name:'Médico B'}],provider_id:provider,centros:provider?[{nombre:'Centro ficticio'}]:[],reportes:provider==='p1'?[{id:'report-a',patient_name:'Paciente ficticio',centro:'Centro ficticio',status:'borrador',total:850}]:[],report_count:provider==='p1'?1:0,report}};}});`});
  if(p==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
  return route.fulfill({contentType:'text/javascript',body:await readFile(new URL(p.slice(1),root))});
 });
 await page.goto('http://127.0.0.1:8881/');
 await page.evaluate(async()=>{window.calls=[];window.context={role:'client',membership:{organization_id:'wrong-membership'},viewAs:{orgId:'org-client'}};window.mod=await import('/js/modules/hospitalizacion.js');await mod.render(document.querySelector('main'),context);});
 assert.equal(await page.getByLabel('Médico del consultorio').count(),1);
 assert.equal(await page.locator('.hosp-row').count(),0);
 await page.getByLabel('Médico del consultorio').selectOption('p1');await page.locator('.hosp-row').waitFor();await page.locator('.hosp-row').click();await page.locator('.hosp-support-detail').waitFor();
 assert.match(await page.locator('.hosp-support-detail').textContent(),/Servicio de prueba/);
 assert.equal(await page.locator('input,textarea,form').count(),0);
 assert.equal(await page.getByRole('button',{name:/Crear|Enviar|Agregar|Quitar|Imprimir|Exportar/}).count(),0);
 assert.ok((await page.evaluate(()=>calls)).every(c=>c.name==='hospital_support_context'&&c.args.p_org==='org-client'));
 await page.evaluate(()=>window.defer=true);await page.locator('.hosp-row').click();await page.waitForFunction(()=>!!window.resolveDetail);
 await page.getByLabel('Médico del consultorio').selectOption('p2');await page.waitForFunction(()=>document.querySelector('main').textContent.includes('aún no tiene reportes'));
 await page.evaluate(()=>resolveDetail());assert.equal(await page.locator('.hosp-support-detail').count(),0);
 await page.evaluate(async()=>{window.calls=[];await mod.render(document.querySelector('main'),{...context,role:'capturer',viewAs:{orgId:'org-client',targetName:'Secretaria ficticia'}});});
 assert.match(await page.locator('main').textContent(),/no muestra reportes individuales/);assert.equal(await page.evaluate(()=>calls.length),0);
 await page.evaluate(async()=>{window.calls=[];window.single=true;window.defer=false;await mod.render(document.querySelector('main'),context);});await page.locator('.hosp-row').waitFor();assert.equal(await page.locator('select').count(),0);
 await page.evaluate(async()=>{window.calls=[];await mod.render(document.querySelector('main'),{role:'client'});});assert.deepEqual(await page.evaluate(()=>calls.map(c=>c.name)),['hospital_centers_mine','hospital_report_list']);assert.equal(await page.getByText('Nuevo reporte',{exact:true}).count(),1);
 assert.deepEqual(errors,[]);console.log('PASS: soporte con consultorio explícito, selector médico, detalle solo lectura, bloqueo individual, carreras y flujo médico original');
}finally{await browser.close();}
