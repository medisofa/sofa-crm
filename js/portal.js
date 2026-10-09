/** SOFA · 2.8 · Iteración 38 · Portal del paciente.
 *  Página pública que abre el enlace personal que el consultorio envía por WhatsApp (portal.html#t=CLAVE).
 *  La clave va después de «#»: el navegador no la envía al servidor de la página.
 *  2.9 · Iteración 39: el paciente confirma su cita o pide cambiarla (lo demás es solo lectura). */
import { sb, configProblem } from './supabase.js';

const root = document.getElementById('portal');
const KINDS = { receta: 'Receta', laboratorio: 'Laboratorio', imagen: 'Imágenes', referimiento: 'Referimiento' };
const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) if (v != null && v !== false) { if (k === 'class') e.className = v; else e.setAttribute(k, v); }
  for (const k of kids.flat()) if (k != null && k !== false && k !== '') e.append(k instanceof Node ? k : document.createTextNode(String(k)));
  return e;
};
const date = (d) => (d ? new Date(`${String(d).slice(0, 10)}T12:00:00`).toLocaleDateString('es-DO', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '');
const short = (d) => (d ? new Date(d).toLocaleDateString('es-DO', { day: 'numeric', month: 'short', year: 'numeric' }) : '');
const money = (n) => `RD$ ${Number(n || 0).toLocaleString('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fail = (msg) => root.replaceChildren(el('div', { class: 'pt-err', role: 'alert' }, el('strong', {}, 'No se pudo abrir su información'), el('p', {}, msg)));

async function main() {
  const token = new URLSearchParams(location.hash.slice(1)).get('t') || '';
  if (!token) return fail('El enlace está incompleto. Ábralo tal como le llegó por WhatsApp o pida uno nuevo a su consultorio.');
  const problem = configProblem(); if (problem) return fail('El portal no está configurado. Avise a su consultorio.');
  const { data, error } = await sb().rpc('portal_view', { p_token: token });
  if (error) return fail(error.message || 'Intente de nuevo en unos minutos.');
  const d = data; const c = d.clinic || {};
  const wa = String(c.whatsapp || c.phone || '').replace(/\D/g, '');
  const kids = [
    d.test_mode ? el('div', { class: 'pt-test', role: 'note' }, 'MODO PRUEBA · Datos ficticios para probar el portal.') : '',
    el('header', { class: 'pt-head' }, el('h1', {}, `Hola, ${d.patient.first_name}`), el('p', {}, c.name || 'Su consultorio'),
      d.patient.doc ? el('p', { class: 'pt-mut', style: 'color:inherit;opacity:.8' }, `Documento ${d.patient.doc}`) : ''),
    el('section', { class: 'pt-card' }, el('h2', {}, 'Próximas citas'),
      d.appointments.length ? d.appointments.map((a) => appointment(token, a)) : el('p', { class: 'pt-mut' }, 'No tiene citas programadas.')),
    d.orders ? el('section', { class: 'pt-card' }, el('h2', {}, 'Recetas y órdenes (últimos 6 meses)'),
      d.orders.length ? d.orders.map(order) : el('p', { class: 'pt-mut' }, 'No hay recetas ni órdenes recientes.')) : '',
    el('section', { class: 'pt-card' }, el('h2', {}, 'Saldo en el consultorio'),
      d.balance.items.length ? [el('div', { class: 'pt-big' }, money(d.balance.total)),
        ...d.balance.items.map((i) => el('div', { class: 'pt-item' }, `${short(i.date)} · ${i.service}`, el('span', { style: 'float:right' }, money(i.amount))))]
        : el('p', { class: 'pt-mut' }, 'No tiene saldo pendiente.')),
    el('section', { class: 'pt-card' }, el('h2', {}, '¿Dudas o cambiar una cita?'),
      el('p', {}, [c.name, c.address].filter(Boolean).join(' · ')),
      wa ? el('a', { class: 'pt-btn', href: `https://wa.me/${wa.length === 10 ? `1${wa}` : wa}`, target: '_blank', rel: 'noopener' }, 'Escribir al consultorio por WhatsApp') : '',
      c.phone ? el('p', { class: 'pt-mut' }, `Teléfono: ${c.phone}`) : ''),
    el('p', { class: 'pt-mut' }, `Este enlace es personal: no lo comparta. Vence el ${short(d.expires_at)}.`)];
  root.replaceChildren(...kids);
}

function appointment(token, a) {
  const box = el('div', { class: 'pt-item' });
  const status = el('div', { class: 'pt-mut' });
  const out = el('div', { 'aria-live': 'polite' });
  const acts = el('div', { class: 'pt-acts' });
  const paint = () => {
    status.textContent = (a.status === 'confirmada' ? 'Confirmada' : 'Programada') + (a.change_requested ? ' · Cambio pedido: el consultorio le escribirá' : '');
    acts.replaceChildren();
    if (!a.id) return;   // portal anterior a la 2.9
    if (a.status === 'programada') acts.append(button('Confirmar cita', 'pt-btn', () => send('confirmar')));
    if (!a.change_requested) acts.append(button('Pedir cambio', 'pt-btn pt-sec', askChange));
  };
  const button = (text, cls, fn) => { const b = el('button', { type: 'button', class: cls }, text); b.addEventListener('click', fn); return b; };
  async function send(action, noteText = null) {
    acts.querySelectorAll('button').forEach((b) => { b.disabled = true; });
    out.replaceChildren();
    const { data, error } = await sb().rpc('portal_appointment_action', { p_token: token, p_appointment: a.id, p_action: action, p_note: noteText });
    if (error) { out.replaceChildren(el('p', { class: 'pt-err-s', role: 'alert' }, error.message || 'No se pudo enviar. Intente de nuevo.')); paint(); return false; }
    if (action === 'confirmar') a.status = 'confirmada'; else a.change_requested = true;
    out.replaceChildren(el('p', { class: 'pt-ok', role: 'status' }, data?.message || 'Listo.'));
    paint(); return true;
  }
  function askChange() {
    const txt = el('textarea', { rows: '2', maxlength: '300', id: `pt-n-${a.id}`, placeholder: 'Ej.: mejor el jueves en la tarde' });
    const lab = el('label', { for: `pt-n-${a.id}` }, '¿Qué día u hora le conviene?');
    const ok = button('Enviar pedido', 'pt-btn', async () => { if (!txt.value.trim()) { out.replaceChildren(el('p', { class: 'pt-err-s', role: 'alert' }, 'Escriba qué día u hora le conviene.')); return; } if (await send('cambio_cita', txt.value.trim())) form.remove(); });
    const form = el('div', { class: 'pt-form' }, lab, txt, ok);
    acts.replaceChildren(form); txt.focus();
  }
  box.append(el('strong', {}, date(a.date)), el('div', {}, [a.time ? `${a.time} · ` : '', a.doctor || ''].join('')), status, acts, out);
  paint();
  return box;
}

function order(o) {
  const c = o.content || {};
  const body = o.kind === 'receta'
    ? el('ol', {}, (c.items || []).map((i) => el('li', {}, el('strong', {}, i.medicamento || ''), el('div', {}, [i.dosis, i.frecuencia, i.duracion].filter(Boolean).join(' · ')))))
    : o.kind === 'referimiento' ? el('p', {}, `Referido a: ${c.especialidad || ''}`)
      : el('ul', {}, (c.items || []).map((i) => el('li', {}, i.estudio || '')));
  return el('div', { class: 'pt-item' }, el('strong', {}, `${KINDS[o.kind] || o.kind} · ${short(o.at)}`), el('div', { class: 'pt-mut' }, o.doctor || ''), body,
    c.indicaciones ? el('p', {}, `Indicaciones: ${c.indicaciones}`) : '');
}

main().catch(() => fail('Revise su conexión a internet e intente de nuevo.'));
