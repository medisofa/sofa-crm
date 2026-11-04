// Verifies a returning browser with an old worker/cache, including a stale unversioned CDN response.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.SOFA_PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('../../', import.meta.url));
const requests = []; let published = false;
const oldModule = `export async function mountTariffImport(root){root.innerHTML='<button disabled>Confirmar: guardar 10 tarifa(s)</button>';}`;
const oldWorker = `const CACHE='sofa-shell-5.23.1';self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(['/js/modules/tarifario-import.js','/css/iter18.css'])).then(()=>self.skipWaiting())));self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));self.addEventListener('fetch',e=>{if(new URL(e.request.url).origin!==self.location.origin)return;e.respondWith(caches.open(CACHE).then(async c=>(await c.match(e.request,{ignoreSearch:true}))||fetch(e.request)));});`;
const html = `<!doctype html><html><head><link rel="stylesheet" href="/css/variables.css"><link rel="stylesheet" href="/css/iter18.css"></head><body><main></main><script>
window.mockDB={async rpc(name,args){if(name==='client_ars_matrix')return {data:{providers:[{id:'doctor',name:'Dra. Prueba'}],ars:[{id:'ars',name:'ARS Prueba'}]}};
if(name==='ars_catalog'||name==='tariff_import_history')return {data:[]};if(name==='import_contract_tariffs_v2'&&!args.p_commit)return {data:{errors:[],rows:[{row:1,service:'Servicio de prueba',amount:1500,change:'nueva',valid_from:'2026-01-01'}],new:1,changed:0,same:0}};throw Error('Unexpected RPC '+name)}};
</script><script type="module">import{mountTariffImport}from'/js/modules/tarifario-import.js';await mountTariffImport(document.querySelector('main'),{orgId:'org',canEdit:true});window.loaded=true;</script></body></html>`;
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://test'); requests.push(url.pathname + url.search);
  const send = (body, type = 'text/javascript') => { res.setHeader('Content-Type', type); res.setHeader('Cache-Control', 'public,max-age=86400'); res.end(body); };
  try {
    if (url.pathname === '/' || url.pathname === '/index.html') return send(html, 'text/html');
    if (url.pathname === '/sw.js') { res.setHeader('Service-Worker-Allowed', '/'); return send(url.searchParams.has('legacy') ? oldWorker : await readFile(root + 'sw.js', 'utf8')); }
    if (url.pathname === '/js/supabase.js') return send('export const sb=()=>window.mockDB;');
    if (url.pathname === '/js/modules/tarifario-import.js' && (!published || url.searchParams.get('sofa_v') !== '5.28.0')) return send(oldModule);
    if (url.pathname === '/css/iter18.css' && (!published || url.searchParams.get('sofa_v') !== '5.28.0')) return send('button{background:transparent;color:#999}', 'text/css');
    if (url.pathname === '/js/version.js' && url.searchParams.get('sofa_v') !== '5.28.0') return send("export const APP_VERSION='5.23.1';");
    const body = await readFile(root + url.pathname.slice(1));
    return send(body, url.pathname.endsWith('.css') ? 'text/css' : url.pathname.endsWith('.html') ? 'text/html' : 'text/javascript');
  } catch { res.statusCode = 404; res.end('Missing'); }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: process.env.SOFA_CHROMIUM || '/usr/bin/chromium', args: ['--no-sandbox'] });
try {
  const context = await browser.newContext(); const page = await context.newPage(); const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(origin + '/index.html#/clientes/test-client');
  await page.getByRole('button', { name: 'Confirmar: guardar 10 tarifa(s)' }).waitFor();
  await page.evaluate(async () => {
    localStorage.setItem('session-marker', 'preserve-this-session');
    await caches.open('unrelated-app-cache');
    await navigator.serviceWorker.register('/sw.js?legacy=1', { updateViaCache: 'none' });
    await navigator.serviceWorker.ready;
  });
  await page.waitForFunction(() => navigator.serviceWorker.controller?.scriptURL.includes('legacy=1'));
  published = true;
  await page.reload();
  await page.getByRole('button', { name: 'Confirmar: guardar 10 tarifa(s)' }).waitFor();
  // Switching the published version alone must not be mistaken for a successful client upgrade.
  await page.evaluate(async () => { await navigator.serviceWorker.register('/sw.js?v=5.28.0', { updateViaCache: 'none' }); });
  await page.waitForFunction(() => navigator.serviceWorker.controller?.scriptURL.includes('v=5.28.0'));
  await page.reload();
  await page.locator('#ti-file').waitFor();
  await page.locator('#ti-ars').selectOption('ars');
  await page.locator('#ti-file').setInputFiles({ name: 'tarifa.csv', mimeType: 'text/csv', buffer: Buffer.from('Servicio;Tarifa;Desde\nP1;1500;01/01/2026') });
  await page.getByRole('button', { name: 'Revisar archivos', exact: true }).click();
  const save = page.getByRole('button', { name: /^Guardar tarifario:/ });
  await save.waitFor(); assert.equal(await save.isEnabled(), true);
  assert.equal(await save.evaluate((e) => getComputedStyle(e).backgroundColor), 'rgb(23, 109, 58)');
  assert.equal(await page.getByRole('button', { name: 'Confirmar: guardar 10 tarifa(s)' }).count(), 0);
  const keys = await page.evaluate(() => caches.keys());
  assert.ok(keys.includes('sofa-shell-5.28.0'));
  assert.ok(!keys.includes('sofa-shell-5.23.1'));
  assert.ok(keys.includes('unrelated-app-cache'));
  assert.equal(await page.evaluate(() => localStorage.getItem('session-marker')), 'preserve-this-session');
  assert.ok(requests.some((u) => u.startsWith('/js/modules/tarifario-import.js?sofa_v=5.28.0')));
  assert.ok(requests.some((u) => u.startsWith('/css/iter18.css?sofa_v=5.28.0')));
  await page.waitForFunction(async () => {
    const c = await caches.open('sofa-shell-5.28.0');
    return (await Promise.all(['/js/modules/tarifario-import.js','/js/modules/tariff-code-exceptions.js','/js/utils/xlsx-lite.js','/js/services/iter18.js','/js/supabase.js'].map((u) => c.match(u)))).every(Boolean);
  });
  await context.setOffline(true); await page.reload();
  await page.locator('#ti-file').waitFor();
  assert.equal(await page.locator('#ti-file').getAttribute('multiple'), '');
  assert.equal(await page.evaluate(async () => (await import('/js/version.js?v=5.28.0')).APP_VERSION), '5.28.0');
  assert.equal(await page.evaluate(() => localStorage.getItem('session-marker')), 'preserve-this-session');
  assert.deepEqual(errors, []);
  console.log('PASS: sesión antigua conserva el botón viejo tras recargar; actualización 5.28.0 recibe botón verde, renueva solo caché SOFA, conserva sesión y funciona sin conexión con los módulos nuevos.');
} finally { await browser.close(); await new Promise((resolve) => server.close(resolve)); }
