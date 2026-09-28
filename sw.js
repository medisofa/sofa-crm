/**
 * SOFA · Service worker (PWA).
 * Solo guarda el "cascarón" de la aplicación (HTML, CSS, JS, íconos) para que
 * abra rápido e instalable. NUNCA intercepta ni guarda respuestas de Supabase:
 * los datos de pacientes y cobros no quedan en caché.
 * Al publicar una versión nueva, cambia VERSION para renovar la caché.
 */
const VERSION = 'sofa-shell-0.3.0';
const SHELL = [
  './', './index.html', './login.html', './manifest.json',
  './css/variables.css', './css/components.css', './css/app.css',
  './vendor/supabase-js-2.117.2.umd.js',
  './js/config.js', './js/supabase.js', './js/auth.js', './js/router.js', './js/app.js', './js/login.js',
  './js/utils/dom.js', './js/utils/ui.js', './js/utils/formatters.js', './js/utils/validation.js', './js/utils/permissions.js',
  './js/services/stats.js', './js/services/catalog.js', './js/services/clients.js', './js/services/admin.js',
  './js/modules/home.js', './js/modules/clients.js', './js/modules/coding.js', './js/modules/ars.js', './js/modules/users.js',
  './js/modules/settings.js', './js/modules/profile.js', './js/modules/diagnostics.js', './js/modules/placeholder.js',
  './assets/icons/icon-192.png', './assets/icons/icon-512.png', './assets/icons/favicon-32.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return; // Supabase y cualquier otro origen: siempre red
  if (req.mode === 'navigate') {
    // Páginas: primero la red (versión actual); sin conexión, la copia guardada
    e.respondWith(fetch(req).then((res) => { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); return res; })
      .catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match('./index.html'))));
    return;
  }
  // Archivos del cascarón: copia guardada al instante y actualización en segundo plano
  e.respondWith(caches.open(VERSION).then((c) => c.match(req).then((cached) => {
    const net = fetch(req).then((res) => { if (res.ok) c.put(req, res.clone()); return res; }).catch(() => cached);
    return cached || net;
  })));
});
