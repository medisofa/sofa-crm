// Requires the isolated fixture DB. SOFA_OPENING_DB_CONTAINER=... SOFA_PLAYWRIGHT_MODULE=... node tests/browser/opening-history.mjs
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('../../', import.meta.url));
const container = process.env.SOFA_OPENING_DB_CONTAINER || 'sofa-opening-history-test';
const org = '10000000-0000-4000-8000-000000000001';
const provider = '20000000-0000-4000-8000-000000000001';
const ars = '30000000-0000-4000-8000-000000000001';
const sqlLiteral = (v) => v == null ? 'null' : "'" + String(typeof v === 'object' ? JSON.stringify(v) : v).replace(/'/g, "''") + "'";
function sql(text) { return new Promise((resolve, reject) => {
  const p = spawn('docker', ['exec', '-i', container, 'psql', '-U', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1']);
  let out = '', err = ''; p.stdout.on('data', (s) => { out += s; }); p.stderr.on('data', (s) => { err += s; });
  p.on('error', reject); p.on('close', (code) => code ? reject(Error(err)) : resolve(out.trim())); p.stdin.end(text);
}); }
const signatures = {
  opening_history_context: ['p_org'], opening_history_board: ['p_org', 'p_offset', 'p_limit', 'p_status'],
  opening_history_preview: ['p_org', 'p_provider', 'p_ars', 'p_start', 'p_asof', 'p_code', 'p_rows'],
  opening_history_authorize: ['p_org', 'p_provider', 'p_ars', 'p_start', 'p_asof', 'p_code', 'p_rows', 'p_expected', 'p_reason'],
  opening_history_commit: ['p_authorization'], opening_history_item: ['p_item'],
  opening_history_review: ['p_item', 'p_status', 'p_note', 'p_expected_revision'],
  opening_history_rectify: ['p_item', 'p_billed', 'p_paid', 'p_retained', 'p_glosa', 'p_reason', 'p_expected_revision'],
  opening_history_recovery_add: ['p_item', 'p_amount', 'p_reference', 'p_paid_on', 'p_note']
};
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } }); const calls = [], errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.route('**/*', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/preview.html') return route.fulfill({ contentType: 'text/html', body: '<link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/iter18.css"><main></main>' });
    if (path === '/js/supabase.js') return route.fulfill({ contentType: 'text/javascript', body: `export const sb = () => ({rpc: async(name,args)=>{const r=await fetch('/rpc',{method:'POST',body:JSON.stringify({name,args,role:window.testRole||'admin'})});return r.json()}});` });
    if (path === '/rpc') {
      const { name, args, role } = route.request().postDataJSON(); calls.push({ name, args });
      if (!signatures[name]) return route.fulfill({ json: { error: { message: 'Unexpected RPC ' + name } } });
      try {
        const statement = `do $$ begin perform set_config('test.uid','50000000-0000-4000-8000-000000000001',false);perform set_config('test.org',${sqlLiteral(org)},false);perform set_config('test.role',${sqlLiteral(role)},false);end $$; set role authenticated; select jsonb_build_object('data',public.${name}(${signatures[name].map((key) => sqlLiteral(args[key])).join(',')}));`;
        return route.fulfill({ json: JSON.parse(await sql(statement)) });
      } catch (e) { return route.fulfill({ json: { error: { message: e.message } } }); }
    }
    if (!path.startsWith('/js/') && !path.startsWith('/css/')) return route.abort();
    try { return route.fulfill({ contentType: path.endsWith('.css') ? 'text/css' : 'text/javascript', body: await readFile(root + path.slice(1), 'utf8') }); }
    catch { return route.fulfill({ status: 404, body: 'Missing' }); }
  });
  await page.goto('http://127.0.0.1:8881/preview.html');
  await page.evaluate(async ({ org }) => { const m = await import('/js/modules/opening-history.js'); window.mountHistory = m.mountOpeningHistory; await m.mountOpeningHistory(document.querySelector('main'), { orgId: org, role: 'admin' }); }, { org });
  await page.getByText('Cargar códigos existentes, reclamaciones y pagos anteriores', { exact: true }).click();
  await page.getByRole('combobox', { name: 'ARS de la carga histórica' }).selectOption(ars);
  await page.getByRole('textbox', { name: 'Código de prestador existente' }).fill('ANT-123');
  await page.getByLabel('Corte de los saldos iniciales', { exact: true }).fill('2026-10-02');
  const header = 'Tipo;Radicación;Reclamación;Fecha radicación;Fecha servicio;Servicio / Descripción;NSS;Autorización;Facturado;Pagado;Retención;Glosa aceptada;Referencia pago;Fecha pago\n';
  const file = (name, text) => ({ name, mimeType: 'text/csv', buffer: Buffer.from(text) });
  await page.getByLabel('Archivos de cartera anterior').setInputFiles([
    file('totales.csv', header + 'resumen;RAD-PREVIA;;01/08/2026;;;;;1000;400;0;100;;\nresumen;RAD-SIN-PAGO;;01/07/2026;;;;;500;;;;;'),
    file('detalle.csv', header + 'reclamacion;RAD-PREVIA;REC-1;;20/07/2026;Servicio anterior;NSS1;AUT1;1000;oops;0;100;;\npago;RAD-PREVIA;REC-1;;;;;;;400;;;ABONO-1;15/09/2026')
  ]);
  await page.getByRole('button', { name: 'Revisar cartera anterior', exact: true }).click();
  const correction = page.getByRole('textbox', { name: 'Pagado · detalle.csv · fila 2', exact: true });
  await correction.waitFor(); assert.equal(await correction.inputValue(), 'oops');
  await correction.fill('400');
  await page.getByRole('button', { name: 'Volver a revisar correcciones', exact: true }).click();
  await page.getByText('Revise los saldos y las alertas. Administración debe autorizar antes de validar y guardar.', { exact: true }).waitFor();
  const reason = page.getByRole('textbox', { name: 'Soporte de la autorización histórica' });
  await reason.waitFor();
  assert.match(await page.locator('.oh-upload').textContent(), /Pago parcial/);
  assert.match(await page.locator('.oh-upload').textContent(), /Pago no informado/);
  const authorize = page.getByRole('button', { name: 'Autorizar carga de apertura', exact: true });
  const save = page.getByRole('button', { name: 'Guardar cartera anterior', exact: true });
  assert.equal(await save.isDisabled(), true);
  await reason.fill('Contrato y estados de cuenta de las ARS verificados');
  await page.getByRole('checkbox', { name: /Verifiqué el código existente/ }).check();
  assert.equal(await authorize.isEnabled(), true);
  await authorize.click();
  await page.getByText(/Carga autorizada\. Aún no/).waitFor();
  assert.equal(await sql('select count(*) from app.opening_history_items'), '0');
  assert.equal(await save.isDisabled(), true);
  await page.getByRole('button', { name: 'Validar autorización antes de guardar', exact: true }).click();
  await page.getByText('Autorización y saldos validados. Puede confirmar el guardado.', { exact: true }).waitFor();
  assert.equal(await save.isEnabled(), true);
  await save.click();
  await page.getByText(/Carga completada: 2 radicación/).waitFor();
  assert.equal(await sql('select count(*) from app.opening_history_items'), '2');
  assert.equal(await sql('select count(*) from public.service_lines'), '0');
  assert.equal(await sql('select count(*) from public.payments'), '0');
  assert.equal(await sql('select count(*) from public.sofa_fees'), '0');
  assert.equal(await sql("select status from public.provider_ars_codes where code='ANT-123'"), 'codificado');
  await page.locator('.oh-table tr').filter({ hasText: 'RAD-PREVIA' }).getByRole('button', { name: 'Abrir auditoría' }).click();
  await page.getByRole('heading', { name: 'Auditoría de RAD-PREVIA', exact: true }).waitFor();
  assert.match(await page.locator('.oh-detail').textContent(), /pagado: oops → 400/);
  await page.getByRole('textbox', { name: 'Hallazgo o soporte de auditoría' }).fill('Relación ARS y abono bancario cotejados sin duplicidad');
  await page.getByRole('button', { name: 'Guardar auditoría histórica', exact: true }).click();
  await page.getByText('Relación ARS y abono bancario cotejados sin duplicidad', { exact: true }).waitFor();
  await page.getByText('Documentar un cobro recibido después del corte', { exact: true }).click();
  await page.getByLabel('Monto de cobro posterior', { exact: true }).fill('500');
  await page.getByLabel('Fecha de cobro posterior', { exact: true }).fill('2026-10-15');
  await page.getByLabel('Referencia de cobro posterior', { exact: true }).fill('RECUP-1');
  await page.getByLabel('Soporte de cobro posterior', { exact: true }).fill('Transferencia posterior cotejada con cuenta bancaria');
  await page.getByRole('checkbox', { name: /Confirmo que este cobro/ }).check();
  await page.getByRole('button', { name: 'Registrar cobro posterior de cartera anterior', exact: true }).click();
  await page.getByText('RECUP-1', { exact: true }).waitFor();
  assert.equal(await sql("select paid || '|' || recovered || '|' || (billed-paid-retained-accepted_glosa-recovered) from app.opening_history_items where external_ref='RAD-PREVIA'"), '400.00|500.00|0.00');
  await page.locator('.oh-table tr').filter({ hasText: 'RAD-SIN-PAGO' }).getByRole('button', { name: 'Abrir auditoría' }).click();
  await page.getByRole('heading', { name: 'Auditoría de RAD-SIN-PAGO', exact: true }).waitFor();
  await page.getByText('Rectificar saldos iniciales con soporte', { exact: true }).click();
  await page.getByLabel('Rectificar Pagado al corte', { exact: true }).fill('0');
  await page.getByLabel('Soporte de rectificación de apertura', { exact: true }).fill('ARS certifica que no había pagos al corte de esta radicación');
  await page.getByRole('button', { name: 'Autorizar rectificación de saldos' }).click();
  await page.getByText(/Rectificación autorizada: ARS certifica/).waitFor();
  assert.equal(await sql("select paid from app.opening_history_items where external_ref='RAD-SIN-PAGO'"), '0.00');
  await page.setViewportSize({ width: 375, height: 850 });
  for (const theme of ['dark', 'light']) {
    await page.evaluate((t) => { document.documentElement.dataset.theme = t; }, theme);
    assert.equal(await page.locator('.oh-detail textarea').first().evaluate((e) => e.getBoundingClientRect().width <= e.parentElement.getBoundingClientRect().width + 1), true);
  }
  assert.equal(calls.filter((c) => c.name === 'opening_history_commit').length, 1);
  assert.deepEqual(errors, []);
  console.log('PASS: browser → real isolated PostgreSQL, multiarchivo, corrección original, resumen+detalle, autorización, validación, guardado, auditoría, cobro posterior, rectificación y móvil.');
} finally { await browser.close(); }
