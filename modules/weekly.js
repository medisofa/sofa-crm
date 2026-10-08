/** SOFA · 18-C · Cola de mensajes: recordatorios de cita al paciente y resumen semanal al médico.
 *  Sin proveedor externo: el mensaje se abre en WhatsApp (wa.me) con un clic y se marca como enviado. */
import { rpc, pendingMessages, recentSummaries, h, num, fmtDate, note, guarded } from '../services/iter18.js';

const KIND = { recordatorio_cita: 'Recordatorio de cita', seguimiento_cita: 'Seguimiento después de la cita', control_pendiente: 'Consulta de control', reprogramar_cita: 'Reprogramar cita (no asistió)', cobro_pendiente: 'Recordatorio de pago', resumen_semanal: 'Resumen semanal' };
// RD: números locales de 10 dígitos (809/829/849) -> prefijo 1. Si ya trae código de país, se respeta.
const waLink = (phone, body) => {
  let d = String(phone || '').replace(/\D/g, '');
  if (d.length === 10) d = '1' + d;
  return d.length >= 11 ? `https://wa.me/${d}?text=${encodeURIComponent(body)}` : null;
};

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
    out.replaceChildren(
      h('h3', {}, `Pendientes de enviar (${q.pend.length})`),
      q.pend.length ? h('div', { class: 'i18-list' }, ...q.pend.map(card)) : note('No hay mensajes pendientes. Use los botones de arriba o espere la generación automática (resumen: lunes; recordatorios: cada noche).'),
      h('h3', {}, 'Últimos resúmenes semanales'),
      q.sums.length ? h('div', { class: 'i18-list' }, ...q.sums.map((s) => h('details', { class: 'i18-card' },
        h('summary', {}, `${fmtDate(s.scheduled_for)} · ${s.subject || 'Resumen'} · ${s.status}`), h('pre', { class: 'i18-pre' }, s.body)))) : note('Aún no hay resúmenes.'));
  }

  function card(m) {
    const link = waLink(m.to_phone, m.body);
    const open = h('a', { class: 'i18-btn', href: link || '#', target: '_blank', rel: 'noopener noreferrer', 'aria-disabled': link ? null : 'true' }, 'Abrir en WhatsApp');
    open.addEventListener('click', async (ev) => {
      if (!link) { ev.preventDefault(); return msg.replaceChildren(note('Este mensaje no tiene un teléfono válido. Corrija el teléfono en la ficha y vuelva a generarlo.', 'error')); }
      try { await rpc('mark_message', { p_id: m.id, p_status: 'enviado' }); setTimeout(load, 600); } catch (e) { msg.replaceChildren(note(e.message, 'error')); }
    });
    const skip = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descartar');
    skip.addEventListener('click', () => act(skip, () => rpc('mark_message', { p_id: m.id, p_status: 'omitido' }), () => 'Mensaje omitido.'));
    return h('div', { class: 'i18-card' }, h('strong', {}, `${KIND[m.kind] || m.kind} · ${fmtDate(m.scheduled_for)}`),
      h('div', { class: 'i18-sub' }, m.to_phone || 'Sin teléfono'), h('pre', { class: 'i18-pre' }, m.body), h('div', { class: 'i18-bar' }, open, skip));
  }

  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Resumen semanal y recordatorios'),
    h('div', { class: 'i18-bar' }, h('label', {}, 'Citas de los próximos (días)', days), genRem, genSum), msg, out));
  await load();
}
export default render;
export const mount = render;
