/** Private personal reminders. No browser persistence or automatic payment operations. */
import { rpc, h, note, money, fmtDate } from '../services/iter18.js';

export async function mountPhysicianReminders(root, ctx = {}) {
  if (ctx.role !== 'client' || !ctx.membership?.organization_id) return;
  const org = ctx.membership.organization_id;
  let items = [], editing = null, busy = false;
  const status = h('div', { role: 'status', 'aria-live': 'polite' });
  const list = h('div', { class: 'grid two' });
  const refresh = h('button', { type: 'button', class: 'btn' }, 'Actualizar recordatorios');
  const filter = h('select', { id: 'pr-filter', 'aria-label': 'Mostrar recordatorios' },
    h('option', { value: 'pending' }, 'Pendientes'), h('option', { value: 'all' }, 'Todos'), h('option', { value: 'done' }, 'Completados'));
  const title = h('input', { id: 'pr-title', required: true, maxlength: '160', autocomplete: 'off' });
  const kind = h('select', { id: 'pr-kind' }, h('option', { value: 'note' }, 'Nota o recordatorio'), h('option', { value: 'payment' }, 'Cuenta por pagar'));
  const body = h('textarea', { id: 'pr-body', rows: '3', maxlength: '2000' });
  const due = h('input', { id: 'pr-due', type: 'date' });
  const amount = h('input', { id: 'pr-amount', type: 'number', min: '0.01', max: '999999999999.99', step: '0.01' });
  const amountLabel = h('label', { for: 'pr-amount' }, 'Monto (RD$)', amount);
  const submit = h('button', { type: 'submit', class: 'btn primary' }, 'Guardar recordatorio');
  const cancel = h('button', { type: 'button', class: 'btn' }, 'Nueva nota');
  const form = h('form', { class: 'i18-form' },
    h('label', { for: 'pr-kind' }, 'Tipo'), kind, h('label', { for: 'pr-title' }, 'Título', title),
    h('label', { for: 'pr-body' }, 'Detalle personal', body), h('label', { for: 'pr-due' }, 'Fecha de recordatorio o vencimiento', due),
    amountLabel, h('div', { class: 'i18-actions' }, submit, cancel));
  const panel = h('section', { class: 'card', style: 'margin-top:16px' }, h('h3', {}, 'Mis notas y cuentas por pagar'),
    h('p', {}, 'Recordatorios personales de este consultorio, visibles únicamente para su usuario. Para información de pacientes, utilice la Historia clínica.'),
    status, form, h('div', { class: 'i18-bar' }, filter, refresh), h('p', { class: 'small muted' }, 'Se muestran hasta 200 recordatorios, con los pendientes primero.'), list);
  root.append(panel);
  function kindChanged() { const payment = kind.value === 'payment'; amountLabel.hidden = !payment; amount.disabled = !payment; amount.required = payment; due.required = payment; }
  function reset() { editing = { id: crypto.randomUUID(), version: 0, completed: false }; form.reset(); kindChanged(); submit.textContent = 'Guardar recordatorio'; }
  function lock(value) { busy = value; panel.querySelectorAll('button,input,select,textarea').forEach(el => { el.disabled = value; }); if (!value) kindChanged(); }
  function draw() {
    const shown = items.filter(i => filter.value === 'all' || (filter.value === 'done' ? i.completed : !i.completed));
    list.replaceChildren(...(shown.length ? shown.map(item => {
      const edit = h('button', { type: 'button', class: 'btn' }, 'Editar');
      edit.addEventListener('click', () => {
        editing = { ...item }; kind.value = item.kind; title.value = item.title; body.value = item.body;
        due.value = item.due_date || ''; amount.value = item.amount ?? ''; kindChanged(); submit.textContent = 'Guardar cambios'; title.focus();
      });
      const toggle = h('button', { type: 'button', class: 'btn' }, item.completed ? 'Reabrir' : item.kind === 'payment' ? 'Marcar como pagada' : 'Completar');
      toggle.addEventListener('click', async () => {
        if (busy) return;
        await save({ ...item, completed: !item.completed }, false);
      });
      return h('article', { class: 'card' }, h('h4', {}, item.title),
        h('p', {}, `${item.kind === 'payment' ? 'Cuenta por pagar' : 'Nota'} · ${item.completed ? 'Completado' : 'Pendiente'}`),
        item.body ? h('p', { style: 'white-space:pre-wrap;overflow-wrap:anywhere' }, item.body) : '',
        item.due_date ? h('p', {}, `Fecha: ${fmtDate(item.due_date)}`) : '',
        item.kind === 'payment' ? h('p', {}, money(item.amount)) : '', h('div', { class: 'i18-actions' }, edit, toggle));
    }) : [note('No hay recordatorios en esta selección.', 'info')]));
  }
  async function load() {
    const result = await rpc('physician_reminders_v1', { p_org: org, p_action: 'list', p_data: {} });
    if (!result.enabled) { panel.replaceChildren(h('h3', {}, 'Mis notas y cuentas por pagar'), note('Esta función todavía no está activada.', 'info')); return false; }
    items = result.items || []; draw(); return true;
  }
  async function save(data, clearForm) {
    lock(true); status.replaceChildren();
    try {
      const result = await rpc('physician_reminders_v1', { p_org: org, p_action: 'save', p_data: data });
      if (!result.enabled || !result.item) throw Error('La función no está activada. No se guardó el recordatorio.');
      items = [result.item, ...items.filter(i => i.id !== result.item.id)];
      if (clearForm || editing.id === result.item.id) reset();
      draw(); status.replaceChildren(note('Recordatorio guardado.', 'ok'));
    } catch (error) { status.replaceChildren(note(error.message, 'error')); }
    finally { lock(false); }
  }
  form.addEventListener('submit', async event => {
    event.preventDefault(); if (busy || !form.reportValidity()) return;
    await save({ ...editing, kind: kind.value, title: title.value.trim(), body: body.value.trim(), due_date: due.value || null, amount: kind.value === 'payment' ? amount.value : null }, true);
  });
  cancel.addEventListener('click', reset); kind.addEventListener('change', kindChanged); filter.addEventListener('change', draw);
  refresh.addEventListener('click', async () => {
    if (busy) return; lock(true); status.replaceChildren();
    try { if (await load()) reset(); } catch (error) { status.replaceChildren(note(error.message, 'error')); } finally { lock(false); }
  });
  reset(); lock(true); status.textContent = 'Cargando recordatorios…';
  try { await load(); status.replaceChildren(); }
  catch (error) { status.replaceChildren(note(error.message, 'error')); }
  finally { lock(false); }
}
