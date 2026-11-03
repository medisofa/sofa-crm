// SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/tariff-code-exceptions.mjs
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('../../', import.meta.url));
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  const errors = []; page.on('pageerror', (e) => errors.push(e.message));
  await page.route('**/*', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/preview.html') return route.fulfill({ contentType: 'text/html', body: '<link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/iter18.css"><main></main>' });
    if (path === '/js/supabase.js') return route.fulfill({ contentType: 'text/javascript', body: 'export const sb = () => window.mockDB;' });
    if (!path.startsWith('/js/') && !path.startsWith('/css/')) return route.abort();
    try { return route.fulfill({ contentType: path.endsWith('.css') ? 'text/css' : 'text/javascript', body: await readFile(root + path.slice(1), 'utf8') }); } catch { return route.fulfill({ status: 404, body: 'Missing' }); }
  });
  await page.goto('http://127.0.0.1:8881/preview.html');
  await page.evaluate(async () => {
    window.calls = []; window.auths = {}; window.scoped = {}; window.deny = false;
    window.mockDB = { async rpc(name, args) {
      calls.push({ name, args: structuredClone(args) });
      if (name === 'client_ars_matrix') return { data: { providers: [{ id: 'doctor', name: 'Dra. Prueba' }], ars: [{ id: 'ars', name: 'ARS Prueba' }] } };
      if (name === 'ars_catalog' || name === 'tariff_import_history') return { data: [] };
      if (name === 'tariff_code_exception_prepare' || name === 'tariff_code_exception_authorize') {
        if (deny) return { error: { message: 'Solo Administración o Facturación con acceso al cliente puede autorizar códigos exclusivos.' } };
        const proposal = { ars_name: 'ARS Prueba', service_code: args.p_row.servicio, service_description: 'Consulta especializada', reason: args.p_reason,
          codes: args.p_systems.map((system) => ({ system, code: args.p_row[system.toLowerCase()], previous_description: null, general_description: 'Otro servicio general' })) };
        if (name === 'tariff_code_exception_prepare') return { data: proposal };
        if (JSON.stringify(args.p_expected) !== JSON.stringify(proposal)) throw Error('Stale proposal');
        const id = 'approval-' + Object.keys(auths).length;
        auths[id] = structuredClone(args.p_row);
        return { data: { id, proposal, authorized_at: '2026-11-03T12:00:00Z', authorized_by: 'billing-test' } };
      }
      if (name !== 'import_contract_tariffs_v2') throw Error('Unexpected ' + name);
      const problems = [], valid = [];
      for (const [i, r] of args.p_rows.entries()) {
        const auth = auths[r.code_authorization];
        const authorized = auth && auth.simon === r.simon && auth.servicio === r.servicio && auth.ars === r.ars;
        if (!authorized && scoped[r.simon] !== r.servicio) problems.push({ row: i + 1, errors: ['El código SIMON corresponde a otro servicio'], data: r });
        else valid.push({ row: i + 1, service: 'Consulta especializada', current: 850, amount: 850, change: 'igual', valid_from: '2026-01-01' });
      }
      if (args.p_commit) {
        if (problems.length) throw Error('Invalid commit');
        for (const row of args.p_rows) scoped[row.simon] = row.servicio;
      }
      return { data: { errors: problems, rows: valid, new: 0, changed: 0, same: valid.length, imported: 0 } };
    } };
    const { mountTariffImport } = await import('/js/modules/tarifario-import.js');
    await mountTariffImport(document.querySelector('main'), { orgId: 'org', canEdit: true });
  });
  const file = (code = '2467') => ({ name: 'exclusivo.csv', mimeType: 'text/csv', buffer: Buffer.from(`Servicio;Descripción;SIMON;CUPS;Tarifa;Desde\nSOFA-P04;Consulta especializada;${code};;850;01/01/2026`) });
  const prepare = () => page.getByRole('button', { name: 'Revisar propuesta de excepción', exact: true });
  const authorize = () => page.getByRole('button', { name: 'Autorizar excepción para esta ARS', exact: true });
  const save = () => page.getByRole('button', { name: /^Confirmar: guardar/ });
  const confirm = () => page.getByRole('checkbox', { name: /^Autorizo esta asociación/ });
  await page.locator('#ti-ars').selectOption('ars');
  await page.locator('#ti-file').setInputFiles(file());
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByText('¿Este código es exclusivo de la ARS? Proponer excepción', { exact: true }).click();
  const reason = () => page.getByRole('textbox', { name: 'Motivo y referencia del contrato', exact: true });
  await reason().fill('Contrato ARS verificado por Facturación');
  await prepare().click();
  await authorize().waitFor();
  assert.equal(await authorize().isDisabled(), true);
  assert.match(await page.locator('.ti-code-exception').textContent(), /Otro servicio general/);
  assert.deepEqual(await page.evaluate(() => scoped), {});
  await confirm().check();
  assert.equal(await authorize().isEnabled(), true);
  await authorize().click();
  await page.getByText(/Excepción autorizada\. Pulse/).waitFor();
  assert.deepEqual(await page.evaluate(() => scoped), {});
  assert.equal(await save().isDisabled(), true);
  // A changed reason invalidates the old approval, as do field edits.
  await reason().fill('Contrato con referencia actualizada y verificada');
  await prepare().click(); await confirm().check(); await authorize().click();
  await page.getByText(/Excepción autorizada\. Pulse/).waitFor();
  const simon = page.getByRole('textbox', { name: 'SIMON · exclusivo.csv · fila 2', exact: true });
  await simon.fill('2474');
  await page.getByRole('button', { name: 'Volver a validar correcciones', exact: true }).click();
  await page.getByRole('heading', { name: 'exclusivo.csv · fila 2', exact: true }).waitFor();
  const afterEdit = await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2').at(-1).args.p_rows[0]);
  assert.equal(afterEdit.code_authorization, undefined);
  assert.equal(afterEdit.simon, '2474');
  await page.getByText('¿Este código es exclusivo de la ARS? Proponer excepción', { exact: true }).click();
  await reason().fill('Contrato ARS con código exclusivo 2474 confirmado');
  await prepare().click(); await confirm().check(); await authorize().click();
  await page.getByText(/Excepción autorizada\. Pulse/).waitFor();
  await page.getByRole('button', { name: 'Volver a validar correcciones', exact: true }).click();
  await page.getByRole('heading', { name: 'Excepciones autorizadas pendientes de guardar', exact: true }).waitFor();
  assert.match(await save().textContent(), /0 tarifa\(s\) y 1 excepción/);
  assert.equal(await save().isEnabled(), true);
  assert.deepEqual(await page.evaluate(() => scoped), {});
  await save().click();
  await page.getByText('Listo: 0 tarifa(s) guardadas. 1 igual(es) se omitieron. 1 excepción(es) de ARS guardada(s).', { exact: true }).waitFor();
  assert.deepEqual(await page.evaluate(() => scoped), { '2474': 'SOFA-P04' });
  assert.equal(await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2' && c.args.p_commit).length), 1);
  // Permission denial never produces an authorization button or modifies the code map.
  await page.evaluate(() => { deny = true; });
  await page.locator('#ti-file').setInputFiles(file('NEW'));
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByText('¿Este código es exclusivo de la ARS? Proponer excepción', { exact: true }).click();
  await reason().fill('Intento sin permiso para autorizar códigos exclusivos');
  await prepare().click();
  await page.getByText('Solo Administración o Facturación con acceso al cliente puede autorizar códigos exclusivos.', { exact: true }).waitFor();
  assert.equal(await authorize().count(), 0);
  assert.deepEqual(await page.evaluate(() => scoped), { '2474': 'SOFA-P04' });
  await page.setViewportSize({ width: 375, height: 850 });
  for (const theme of ['dark', 'light']) {
    await page.evaluate((t) => { document.documentElement.dataset.theme = t; }, theme);
    assert.equal(await reason().evaluate((e) => e.getBoundingClientRect().width <= e.parentElement.getBoundingClientRect().width), true);
  }
  assert.deepEqual(errors, []);
  console.log('PASS: propuesta, confirmación explícita, autorización, invalidación por edición, revalidación, guardado sin cambio de tarifa, permisos y móvil.');
} finally { await browser.close(); }
