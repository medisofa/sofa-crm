/** SOFA · Autoentrenamiento dinámico por rol.
 * Se alimenta del mismo catálogo de rutas/permisos que usa la aplicación.
 * Al agregar una ventana a NAV o una función a ACTIONS, aparece aquí automáticamente
 * para los roles que tengan acceso, sin mantener un segundo catálogo manual.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { NAV, ROLES, accionesDelRol } from '../utils/permissions.js';
import { APP_VERSION } from '../version.js';
import { supabase, rpc } from '../services/iter18.js';

const KEY_PREFIX = 'sofa.autoentrenamiento.v1';
const GUIDE = {
  'mi-dashboard': ['Identifica tus pendientes y alertas.', 'Abre el módulo que requiere acción.', 'Confirma que el estado se actualizó al terminar.'],
  agenda: ['Ubica la fecha y el profesional correcto.', 'Busca por cédula o NSS y confirma si SOFA encuentra al paciente universal.', 'Reutiliza solo datos administrativos; motivo, autorización y datos clínicos de la cita permanecen nuevos.', 'Confirma paciente, hora y estado antes de salir.'],
  pacientes: ['Busca al paciente por cédula o NSS antes de crear uno nuevo.', 'Si existe en el Registro Universal, usa sus datos administrativos sin ver consultas de otros clientes.', 'Justifica cualquier cambio de cédula, NSS, ARS o afiliación.', 'Guarda solo información necesaria y correcta.'],
  captura: ['Selecciona médico, ARS, paciente y servicio.', 'Busca por cédula o NSS y confirma el paciente universal; solo se cargan datos administrativos.', 'Revisa las sugerencias CIE-10 por servicio, SIMON y CUPS y confirma el diagnóstico documentado.', 'Valida autorización, fecha y tarifa contractual.', 'Revisa el resumen antes de crear la reclamación.'],
  'carga-google': ['Descarga la pestaña Capturas de Google Sheets como CSV.', 'Prevalida médico, ARS, servicio, autorización y tarifa.', 'Revisa las sugerencias CIE-10 generadas por servicio, SIMON y CUPS y confirma el diagnóstico documentado.', 'Usa Completar / editar para corregir datos faltantes; cada cambio queda en bitácora.', 'Importa solo las filas válidas y revisa los errores restantes.'],
  reclamaciones: ['Filtra por estado y prioridad.', 'Abre la reclamación y revisa expediente/trazabilidad.', 'Ejecuta solo la transición permitida para tu rol.'],
  retiros: ['Identifica las reclamaciones a retirar.', 'Registra recepción física y evidencia.', 'Confirma que quedaron listas para validación.'],
  preradicacion: ['Revisa expediente, tarifa y requisitos.', 'Corrige bloqueos antes de radicar.', 'No avances casos incompletos.'],
  radicaciones: ['Agrupa reclamaciones validadas.', 'Confirma ARS, período y evidencia.', 'Registra el envío y conserva trazabilidad.'],
  glosas: ['Clasifica causa y monto.', 'Revisa plazo y evidencia para responder.', 'Documenta la acción y próximo seguimiento.'],
  pagos: ['Confirma pago recibido de la ARS.', 'Concilia y distribuye contra reclamaciones.', 'Revisa diferencias antes de cerrar.'],
  usuarios: ['Revisa estado, rol y organización.', 'Valida el usuario antes de activarlo.', 'Usa mínimo privilegio y desactiva accesos obsoletos.'],
  permisos: ['Revisa qué módulos corresponden al rol.', 'No uses el menú como sustituto de RLS.', 'Valida el resultado con una cuenta de prueba.'],
  seguridad: ['Revisa MFA y estado de la cuenta.', 'No compartas credenciales.', 'Reporta cualquier acceso que no reconozcas.']
};

const ACTION_LABELS = {
  'users.toggle': 'Activar o desactivar usuarios',
  'users.invite': 'Invitar y asignar usuarios',
  'claims.capture': 'Capturar reclamaciones',
  'claims.move': 'Mover reclamaciones entre estados',
  'claims.audit': 'Auditar reclamaciones',
  'claims.recheck': 'Revalidar reclamaciones',
  'submissions.send': 'Radicar reclamaciones',
  'glosas.edit': 'Gestionar glosas',
  'payments.create': 'Registrar pagos ARS',
  'payments.distribute': 'Distribuir pagos',
  'capturers.assign': 'Asignar médicos a secretarias',
  'docs.upload': 'Cargar documentos',
  'dossier.upload': 'Cargar expediente digital',
  'security.admin': 'Administrar seguridad'
};

const prettyAction = (a) => ACTION_LABELS[a] || a.split('.').map((x) => x.replaceAll('_', ' ')).join(' · ');

function readState(key) {
  try { return JSON.parse(localStorage.getItem(key) || '{}'); } catch (_) { return {}; }
}
function saveState(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch (_) { /* no bloquea el entrenamiento */ }
}
function routeCatalog(role) {
  return NAV.flatMap((g) => g.items.map((i) => ({ ...i, group: g.group })))
    .filter((i) => i.route !== 'autoentrenamiento' && i.ready && !i.hidden && i.roles.includes(role));
}
function signature(routes, actions) {
  return [...routes.map((r) => `r:${r.route}:${r.label}`), ...actions.map((a) => `a:${a}`)].sort().join('|');
}
function genericGuide(label) {
  return [
    `Abre «${label}» y ubica los filtros, estados y acciones disponibles.`,
    'Practica con un caso de prueba siguiendo el flujo normal de tu rol.',
    'Antes de guardar, revisa datos, resultado y siguiente paso.'
  ];
}

export async function render(main, ctx) {
  const role = ctx.role;
  const roleName = ROLES[role]?.name || role;
  const routes = routeCatalog(role);
  const localActions = accionesDelRol(role);
  let governed = [];
  try { governed = await rpc('my_role_capabilities'); } catch (_) { /* fallback al contrato local mientras se despliega RBAC */ }
  const governedActions = (Array.isArray(governed) ? governed : []).filter((x) => x.can_view).map((x) => x.capability_code);
  const actions = [...new Set([...localActions, ...governedActions])].sort();
  const key = `${KEY_PREFIX}:${ctx.session.user.id}:${role}`;
  const state = readState(key);
  try {
    const { data, error } = await supabase.from('user_training_progress')
      .select('training_key,training_version,status,completed_at,metadata')
      .eq('user_id', ctx.session.user.id).eq('role_code', role);
    if (!error && Array.isArray(data)) {
      state.completed = state.completed || {};
      data.forEach((x) => { if (String(x.training_key).startsWith('route:')) state.completed[String(x.training_key).slice(6)] = x.status === 'completed'; });
    }
  } catch (_) { /* localStorage sigue siendo fallback */ }
  state.completed = state.completed || {};
  state.seenRoutes = Array.isArray(state.seenRoutes) ? state.seenRoutes : [];
  state.seenActions = Array.isArray(state.seenActions) ? state.seenActions : [];

  const newRoutes = routes.filter((r) => !state.seenRoutes.includes(r.route));
  const newActions = actions.filter((a) => !state.seenActions.includes(a));
  const currentSignature = signature(routes, actions);
  const changed = !!state.signature && state.signature !== currentSignature;

  const doneCount = routes.filter((r) => state.completed[r.route]).length;
  const pct = routes.length ? Math.round((doneCount / routes.length) * 100) : 100;

  paint(main, html`
    <div class="page-head">
      <div class="t"><h2>Mi autoentrenamiento</h2>
        <p>${roleName} · contenido generado desde los módulos y funciones que tu rol puede usar actualmente.</p>
      </div>
      <button class="btn" id="syncTraining">Actualizar contenido</button>
    </div>

    ${changed || newRoutes.length || newActions.length ? html`
      <div class="card" style="margin-bottom:14px;border-left:4px solid var(--warn)">
        <h2>Hay cambios en tu entrenamiento</h2>
        <p class="sub">SOFA detectó módulos o funciones nuevas para tu rol. Revísalas antes de continuar trabajando.</p>
        <div class="small"><b>${newRoutes.length}</b> ventana(s) nueva(s) · <b>${newActions.length}</b> función(es) nueva(s).</div>
      </div>` : ''}

    <div class="grid kpis">
      <div class="kpi"><div class="l">Rol</div><div class="v" style="font-size:1.05rem">${roleName}</div></div>
      <div class="kpi"><div class="l">Módulos para aprender</div><div class="v">${routes.length}</div></div>
      <div class="kpi"><div class="l">Funciones habilitadas</div><div class="v">${actions.length}</div></div>
      <div class="kpi"><div class="l">Progreso</div><div class="v">${pct}%</div><div class="h">${doneCount} de ${routes.length} módulos</div></div>
    </div>

    <div class="card" style="margin-top:14px">
      <h2>Ruta de aprendizaje de tu rol</h2>
      <p class="sub">La lista se actualiza con el catálogo de permisos de SOFA. Si se agrega una ventana nueva a tu rol, aparecerá aquí automáticamente.</p>
      <div style="height:10px;background:var(--surface-2);border-radius:6px;overflow:hidden;margin:8px 0 14px">
        <div style="height:100%;width:${pct}%;background:var(--ok)"></div>
      </div>
      <div class="list" id="trainingList">
        ${routes.map((r) => {
          const steps = GUIDE[r.route] || genericGuide(r.label);
          const done = !!state.completed[r.route];
          const fresh = newRoutes.some((x) => x.route === r.route);
          return html`<div class="li" style="align-items:flex-start">
            <span class="pill ${done ? 'ok' : fresh ? 'warn' : ''}">${done ? 'Completado' : fresh ? 'Nuevo' : 'Pendiente'}</span>
            <div class="b">
              <div class="t1">${r.label} <span class="small muted">· ${r.group}</span></div>
              <ol class="small" style="margin:6px 0 8px;padding-left:20px">${steps.map((s) => html`<li>${s}</li>`)}</ol>
              <div class="toolbar" style="margin:0">
                <a class="btn sm" href="#/${r.route}">Abrir módulo</a>
                <button class="btn sm ${done ? '' : 'primary'}" data-train="${r.route}">${done ? 'Marcar pendiente' : 'Marcar completado'}</button>
              </div>
            </div>
          </div>`;
        })}
      </div>
    </div>

    <div class="card" style="margin-top:14px">
      <h2>Funciones de tu rol</h2>
      <p class="sub">Estas funciones combinan el contrato local con la matriz gobernada <span class="mono">role_capabilities</span>. Una capacidad nueva aparece al asignarse al rol.</p>
      <div class="list">${actions.map((a) => html`<div class="li"><div class="b"><div class="t1">${prettyAction(a)}</div><div class="t2 mono">${a}</div></div>${newActions.includes(a) ? html`<span class="pill warn">Nueva</span>` : html`<span class="pill ok">Habilitada</span>`}</div>`)}</div>
    </div>

    <div class="card" style="margin-top:14px">
      <h2>Cómo se mantiene actualizado</h2>
      <p class="small">Versión actual de SOFA: <b>${APP_VERSION}</b>. El autoentrenamiento toma sus ventanas desde <span class="mono">NAV</span> y sus funciones desde <span class="mono">ACTIONS</span>. No se mantiene una lista paralela: los cambios de permisos del rol alimentan este módulo.</p>
    </div>`);

  const persistSeen = () => {
    state.seenRoutes = routes.map((r) => r.route);
    state.seenActions = [...actions];
    state.signature = currentSignature;
    state.lastSeenVersion = APP_VERSION;
    state.lastSeenAt = new Date().toISOString();
    saveState(key, state);
  };

  $('#syncTraining', main).addEventListener('click', () => {
    persistSeen();
    location.hash = '#/autoentrenamiento';
    location.reload();
  });

  $('#trainingList', main).addEventListener('click', async (e) => {
    const b = e.target.closest('[data-train]'); if (!b) return;
    const route = b.dataset.train;
    state.completed[route] = !state.completed[route];
    persistSeen();
    try {
      await supabase.from('user_training_progress').upsert({
        user_id: ctx.session.user.id,
        role_code: role,
        training_key: `route:${route}`,
        training_version: 1,
        status: state.completed[route] ? 'completed' : 'pending',
        last_seen_at: new Date().toISOString(),
        completed_at: state.completed[route] ? new Date().toISOString() : null,
        metadata: { app_version: APP_VERSION }
      }, { onConflict: 'user_id,role_code,training_key' });
    } catch (_) { /* la experiencia continúa con localStorage */ }
    location.hash = '#/autoentrenamiento';
    location.reload();
  });

  if (!state.signature) persistSeen();
}

export default render;
