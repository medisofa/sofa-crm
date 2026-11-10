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
const VERSION = 'sofa-shell-5.35.1';
const ASSET_VERSION = VERSION.replace('sofa-shell-', '');

/** Lo mínimo para que la aplicación arranque y pinte algo sin conexión. */
const SHELL = [
  './', './index.html', './login.html', './portal.html', './manifest.json',
  './css/variables.css', './css/components.css', './css/app.css', './css/iter18.css',
  './vendor/supabase-js-2.117.2.umd.js',
  './js/boot-guard.js', './js/anti-marcos.js', './js/version.js',
  './js/supabase.js', './js/auth.js', './js/router.js', './js/app.js', './js/login.js', './js/portal.js',
  './js/utils/progress-guard.js', './js/utils/intake-autosave.js', './js/utils/intake-draft.js',
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
  await Promise.all(SHELL.map(async (url) => {
    try {
      const req = new Request(new URL(url, self.location.href), { cache: 'reload' });
      const res = await fetch(versionedAssetRequest(req), { cache: 'reload' });
      if (!cacheableStaticResponse(req, res)) throw new Error(`Recurso no cacheable: HTTP ${res.status}`);
      await cache.put(req, res);
    } catch { faltantes.push(url); }
  }));
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
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('sofa-shell-') && k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (!staticShellRequest(req)) return;   // Las APIs y los documentos de usuario nunca pasan por esta caché.
  // Primero la red (siempre la versión publicada, incluido js/config.js). `cache: 'no-store'`
  // evita que un `fetch()` normal devuelva una copia de la caché HTTP del navegador (el origen
  // manda Cache-Control de varios minutos): sin esto, "siempre la red" podía en realidad servir
  // una respuesta de minutos atrás hasta que esa caché expirara.
  // Solo se guardan recursos estáticos permitidos y con tipo de contenido esperado.
  e.respondWith(
    fetch(versionedAssetRequest(req), { cache: 'no-store' }).then((res) => {
      if (cacheableStaticResponse(req, res)) {
        const copia = res.clone();
        e.waitUntil(caches.open(VERSION).then((c) => c.put(req, copia)).catch(() => {}));
      }
      return res;
    }).catch(() => caches.open(VERSION).then(async (cache) =>
      (await cache.match(req, { ignoreSearch: true })) || (req.mode === 'navigate' ? cache.match('./index.html') : Response.error())))
  );
});

/** La URL de red cambia por entrega aunque un CDN conserve la ruta sin versión.
 * La clave local sigue siendo la petición original y solo se consulta la caché de esta entrega.
 * No modifica navegaciones ni peticiones a Supabase u otros orígenes. */
function versionedAssetRequest(req) {
  const url = new URL(req.url);
  if (req.mode === 'navigate' || !/\.(js|css)$/i.test(url.pathname)) return req;
  url.searchParams.set('sofa_v', ASSET_VERSION);
  return new Request(url, req);
}

/** Lista positiva: nada de APIs, documentos, peticiones autenticadas ni parámetros de datos. */
function staticShellRequest(req) {
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin || req.headers.has('Authorization')) return false;
  if ([...url.searchParams.keys()].some((key) => !['v', 'sofa_v'].includes(key))) return false;
  const base = new URL('./', self.location.href).pathname;
  if (!url.pathname.startsWith(base)) return false;
  const path = url.pathname.slice(base.length);
  if (['', 'index.html', 'login.html', 'portal.html', 'manifest.json'].includes(path)) return true;
  return /^(?:js|css|vendor|assets)\/[a-zA-Z0-9_./-]+\.(?:js|css|png|svg|jpg|jpeg|webp|ico|woff|woff2)$/i.test(path);
}

function cacheableStaticResponse(req, res) {
  if (!staticShellRequest(req) || !res.ok || /(?:no-store|private)/i.test(res.headers.get('Cache-Control') || '')) return false;
  const path = new URL(req.url).pathname;
  const type = (res.headers.get('Content-Type') || '').toLowerCase();
  if (/\.js$/i.test(path)) return /(?:java|ecma)script/.test(type);
  if (/\.css$/i.test(path)) return type.startsWith('text/css');
  if (/manifest\.json$/i.test(path)) return /application\/(?:manifest\+json|json)/.test(type);
  if (/\.(?:png|svg|jpg|jpeg|webp|ico)$/i.test(path)) return type.startsWith('image/');
  if (/\.woff2?$/i.test(path)) return type.startsWith('font/') || type.startsWith('application/font');
  return type.startsWith('text/html');
}
