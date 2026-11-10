/** Flujo hospitalario con datos ficticios: ficha completa, servicios y supervisión. */
import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOFA_PLAYWRIGHT_MODULE||'playwright');const root=new URL('../../',import.meta.url);
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{const p=new URL(route.request().url()).pathname;if(p==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><main></main>'});
 if(p==='/js/supabase.js')return route.fulfill({contentType:'text/javascript',body:`export const sb=()=>({rpc:async(name,args)=>{window.calls.push({name,args});try{return {data:await window.handleRpc(name,args)}}catch(e){return {error:{message:e.message}}}}});`});
 if(p==='/js/utils/diag-log.js')return route.fulfill({contentType:'text/javascript',body:'export const logDiag=()=>{};'});
 return route.fulfill({contentType:'text/javascript',body:await readFile(new URL(p.slice(1),root))});});
 await page.goto('http://127.0.0.1:8881/');for(const css of ['variables.css','components.css','app.css','iter18.css'])await page.addStyleTag({content:await readFile(new URL('css/'+css,root),'utf8')});await page.evaluate(()=>{document.documentElement.dataset.theme='dark';document.querySelector('main').className='page';});await page.evaluate(async()=>{window.calls=[];window.catalog=[{id:'ars-a',name:'ARS ficticia'}];window.report=null;
 window.handleRpc=async(name,a)=>{
  if(name==='hospital_centers_mine')return {soy_medico:true,provider_id:'provider-a',centros:[{center_id:'center-a',nombre:'Centro ficticio'}]};
  if(name==='ars_catalog')return catalog;
  if(name==='hospital_report_list')return report?[report]:[];
  if(name==='hospital_report_get')return structuredClone(report);
  if(name==='hospital_my_tariff')return [{procedure_id:'service-a',codigo:'QA-A',servicio:'Consulta de prueba',amount:850},{procedure_id:'service-b',codigo:'QA-B',servicio:'Procedimiento de prueba',amount:1200}];
  if(name==='hospital_report_save_contact'){
   if(window.failSave)throw new Error('No se guardó el reporte ni el contacto.');
   report={id:a.p_id||'report-a',provider_id:'provider-a',center_id:a.p_center,centro:'Centro ficticio',patient_name:a.p_patient_name,patient_doc:a.p_patient_doc,patient_phone:a.p_phone,ars_id:a.p_ars,ars:a.p_ars?'ARS ficticia':null,admission_date:a.p_admission,discharge_date:a.p_discharge,notes:a.p_notes,status:'borrador',puede_editar:true,total:report?.total||0,lineas:report?.lineas||[]};return structuredClone(report);
  }
  if(name==='hospital_report_line_add'){report.lineas.push({id:'line-'+report.lineas.length,procedure_id:a.p_procedure,service_date:a.p_service_date,servicio:'Servicio de prueba',quantity:a.p_quantity,unit_amount:a.p_unit_amount,amount:a.p_quantity*a.p_unit_amount});report.total=report.lineas.reduce((s,l)=>s+l.amount,0);return structuredClone(report);}
  if(name==='hospital_report_submit'){report.status='enviado';report.puede_editar=false;return structuredClone(report);}
  if(name==='hospital_staff_context')return {report_count:1,reportes:[{...report,medico:'Médico ficticio'}],report:a.p_report?{...structuredClone(report),medico:'Médico ficticio',puede_editar:true}:null};
  throw new Error('Unexpected RPC '+name);
 };
 window.mod=await import('/js/modules/hospitalizacion.js');await mod.render(document.querySelector('main'),{role:'client'});
 const {canSee}=await import('/js/utils/permissions.js');window.access={opsCenters:canSee('centros','operations'),opsHospital:canSee('hospitalizacion','operations'),billingHospital:canSee('hospitalizacion','billing'),billingCenters:canSee('centros','billing'),capturerHospital:canSee('hospitalizacion','capturer')};});
 assert.deepEqual(await page.evaluate(()=>access),{opsCenters:true,opsHospital:true,billingHospital:true,billingCenters:false,capturerHospital:false});
 await page.getByText('Nuevo reporte',{exact:true}).click();let form=page.locator('.hosp-new').first();
 await form.getByLabel('Nombre del paciente').fill('Paciente ficticio');await form.getByLabel('Teléfono del paciente').fill('8095550101');await form.getByLabel('ARS del paciente').selectOption('ars-a');await form.getByLabel('Fecha de ingreso').fill('2026-11-08');await form.getByLabel('Fecha de alta').fill('2026-11-07');await form.getByRole('button',{name:'Crear reporte'}).click();assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='hospital_report_save_contact').length),0);
 await form.getByLabel('Fecha de alta').fill('2026-11-09');await page.evaluate(()=>window.failSave=true);await form.getByRole('button',{name:'Crear reporte'}).click();assert.equal(await form.getByLabel('Nombre del paciente').inputValue(),'Paciente ficticio');assert.equal(await page.evaluate(()=>report),null);
 await page.evaluate(()=>window.failSave=false);await form.getByRole('button',{name:'Crear reporte'}).click();await page.locator('.hosp-detail').waitFor();
 let saved=await page.evaluate(()=>report);assert.equal(saved.patient_phone,'8095550101');assert.equal(saved.ars_id,'ars-a');assert.equal(saved.discharge_date,'2026-11-09');assert.equal(await page.evaluate(()=>calls.filter(c=>c.name==='hospital_report_save').length),0);
 await page.locator('.hosp-detail').getByLabel('Servicio del tarifario').selectOption('service-a');await page.locator('.hosp-detail').getByLabel('Fecha del servicio').fill('2026-11-08');await page.waitForFunction(()=>!document.querySelector('[aria-label="Servicio del tarifario"]').disabled);await page.locator('.hosp-detail').getByLabel('Servicio del tarifario').selectOption('service-a');await page.getByRole('button',{name:'Agregar servicio',exact:true}).click();
 await page.waitForFunction(()=>report.lineas.length===1);await page.waitForFunction(()=>!document.querySelector('[aria-label="Servicio del tarifario"]').disabled);await page.locator('.hosp-detail').getByLabel('Servicio del tarifario').selectOption('service-b');await page.getByRole('button',{name:'Agregar servicio',exact:true}).click();await page.waitForFunction(()=>report.lineas.length===2);assert.equal(await page.evaluate(()=>report.total),2050);await page.waitForFunction(()=>document.querySelector('.hosp-list')?.textContent.includes('2,050')); 
 if(process.env.SOFA_HOSPITAL_SCREENSHOTS)await page.screenshot({path:'/workspace/artifacts/hospital-preview/pantalla-implementada.png',fullPage:true});
 for(const width of [1440,390,320]){await page.setViewportSize({width,height:1050});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Hospital sin overflow '+width);}
 await page.setViewportSize({width:1440,height:1050});
 // A missing catalog entry must not erase a previously registered ARS.
 await page.evaluate(async()=>{window.catalog=[];await mod.render(document.querySelector('main'),{role:'client',arg:'report-a'});});assert.equal(await page.locator('.hosp-detail').getByLabel('ARS del paciente').inputValue(),'ars-a');
 await page.locator('.hosp-detail').getByLabel('Teléfono del paciente').fill('8095550202');await page.getByRole('button',{name:'Guardar datos del reporte'}).click();await page.waitForFunction(()=>report.patient_phone==='8095550202');assert.equal(await page.evaluate(()=>report.ars_id),'ars-a');
 page.on('dialog',d=>d.accept());await page.getByRole('button',{name:'Enviar y avisar a SoFa'}).click();await page.waitForFunction(()=>report.status==='enviado');assert.equal(await page.getByRole('button',{name:'Agregar servicio',exact:true}).count(),0);
 await page.evaluate(async()=>{window.calls=[];await mod.render(document.querySelector('main'),{role:'billing',arg:'report-a'});});assert.equal(await page.locator('.hosp-staff-detail').count(),1);assert.equal(await page.locator('input,textarea,form').count(),0);assert.equal(await page.getByRole('button',{name:/Crear|Guardar|Agregar|Quitar|Enviar|Imprimir/}).count(),0);assert.equal(await page.getByRole('link',{name:'Gestionar centros'}).count(),0);assert.deepEqual(await page.evaluate(()=>calls.map(c=>c.name)),['hospital_staff_context']);
 await page.evaluate(async()=>{await mod.render(document.querySelector('main'),{role:'operations',arg:'report-a'});});assert.equal(await page.getByRole('link',{name:'Gestionar centros'}).count(),1);if(process.env.SOFA_HOSPITAL_SCREENSHOTS)await page.screenshot({path:'/workspace/artifacts/hospital-preview/seguimiento-implementado.png',fullPage:true});
 await page.evaluate(async()=>{window.calls=[];const centers=await import('/js/modules/centros.js');await centers.render(document.querySelector('main'),{viewAs:{orgId:'org-a'}});});assert.equal(await page.evaluate(()=>calls.length),0);assert.equal(await page.locator('input,form,button').count(),0);
 assert.deepEqual(errors,[]);console.log('PASS: campos atómicos y recuperación, ARS conservada, fechas, múltiples servicios, avisar, supervisión readonly y permisos de centros');
}finally{await browser.close();}
