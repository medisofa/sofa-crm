/** SOFA · 5.4.0 · I64 · Medición de tiempos de carga (indicador p95).
 *  El router llama a medirRuta(clave) al empezar a mostrar una pantalla y a la función que devuelve cuando termina de pintarla:
 *      const fin = medirRuta(clave); await render(root, ctx); fin();
 *  Solo se envía la CLAVE de la pantalla (p. ej. «cartera») y los milisegundos: nunca la dirección completa, parámetros, nombres ni identificadores.
 *  Medir nunca debe estorbar: sin internet, sin sesión, con error o con exceso de uso, simplemente no se registra y no se avisa al usuario.
 *  Tope de frecuencia en el navegador: una vez cada 20 segundos por pantalla y 40 envíos por sesión (el servidor también pone su propio tope). */
import { rpc } from './iter18.js';

const ULTIMO = new Map();
let enviados = 0;
const MIN_ENTRE_ENVIOS_MS = 20000;
const TOPE_SESION = 40;

/** Deja solo la clave de la pantalla: minúsculas, letras, números, guion y guion bajo; sin parámetros ni identificadores. */
export function claveSegura(ruta) {
  const base = String(ruta || '').replace(/^#?\/?/, '').split(/[/?#]/)[0].toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(base) || /[0-9]{5,}/.test(base)) return null;
  return base;
}

export function medirRuta(ruta) {
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();
  const clave = claveSegura(ruta);
  let hecho = false;
  return function fin() {
    if (hecho || !clave) return;
    hecho = true;
    const pintado = () => {
      const ms = Math.round((typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0);
      enviar(clave, ms);
    };
    // Se mide hasta que el navegador pinta (dos cuadros), no hasta que termina el código
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(() => requestAnimationFrame(pintado)); else setTimeout(pintado, 0);
  };
}

function enviar(clave, ms) {
  try {
    if (ms < 0 || ms > 600000 || enviados >= TOPE_SESION) return;
    if (typeof navigator !== 'undefined' && navigator.onLine === false) return;
    const ahora = Date.now();
    if (ahora - (ULTIMO.get(clave) || 0) < MIN_ENTRE_ENVIOS_MS) return;
    ULTIMO.set(clave, ahora);
    enviados += 1;
    rpc('perf_record', { p_route: clave, p_ms: ms }).catch(() => { /* medir nunca estorba */ });
  } catch (_) { /* medir nunca estorba */ }
}

// ── Lecturas para la pantalla «Rendimiento» ─────────────────────────────────────
export const perfReport = (days = 7) => rpc('perf_report', { p_days: days });
export const perfDb = () => rpc('perf_db_overview');
export const perfParams = () => rpc('perf_params_get');
export const perfParamsSet = (v) => rpc('perf_params_set', { p_db_limit_bytes: v.dbLimitBytes ?? null, p_p95_target_ms: v.p95TargetMs ?? null, p_retention_days: v.retentionDays ?? null, p_archive_min_days: v.archiveMinDays ?? null, p_rate_per_minute: v.ratePerMinute ?? null });
export const archivesList = (org = null) => rpc('archives_list', { p_org: org });
export const archiveCandidates = (org) => rpc('archive_candidates', { p_org: org });
export const archivePeriod = (org, period, reason = null) => rpc('archive_period', { p_org: org, p_period: period, p_reason: reason });
export const archiveUntil = (org, until, reason = null) => rpc('archive_periods_until', { p_org: org, p_until: until, p_reason: reason });
export const restorePeriod = (org, period, reason) => rpc('restore_period', { p_org: org, p_period: period, p_reason: reason });
export const historySearch = (f = {}, after = null) => rpc('history_search', {
  p_org: f.org || null, p_q: f.q || null, p_ars: f.ars || null, p_provider: f.provider || null, p_from: f.from || null, p_to: f.to || null,
  p_status: f.status || null, p_min: f.min === '' || f.min == null ? null : Number(f.min), p_max: f.max === '' || f.max == null ? null : Number(f.max),
  p_archived_only: !!f.archivedOnly, p_limit: f.limit || 50, p_after: after });
