/** Paleta de comandos: abre con Ctrl+K, busca difuso por nombre y familia, navega con Enter,
 *  guarda recientes y cierra con Esc devolviendo el foco. Datos ficticios; sin red. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROME || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage({ viewport: { width: 1000, height: 800 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.hostname !== '127.0.0.1') return route.abort();
    if (u.pathname === '/') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><html lang="es"><meta charset="utf-8"><body><button id="opener">abrir</button></body></html>' });
    try { return route.fulfill({ body: await readFile(new URL(u.pathname.slice(1), root)), contentType: u.pathname.endsWith('.css') ? 'text/css' : 'text/javascript' }); }
    catch { return route.fulfill({ status: 404, body: 'Missing ' + u.pathname }); }
  });
  await page.goto('http://127.0.0.1:8991/');
  await page.evaluate(async () => {
    const FAKE = [
      { route: 'flujo-pacientes', label: 'Flujo de pacientes', group: 'Pacientes y atención' },
      { route: 'pacientes', label: 'Pacientes', group: 'Pacientes y atención' },
      { route: 'historia-clinica', label: 'Historia clínica', group: 'Pacientes y atención' },
      { route: 'reclamaciones', label: 'Reclamaciones', group: 'Facturación y radicación' },
      { route: 'glosas', label: 'Glosas', group: 'Cobros y finanzas' } ];
    const m = await import('/js/modules/command-palette.js');
    window.__nav = null;
    window.pal = m.initCommandPalette({ items: () => FAKE, scopeKey: (k) => k + '.qa', currentRoute: () => 'inicio', onNavigate: (r) => { window.__nav = r; } });
    document.getElementById('opener').focus();
  });
  // Abre con Ctrl+K
  await page.keyboard.press('Control+k');
  await page.locator('[role=dialog]').waitFor();
  assert.ok(await page.evaluate(() => document.activeElement && document.activeElement.id === 'cmdpInput'), 'El input recibe el foco al abrir');
  // Búsqueda por nombre + Enter navega
  await page.keyboard.type('histor');
  assert.equal(await page.locator('.cmdp-opt').first().locator('.lb').textContent(), 'Historia clínica');
  await page.keyboard.press('Enter');
  assert.equal(await page.evaluate(() => window.__nav), 'historia-clinica', 'Enter navega a la ruta activa');
  assert.ok(!(await page.locator('[role=dialog]').isVisible()), 'Se cierra al navegar');
  assert.ok(await page.evaluate(() => document.activeElement && document.activeElement.id === 'opener'), 'Devuelve el foco al abrir');
  // Búsqueda difusa por subsecuencia
  await page.evaluate(() => window.pal.open());
  await page.keyboard.type('hcl');
  assert.equal(await page.locator('.cmdp-opt .lb').first().textContent(), 'Historia clínica', 'Coincidencia difusa hcl→Historia clínica');
  // Coincidencia por familia
  await page.fill('#cmdpInput', 'cobros');
  assert.equal(await page.locator('.cmdp-opt .lb').first().textContent(), 'Glosas', 'Encuentra por nombre de familia');
  // Flechas cambian la selección
  await page.fill('#cmdpInput', 'a');
  const n = await page.locator('.cmdp-opt').count(); assert.ok(n >= 2, 'Varias coincidencias');
  await page.keyboard.press('ArrowDown');
  assert.equal(await page.locator('.cmdp-opt[aria-selected=true]').first().getAttribute('id'), 'cmdp-opt-1', 'ArrowDown mueve la selección');
  // Esc cierra
  await page.keyboard.press('Escape');
  assert.ok(!(await page.locator('[role=dialog]').isVisible()), 'Esc cierra');
  // Recientes
  await page.evaluate(() => window.pal.recordVisit('reclamaciones'));
  await page.evaluate(() => window.pal.open());
  assert.equal(await page.locator('.cmdp-head').first().textContent(), 'Recientes');
  assert.equal(await page.locator('.cmdp-opt .lb').first().textContent(), 'Reclamaciones', 'El reciente aparece primero');
  assert.equal(errors.length, 0, 'Sin errores JS: ' + errors.join(' | '));
  console.log('PASS command-palette · Ctrl+K, búsqueda difusa, teclado, recientes y foco');
} finally { await browser.close(); }
