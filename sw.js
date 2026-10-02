/**
 * SOFA · Service worker (PWA).
 * Solo guarda el "cascarón" de la aplicación (HTML, CSS, JS, íconos) para que
 * abra rápido e instalable. NUNCA intercepta ni guarda respuestas de Supabase:
 * los datos de pacientes y cobros no quedan en caché.
 * Al publicar una versión nueva, cambia VERSION para renovar la caché.
 */
const VERSION = 'sofa-shell-1.6.1';
const SHELL = [
  './', './index.html', './login.html', './manifest.json',
  './css/variables.css', './css/components.css', './css/app.css',
  './vendor/supabase-js-2.117.2.umd.js',
  './js/boot-guard.js', './js/version.js', './js/config.js', './js/supabase.js', './js/auth.js', './js/router.js', './js/app.js', './js/login.js',
  './js/utils/dom.js', './js/utils/ui.js', './js/utils/formatters.js', './js/utils/validation.js', './js/utils/permissions.js',
  './js/services/stats.js', './js/services/catalog.js', './js/services/clients.js', './js/services/admin.js',
  './js/modules/dossier-card.js', './js/modules/prerad.js', './js/modules/requirements.js', './js/services/dossier.js',
  './assets/brand/sofa-logo.png', './assets/brand/sofa-logo-white.png', './assets/brand/sofa-symbol.png', './js/modules/fee-invoice.js', './js/modules/agenda.js', './js/modules/private-tariffs.js', './js/modules/practice.js', './js/services/consultorio.js', './js/modules/provider360.js', './js/modules/client-commercial.js', './js/utils/pdf-invoice.js', './vendor/jspdf-4.2.1.umd.min.js', './vendor/jspdf-autotable-5.0.8.min.js', './js/modules/capture.js', './js/modules/claims.js', './js/modules/claim.js', './js/modules/claim-dialogs.js', './js/modules/pickups.js', './js/modules/contracts.js', './js/services/claims.js',
  './js/modules/home.js', './js/modules/clients.js', './js/modules/coding.js', './js/modules/ars.js', './js/modules/users.js',
  './js/modules/settings.js', './js/modules/profile.js', './js/modules/diagnostics.js', './js/modules/placeholder.js',
  './js/modules/client.js', './js/modules/contacts.js', './js/modules/crm-dialogs.js', './js/modules/leads.js', './js/modules/opportunity.js', './js/modules/partners.js', './js/modules/pipeline.js', './js/modules/tasks.js', './js/services/crm.js', './js/services/tasks.js', './js/utils/constants.js', './js/utils/whatsapp.js',
  './js/services/submissions.js', './js/services/documents.js', './js/modules/submissions.js', './js/modules/submission.js', './js/modules/submission-dialogs.js', './js/modules/documents.js',
  './js/services/finance.js', './js/modules/glosas.js', './js/modules/payments.js', './js/modules/fees.js', './js/modules/finance-dialogs.js',
  './js/services/tariffs.js', './js/modules/tariff-dialogs.js', './js/modules/coding-concept.js',
  './js/utils/charts.js', './js/utils/filters.js', './js/services/bi.js', './js/modules/dashboard.js', './js/modules/today.js', './js/modules/aging.js', './js/modules/reports.js',
  './js/services/habilitation.js', './js/modules/habilitation.js', './js/modules/habilitation-case.js', './js/modules/habilitation-dialogs.js',
  './js/services/intel.js', './js/modules/market.js', './js/modules/market-dialogs.js', './js/modules/guides.js',
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
  // Primero la red (siempre la versión publicada, incluido js/config.js);
  // sin conexión, la copia guardada del cascarón
  e.respondWith(fetch(req).then((res) => {
    if (res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); }
    return res;
  }).catch(() => caches.match(req, { ignoreSearch: true })
    .then((r) => r || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error()))));
});
