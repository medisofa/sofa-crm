// 5.43.1 · Buscar no oculta reclamaciones. Uso: node tests/browser/claims-search.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage(); const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const services = `
    const row = (id) => ({ id, folio: 'REC-' + id, patient_name: 'Paciente ' + id, service_name: 'Consulta', claim_status: 'capturada', service_date: '2026-10-01', claimed: 750, member_number: id });
    export async function listClaims(a) { window.calls.push({ ...a }); const data = a.q === '1920024538' ? [row('C')] : a.q ? [] : [row('A'), row('B'), row('C')]; return { data, count: data.length }; }
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
  const mocks = { '/': '<main></main>', '/js/modules/opening-history.js': 'export const OPENING_ROLES=[]; export function mountOpeningHistoryPicker() {}',
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
  assert.deepEqual(await folios(), ['REC-A', 'REC-B', 'REC-C']);
  await page.locator('#q').fill('1920024538');
  await page.locator('.search-hit-note').waitFor();
  assert.deepEqual(await folios(), ['REC-C', 'REC-A', 'REC-B']);
  assert.equal(await page.locator('tr.search-hit').count(), 1);
  assert.match(await page.locator('tr.search-hit').textContent(), /Coincide/);
  await page.locator('#q').fill('zzzz');
  await page.getByText('Sin coincidencias', { exact: false }).first().waitFor();
  await page.waitForFunction(() => document.querySelector('.search-hit-note')?.textContent.includes('zzzz'));
  assert.deepEqual(await folios(), ['REC-A', 'REC-B', 'REC-C']);
  assert.deepEqual(errors, []);
  console.log('PASS: la coincidencia sube de primera, las demás siguen visibles y sin coincidencias muestra todo');
} finally { await browser.close(); }
