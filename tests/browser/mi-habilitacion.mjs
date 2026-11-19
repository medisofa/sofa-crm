/** Mi habilitación: la pantalla del cliente agrupa por área plegable, muestra avance por área y
 *  filtra documentos con el buscador. Datos ficticios; solo se mockea la conexión Supabase. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROME || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 1000 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.hostname !== '127.0.0.1') return route.abort();
    const mocks = {
      '/': '<!doctype html><html lang="es"><meta charset="utf-8"><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/iter18.css"><main class="page"></main></html>',
      '/js/supabase.js': `export const sb = () => ({
        rpc: async (name) => name === 'client_habilitation'
          ? { data: [window.__CASE], error: null }
          : { data: {}, error: null },
        storage: { from: () => ({ createSignedUrl: async () => ({ data: { signedUrl: '#' }, error: null }) }) }
      });`
    };
    if (u.pathname in mocks) return route.fulfill({ contentType: u.pathname === '/' ? 'text/html' : 'text/javascript', body: mocks[u.pathname] });
    try { return route.fulfill({ body: await readFile(new URL(u.pathname.slice(1), root)), contentType: u.pathname.endsWith('.css') ? 'text/css' : 'text/javascript' }); }
    catch { return route.fulfill({ status: 404, body: 'Missing ' + u.pathname }); }
  });
  await page.goto('http://127.0.0.1:8899/');
  await page.evaluate(async () => {
    window.__CASE = { id: 'c1', name: 'Centro Demo', type: 'Centro médico', folio: 'HAB-2026-0001',
      stage_label: 'Ensamblaje del expediente', target_date: null, license_valid_until: null, license_days_left: null, pss_code: null, sofa_reset_note: null,
      counts: { applicable: 4, verde: 1, amarillo: 0, rojo: 1, pendiente: 2, critical_open: 1 },
      areas: [
        { area: '0. Expediente DGHA (orden oficial)', items: [
          { id: 'i1', requirement: 'Certificación de No Objeción a la construcción', status: 'pendiente', critical: true, hint: 'Copia del Ministerio de Salud.', can_submit: true },
          { id: 'i2', requirement: 'Certificado de RNC actualizado', status: 'verde', critical: true, hint: '', submitted_at: '2026-11-10', client_note: 'Entregado', storage_path: null, file_name: null } ] },
        { area: '3. Planta física', items: [
          { id: 'i3', requirement: 'Rampa de accesibilidad universal', status: 'rojo', critical: false, hint: 'Requiere obra menor.' },
          { id: 'i4', requirement: 'Señalización de ruta de evacuación', status: 'pendiente', critical: false, hint: '', can_submit: true } ] } ] };
    const m = await import('/js/modules/mi-habilitacion.js');
    await m.render(document.querySelector('main'), { role: 'client', membership: { organization_id: 'org-1' } });
  });
  await page.locator('section.i18-card').waitFor();
  assert.match(await page.locator('h3').first().textContent(), /Centro Demo/);
  assert.equal(await page.locator('details').count(), 2, 'Dos áreas plegables');
  assert.equal(await page.locator('.mh-sum-bar i').count(), 2, 'Barra de avance por área');
  const w = await page.locator('details', { hasText: 'Expediente DGHA' }).locator('.mh-sum-bar i').evaluate(el => el.style.width);
  assert.equal(w, '50%', 'El área con 1 de 2 verdes muestra 50%');
  // Upload UI presente para un pendiente
  assert.equal(await page.getByRole('button', { name: 'Lo entregué' }).count(), 2, 'Dos requisitos permiten entregar');
  // Buscar filtra
  const q = page.locator('.mh-search').first();
  await q.fill('no objec'); await page.waitForTimeout(80);
  assert.equal(await page.locator('li:visible').count(), 1, 'El buscador deja solo la No Objeción');
  assert.ok(!(await page.locator('details', { hasText: 'Planta física' }).first().isVisible()), 'El área sin coincidencias se oculta');
  await q.fill('zzzz'); await page.waitForTimeout(80);
  assert.match(await page.locator('.i18-note', { hasText: 'coincide' }).first().textContent(), /Ningún documento coincide/);
  await q.fill(''); await page.waitForTimeout(80);
  assert.equal(await page.locator('li:visible').count(), 4, 'Al borrar vuelven los 4 documentos');
  assert.equal(errors.length, 0, 'Sin errores JS: ' + errors.join(' | '));
  console.log('PASS mi-habilitacion · áreas plegables, avance por área y buscador');
} finally { await browser.close(); }
