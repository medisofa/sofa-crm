/** SOFA · 4.9.0 · I59 · «Mi bandeja»: la bandeja única de trabajo del facturador.
 *  Una sola cola, en orden, con lo que hay que hacer hoy: capturas incompletas, lotes por radicar, glosas por responder y cobros por escalar.
 *  Facturación ve solo lo suyo; Super Admin, Administrador y Operaciones ven todo lo que su acceso permite y administran asignaciones y ausencias.
 *  La cola se calcula en la base de datos desde las tablas existentes (no guarda copias) y el servidor vuelve a verificar el rol en cada función. */
import { rpc, h, money, fmtDate, note, kpi, table, guarded, realClientOptions, clientName } from '../services/iter18.js';
import { canOpen } from '../utils/permissions.js';

const TYPES = { captura_incompleta: 'Capturas incompletas', lote_por_radicar: 'Lotes por radicar', glosa_responder: 'Glosas por responder', cobro_escalar: 'Cobros por escalar' };
const PRIO = { critica: 'Crítica', alta: 'Alta', normal: 'Normal' };
const REASON = { sin_asignacion: 'Sin asignar: asigne el cliente a una persona', ausente_sin_suplente: 'Responsable ausente y sin suplente', persona_no_disponible: 'La persona asignada ya no está disponible' };
const ABS = { en_curso: 'En curso', programada: 'Programada', terminada: 'Terminada' };
const localIso = (add = 0) => { const d = new Date(); d.setDate(d.getDate() + add); return d.toLocaleDateString('en-CA'); };
const dueText = (n) => (n > 0 ? `Vencida hace ${n} día${n === 1 ? '' : 's'}` : n === 0 ? 'Vence hoy' : `Vence en ${-n} día${n === -1 ? '' : 's'}`);

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const sup = ['super_admin', 'admin', 'operations'].includes(ctx.role);
  const canClose = ['super_admin', 'admin'].includes(ctx.role);
  const tabsBar = h('div', { class: 'i18-tabs mb-tabs', role: 'tablist', 'aria-label': 'Secciones de la bandeja' });
  const panel = h('div', { class: 'mb-panel', role: 'tabpanel', 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Mi bandeja'),
    h('p', { class: 'i18-sub' }, sup ? 'Todo el trabajo del equipo en una sola cola: lo vencido primero, luego lo que vence pronto y lo de más monto. Asigne clientes y registre ausencias para que nada quede sin dueño.'
      : 'Lo que le toca hoy, en orden: lo vencido primero, luego lo que vence pronto y lo de más monto.'), tabsBar, panel));
  const SECTIONS = sup
    ? [['bandeja', 'Bandeja'], ['carga', 'Carga por persona'], ['asignaciones', 'Asignaciones'], ['ausencias', 'Ausencias'], ['vencidas', 'Vencidas por día'], ['reglas', 'Reglas']]
    : [['bandeja', 'Mi bandeja'], ['vencidas', 'Mi indicador']];
  const VIEW = { bandeja, carga, asignaciones, ausencias, vencidas, reglas };
  let current = 'bandeja'; let type = null;

  function tabs() {
    tabsBar.replaceChildren(...SECTIONS.map(([k, label]) => {
      const b = h('button', { class: 'i18-tab', type: 'button', role: 'tab', id: `mb-tab-${k}`, 'aria-selected': k === current ? 'true' : 'false', 'aria-controls': 'mb-panel' }, label);
      b.addEventListener('click', () => { current = k; tabs(); show(); });
      return b;
    }));
  }
  function show() { panel.replaceChildren(); panel.id = 'mb-panel'; panel.setAttribute('aria-labelledby', `mb-tab-${current}`); return VIEW[current](); }

  // ── Bandeja ────────────────────────────────────────────────────────────────────────────────────────────────────────
  function target(t) {
    const hrefs = t.type === 'glosa_responder' ? [`#/glosas/${t.entity_id}`] : t.type === 'cobro_escalar' ? ['#/cartera'] : [`#/radicaciones/${t.entity_id}`, '#/reclamaciones'];
    return hrefs.find((x) => canOpen(x, ctx.role)) || null;
  }
  async function bandeja() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const d = await guarded(box, () => rpc('inbox_my', { p_type: type }));
    if (!d) return;
    const out = [];
    if (d.my_absence) out.push(note(`${d.my_absence.in_progress ? 'Está ausente' : 'Tiene una ausencia programada'} del ${fmtDate(d.my_absence.starts_on)} al ${fmtDate(d.my_absence.ends_on)}${d.my_absence.backup ? `: su trabajo lo atiende ${d.my_absence.backup}` : ': sin suplente, su trabajo lo ve la supervisión'}.`, 'warn'));
    (d.covering || []).forEach((c) => out.push(note(`Hoy cubre a ${c.name} hasta el ${fmtDate(c.until)}: sus tareas aparecen aquí marcadas «Cubriendo».`, 'info')));
    const t = d.totals;
    out.push(h('div', { class: 'i18-kpis' }, kpi('Tareas', String(t.total), d.view === 'todo' ? 'De todos los clientes que usted ve' : 'Las suyas'), kpi('Vencidas', String(t.overdue), money(t.overdue_amount)),
      kpi('Prioridad alta', String(t.high), 'Vencen pronto o son de monto alto'), kpi('Monto pendiente', money(t.amount)), d.view === 'todo' ? kpi('Sin responsable', String(t.unassigned), t.unassigned ? 'Asígnelos en «Asignaciones»' : 'Todo tiene dueño') : null));
    const all = h('button', { class: 'mb-count', type: 'button', 'aria-pressed': type ? 'false' : 'true' }, h('strong', {}, String(t.total)), h('span', {}, 'Todas'));
    all.addEventListener('click', () => { type = null; show(); });
    out.push(h('div', { class: 'mb-counters', role: 'group', 'aria-label': 'Tareas por tipo' }, all, ...d.counts.map((c) => {
      const b = h('button', { class: `mb-count${c.overdue ? ' mb-late' : ''}`, type: 'button', 'aria-pressed': type === c.type ? 'true' : 'false', 'data-type': c.type },
        h('strong', {}, String(c.total)), h('span', {}, c.label), c.overdue ? h('small', {}, `${c.overdue} vencida${c.overdue === 1 ? '' : 's'}`) : h('small', {}, c.total ? 'Al día' : 'Nada pendiente'));
      b.addEventListener('click', () => { type = type === c.type ? null : c.type; show(); });
      return b;
    })));
    if (!d.tasks.length) out.push(note(type ? `No hay ${TYPES[type].toLowerCase()} pendientes.` : d.view === 'todo' ? 'No hay tareas pendientes.' : 'No tiene tareas pendientes. Si espera trabajo, pida a su supervisor que le asigne clientes.', 'ok'));
    else {
      const cols = [
        { label: 'Prioridad', get: (x) => h('span', { class: `mb-prio mb-${x.priority}` }, PRIO[x.priority] || x.priority) },
        { label: 'Tarea', get: (x) => h('div', {}, h('strong', {}, x.type_label), h('div', {}, x.title), h('small', { class: 'i18-sub' }, x.detail), x.covering ? h('div', { class: 'mb-cover' }, `Cubriendo a ${x.assigned_to}`) : null) },
        { label: 'Cliente', get: (x) => x.client },
        { label: 'Vence', get: (x) => h('div', {}, fmtDate(x.due_on), h('small', { class: x.days_late > 0 ? 'mb-over' : 'i18-sub' }, dueText(x.days_late))) },
        { label: 'Monto', right: true, get: (x) => money(x.amount) }
      ];
      if (d.view === 'todo') cols.push({ label: 'Responsable', get: (x) => (x.assignee ? x.assignee : h('span', { class: 'mb-none' }, REASON[x.unassigned_reason] || 'Sin responsable')) });
      cols.push({ label: '', get: (x) => { const href = target(x); return href ? h('a', { class: 'i18-btn i18-sec', href }, 'Abrir') : h('small', { class: 'i18-sub' }, 'Solo lectura'); } });
      out.push(table(cols, d.tasks));
      if (d.truncated) out.push(note('Se muestran las primeras 300 tareas. Filtre por tipo para ver el resto.', 'info'));
    }
    box.replaceChildren(...out);
  }

  // ── Carga por persona (supervisor) ─────────────────────────────────────────────────────────────────────────────────
  async function carga() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const d = await guarded(box, () => rpc('inbox_supervisor'));
    if (!d) return;
    const u = d.unassigned;
    const out = [h('div', { class: 'i18-kpis' }, kpi('Tareas en la cola', String(d.totals.total)), kpi('Vencidas', String(d.totals.overdue), money(d.totals.overdue_amount)), kpi('Sin responsable', String(u.total), u.overdue ? `${u.overdue} vencida(s)` : 'Nada atrasado'),
      ...d.by_type.map((x) => kpi(x.label, String(x.total), x.overdue ? `${x.overdue} vencida(s)` : 'Al día')))];
    out.push(h('h3', {}, 'Carga por persona'));
    out.push(table([
      { label: 'Persona', get: (p) => h('div', {}, h('strong', {}, p.name), p.absent ? h('div', { class: 'mb-cover' }, `Ausente hasta el ${fmtDate(p.absent.ends_on)}${p.absent.backup ? ` · lo cubre ${p.absent.backup}` : ' · sin suplente'}`) : null,
        p.covers.length ? h('div', { class: 'mb-cover' }, `Cubre a ${p.covers.join(', ')}`) : null) },
      { label: 'Tareas', right: true, get: (p) => String(p.total) },
      { label: 'Vencidas', right: true, get: (p) => h('span', { class: p.overdue ? 'mb-over' : '' }, String(p.overdue)) },
      { label: 'Prioridad alta', right: true, get: (p) => String(p.high) },
      { label: 'Monto vencido', right: true, get: (p) => money(p.overdue_amount) },
      { label: 'Peor atraso', right: true, get: (p) => (p.worst_late ? `${p.worst_late} día${p.worst_late === 1 ? '' : 's'}` : '—') },
      { label: 'Por tipo', get: (p) => Object.entries(p.by_type).filter(([, n]) => n > 0).map(([k, n]) => `${TYPES[k]}: ${n}`).join(' · ') || '—' }
    ], d.people));
    out.push(h('h3', {}, 'Sin responsable'));
    out.push(u.total ? h('div', { class: 'i18-card' }, h('p', {}, `${u.total} tarea(s) sin responsable · ${money(u.amount)}.`),
      h('ul', { class: 'mb-reasons' }, Object.entries(u.by_reason).filter(([, n]) => n > 0).map(([k, n]) => h('li', {}, `${REASON[k]}: ${n}`))),
      u.clients.length ? table([{ label: 'Cliente', get: (c) => c.client }, { label: 'Tareas', right: true, get: (c) => String(c.tasks) }, { label: 'Causa', get: (c) => REASON[c.reason] || c.reason }], u.clients) : null)
      : note('Todo tiene responsable.', 'ok'));
    box.replaceChildren(...out);
  }

  // ── Asignaciones (supervisor): por cliente fijo, con tipo opcional ─────────────────────────────────────────────────
  async function asignaciones() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const d = await guarded(box, () => rpc('inbox_assignments_list'));
    if (!d) return;
    let clients = [];
    try { clients = await realClientOptions(); } catch (e) { box.append(note(e.message, 'error')); }
    const org = h('select', { id: 'mb-as-org' }, h('option', { value: '' }, 'Elija un cliente…'), clients.map((c) => h('option', { value: c.id }, clientName(c))));
    const who = h('select', { id: 'mb-as-who' }, h('option', { value: '' }, 'Elija a la persona…'), d.billers.map((b) => h('option', { value: b.user_id }, b.name)));
    const typ = h('select', { id: 'mb-as-type' }, h('option', { value: '' }, 'Todos los tipos de tarea'), d.types.map((t) => h('option', { value: t.code }, t.label)));
    const why = h('input', { id: 'mb-as-note', type: 'text', maxlength: '300', placeholder: 'Nota (opcional)' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Asignar');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      out.replaceChildren(); go.disabled = true;
      try {
        const r = await rpc('inbox_assignment_save', { p_org: org.value || null, p_assignee: who.value || null, p_type: typ.value || null, p_note: why.value });
        await show();
        const o = document.getElementById('mb-out'); if (o) o.replaceChildren(note(r.previous_assignee ? 'Asignación cambiada: la anterior quedó en el historial.' : 'Asignación guardada.', 'ok'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    const form = h('div', { class: 'i18-card' }, h('p', { class: 'i18-sub' }, 'Cada cliente tiene una persona fija de Facturación. Si elige un tipo de tarea, esa asignación manda sobre la general del cliente (por ejemplo, las glosas de un cliente las lleva otra persona).'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'mb-as-org' }, 'Cliente', org), h('label', { for: 'mb-as-who' }, 'Responsable', who), h('label', { for: 'mb-as-type' }, 'Tipo de tarea', typ), h('label', { for: 'mb-as-note' }, 'Nota', why), go), out);
    const rows = d.assignments.length ? table([
      { label: 'Cliente', get: (a) => a.client }, { label: 'Tipo de tarea', get: (a) => a.type_label }, { label: 'Responsable', get: (a) => a.assignee },
      { label: 'Desde', get: (a) => fmtDate(a.since) }, { label: 'Estado', get: (a) => (a.available ? 'Disponible' : h('span', { class: 'mb-over' }, 'No disponible: reasigne')) },
      { label: '', get: (a) => { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Quitar la asignación de ${a.client}` }, 'Quitar'); b.addEventListener('click', async () => {
        b.disabled = true; try { await rpc('inbox_assignment_remove', { p_id: a.id }); await show(); } catch (e) { const o = document.getElementById('mb-out'); if (o) o.replaceChildren(note(e.message, 'error')); b.disabled = false; } }); return b; } }
    ], d.assignments) : note('Todavía no hay clientes asignados.', 'warn');
    const unc = d.uncovered.length ? h('div', { class: 'i18-card' }, h('strong', {}, 'Clientes sin cubrir'), h('p', { class: 'i18-sub' }, 'Sus tareas aparecen «sin responsable» solo para la supervisión.'),
      h('ul', { class: 'mb-reasons' }, d.uncovered.map((u) => { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Asignar');
        b.addEventListener('click', () => { org.value = u.organization_id; who.focus(); });
        return h('li', {}, `${u.client} · falta: ${u.missing.length === 4 ? 'todo' : u.missing.map((m) => TYPES[m]).join(', ')} `, b); }))) : note('Todos los clientes tienen responsable.', 'ok');
    box.replaceChildren(h('div', { id: 'mb-out', 'aria-live': 'polite' }), form, h('h3', {}, 'Asignaciones vigentes'), rows, h('h3', {}, 'Cobertura'), unc);
  }

  // ── Ausencias (supervisor): mientras alguien falta, lo suyo pasa a su suplente ─────────────────────────────────────
  async function ausencias() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const [d, list] = await Promise.all([guarded(box, () => rpc('inbox_assignments_list')), rpc('inbox_absences_list').catch((e) => e)]);
    if (!d) return;
    if (list instanceof Error) { box.replaceChildren(note(list.message, 'error')); return; }
    const who = h('select', { id: 'mb-ab-who' }, h('option', { value: '' }, 'Elija a la persona…'), d.billers.map((b) => h('option', { value: b.user_id }, b.name)));
    const from = h('input', { id: 'mb-ab-from', type: 'date', value: localIso() });
    const to = h('input', { id: 'mb-ab-to', type: 'date', value: localIso(1) });
    const bk = h('select', { id: 'mb-ab-backup' }, h('option', { value: '' }, 'Sin suplente'), d.billers.map((b) => h('option', { value: b.user_id }, b.name)));
    const why = h('input', { id: 'mb-ab-note', type: 'text', maxlength: '300', placeholder: 'Motivo (opcional)' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar ausencia');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      out.replaceChildren(); go.disabled = true;
      try {
        const r = await rpc('inbox_absence_save', { p_user: who.value || null, p_from: from.value || null, p_to: to.value || null, p_backup: bk.value || null, p_note: why.value });
        await show();
        const o = document.getElementById('mb-out'); if (o) o.replaceChildren(note(`Ausencia registrada. Tareas que hoy pasan al suplente o a la supervisión: ${r.tasks_now}.${r.warnings.length ? ' ' + r.warnings.join(' ') : ''}`, r.warnings.length ? 'warn' : 'ok'));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    const form = h('div', { class: 'i18-card' }, h('p', { class: 'i18-sub' }, 'Mientras la persona falta, lo suyo pasa solo a su suplente; al terminar las fechas todo vuelve a ella. Sin suplente, las tareas quedan «sin responsable» para la supervisión.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'mb-ab-who' }, 'Persona que falta', who), h('label', { for: 'mb-ab-from' }, 'Desde', from), h('label', { for: 'mb-ab-to' }, 'Hasta (inclusive)', to),
        h('label', { for: 'mb-ab-backup' }, 'Suplente', bk), h('label', { for: 'mb-ab-note' }, 'Motivo', why), go), out);
    const rows = list.length ? table([
      { label: 'Persona', get: (a) => a.name }, { label: 'Desde', get: (a) => fmtDate(a.starts_on) }, { label: 'Hasta', get: (a) => fmtDate(a.ends_on) },
      { label: 'Suplente', get: (a) => a.backup || h('span', { class: 'mb-none' }, 'Sin suplente') }, { label: 'Estado', get: (a) => ABS[a.status] || a.status }, { label: 'Motivo', get: (a) => a.note || '—' },
      { label: '', get: (a) => { if (a.status === 'terminada') return ''; const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Cancelar la ausencia de ${a.name}` }, 'Cancelar');
        b.addEventListener('click', async () => { b.disabled = true; try { await rpc('inbox_absence_cancel', { p_id: a.id }); await show(); } catch (e) { const o = document.getElementById('mb-out'); if (o) o.replaceChildren(note(e.message, 'error')); b.disabled = false; } }); return b; } }
    ], list) : note('No hay ausencias registradas.', 'info');
    box.replaceChildren(h('div', { id: 'mb-out', 'aria-live': 'polite' }), form, h('h3', {}, 'Ausencias'), rows);
  }

  // ── Indicador: tareas vencidas por facturador al cierre del día ────────────────────────────────────────────────────
  async function vencidas() {
    const from = h('input', { id: 'mb-ve-from', type: 'date', value: localIso(-13) });
    const to = h('input', { id: 'mb-ve-to', type: 'date', value: localIso() });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Consultar');
    const close = canClose ? h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Cerrar el día ahora') : null;
    const res = h('div', { 'aria-live': 'polite' });
    panel.append(h('p', { class: 'i18-sub' }, 'Cuántas tareas vencidas tenía cada persona al cerrar cada día. El cierre se guarda solo cada noche; el día de hoy se muestra en vivo.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'mb-ve-from' }, 'Desde', from), h('label', { for: 'mb-ve-to' }, 'Hasta', to), go, close), res);
    async function load() {
      const d = await guarded(res, () => rpc('inbox_overdue_report', { p_from: from.value || null, p_to: to.value || null }));
      if (!d) return;
      res.replaceChildren(h('h3', {}, 'Por persona en el período'),
        d.by_person.length ? table([{ label: 'Persona', get: (z) => z.assignee }, { label: 'Días medidos', right: true, get: (z) => String(z.days) }, { label: 'Días con vencidas', right: true, get: (z) => String(z.days_with_overdue) },
          { label: 'Máximo en un día', right: true, get: (z) => String(z.max_overdue) }, { label: 'Promedio', right: true, get: (z) => String(z.avg_overdue) }, { label: 'Último día medido', right: true, get: (z) => String(z.last_overdue) }], d.by_person)
          : note('No hay cierres guardados en ese período todavía. Se guardan solos cada noche; el día de hoy aparece en vivo.', 'info'),
        h('h3', {}, 'Día por día'),
        d.rows.length ? table([{ label: 'Día', get: (r) => h('span', {}, fmtDate(r.day), r.live ? h('small', { class: 'i18-sub' }, ' · en vivo') : null) }, { label: 'Persona', get: (r) => r.assignee },
          { label: 'Abiertas', right: true, get: (r) => String(r.open) }, { label: 'Vencidas', right: true, get: (r) => h('span', { class: r.overdue ? 'mb-over' : '' }, String(r.overdue)) },
          { label: 'Monto vencido', right: true, get: (r) => money(r.overdue_amount) },
          { label: 'Por tipo', get: (r) => Object.entries(r.by_type || {}).map(([k, n]) => `${TYPES[k] || k}: ${n}`).join(' · ') || '—' }], d.rows) : note('Sin datos en ese período.', 'info'));
    }
    go.addEventListener('click', load);
    if (close) close.addEventListener('click', async () => {
      if (!window.confirm('Se guarda la foto de hoy de las tareas vencidas de cada persona. Si ya se había cerrado hoy, se reemplaza. ¿Continuar?')) return;
      close.disabled = true;
      try { const r = await rpc('inbox_close_day_now'); res.replaceChildren(note(`Día cerrado: ${r.rows} fila(s) guardadas.`, 'ok')); } catch (e) { res.replaceChildren(note(e.message, 'error')); }
      close.disabled = false;
    });
    await load();
  }

  // ── Reglas: parámetros de prioridad ────────────────────────────────────────────────────────────────────────────────
  async function reglas() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const p = await guarded(box, () => rpc('inbox_params_get'));
    if (!p) return;
    const grace = h('input', { id: 'mb-pa-grace', type: 'number', min: '0', max: '30', value: String(p.collection_grace_days), disabled: !p.can_edit });
    const soon = h('input', { id: 'mb-pa-soon', type: 'number', min: '0', max: '10', value: String(p.soon_days), disabled: !p.can_edit });
    const high = h('input', { id: 'mb-pa-high', type: 'number', min: '0', step: '1000', value: String(p.high_amount), disabled: !p.can_edit });
    const go = h('button', { class: 'i18-btn', type: 'button', disabled: !p.can_edit }, 'Guardar reglas');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      out.replaceChildren(); go.disabled = true;
      try { await rpc('inbox_params_set', { p_grace: Number(grace.value), p_soon: Number(soon.value), p_high: Number(high.value) }); out.replaceChildren(note('Reglas guardadas.', 'ok')); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); }
      go.disabled = false;
    });
    box.replaceChildren(h('div', { class: 'i18-card' },
      h('ul', { class: 'mb-reasons' },
        h('li', {}, h('strong', {}, 'Crítica: '), 'ya venció.'), h('li', {}, h('strong', {}, 'Alta: '), 'vence en los próximos días o el monto llega al umbral.'), h('li', {}, h('strong', {}, 'Normal: '), 'el resto.'),
        h('li', {}, 'Dentro de cada prioridad: primero la más vencida y, si empatan, la de mayor monto.'),
        h('li', {}, 'Capturas y lotes vencen en la fecha límite de radicación; las glosas, a los 7 días hábiles de notificadas; los cobros, al empezar su etapa de cartera más los días de gracia.')),
      h('div', { class: 'i18-bar' }, h('label', { for: 'mb-pa-grace' }, 'Días de gracia del cobro', grace), h('label', { for: 'mb-pa-soon' }, 'Días de «vence pronto»', soon), h('label', { for: 'mb-pa-high' }, 'Monto alto (RD$)', high), go),
      p.can_edit ? null : note('Solo el Super Admin o el Administrador cambian estas reglas.', 'info'), out));
  }

  tabs(); await show();
}
export default render;
