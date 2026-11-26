// 5.43.2 · Elegir un lote filtra sus reclamaciones y lleva a su radicación. Uso: node tests/browser/claims-lot.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage(); const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const services = `
    const row = (id) => ({ id, folio: 'REC-' + id, patient_name: 'Paciente ' + id, service_name: 'Consulta', claim_status: 'capturada', submission_id: id === 'C' ? 's2' : 's1', service_date: '2026-10-01', claimed: 750, member_number: id });
    export async function listClaims(a) { window.calls.push({ ...a }); const data = [row('A'), row('B'), row('C')].filter((r) => !a.submissionId || r.submission_id === a.submissionId); return { data, count: data.length }; }
    export async function getClaim() { return null; }
    export async function claimCounts() { return []; }
    export async function claimLocations() { return []; }
    export async function claimTransitions() { return []; }
    export async function captureProviders() { return []; }
    export async function activeArs() { return []; }
    export async function claimAuthorizationReview() { return []; }
    export async function claimDuplicateCandidates() { return []; }
    export async function reviewClaimDuplicate() {}
    export async function requestClaimDuplicateExclusion() {}
    export async function listClaimDuplicateResolutionRequests() { return []; }`;
  const subs = `export async function listPendingLots() { return [{ id: 's1', folio: 'RAD-2026-0012', provider_name: 'Dra. Prueba', period: '2026-11', claimed: 1500 }, { id: 's2', folio: 'RAD-2026-0013', provider_name: 'Dra. Prueba', period: '2026-11', claimed: 750 }]; }`;
  const mocks = { '/js/services/submissions.js': subs, '/': '<main></main>', '/js/modules/opening-history.js': 'export const OPENING_ROLES=[]; export function mountOpeningHistoryPicker() {}',
    '/js/modules/clients.js': 'export const pager=()=>"";', '/js/utils/diag-log.js': 'export function logDiag() {}', '/js/supabase.js': 'export const sb=()=>({});', '/js/services/claims.js': services };
  await page.route('**/*', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path in mocks) return route.fulfill({ contentType: path === '/' ? 'text/html' : 'text/javascript', body: mocks[path] });
    return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL(path.slice(1), root)) });
  });
  await page.goto('http://127.0.0.1:8882/');
  await page.evaluate(async () => { window.calls = []; const { render } = await import('/js/modules/claims.js'); await render(document.querySelector('main'), { role: 'admin' }); });
  const folios = () => page.locator('#l tbody tr td[data-l="Folio"] b').allTextContents();
  await page.locator('#l tbody tr').first().waitFor();
  await page.locator('#fr option[value="s1"]').waitFor({ state: 'attached' });
  await page.locator('#fr').selectOption('s1');
  await page.waitForFunction(() => document.querySelectorAll('#l tbody tr').length === 2);
  assert.deepEqual(await folios(), ['REC-A', 'REC-B']);
  assert.match(await page.locator('#lote').textContent(), /RAD-2026-0012.*Dra\. Prueba/s);
  assert.equal(await page.locator('#lote a').getAttribute('href'), '#/radicaciones/s1');
  await page.locator('[data-sel]').first().check();
  assert.equal(await page.locator('#bulk a', { hasText: 'Pasar RAD-2026-0012 a radicación (1)' }).getAttribute('href'), '#/radicaciones/s1');
  await page.locator('#fr').selectOption('');
  await page.waitForFunction(() => document.querySelectorAll('#l tbody tr').length === 3);
  assert.equal(await page.locator('#lote a').count(), 0);
  await page.locator('#all').check();
  assert.deepEqual(await page.locator('#bulk a').allTextContents(), ['Pasar RAD-2026-0012 a radicación (2)', 'Pasar RAD-2026-0013 a radicación (1)']);
  await page.screenshot({ path: '/tmp/lote.png' });
  await page.locator('#fr').selectOption('s1');
  await page.waitForFunction(() => document.querySelectorAll('#l tbody tr').length === 2);
  await page.screenshot({ path: '/tmp/lote.png' });
  assert.deepEqual(errors, []);
  console.log('PASS: el lote filtra sus reclamaciones y ofrece pasar a radicación');
} finally { await browser.close(); }
