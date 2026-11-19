// Verifica la columna "Avance" en la lista de reclamaciones:
// barra proporcional al porcentaje, clase `full` + 100% cuando está pagada,
// y 0% cuando el backend no devuelve avance.
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
 const page = await browser.newPage(); const errors = [];
 page.on('pageerror', e => errors.push(e.message));
 const rows = [
  { id: 'r1', folio: 'REC-1', service_name: 'Consulta', patient_name: 'Paciente Uno', provider_name: 'Médico', ars_name: 'ARS', claimed: 1000, contracted: true, claim_status: 'capturada', avance: 12 },
  { id: 'r2', folio: 'REC-2', service_name: 'Seguimiento', patient_name: 'Paciente Dos', provider_name: 'Médico', ars_name: 'ARS', claimed: 1000, contracted: true, claim_status: 'radicada', avance: 68 },
  { id: 'r3', folio: 'REC-3', service_name: 'Cirugía', patient_name: 'Paciente Tres', provider_name: 'Médico', ars_name: 'ARS', claimed: 1000, contracted: true, claim_status: 'pagada', avance: 100 },
  { id: 'r4', folio: 'REC-4', service_name: 'Laboratorio', patient_name: 'Paciente Cuatro', provider_name: 'Médico', ars_name: 'ARS', claimed: 1000, contracted: true, claim_status: 'capturada', avance: null },
 ];
 await page.route('**/*', async route => {
  const path = new URL(route.request().url()).pathname;
  const mocks = {
   '/': '<main></main>',
   '/js/modules/opening-history.js': 'export const OPENING_ROLES=[]; export function mountOpeningHistoryPicker() {}',
   '/js/modules/clients.js': 'export const pager=()=>"";',
   '/js/utils/diag-log.js': 'export function logDiag() {}',
   '/js/supabase.js': 'export const sb=()=>({});',
   '/js/services/claims.js': `
    export async function listClaims(args) { if(args.size===1000) return {data:[],count:0}; return {data:${JSON.stringify(rows)},count:${rows.length}}; }
    export async function claimCounts() { return []; }
    export async function claimLocations() {return [];}
    export async function claimTransitions() {return [];}
    export async function captureProviders() {return [];}
    export async function activeArs() {return [];}
    export async function claimDuplicateCandidates() {return [];}
    export async function requestClaimDuplicateExclusion(){return {id:'x',status:'pendiente'};}
    export async function listClaimDuplicateResolutionRequests(){return [];}
    export async function reviewClaimDuplicate(){return 1;}`,
  };
  if (path in mocks) return route.fulfill({ contentType: path === '/' ? 'text/html' : 'text/javascript', body: mocks[path] });
  return route.fulfill({ contentType:'text/javascript',body:await readFile(new URL(path.slice(1),root)) });
 });
 await page.goto('http://127.0.0.1:8881/');
 await page.evaluate(async()=>{ const {render}=await import('/js/modules/claims.js'); await render(document.querySelector('main'),{role:'admin'}); });

 // El encabezado Avance existe.
 await page.locator('th', { hasText: 'Avance' }).first().waitFor();

 // Cada reclamación trae su celda de avance.
 assert.equal(await page.locator('td[data-l="Avance"] .avance').count(), 4, 'una barra de avance por reclamación');

 // REC-2 radicada: 68%, barra al 68%, sin clase full.
 const r2 = page.locator('tr:has(b.mono:text-is("REC-2")) td[data-l="Avance"]');
 assert.equal((await r2.locator('.avance-pct').innerText()).trim(), '68%');
 assert.match(await r2.locator('.avance-bar i').getAttribute('style'), /width:\s*68%/);
 assert.equal(await r2.locator('.avance-bar i.full').count(), 0, 'radicada no debe marcarse como pagada');

 // REC-3 pagada: 100%, barra llena (clase full).
 const r3 = page.locator('tr:has(b.mono:text-is("REC-3")) td[data-l="Avance"]');
 assert.equal((await r3.locator('.avance-pct').innerText()).trim(), '100%');
 assert.equal(await r3.locator('.avance-bar i.full').count(), 1, 'pagada debe marcarse full');
 assert.match(await r3.locator('.avance-bar i').getAttribute('style'), /width:\s*100%/);

 // REC-4 sin avance del backend: muestra 0% y barra vacía, sin romper.
 const r4 = page.locator('tr:has(b.mono:text-is("REC-4")) td[data-l="Avance"]');
 assert.equal((await r4.locator('.avance-pct').innerText()).trim(), '0%');
 assert.match(await r4.locator('.avance-bar i').getAttribute('style'), /width:\s*0%/);

 assert.deepEqual(errors, [], 'sin errores de página');
 console.log('OK avance-reclamaciones: encabezado, barra proporcional, full al pagar y 0% sin dato.');
} finally { await browser.close(); }
