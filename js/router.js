/**
 * SOFA · Enrutador por hash (#/ruta/parametro). Compatible con GitHub Pages
 * sin configuración de servidor.
 */
import { findRoute, canSee } from './utils/permissions.js';
import { medirRuta } from './services/perf.js';   // 5.0.0 · I64: tiempos de carga por pantalla (indicador p95)

export const MODULES = {
  inicio: 'home.js', clientes: 'clients.js', codificacion: 'coding.js', ars: 'ars.js',
  usuarios: 'users.js', parametros: 'settings.js', perfil: 'profile.js', diagnostico: 'diagnostics.js',
  oportunidades: 'pipeline.js', prospectos: 'leads.js', contactos: 'contacts.js', aliados: 'partners.js', tareas: 'tasks.js',
  radicaciones: 'submissions.js', documentos: 'documents.js',
  glosas: 'glosas.js', pagos: 'payments.js', honorarios: 'fees.js', medicos: 'provider360.js', agenda: 'agenda.js', practica: 'practice.js', 'tarifas-privadas': 'private-tariffs.js',
  hoy: 'today.js', dashboard: 'dashboard.js', aging: 'aging.js', reportes: 'reports.js',
  habilitacion: 'habilitation.js', mercado: 'market.js', guias: 'guides.js',
  captura: 'capture.js', reclamaciones: 'claims.js', retiros: 'pickups.js', contratos: 'contracts.js',
  preradicacion: 'prerad.js', requisitos: 'requirements.js',
  // Iteraciones 18 a 28 (SOFA 1.9.0)
  'mi-dashboard': 'dashboard-rol.js',
  'estado-cuenta': 'statement.js', 'calendario-cobros': 'collections-calendar.js', mensajes: 'weekly.js', rentabilidad: 'profitability.js',
  pacientes: 'pacientes.js', 'saldos-pacientes': 'saldos-pacientes.js', 'indicadores-agenda': 'indicadores-agenda.js',
  seguimiento: 'seguimiento.js', 'avisos-pacientes': 'avisos-pacientes.js', 'mis-secretarias': 'mis-secretarias.js',
  centros: 'centros.js', 'alta-usuarios': 'usuarios.js', 'cambio-clave': 'cambio-clave.js',
  'analitica-glosas': 'analitica-glosas.js', 'salud-clientes': 'salud-clientes.js',
  // 2.0 · Iteración 29
  'historia-clinica': 'historia-clinica.js', 'hc-control': 'hc-control.js', seguridad: 'seguridad.js',
  // 2.1 · Iteraciones 30 y 31
  'mi-ficha': 'mi-ficha.js', 'mi-incorporacion': 'mi-incorporacion.js',
  // 2.2 a 2.6 · Iteraciones 32 a 36
  vencimientos: 'vencimientos.js', 'codigos-ars': 'codigos-ars.js', revision: 'revision.js',
  // 2.7 · Iteración 37
  conciliacion: 'conciliacion.js',
  // 3.0 · Iteración 40
  'mi-cuenta-sofa': 'mi-cuenta-sofa.js', 'casos-servicio': 'servicios-sofa.js',
  // 3.1 a 3.5 · Iteraciones 41 a 45
  ecf: 'ecf-preparacion.js', preauditoria: 'preauditoria.js', 'causas-glosa': 'causas-glosa.js', cartera: 'cartera.js', 'brechas-tarifa': 'brechas-tarifa.js',
  // 3.6 a 4.0 · Iteraciones 46 a 50
  'auditoria-expedientes': 'auditoria-expedientes.js', insumos: 'insumos.js', 'mi-habilitacion': 'mi-habilitacion.js', direccion: 'direccion.js',
  'mis-horas': 'mis-horas.js', 'salud-sistema': 'salud-sistema.js',
  // 4.1 a 4.5 · Iteraciones 51 a 55
  propuestas: 'propuestas.js', verificacion: 'verificacion.js', 'informe-trimestral': 'informe-trimestral.js', 'casos-exito': 'referidos.js', recomendar: 'referidos.js',
  'onboarding-30': 'onboarding-30.js', 'mis-30-dias': 'onboarding-30.js',
  // 4.8 · P1 · planes y bloqueo por plan
  'mi-plan': 'mi-plan.js', planes: 'planes-admin.js',
  // 4.9 · P2, I56, I57, I58 e I59
  'mi-suscripcion': 'suscripcion.js', suscripciones: 'suscripciones-admin.js',
  'puesta-en-marcha': 'go-live.js', 'mi-puesta-en-marcha': 'go-live.js',
  'tarifas-versiones': 'tarifas-versiones.js', 'aplicar-pago': 'aplicar-pago.js', 'mi-bandeja': 'mi-bandeja.js',
  // 5.0.0 · I60 a I64
  'reconsideracion': 'reconsideracion.js', 'calidad-captura': 'calidad-captura.js', 'expediente': 'expediente.js',
  'mis-avisos': 'mis-avisos.js', 'cola-correos': 'cola-correos.js', 'rendimiento': 'rendimiento.js',
  // 5.5.0 · I65 · cierre de Fase A
  'novedades': 'novedades.js'
};
export const DEFAULT_ROUTE = 'inicio';

export function parseHash() {
  const h = decodeURIComponent(location.hash.replace(/^#\/?/, ''));
  const [route, ...rest] = h.split('/').filter(Boolean);
  return { route: route || DEFAULT_ROUTE, arg: rest.join('/') || null };
}

/** Resuelve qué módulo mostrar según la ruta y el rol */
export async function resolve(role) {
  const { route, arg } = parseHash();
  const def = findRoute(route);
  if (!def) return { kind: 'notfound', route };
  if (!canSee(route, role)) return { kind: 'forbidden', def };
  if (!def.ready) {
    const mod = await import('./modules/placeholder.js');
    return { kind: 'module', def, mod, arg };
  }
  const mod = await import(`./modules/${MODULES[route]}`);
  return { kind: 'module', def, mod: conMedicion(route, mod), arg };
}

/** 5.0.0 · I64: envuelve render() para medir cuánto tarda en pintarse la pantalla (solo la clave de la ruta, nunca parámetros).
 *  Medir nunca estorba: si falla la medición se ignora, y si render() falla no se registra el tiempo. */
function conMedicion(route, mod) {
  if (typeof mod.render !== 'function') return mod;
  return { ...mod, render: async (root, ctx) => {
    let fin = () => {};
    try { fin = medirRuta(route); } catch { /* medir nunca estorba */ }
    const r = await mod.render(root, ctx);
    try { fin(); } catch { /* medir nunca estorba */ }
    return r;
  } };
}
