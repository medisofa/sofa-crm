// SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/tariff-import.mjs
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
    window.calls = []; window.failValidation = false;
    window.mockDB = { async rpc(name, args) {
      calls.push({ name, args: structuredClone(args) });
      if (name === 'client_ars_matrix') return { data: { providers: [{ id: 'doctor', name: 'Dra. Prueba' }], ars: [{ id: 'ars', name: 'ARS Prueba' }] } };
      if (name === 'ars_catalog' || name === 'tariff_import_history') return { data: [] };
      if (name !== 'import_contract_tariffs_v2') throw Error('Unexpected ' + name);
      if (failValidation && !args.p_commit) return { error: { message: 'Fallo de validación de prueba' } };
      const problems = [], valid = [], seen = new Map();
      for (const [i, r] of args.p_rows.entries()) {
        const messages = [];
        if (r.simon === 'BAD') messages.push('El código SIMON corresponde a otro servicio');
        if (!r.servicio && !r.simon && !r.cups) messages.push('Falta el servicio (código interno, nombre, SIMON o CUPS)');
        if (seen.has(r.servicio)) messages.push('Duplicado o vigencia superpuesta con la fila ' + seen.get(r.servicio));
        if (r.servicio) seen.set(r.servicio, i + 1);
        if (messages.length) problems.push({ row: i + 1, errors: messages, data: r });
        else valid.push({ row: i + 1, service: 'Servicio ' + r.servicio, amount: Number(r.tarifa), change: 'nueva', valid_from: '2027-01-01' });
      }
      if (args.p_commit && problems.length) throw Error('Attempted invalid commit');
      return { data: { errors: problems, rows: valid, new: valid.length, changed: 0, same: 0, imported: args.p_commit ? valid.length : 0 } };
    } };
    const { mountTariffImport } = await import('/js/modules/tarifario-import.js');
    await mountTariffImport(document.querySelector('main'), { orgId: 'org', canEdit: true });
  });
  await page.locator('#ti-ars').selectOption('ars');
  const header = 'Descripción;Servicio;SIMON;CUPS;Tarifa;Desde;Hasta\r\n';
  const file = (name, text) => ({ name, mimeType: 'text/csv', buffer: Buffer.from(text) });
  await page.locator('#ti-file').setInputFiles([
    file('primero.csv', header + 'Texto válido;P1;;;1500;01/01/2027;\r\n\r\n"Texto <script>no ejecutar</script>";P2;BAD;;2000;01/01/2027;\r\n'),
    file('segundo.csv', header + 'Otro texto;P1;;;1500;01/01/2027;\r\n')
  ]);
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByRole('heading', { name: 'primero.csv · fila 4', exact: true }).waitFor();
  assert.equal(await page.locator('.ti-error-card').count(), 2);
  assert.match(await page.locator('.ti-error-card').nth(1).textContent(), /con primero.csv · fila 2/);
  assert.match(await page.locator('.ti-error-card').first().textContent(), /Texto <script>no ejecutar<\/script>/);
  assert.equal(await page.locator('main script').count(), 0);
  const save = () => page.getByRole('button', { name: /^Confirmar: guardar/ });
  assert.equal(await save().isDisabled(), true);
  const simon = page.getByRole('textbox', { name: 'SIMON · primero.csv · fila 4', exact: true });
  assert.equal(await simon.getAttribute('aria-invalid'), 'true');
  await simon.fill('OK');
  assert.match(await page.getByText(/Hay cambios pendientes de validar/).textContent(), /pendientes de validar/);
  await page.getByRole('button', { name: 'Volver a validar correcciones', exact: true }).click();
  await page.waitForFunction(() => document.querySelectorAll('.ti-error-card').length === 1);
  await page.getByRole('button', { name: 'Excluir esta fila del lote' }).click();
  await page.waitForFunction(() => !document.querySelector('.ti-error-card'));
  assert.equal(await save().isEnabled(), true);
  // Revalidation failure must block the previous confirmation.
  await page.evaluate(() => { failValidation = true; });
  await page.getByRole('button', { name: 'Volver a validar correcciones' }).click();
  await page.getByText('Fallo de validación de prueba', { exact: true }).waitFor();
  assert.equal(await save().isDisabled(), true);
  await page.evaluate(() => { failValidation = false; });
  await page.getByRole('button', { name: 'Volver a validar correcciones' }).click();
  await page.waitForFunction(() => !document.querySelector('.i18-actions:last-child button').disabled);
  const downloadEvent = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Descargar copia corregida (CSV)' }).click();
  assert.equal((await downloadEvent).suggestedFilename(), 'tarifario_corregido.csv');
  await page.setViewportSize({ width: 375, height: 800 });
  assert.equal(await page.locator('.i18-table tbody td').first().getAttribute('data-l'), 'Archivo / Fila');
  await save().click();
  await page.getByText('Listo: 2 tarifa(s) guardadas. 0 igual(es) se omitieron.', { exact: true }).waitFor();
  const commits = await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2' && c.args.p_commit));
  assert.equal(commits.length, 1);
  assert.deepEqual(commits[0].args.p_rows.map((r) => [r.servicio, r.simon]), [['P1', ''], ['P2', 'OK']]);
  assert.match(commits[0].args.p_file, /primero.csv.*segundo.csv/);
  // A malformed file blocks the entire selection; no silent partial import.
  const count = await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2').length);
  await page.locator('#ti-file').setInputFiles([file('bien.csv', header + 'Uno;P3;;;1500;;;'), file('mal.csv', 'Columna;Otra\nfoo;bar')]);
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByText(/mal.csv: Faltan encabezados/).waitFor();
  assert.equal(await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2').length), count);
  // Context edits invalidate a previously validated batch.
  await page.locator('#ti-file').setInputFiles(file('bien.csv', header + 'Uno;P3;;;1500;01/01/2027;'));
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await save().waitFor();
  await page.locator('#ti-ct').fill('Nuevo contrato');
  assert.equal(await save().count(), 0);
  await page.locator('#ti-file').setInputFiles(file('grande.csv', header + Array.from({ length: 5001 }, (_, i) => `Texto;P${i};;;1500;01/01/2027;`).join('\n')));
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByText(/El lote tiene 5001 filas/).waitFor();
  // A stored ZIP fixture exercises the XLSX parser and real worksheet row numbers.
  function xlsxFixture() {
    const name = Buffer.from('xl/worksheets/sheet1.xml');
    const xml = '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Servicio</t></is></c><c r="B1" t="inlineStr"><is><t>SIMON</t></is></c><c r="C1" t="inlineStr"><is><t>Tarifa</t></is></c></row><row r="8"><c r="A8" t="inlineStr"><is><t>P8</t></is></c><c r="B8" t="inlineStr"><is><t>BAD</t></is></c><c r="C8"><v>1800</v></c></row></sheetData></worksheet>';
    const data = Buffer.from(xml); let crc = 0xffffffff;
    for (const byte of data) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4); local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(name.length, 26);
    const central = Buffer.alloc(46); central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6); central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(name.length, 28);
    const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10); end.writeUInt32LE(central.length + name.length, 12); end.writeUInt32LE(local.length + name.length + data.length, 16);
    return Buffer.concat([local, name, data, central, name, end]);
  }
  await page.locator('#ti-file').setInputFiles([
    { name: 'hoja.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: xlsxFixture() },
    file('adicional.csv', 'Código SIMON;Tarifa\n1234;1500')
  ]);
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  await page.getByRole('heading', { name: 'hoja.xlsx · fila 8', exact: true }).waitFor();
  const last = await page.evaluate(() => calls.filter((c) => c.name === 'import_contract_tariffs_v2').at(-1).args.p_rows);
  assert.equal(last[0].servicio, 'P8');
  assert.equal(last[1].servicio, '');
  assert.equal(last[1].simon, '1234');
  // Original values remain legible in both themes on mobile.
  for (const theme of ['dark', 'light']) {
    await page.evaluate((t) => { document.documentElement.dataset.theme = t; }, theme);
    const field = page.getByRole('textbox', { name: 'SIMON · hoja.xlsx · fila 8', exact: true });
    assert.equal(await field.getAttribute('aria-invalid'), 'true');
    assert.equal(await field.evaluate((e) => e.getBoundingClientRect().width <= e.parentElement.getBoundingClientRect().width), true);
  }
  assert.deepEqual(errors, []);
  console.log('PASS: multiarchivo, texto original, corrección, duplicados, exclusión, revalidación, bloqueo de guardado, exportación, móvil, límite del lote y XLSX con filas discontinuas.');
} finally { await browser.close(); }
