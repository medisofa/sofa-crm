/**
 * SOFA · Service worker (PWA).
 * Solo guarda el "cascarón" de la aplicación (HTML, CSS, JS, íconos) para que abra rápido
 * e instalable. NUNCA intercepta ni guarda respuestas de Supabase: los datos de pacientes
 * y cobros no quedan en caché.
 *
 * 5.11.1 · Reescrito. Qué cambió y por qué:
 *
 *   1. La instalación ya NO es atómica. Antes era `cache.addAll(SHELL)`, y addAll falla
 *      entero si UNA sola de sus rutas devuelve 404. Con una lista de 103 rutas escrita a
 *      mano, basta que se renombre un archivo para que el service worker no instale nada
 *      y la aplicación se quede SIN modo sin conexión, en silencio y sin aviso.
 *      Ahora cada archivo se guarda por separado: si uno falta, se anota y los demás entran.
 *
 *   2. SHELL ya no lista los módulos de pantalla. Esa lista era de la versión 1.7.5 y había
 *      que acordarse de ampliarla en cada entrega; nadie lo hizo en decenas de pantallas.
 *      Ahora SHELL es solo lo que hace falta para ARRANCAR, y las pantallas se guardan solas
 *      la primera vez que se abren (lo hace el `fetch` de abajo). Así no hay lista que caducar.
 *
 *   3. `js/config.js` sale de la precarga. Lleva credenciales, está en .gitignore y puede no
 *      estar publicado: si faltaba, tumbaba la instalación completa (punto 1). Se sigue
 *      sirviendo de la red primero, y se guarda al vuelo para que la app arranque sin conexión.
 *
 * AL PUBLICAR UNA VERSIÓN NUEVA: cambia VERSION abajo para que se renueve la caché.
 * Mantenlo igual al APP_VERSION de js/version.js.
 */
const VERSION = 'sofa-shell-5.22.4';

/** Lo mínimo para que la aplicación arranque y pinte algo sin conexión. */
const SHELL = [
  './', './index.html', './login.html', './portal.html', './manifest.json',
  './css/variables.css', './css/components.css', './css/app.css', './css/iter18.css',
  './vendor/supabase-js-2.117.2.umd.js',
  './js/boot-guard.js', './js/anti-marcos.js', './js/version.js',
  './js/supabase.js', './js/auth.js', './js/router.js', './js/app.js', './js/login.js', './js/portal.js',
  './js/utils/dom.js', './js/utils/ui.js', './js/utils/formatters.js',
  './js/utils/validation.js', './js/utils/permissions.js', './js/utils/constants.js',
  './js/modules/home.js', './js/modules/placeholder.js', './js/modules/profile.js', './js/modules/diagnostics.js',
  './assets/brand/sofa-logo.png', './assets/brand/sofa-logo-white.png', './assets/brand/sofa-symbol.png',
  './assets/icons/icon-192.png', './assets/icons/icon-512.png', './assets/icons/favicon-32.png'
];

/** Guarda una por una: lo que falte se anota en la consola y no tumba a las demás. */
async function guardarCascaron() {
  const cache = await caches.open(VERSION);
  const faltantes = [];
  await Promise.all(SHELL.map((url) =>
    cache.add(new Request(url, { cache: 'reload' })).catch(() => faltantes.push(url))
  ));
  if (faltantes.length) {
    console.warn('SOFA · service worker: estos archivos del cascarón no se pudieron guardar y la app no funcionará sin conexión hasta que existan:', faltantes);
  }
  return faltantes;
}

self.addEventListener('install', (e) => {
  e.waitUntil(guardarCascaron().then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;   // Supabase y cualquier otro origen: siempre red
  // Primero la red (siempre la versión publicada, incluido js/config.js).
  // Toda respuesta buena se guarda, así una pantalla abierta una vez queda disponible sin conexión.
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copia = res.clone(); caches.open(VERSION).then((c) => c.put(req, copia)); }
      return res;
    }).catch(() => caches.match(req, { ignoreSearch: true })
      .then((r) => r || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error())))
  );
});
