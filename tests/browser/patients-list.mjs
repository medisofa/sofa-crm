// SOFA_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/browser/patients-list.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage();
  await page.route('**/*', async route => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/') return route.fulfill({ contentType: 'text/html', body: '<main></main>' });
    if (path === '/js/supabase.js') return route.fulfill({ contentType: 'text/javascript', body: 'export const sb = () => window.mockDB;' });
    return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL(path.slice(1), root)) });
  });
  await page.goto('http://127.0.0.1:8881/');
  await page.evaluate(async () => {
    window.calls = [];
    window.mockDB = {
      from(table) {
        const filters = {}; let start = 0, end = 25;
        const chain = {
          select() { return chain; }, eq(k, v) { filters[k] = v; return chain; }, order() { return chain; },
          range(a, b) { start = a; end = b; return chain; },
          then(resolve) {
            if (table === 'providers') return Promise.resolve({ data: [{ organization_id: 'a', full_name: 'Cliente A' }, { organization_id: 'b', full_name: 'Cliente B' }] }).then(resolve);
            calls.push({ table, filters, start, end });
            const rows = Array.from({ length: filters.organization_id === 'a' ? 27 : 0 }, (_, i) => ({ id: String(i), name: `Paciente ${i}`, doc: 'Ficticio' }));
            return Promise.resolve({ data: rows.slice(start, end + 1) }).then(resolve);
          }
        }; return chain;
      },
      rpc(name, args) { calls.push({ name, args }); return Promise.resolve({ data: name === 'search_patients' ? [{ id: 'search', name: 'Resultado de búsqueda' }] : [] }); }
    };
    const { render } = await import('/js/modules/pacientes.js');
    await render(document.querySelector('main'));
  });
  assert.equal(await page.locator('tbody tr').count(), 25);
  assert.equal(await page.getByRole('button', { name: 'Anterior', exact: true }).isDisabled(), true);
  await page.getByRole('button', { name: 'Siguiente', exact: true }).click();
  await page.getByText('Página 2', { exact: true }).waitFor();
  assert.equal(await page.locator('tbody tr').count(), 2);
  assert.equal(await page.getByRole('button', { name: 'Siguiente', exact: true }).isDisabled(), true);
  await page.locator('#px-q').fill('Resultado');
  await page.getByRole('button', { name: 'Buscar', exact: true }).click();
  await page.getByText('Resultado de búsqueda', { exact: true }).waitFor();
  await page.locator('#px-org').selectOption('b');
  await page.getByText('Sin datos para mostrar.', { exact: true }).waitFor();
  assert.equal(await page.locator('#px-q').inputValue(), '');
  const last = await page.evaluate(() => calls.at(-1));
  assert.equal(last.filters.organization_id, 'b');
  assert.equal(last.filters.is_active, true);
  assert.equal(last.start, 0);
  console.log('PASS: initial patient list, pagination, search, client isolation and empty state');
} finally { await browser.close(); }
