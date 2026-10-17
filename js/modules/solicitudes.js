/** SOFA · 5.15.0 · I72 · «Solicitudes»: la bandeja del equipo para lo que entra por el enlace público.
 *  El prospecto llena el formulario desde Instagram, sube sus documentos, y aquí se trabaja:
 *  se asigna a alguien, se mueve de estado, se revisan los documentos y queda la bitácora de todo.
 *
 *  Esta pantalla no escribe nada directo: todo pasa por las funciones de la base, que vuelven a
 *  verificar el rol en cada llamada. Los documentos viven en un bucket privado y se abren con un
 *  enlace firmado que dura un minuto; no hay URL permanente que se pueda reenviar. */
import { rpc, h, note, table, kpi, guarded, fmtDate, supabase } from '../services/iter18.js';

const ESTADOS = {
  nueva: 'Nueva',
  por_revisar: 'Por revisar',
  en_contacto: 'En contacto',
  documentos_pendientes: 'Faltan documentos',
  lista: 'Lista para convertir',
  convertida: 'Convertida en cliente',
  descartada: 'Descartada'
};
// Los dos últimos cierran la solicitud: ya no se trabaja, se consulta.
const CERRADOS = ['convertida', 'descartada'];
const CANALES = { instagram: 'Instagram', whatsapp: 'WhatsApp', charla: 'Charla', referido: 'Referido', web: 'Web' };

const esMias = (role) => ['super_admin', 'admin', 'assistant', 'operations'].includes(role);
const canal = (c) => CANALES[c] || c || '—';
const estado = (e) => ESTADOS[e] || e;
const cuando = (iso) => {
  if (!iso) return '—';
  const d = new Date(iso);
  return isNaN(d) ? '—' : d.toLocaleString('es-DO', { dateStyle: 'medium', timeStyle: 'short' });
};
const pesos = (b) => (b == null ? '' : b < 1024 ? b + ' B' : b < 1048576 ? Math.round(b / 1024) + ' KB' : (b / 1048576).toFixed(1) + ' MB');

/** Hace cuántos días entró. Sirve para ver de un vistazo lo que se está enfriando. */
function diasDesde(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return null;
  return Math.floor((Date.now() - d.getTime()) / 86400000);
}
function edad(iso, cerrada) {
  const n = diasDesde(iso);
  if (n == null) return h('span', {}, '—');
  const texto = n === 0 ? 'hoy' : n === 1 ? 'ayer' : `hace ${n} días`;
  // Una solicitud abierta de más de 3 días es una persona esperando respuesta.
  const tarde = !cerrada && n >= 3;
  return h('span', { class: tarde ? 'sol-tarde' : '' }, texto);
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (!esMias(ctx.role)) {
    root.append(h('div', { class: 'i18-wrap' }, note('Esta bandeja es del equipo de SOFA. Si cree que debería verla, pida al Administrador que revise su rol.', 'error')));
    return;
  }
  const puedeTrabajar = ['super_admin', 'admin', 'assistant', 'operations'].includes(ctx.role);

  const kpis = h('div', { class: 'i18-kpis' });
  const barra = h('div', { class: 'i18-bar' });
  const panel = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Solicitudes'),
    h('p', { class: 'i18-sub' }, 'Lo que llega por el enlace público de Instagram y WhatsApp. Cada solicitud trae lo que la persona pidió, las ARS que le interesan y los documentos que ya subió.'),
    kpis, barra, panel));

  let filtro = '';      // '' = todas
  let abierta = null;   // id de la solicitud abierta en la ficha

  /* ── Contadores y filtros ───────────────────────────────────────────────── */
  async function cabecera() {
    let c;
    try { c = await rpc('service_requests_counts'); }
    catch (e) { kpis.replaceChildren(note(e.message, 'error')); return; }
    const pendientes = ['nueva', 'por_revisar', 'en_contacto', 'documentos_pendientes']
      .reduce((n, k) => n + Number(c[k] || 0), 0);
    kpis.replaceChildren(
      kpi('Por atender', String(pendientes), 'Todo lo que aún no está cerrado'),
      kpi('Sin asignar', String(c.sin_asignar || 0), 'Nadie las está trabajando'),
      kpi('Listas para convertir', String(c.lista || 0), 'Ya tienen todo lo que hace falta'),
      kpi('Convertidas', String(c.convertida || 0), 'Terminaron siendo clientes'));

    const chip = (clave, texto, n) => {
      const b = h('button', {
        class: 'i18-btn' + (filtro === clave ? '' : ' i18-sec'),
        type: 'button', 'aria-pressed': filtro === clave ? 'true' : 'false'
      }, n == null ? texto : `${texto} (${n})`);
      b.addEventListener('click', () => { filtro = clave; abierta = null; pintar(); });
      return b;
    };
    barra.replaceChildren(
      chip('', 'Todas', c.total || 0),
      ...Object.entries(ESTADOS).map(([k, label]) => chip(k, label, Number(c[k] || 0))));
  }

  /* ── La lista ───────────────────────────────────────────────────────────── */
  async function lista() {
    const box = h('div', {});
    panel.replaceChildren(box);
    const filas = await guarded(box, () => rpc('service_requests_list', { p_status: filtro || null }));
    if (filas == null) return;
    if (!filas.length) {
      box.replaceChildren(note(filtro
        ? `No hay ninguna solicitud en «${estado(filtro)}».`
        : 'Todavía no ha entrado ninguna solicitud. Cuando alguien use el enlace de la bio, aparecerá aquí.'));
      return;
    }
    box.replaceChildren(table([
      { key: 'folio', label: 'Solicitud', get: (r) => {
        const a = h('button', { class: 'i18-link', type: 'button' }, r.folio);
        a.addEventListener('click', () => { abierta = r.id; pintar(); });
        return h('div', {}, a, h('div', { class: 'i18-sub' }, edad(r.creada, CERRADOS.includes(r.estado))));
      } },
      { key: 'quien', label: 'Quién', get: (r) => h('div', {},
        h('b', {}, r.nombre || '—'),
        h('div', { class: 'i18-sub' }, [r.especialidad, r.empresa].filter(Boolean).join(' · ') || '—')) },
      { key: 'contacto', label: 'Contacto', get: (r) => h('div', {},
        r.telefono || '—', h('div', { class: 'i18-sub' }, r.correo || '')) },
      { key: 'pide', label: 'Qué pide', get: (r) => r.servicios || '—' },
      { key: 'canal', label: 'Canal', get: (r) => canal(r.canal) },
      { key: 'docs', label: 'Docs', right: true, get: (r) => String(r.documentos ?? 0) },
      { key: 'estado', label: 'Estado', get: (r) => h('span', { class: 'sol-pill sol-' + (r.estado === 'lista' ? 'lista_' : r.estado) }, estado(r.estado)) },
      { key: 'de', label: 'Asignada a', get: (r) => r.asignado_a || h('span', { class: 'sol-tarde' }, 'Sin asignar') }
    ], filas));
  }

  /* ── La ficha ───────────────────────────────────────────────────────────── */
  async function ficha(id) {
    const box = h('div', {});
    panel.replaceChildren(box);
    const d = await guarded(box, () => rpc('service_request_get', { p_id: id }));
    if (d == null) return;
    const cerrada = CERRADOS.includes(d.estado);
    // El equipo se pide una vez: sirve para el desplegable y para poner el nombre de quien la lleva.
    const gente = await rpc('service_request_staff').catch(() => []);
    const nombreDe = (uid) => (gente.find((p) => p.id === uid) || {}).nombre || (uid ? 'Alguien del equipo' : null);

    const volver = h('button', { class: 'i18-btn i18-sec', type: 'button' }, '← Volver a la lista');
    volver.addEventListener('click', () => { abierta = null; pintar(); });

    const aviso = h('div', { 'aria-live': 'polite' });
    const decir = (texto, tipo = 'ok') => aviso.replaceChildren(note(texto, tipo));
    const refrescar = async () => { await cabecera(); await ficha(id); };

    const dato = (etiqueta, valor) => h('div', { class: 'sol-dato' },
      h('div', { class: 'i18-sub' }, etiqueta), h('div', {}, valor || '—'));

    box.replaceChildren(
      h('div', { class: 'i18-bar' }, volver),
      h('h3', {}, `${d.folio} · ${d.nombre || 'Sin nombre'}`),
      h('p', { class: 'i18-sub' },
        `${estado(d.estado)} · entró ${cuando(d.creada)} por ${canal(d.canal)}. El enlace del prospecto sirve hasta el ${fmtDate(d.expira)}.`),
      aviso,

      h('div', { class: 'sol-datos' },
        dato('Teléfono', d.telefono),
        dato('WhatsApp', d.whatsapp),
        dato('Correo', d.correo),
        dato('Qué es', d.tipo === 'medico' ? 'Médico o profesional de la salud' : d.tipo === 'centro' ? 'Centro o clínica' : d.tipo),
        dato('Consultorio o centro', d.empresa),
        dato('Especialidad', d.especialidad),
        dato('Ciudad', d.ciudad),
        dato('Asignada a', nombreDe(d.asignado_a) || 'Sin asignar')),

      h('h4', {}, 'Qué pidió'),
      h('ul', { class: 'sol-lista' }, (d.servicios || []).length
        ? d.servicios.map((s) => h('li', {}, s))
        : h('li', { class: 'i18-sub' }, 'No marcó nada.')),

      h('h4', {}, 'Con cuáles ARS quiere trabajar'),
      h('p', {}, (d.ars || []).length ? d.ars.join(' · ') : h('span', { class: 'i18-sub' }, 'No marcó ninguna. Vale preguntarle.')),

      d.mensaje ? h('div', {}, h('h4', {}, 'Lo que nos escribió'), h('p', { class: 'sol-cita' }, d.mensaje)) : null,

      documentos(d, refrescar, decir),
      acciones(d, cerrada, gente, refrescar, decir),
      consentimiento(d),
      bitacora(d));
  }

  /* ── Documentos ─────────────────────────────────────────────────────────── */
  function documentos(d, refrescar, decir) {
    const docs = d.documentos || [];
    const caja = h('div', {}, h('h4', {}, `Documentos (${docs.length})`));
    if (!docs.length) {
      caja.append(note('Todavía no ha subido nada. El enlace privado que recibió le sirve para subirlos cuando pueda.'));
      return caja;
    }
    caja.append(table([
      { key: 'nombre', label: 'Documento', get: (x) => h('div', {}, x.nombre,
        h('div', { class: 'i18-sub' }, [x.tipo, pesos(x.bytes)].filter(Boolean).join(' · '))) },
      { key: 'subido', label: 'Cuándo lo subió', get: (x) => cuando(x.subido) },
      { key: 'ver', label: '', get: (x) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver');
        b.addEventListener('click', async () => {
          b.disabled = true;
          try {
            // El bucket es privado: se pide un enlace firmado que dura un minuto.
            const { data, error } = await supabase.storage.from('intake').createSignedUrl(x.ruta, 60);
            if (error) throw error;
            window.open(data.signedUrl, '_blank', 'noopener');
          } catch (e) {
            decir('No se pudo abrir «' + x.nombre + '». Vuelva a intentar; si sigue igual, avise a soporte. (' + (e.message || e) + ')', 'error');
          } finally { b.disabled = false; }
        });
        return b;
      } },
      { key: 'rev', label: '', get: (x) => {
        if (!puedeTrabajar) return '';
        const ok = h('button', { class: 'i18-btn i18-sec', type: 'button', title: 'Marcar el documento como aceptado' }, 'Aceptar');
        const no = h('button', { class: 'i18-btn i18-sec', type: 'button', title: 'Pedir que lo suba de nuevo' }, 'Rechazar');
        ok.addEventListener('click', async () => {
          ok.disabled = no.disabled = true;
          try { await rpc('service_request_doc_review', { p_doc: x.id, p_ok: true, p_reason: null }); await refrescar(); }
          catch (e) { decir(e.message, 'error'); ok.disabled = no.disabled = false; }
        });
        no.addEventListener('click', async () => {
          const motivo = prompt('¿Qué le falta a «' + x.nombre + '»? Se lo diremos al prospecto.');
          if (motivo == null || !motivo.trim()) return;
          ok.disabled = no.disabled = true;
          try { await rpc('service_request_doc_review', { p_doc: x.id, p_ok: false, p_reason: motivo.trim() }); await refrescar(); }
          catch (e) { decir(e.message, 'error'); ok.disabled = no.disabled = false; }
        });
        return h('span', { class: 'sol-acc' }, ok, no);
      } }
    ], docs));
    return caja;
  }

  /* ── Acciones: asignar y mover de estado ────────────────────────────────── */
  function acciones(d, cerrada, gente, refrescar, decir) {
    if (!puedeTrabajar) return null;
    const caja = h('div', {}, h('h4', {}, 'Trabajar esta solicitud'));
    if (cerrada) {
      caja.append(note(d.estado === 'convertida'
        ? 'Esta solicitud ya se convirtió en cliente. Queda aquí como historia.'
        : 'Esta solicitud está descartada. Queda aquí como historia.'));
      return caja;
    }

    const quien = h('select', { 'aria-label': 'A quién se le asigna' },
      h('option', { value: '' }, gente.length ? 'Elija a quién se la asigna…' : 'No se pudo cargar el equipo'),
      ...gente.map((p) => h('option', { value: p.id, selected: p.id === d.asignado_a }, `${p.nombre} · ${p.rol}`)));

    const fecha = h('input', { type: 'date', 'aria-label': 'Para cuándo' });
    const asignar = h('button', { class: 'i18-btn', type: 'button' }, 'Asignar');
    asignar.addEventListener('click', async () => {
      if (!quien.value) { decir('Elija primero a quién se la asigna.', 'error'); return; }
      asignar.disabled = true;
      try { await rpc('service_request_assign', { p_id: d.id, p_user: quien.value, p_due: fecha.value || null }); await refrescar(); }
      catch (e) { decir(e.message, 'error'); asignar.disabled = false; }
    });

    const nuevo = h('select', { 'aria-label': 'Mover a qué estado' },
      h('option', { value: '' }, 'Mover a…'),
      ...Object.entries(ESTADOS).filter(([k]) => k !== d.estado).map(([k, v]) => h('option', { value: k }, v)));
    const mover = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Cambiar el estado');
    mover.addEventListener('click', async () => {
      if (!nuevo.value) { decir('Elija primero a qué estado la mueve.', 'error'); return; }
      let motivo = null;
      if (nuevo.value === 'descartada') {
        motivo = prompt('¿Por qué se descarta? Queda en la bitácora.');
        if (motivo == null || !motivo.trim()) return;
        motivo = motivo.trim();
      }
      mover.disabled = true;
      try { await rpc('service_request_set_status', { p_id: d.id, p_status: nuevo.value, p_reason: motivo }); await refrescar(); }
      catch (e) { decir(e.message, 'error'); mover.disabled = false; }
    });

    caja.append(
      h('div', { class: 'i18-bar' }, quien, fecha, asignar),
      h('p', { class: 'i18-sub' }, 'La fecha es opcional: si la pone, a esa persona le queda la tarea con ese vencimiento.'),
      h('div', { class: 'i18-bar' }, nuevo, mover));
    return caja;
  }

  /* ── Consentimiento: lo que la persona aceptó, y cuándo ─────────────────── */
  function consentimiento(d) {
    const c = d.consentimiento || {};
    if (!c.texto) return null;
    return h('div', {},
      h('h4', {}, 'Lo que autorizó'),
      h('p', { class: 'sol-cita' }, c.texto),
      h('p', { class: 'i18-sub' }, 'Aceptado el ' + cuando(c.fecha).replace(/\.$/, '') + '.'));
  }

  /* ── Bitácora ───────────────────────────────────────────────────────────── */
  function bitacora(d) {
    const ev = d.bitacora || [];
    const texto = (e) => {
      const q = e.publico ? 'El prospecto' : (e.quien || 'El sistema');
      const det = e.detalle || {};
      switch (e.evento) {
        case 'creada': return `${q} envió la solicitud.`;
        case 'documento': return `${q} subió «${det.nombre || 'un documento'}».`;
        case 'documento_aceptado': return `${q} aceptó «${det.nombre || 'un documento'}».`;
        case 'documento_rechazado': return `${q} rechazó «${det.nombre || 'un documento'}»: ${det.motivo || 'sin motivo'}.`;
        case 'asignada': return `${q} la asignó.`;
        case 'estado': return `${q} la movió a «${estado(det.a)}»${det.motivo ? ': ' + det.motivo : ''}.`;
        case 'aviso': return 'Se avisó al equipo.';
        case 'aviso_fallido': return 'No se pudo avisar al equipo (la solicitud sí quedó guardada).';
        default: return `${q} · ${e.evento}`;
      }
    };
    return h('div', {},
      h('h4', {}, 'Bitácora'),
      h('ul', { class: 'sol-bit' }, ev.length
        ? ev.map((e) => h('li', {}, h('span', { class: 'i18-sub' }, cuando(e.cuando)), ' ', texto(e)))
        : h('li', { class: 'i18-sub' }, 'Sin movimientos.')));
  }

  async function pintar() {
    await cabecera();
    if (abierta) await ficha(abierta); else await lista();
  }
  await pintar();
}
