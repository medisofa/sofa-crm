/** SOFA · 18-C · Cola de mensajes: recordatorios de cita al paciente y resumen semanal al médico.
 *  Sin proveedor externo: el mensaje se abre en WhatsApp (wa.me) con un clic y se marca como enviado.
 *  2.9 · Iteración 39: los mensajes al paciente pueden llevar su enlace al portal ({enlace}). El enlace se crea
 *  en el momento de enviar (nunca se guarda en el mensaje) y la pantalla muestra los pedidos que llegan desde el portal. */
import { rpc, pendingMessages, recentSummaries, h, num, fmtDate, note, guarded } from '../services/iter18.js';

const KIND = { recordatorio_cita: 'Recordatorio de cita', seguimiento_cita: 'Seguimiento después de la cita', control_pendiente: 'Consulta de control', reprogramar_cita: 'Reprogramar cita (no asistió)', cobro_pendiente: 'Recordatorio de pago', resumen_semanal: 'Resumen semanal' };
// RD: números locales de 10 dígitos (809/829/849) -> prefijo 1. Si ya trae código de país, se respeta.
const waLink = (phone, body) => {
  let d = String(phone || '').replace(/\D/g, '');
  if (d.length === 10) d = '1' + d;
  return d.length >= 11 ? `https://wa.me/${d}${body == null ? '' : `?text=${encodeURIComponent(body)}`}` : null;
};
const LINK = '{enlace}';
const hasLink = (m) => String(m.body || '').includes(LINK);
/** Texto que se ve en pantalla: la marca {enlace} se muestra como lo que es. */
const shown = (body) => String(body || '').split(LINK).join('[enlace personal: se crea al enviar]');
/** Si no se pudo crear el enlace, el mensaje sale sin la frase del portal. */
const withoutLink = (body) => String(body || '').replace(/\s*Vea[^.:]*:\s*\{enlace\}\.?/g, '').split(LINK).join('').trim();
export const portalUrl = (token) => `${new URL('portal.html', location.href.split('#')[0]).href}#t=${token}`;
const KIND_REQ = { confirmar: 'Confirmó la cita', cambio_cita: 'Pide cambiar la cita' };

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const msg = h('div');
  const days = h('input', { type: 'number', min: '1', max: '7', value: '1', id: 'i18-wk-days', style: 'width:5rem' });

  async function act(btn, fn, okText) {
    btn.disabled = true; msg.replaceChildren();
    try { const r = await fn(); msg.replaceChildren(note(okText(r))); await load(); }
    catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    finally { btn.disabled = false; }
  }
  const genRem = h('button', { class: 'i18-btn', type: 'button' }, 'Generar recordatorios');
  const genSum = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Generar resúmenes de esta semana');
  genRem.addEventListener('click', () => act(genRem, () => rpc('generate_appointment_reminders', { p_days: Number(days.value) || 1, p_provider: null }), (n) => `${num(n)} recordatorio(s) nuevo(s) en la cola.`));
  genSum.addEventListener('click', () => act(genSum, () => rpc('generate_weekly_summaries', {}), (n) => `${num(n)} resumen(es) nuevo(s). Cada médico también recibe una notificación en SOFA.`));

  async function load() {
    const q = await guarded(out, async () => ({ pend: await pendingMessages(), sums: await recentSummaries() }));
    if (!q) return;
    loadRequests();
    out.replaceChildren(
      h('h3', {}, `Pendientes de enviar (${q.pend.length})`),
      requestsBox,
      q.pend.length ? h('div', { class: 'i18-list' }, ...q.pend.map(card)) : note('No hay mensajes pendientes. Use los botones de arriba o espere la generación automática (resumen: lunes; recordatorios: cada noche).'),
      h('h3', {}, 'Últimos resúmenes semanales'),
      q.sums.length ? h('div', { class: 'i18-list' }, ...q.sums.map((s) => h('details', { class: 'i18-card' },
        h('summary', {}, `${fmtDate(s.scheduled_for)} · ${s.subject || 'Resumen'} · ${s.status}`), h('pre', { class: 'i18-pre' }, s.body)))) : note('Aún no hay resúmenes.'));
  }

  // 2.9 · Pedidos que el paciente hace desde su portal (confirmar o cambiar la cita)
  const requestsBox = h('div', { 'aria-live': 'polite' });
  async function loadRequests() {
    let list = [];
    try { list = await rpc('portal_requests_list', { p_org: null, p_status: 'pendiente' }); } catch { requestsBox.replaceChildren(); return; }   // antes de la 136 no existe
    if (!list.length) { requestsBox.replaceChildren(); return; }
    requestsBox.replaceChildren(h('h3', {}, `Pedidos desde el portal del paciente (${list.length})`),
      h('div', { class: 'i18-list' }, ...list.map(requestCard)));
  }
  function requestCard(r) {
    const a = r.appointment || {};
    const wa = waLink(r.phone, null);
    const done = h('button', { class: 'i18-btn', type: 'button' }, 'Marcar atendido');
    const txt = h('input', { type: 'text', maxlength: '300', placeholder: 'Qué se hizo (opcional)', 'aria-label': 'Qué se hizo', style: 'min-width:220px' });
    done.addEventListener('click', () => act(done, () => rpc('portal_request_done', { p_id: r.id, p_note: txt.value.trim() || null }), () => 'Pedido marcado como atendido.'));
    return h('div', { class: 'i18-card' + (r.kind === 'cambio_cita' ? ' pr-cambio' : '') },
      h('strong', {}, `${KIND_REQ[r.kind] || r.kind} · ${r.patient}`),
      h('div', { class: 'i18-sub' }, `Cita: ${fmtDate(a.date)} ${a.time || ''} · ${a.doctor || ''} · pedido el ${fmtDate(r.at)}`),
      r.note ? h('p', {}, `«${r.note}»`) : null,
      h('div', { class: 'i18-bar' }, wa ? h('a', { class: 'i18-btn i18-sec', href: wa, target: '_blank', rel: 'noopener noreferrer' }, 'Escribir al paciente') : h('span', { class: 'i18-sub' }, 'Sin teléfono'), txt, done));
  }

  function card(m) {
    const portal = hasLink(m);
    const link = waLink(m.to_phone, portal ? withoutLink(m.body) : m.body);
    const open = h('a', { class: 'i18-btn', href: link || '#', target: '_blank', rel: 'noopener noreferrer', 'aria-disabled': link ? null : 'true' }, 'Abrir en WhatsApp');
    open.addEventListener('click', async (ev) => {
      if (!link) { ev.preventDefault(); return msg.replaceChildren(note('Este mensaje no tiene un teléfono válido. Corrija el teléfono en la ficha y vuelva a generarlo.', 'error')); }
      if (portal) {
        // La ventana se abre ya (si no, el navegador la bloquea) y luego se le pone la dirección con el enlace recién creado.
        ev.preventDefault();
        const w = window.open('', '_blank');
        let body = withoutLink(m.body);
        try { const r = await rpc('message_portal_link', { p_message: m.id }); body = String(m.body).split(LINK).join(portalUrl(r.token)); }
        catch (e) { msg.replaceChildren(note(`El mensaje sale sin enlace al portal: ${e.message}`, 'error')); }
        const url = waLink(m.to_phone, body);
        if (w) { w.opener = null; w.location.href = url; } else { location.href = url; }
      }
      try { await rpc('mark_message', { p_id: m.id, p_status: 'enviado' }); setTimeout(load, 600); } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    });
    const skip = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descartar');
    skip.addEventListener('click', () => act(skip, () => rpc('mark_message', { p_id: m.id, p_status: 'omitido' }), () => 'Mensaje omitido.'));
    return h('div', { class: 'i18-card' }, h('strong', {}, `${KIND[m.kind] || m.kind} · ${fmtDate(m.scheduled_for)}`),
      h('div', { class: 'i18-sub' }, m.to_phone || 'Sin teléfono'), h('pre', { class: 'i18-pre' }, shown(m.body)),
      portal ? h('div', { class: 'i18-sub' }, 'Lleva el enlace personal del paciente a su portal: se crea al tocar «Abrir en WhatsApp» y anula el anterior.') : null, h('div', { class: 'i18-bar' }, open, skip));
  }

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Resumen semanal y recordatorios'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Citas de los próximos (días)', days), genRem, genSum), msg, out));
  await load();
}
export default render;
export const mount = render;
