/** Íconos por ruta: toda ruta de permissions.js tiene un ícono propio y el patrón de enlace del menú
 *  (dom.js html/render/raw + route-icons.icon) pinta el <svg>. Sin datos reales. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = new URL('../../', import.meta.url);
const perm = await readFile(new URL('js/utils/permissions.js', root), 'utf8');
const routes = [...new Set([...perm.matchAll(/route: '([^']+)'/g)].map(m => m[1]))];
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROME || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
try {
  const page = await browser.newPage();
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.route('**/*', async r => {
    const u = new URL(r.request().url());
    if (u.hostname !== '127.0.0.1') return r.abort();
    if (u.pathname === '/') return r.fulfill({ contentType: 'text/html', body: '<!doctype html><meta charset="utf-8"><main></main>' });
    try { return r.fulfill({ body: await readFile(new URL(u.pathname.slice(1), root)), contentType: u.pathname.endsWith('.css') ? 'text/css' : 'text/javascript' }); }
    catch { return r.fulfill({ status: 404, body: 'x' }); }
  });
  await page.goto('http://127.0.0.1:8991/');
  const res = await page.evaluate(async (routes) => {
    const { html, render, raw } = await import('/js/utils/dom.js');
    const { icon, ROUTE_ICON } = await import('/js/utils/route-icons.js');
    const fb = icon('__ruta_inexistente__');               // ícono de respaldo
    const sinPropio = routes.filter(x => icon(x) === fb);   // rutas que caen al respaldo
    const host = document.querySelector('main');
    // Pinta un enlace por ruta con el MISMO patrón que app.js, incluyendo una etiqueta con HTML para probar escape
    render(host, html`${routes.map(x => html`<div class="nav-link-row"><a href="#/${x}">${raw(icon(x))}<span class="nav-ic-lbl">${'<b>' + x + '</b>'}</span></a></div>`)}`);
    const links = [...host.querySelectorAll('.nav-link-row > a')];
    const conSvg = links.filter(a => a.querySelector('svg')).length;
    const escapoOk = host.innerHTML.includes('&lt;b&gt;') && !host.querySelector('.nav-ic-lbl b');
    return { total: routes.length, keys: Object.keys(ROUTE_ICON).length, sinPropio, links: links.length, conSvg, escapoOk };
  }, routes);
  assert.equal(res.sinPropio.length, 0, 'Rutas sin ícono propio: ' + res.sinPropio.join(', '));
  assert.equal(res.links, routes.length, 'Un enlace por ruta');
  assert.equal(res.conSvg, routes.length, 'Cada enlace del menú pinta su <svg>');
  assert.ok(res.escapoOk, 'La etiqueta del menú se escapa (sin HTML inyectado)');
  assert.equal(errors.length, 0, 'Sin errores JS: ' + errors.join(' | '));
  console.log(`PASS route-icons · ${res.total} rutas, todas con ícono propio; menú pinta ${res.conSvg} <svg>; etiqueta escapada`);
} finally { await browser.close(); }
