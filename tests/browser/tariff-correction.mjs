// 5.43.0 · Diálogo «Corregir tarifa». Uso: node tests/browser/tariff-correction.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage(); const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  const mocks = { '/': '<main></main>', '/js/utils/diag-log.js': 'export function logDiag() {}', '/js/supabase.js': 'export const sb=()=>({});',
    '/js/services/iter18.js': 'export const rpc = (n, a) => window.__rpc(n, a);' };
  await page.route('**/*', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path in mocks) return route.fulfill({ contentType: path === '/' ? 'text/html' : 'text/javascript', body: mocks[path] });
    return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL(path.slice(1), root)) });
  });
  await page.goto('http://127.0.0.1:8883/');
  await page.evaluate(async () => {
    window.calls = [];
    const tariff = { id: 't', amount: 750, currency: 'DOP', valid_from: '2026-07-02', scope: 'contrato', service: 'CONSULTA', ars: 'ARS ficticia', provider: 'Médico ficticio' };
    const counts = { total: 3, realinear: 1, resuelta: 0, decision: 1, sin_tocar: 1, clients: 1, sin_tocar_por_estado: { radicada: 1 } };
    window.__rpc = async (n, a) => { window.calls.push({ n, a });
      if (n === 'tariff_correct') return { total: 3, omitidas: 0 };
      return a.p_amount == null ? { tariff, history: [], valid: false } : { tariff, valid: true, counts, sample: [], history: [] }; };
    const { correctTariffDialog } = await import('/js/modules/tariff-correction.js');
    window.result = correctTariffDialog('t');
  });
  await page.locator('#tc_amount').fill('850');
  await page.waitForFunction(() => document.querySelector('#tc_effect').textContent.includes('Se recalculan 2'));
  await page.getByRole('button', { name: 'Aplicar corrección' }).click();
  assert.equal(await page.evaluate(() => calls.filter((c) => c.n === 'tariff_correct').length), 0, 'sin motivo no aplica');
  await page.locator('#tc_reason').fill('El contrato dice 850 y se cargó 750');
  await page.getByRole('button', { name: 'Aplicar corrección' }).click();
  await page.waitForFunction(() => calls.some((c) => c.n === 'tariff_correct'));
  const sent = await page.evaluate(() => calls.find((c) => c.n === 'tariff_correct').a);
  assert.equal(sent.p_amount, 850); assert.deepEqual(sent.p_expected, { old_amount: 750, total: 3 });
  assert.deepEqual(errors, []);
  console.log('PASS: vista previa, motivo obligatorio y envío con el alcance esperado');
} finally { await browser.close(); }
