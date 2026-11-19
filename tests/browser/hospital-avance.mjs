/** Avance hacia el cobro en Hospitalización: barra + porcentaje en la lista (médico y staff)
 *  y en el pie del reporte; clase `full` cuando el reporte llega a 100. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
 const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
 const errors = []; page.on('pageerror', e => errors.push(e.message));
 await page.route('**/*', async route => {
  const p = new URL(route.request().url()).pathname;
  if (p === '/') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><main></main>' });
  if (p === '/js/supabase.js') return route.fulfill({ contentType: 'text/javascript', body: `export const sb=()=>({rpc:async(name,args)=>{window.calls.push({name,args});try{return {data:await window.handleRpc(name,args)}}catch(e){return {error:{message:e.message}}}}});` });
  if (p === '/js/utils/diag-log.js') return route.fulfill({ contentType: 'text/javascript', body: 'export const logDiag=()=>{};' });
  return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL(p.slice(1), root)) });
 });
 await page.goto('http://127.0.0.1:8881/');
 for (const css of ['variables.css', 'components.css', 'app.css', 'iter18.css']) await page.addStyleTag({ content: await readFile(new URL('css/' + css, root), 'utf8') });
 await page.evaluate(async () => {
  window.calls = []; window.reportAvance = 40;
  const base = { id: 'r1', provider_id: 'prov-a', center_id: 'center-a', centro: 'Centro ficticio', medico: 'Médico ficticio', patient_name: 'Paciente ficticio', status: 'enviado', total: 2050, puede_editar: false, admission_date: '2026-11-08', discharge_date: '2026-11-09', ars: null, lineas: [{ id: 'l1', service_date: '2026-11-08', servicio: 'Consulta', codigo: 'QA-A', quantity: 1, unit_amount: 850, amount: 850 }] };
  window.handleRpc = async (name) => {
   if (name === 'hospital_centers_mine') return { soy_medico: true, provider_id: 'prov-a', centros: [{ center_id: 'center-a', nombre: 'Centro ficticio' }] };
   if (name === 'ars_catalog') return [];
   if (name === 'hospital_report_list') return [{ id: 'r1', centro: 'Centro ficticio', medico: 'Médico ficticio', patient_name: 'Paciente ficticio', status: 'enviado', total: 2050, avance: window.reportAvance }];
   if (name === 'hospital_report_get') return { ...structuredClone(base), avance: window.reportAvance };
   if (name === 'hospital_log_list') return { entries: [], can_write: false };
   if (name === 'hospital_staff_context') return { report_count: 1, reportes: [{ ...structuredClone(base), avance: window.reportAvance }], report: null };
   throw new Error('Unexpected RPC ' + name);
  };
  window.mod = await import('/js/modules/hospitalizacion.js');
  await window.mod.render(document.querySelector('main'), { role: 'client' });
 });

 // Médico · fila de la lista con avance 40%.
 await page.locator('.hosp-list .hosp-row').first().waitFor();
 assert.equal((await page.locator('.hosp-list .hosp-row .hosp-av-pct').first().innerText()).trim(), '40%');
 assert.match(await page.locator('.hosp-list .hosp-row .hosp-av-bar i').first().getAttribute('style'), /width:\s*40%/);

 // Abrir el reporte · el pie muestra el avance.
 await page.locator('.hosp-list .hosp-row').first().click();
 await page.locator('.hosp-detail .hosp-foot').waitFor();
 assert.equal((await page.locator('.hosp-detail .hosp-foot .hosp-av-pct').innerText()).trim(), '40%');
 assert.equal(await page.locator('.hosp-detail .hosp-foot .hosp-av-bar i.full').count(), 0, 'avance parcial no debe marcarse full');

 // Reporte cobrado al 100 · barra llena.
 await page.evaluate(async () => { window.reportAvance = 100; await window.mod.render(document.querySelector('main'), { role: 'client', arg: 'r1' }); });
 await page.locator('.hosp-detail .hosp-foot').waitFor();
 assert.equal((await page.locator('.hosp-detail .hosp-foot .hosp-av-pct').innerText()).trim(), '100%');
 assert.equal(await page.locator('.hosp-detail .hosp-foot .hosp-av-bar i.full').count(), 1, 'reporte cobrado debe marcarse full');

 // Vista del staff (billing) · la fila también lleva el avance.
 await page.evaluate(async () => { window.reportAvance = 40; await window.mod.render(document.querySelector('main'), { role: 'billing' }); });
 await page.locator('.hosp-staff .hosp-list .hosp-row').first().waitFor();
 assert.equal((await page.locator('.hosp-staff .hosp-list .hosp-row .hosp-av-pct').first().innerText()).trim(), '40%');

 assert.deepEqual(errors, [], 'sin errores de página');
 console.log('OK hospital-avance: lista del médico, pie del reporte, full al 100 y lista del staff.');
} finally { await browser.close(); }
