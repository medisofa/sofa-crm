/** «Frecuentes» del menú: la lógica real de js/utils/nav-frequency.js en Chromium.
 *  Simula varias navegaciones y comprueba que las más usadas suben, que respeta permisos,
 *  el umbral mínimo y que excluye favoritos y la ruta actual. Datos ficticios; sin Supabase. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROME || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage();
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.hostname !== '127.0.0.1') return route.abort();
    if (u.pathname === '/') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><meta charset="utf-8"><title>t</title>' });
    try { return route.fulfill({ body: await readFile(new URL(u.pathname.slice(1), root)), contentType: 'text/javascript' }); }
    catch { return route.fulfill({ status: 404, body: 'Missing ' + u.pathname }); }
  });
  await page.goto('http://127.0.0.1:8901/');
  const out = await page.evaluate(async () => {
    const m = await import('/js/utils/nav-frequency.js');
    // localStorage falso para no depender del navegador real ni ensuciar nada
    const mem = {}; const store = { getItem: k => (k in mem ? mem[k] : null), setItem: (k, v) => { mem[k] = String(v); }, removeItem: k => { delete mem[k]; } };
    const scope = { userId: 'u1', organizationId: 'org1', role: 'super_admin' };
    const visitar = (r, n) => { for (let i = 0; i < n; i++) m.recordNavVisit(scope, r, store); };
    const allowed = ['reclamaciones', 'glosas', 'pagos', 'pacientes', 'dashboard', 'honorarios'];
    visitar('reclamaciones', 8); visitar('glosas', 5); visitar('pagos', 3);
    visitar('pacientes', 1);              // bajo el umbral MIN_SCORE
    visitar('no-permitida', 9);           // fuera de allowed → nunca debe salir
    const top = m.topNavRoutes(scope, allowed, { limit: 6, storage: store });
    const sinFav = m.topNavRoutes(scope, allowed, { exclude: ['glosas'], limit: 6, storage: store });
    const sinActual = m.topNavRoutes(scope, allowed, { exclude: ['reclamaciones'], limit: 6, storage: store });
    const limitado = m.topNavRoutes(scope, allowed, { limit: 2, storage: store });
    const otroScope = m.topNavRoutes({ userId: 'u2', organizationId: 'org1', role: 'super_admin' }, allowed, { storage: store });
    return { top, sinFav, sinActual, limitado, otroScope, persistido: JSON.parse(mem[Object.keys(mem)[0]]) };
  });
  assert.deepEqual(out.top, ['reclamaciones', 'glosas', 'pagos'], 'Ordena por frecuencia y aplica umbral/permiso: ' + JSON.stringify(out.top));
  assert.ok(!out.top.includes('pacientes'), 'La ruta de una sola visita no aparece (umbral)');
  assert.ok(!out.top.includes('no-permitida'), 'Una ruta fuera de permisos nunca aparece');
  assert.ok(!out.sinFav.includes('glosas'), 'Excluye lo que ya está en Favoritos');
  assert.ok(!out.sinActual.includes('reclamaciones'), 'Excluye la ruta actual');
  assert.equal(out.limitado.length, 2, 'Respeta el límite');
  assert.deepEqual(out.otroScope, [], 'La frecuencia es por usuario: otro usuario no hereda');
  assert.ok(Object.keys(out.persistido).length <= 24, 'Acota el almacén');
  assert.equal(errors.length, 0, 'Sin errores JS: ' + errors.join(' | '));
  console.log('PASS frequent-menus · frecuencia por usuario, umbral, permisos, exclusiones y límite');
} finally { await browser.close(); }
