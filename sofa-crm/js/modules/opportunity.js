/** SOFA · Detalle de oportunidad: datos, diagnóstico de fugas, actividad, tareas y contactos */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, busy, fieldError } from '../utils/ui.js';
import { getOpportunity, updateOpportunity, updateLead, listDiagnostics, addDiagnostic, listActivities, addActivity, listContacts, listStaff, activePartners } from '../services/crm.js';
import { listTasks, updateTask } from '../services/tasks.js';
import { STAGES, OPEN_STAGES, SERVICES, SOURCES, ACTIVITY_TYPES, PRIORITIES, stageLabel, serviceName } from '../utils/constants.js';
import { money, date, dateTime, num } from '../utils/formatters.js';
import { waLink, phoneFmt } from '../utils/whatsapp.js';
import { can } from '../utils/permissions.js';
import { moveTo } from './pipeline.js';
import { taskDialog, contactDialog } from './crm-dialogs.js';
import { isEmail, isPhone } from '../utils/validation.js';

export async function render(main, ctx) {
  const id = ctx.arg;
  paint(main, html`<div id="op"></div>`);
  const box = $('#op', main);
  const o = await loadInto(box, () => getOpportunity(id), () => html``, { isEmpty: (d) => !d, empty: () => emptyView('Oportunidad no encontrada', 'Puede que ya no exista o que tu rol no tenga acceso.', html`<a class="btn" href="#/oportunidades">Volver al pipeline</a>`) });
  if (!o) return;
  ctx.setTitle(o.company);
  const edit = can('crm.edit', ctx.role);
  const open = OPEN_STAGES.includes(o.stage);
  const entity = { type: 'opportunity', id: o.id, label: o.company, organizationId: o.organization_id };
  const msg = `Saludos${o.contact_name ? ` ${o.contact_name}` : ''}. Le escribe el equipo de SOFA · Soluciones de Facturación Médica. `;
  const wa = waLink(o.whatsapp, msg);
  let staff = [], partners = [];
  try { [staff, partners] = await Promise.all([listStaff(), o.lead_id ? activePartners() : []]); } catch { /* opcional */ }

  paint(box, html`
    <div class="page-head"><div class="t"><p><a href="#/oportunidades">← Pipeline</a></p><h2>${o.company}</h2>
      <p><span class="pill ${o.stage === 'cliente' ? 'ok' : o.stage === 'perdido' ? 'bad' : 'info'}">${stageLabel(o.stage)}</span> · ${serviceName(o.service_code)} · ${money(o.estimated_value)}/mes · ${o.probability}%${o.days_in_stage != null && open ? ` · ${o.days_in_stage} días en esta etapa` : ''}</p>
      ${o.stage === 'perdido' && o.lost_reason ? html`<p class="small">Motivo: ${o.lost_reason}</p>` : ''}</div>
      ${wa ? html`<a class="btn" href="${wa}" target="_blank" rel="noopener">WhatsApp</a>` : ''}
      ${o.converted_org_id || (o.organization_id && o.stage === 'cliente') ? html`<a class="btn" href="#/clientes/${o.converted_org_id || o.organization_id}">Ver cliente</a>` : ''}
      ${edit && open ? html`<label class="sr-only" for="stageSel">Etapa</label><select class="input" id="stageSel" style="width:auto">${STAGES.map((s) => opt(s.code, `Mover a: ${s.label}`, o.stage))}</select>` : ''}
    </div>
    <div class="grid two">
      <div class="card"><h2>Datos de la oportunidad</h2>
        <form id="fo" novalidate><div class="form-grid">
          <div class="field"><label for="service_code">Servicio</label><select id="service_code" name="service_code" ${edit ? '' : raw('disabled')}>${SERVICES.map((s) => opt(s.code, s.name, o.service_code))}</select></div>
          <div class="field"><label for="estimated_value">Valor mensual (RD$)</label><input id="estimated_value" name="estimated_value" type="number" min="0" step="100" value="${o.estimated_value}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="probability">Probabilidad (%)</label><input id="probability" name="probability" type="number" min="0" max="100" value="${o.probability}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="owner_id">Responsable</label><select id="owner_id" name="owner_id" ${edit ? '' : raw('disabled')}><option value="">Sin asignar</option>${staff.map((s) => opt(s.id, s.full_name || 'Sin nombre', o.owner_id))}</select></div>
          <div class="field"><label for="next_action">Próxima acción</label><input id="next_action" name="next_action" value="${o.next_action || ''}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="next_action_date">Fecha</label><input id="next_action_date" name="next_action_date" type="date" value="${o.next_action_date || ''}" ${edit ? '' : raw('disabled')}></div>
        </div>${edit ? html`<button class="btn primary" type="submit">Guardar</button>` : ''}</form></div>
      ${o.lead_id ? html`<div class="card"><h2>Prospecto</h2>
        <form id="fl" novalidate><div class="form-grid">
          <div class="field"><label for="company">Médico o centro</label><input id="company" name="company" value="${o.company}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="specialty">Especialidad</label><input id="specialty" name="specialty" value="${o.specialty || ''}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="contact_name">Contacto</label><input id="contact_name" name="contact_name" value="${o.contact_name || ''}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="whatsapp">WhatsApp</label><input id="whatsapp" name="whatsapp" value="${o.whatsapp || ''}" inputmode="tel" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="phone">Teléfono</label><input id="phone" name="phone" value="${o.phone || ''}" inputmode="tel" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="email">Correo</label><input id="email" name="email" type="email" value="${o.email || ''}" ${edit ? '' : raw('disabled')}></div>
          <div class="field"><label for="source">Canal</label><select id="source" name="source" ${edit ? '' : raw('disabled')}>${SOURCES.map((s) => opt(s, s, o.source))}</select></div>
          <div class="field"><label for="referral_partner_id">Aliado</label><select id="referral_partner_id" name="referral_partner_id" ${edit ? '' : raw('disabled')}><option value="">Ninguno</option>${partners.map((p) => opt(p.id, p.full_name, o.referral_partner_id))}</select></div>
        </div>${edit ? html`<button class="btn primary" type="submit">Guardar prospecto</button>` : ''}</form></div>` : ''}
      <div class="card"><h2>Diagnóstico de fugas</h2><p class="sub">Cuánto dinero pierde hoy el prospecto: la base del cierre ("se paga con lo que hoy pierde").</p><div id="diag"></div></div>
      <div class="card"><h2>Actividad</h2>
        ${edit ? html`<form id="fa" class="inline-form row3" novalidate><label class="sr-only" for="atype">Tipo</label><select class="input" id="atype" name="type">${Object.entries(ACTIVITY_TYPES).filter(([k]) => k !== 'sistema').map(([k, l]) => opt(k, l, 'llamada'))}</select>
          <label class="sr-only" for="abody">Qué pasó</label><input class="input" id="abody" name="body" placeholder="Qué pasó y qué se acordó" maxlength="1000"><button class="btn" type="submit">Registrar</button></form>` : ''}
        <div id="acts" class="timeline"></div></div>
      <div class="card"><h2>Tareas</h2>${can('tasks.edit', ctx.role) ? html`<button class="btn sm" id="addTask">+ Tarea</button>` : ''}<div id="tasks"></div></div>
      <div class="card"><h2>Contactos</h2>${edit ? html`<button class="btn sm" id="addContact">+ Contacto</button>` : ''}<div id="contacts"></div></div>
    </div>`);

  // Cambio de etapa
  $('#stageSel', main)?.addEventListener('change', async (e) => { const ok = await moveTo(o, e.target.value, ctx); if (ok && e.target.value !== 'cliente') render(main, ctx); else if (!ok) e.target.value = o.stage; });
  // Guardar oportunidad
  $('#fo', main)?.addEventListener('submit', async (e) => {
    e.preventDefault(); const f = e.target; const v = Object.fromEntries(new FormData(f));
    const p = Number(v.probability);
    if (Number.isNaN(p) || p < 0 || p > 100) { fieldError(f.probability, 'Entre 0 y 100.'); return; } fieldError(f.probability, null);
    await busy(e.submitter, async () => {
      try { await updateOpportunity(o.id, { service_code: v.service_code, estimated_value: Number(v.estimated_value || 0), probability: p, owner_id: v.owner_id || null, next_action: v.next_action || null, next_action_date: v.next_action_date || null }); toast('Oportunidad guardada', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });
  // Guardar prospecto
  $('#fl', main)?.addEventListener('submit', async (e) => {
    e.preventDefault(); const f = e.target; const v = Object.fromEntries(new FormData(f));
    let bad = false;
    if (v.company.trim().length < 2) { fieldError(f.company, 'Obligatorio.'); bad = true; } else fieldError(f.company, null);
    if (v.email && !isEmail(v.email)) { fieldError(f.email, 'Correo no válido.'); bad = true; } else fieldError(f.email, null);
    if (v.whatsapp && !isPhone(v.whatsapp)) { fieldError(f.whatsapp, 'Solo números.'); bad = true; } else fieldError(f.whatsapp, null);
    if (bad) return;
    await busy(e.submitter, async () => {
      try { await updateLead(o.lead_id, { company: v.company.trim(), specialty: v.specialty || null, contact_name: v.contact_name || null, whatsapp: v.whatsapp ? v.whatsapp.replace(/\D/g, '') : null, phone: v.phone || null, email: v.email ? v.email.trim().toLowerCase() : null, source: v.source, referral_partner_id: v.referral_partner_id || null }); toast('Prospecto guardado', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });

  // Diagnóstico de fugas
  const diagBox = $('#diag', main);
  const drawDiag = (list) => {
    const d = list[0];
    const fee = Number(o.estimated_value || 0);
    const roi = d && fee ? Math.round((Number(d.recoverable_monthly) / fee) * 10) / 10 : null;
    const text = d ? `Saludos${o.contact_name ? ` ${o.contact_name}` : ''}. Según el diagnóstico de fugas con ${money(d.monthly_billing)} facturados al mes a las ARS: se glosan cerca de ${money(d.glosa_monthly)} al mes y ${money(d.recoverable_monthly)} son recuperables. Además hay ${money(d.trapped_by_dso)} retenidos por cartera de más de 60 días.${roi ? ` Por cada RD$ 1 de nuestra cuota mensual, usted recupera RD$ ${roi}.` : ''} ¿Coordinamos para iniciar esta semana? — SOFA` : '';
    const link = d ? waLink(o.whatsapp, text) : '';
    return html`${d ? html`<div class="grid kpis">
        <div class="kpi"><div class="l">Glosado al mes</div><div class="v">${money(d.glosa_monthly)}</div></div>
        <div class="kpi"><div class="l">Recuperable al mes</div><div class="v" style="color:var(--ok)">${money(d.recoverable_monthly)}</div></div>
        <div class="kpi"><div class="l">Retenido por cartera</div><div class="v">${money(d.trapped_by_dso)}</div><div class="h">Exceso sobre 60 días</div></div>
        <div class="kpi"><div class="l">Retorno para el cliente</div><div class="v">${roi ? `RD$ ${roi}` : '—'}</div><div class="h">por cada RD$ 1 de cuota</div></div></div>
        <p class="small muted">Registrado ${dateTime(d.created_at)} · facturación ${money(d.monthly_billing)}/mes, ${num(d.glosa_pct)}% glosado, ${num(d.recoverable_pct)}% recuperable, ${num(d.dso_days)} días de cartera.</p>
        ${link ? html`<a class="btn" href="${link}" target="_blank" rel="noopener">Enviar resultado por WhatsApp</a>` : ''}` : html`<p class="small muted">Aún no hay diagnóstico. Con 3 meses de facturación y glosas del prospecto, completa los datos.</p>`}
      ${edit ? html`<form id="fd" novalidate style="margin-top:12px"><div class="form-grid">
        <div class="field"><label for="monthly_billing">Facturación mensual a ARS (RD$)</label><input id="monthly_billing" name="monthly_billing" type="number" min="1" step="1000" value="${d?.monthly_billing || ''}" required></div>
        <div class="field"><label for="glosa_pct">% glosado</label><input id="glosa_pct" name="glosa_pct" type="number" min="0" max="100" step="0.5" value="${d?.glosa_pct ?? 20}"></div>
        <div class="field"><label for="recoverable_pct">% recuperable</label><input id="recoverable_pct" name="recoverable_pct" type="number" min="0" max="100" step="1" value="${d?.recoverable_pct ?? 60}"></div>
        <div class="field"><label for="dso_days">Días de cartera</label><input id="dso_days" name="dso_days" type="number" min="0" max="720" value="${d?.dso_days ?? 120}"></div>
      </div><button class="btn primary" type="submit">${d ? 'Registrar nuevo cálculo' : 'Calcular y guardar'}</button></form>` : ''}`;
  };
  const loadDiag = () => loadInto(diagBox, () => listDiagnostics({ leadId: o.lead_id, organizationId: o.organization_id }), drawDiag, { isEmpty: () => false });
  diagBox.addEventListener('submit', async (e) => {
    e.preventDefault(); const f = e.target; const v = Object.fromEntries(new FormData(f));
    if (!(Number(v.monthly_billing) > 0)) { fieldError(f.monthly_billing, 'Indica la facturación mensual.'); return; }
    await busy(e.submitter, async () => {
      try { await addDiagnostic(ctx.operatorId, { leadId: o.lead_id, organizationId: o.organization_id }, v); await addActivity(ctx.operatorId, { entityType: 'opportunity', entityId: o.id }, 'nota', `Diagnóstico de fugas registrado: facturación ${money(v.monthly_billing)}/mes`); toast('Diagnóstico guardado', 'ok'); loadDiag(); loadActs(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });

  // Actividad
  const actsBox = $('#acts', main);
  const loadActs = () => loadInto(actsBox, () => listActivities({ entityType: 'opportunity', entityId: o.id }), (list) => html`<div class="list">${list.map((a) => html`<div class="li"><div class="b"><div class="t1">${ACTIVITY_TYPES[a.activity_type] || a.activity_type} · <span class="small muted">${dateTime(a.occurred_at)}</span></div><div class="t2">${a.body}</div></div></div>`)}</div>`, { empty: () => emptyView('Sin actividad registrada') });
  $('#fa', main)?.addEventListener('submit', async (e) => {
    e.preventDefault(); const f = e.target; const body = f.body.value.trim();
    if (body.length < 3) { f.body.focus(); toast('Escribe qué pasó.', 'bad'); return; }
    await busy(e.submitter, async () => {
      try { await addActivity(ctx.operatorId, { entityType: 'opportunity', entityId: o.id }, f.type.value, body); f.body.value = ''; toast('Actividad registrada', 'ok'); loadActs(); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
  });

  // Tareas
  const tasksBox = $('#tasks', main);
  const loadTasks = () => loadInto(tasksBox, () => listTasks({ entityType: 'opportunity', entityId: o.id }), (list) => taskList(list, can('tasks.edit', ctx.role)), { empty: () => emptyView('Sin tareas') });
  $('#addTask', main)?.addEventListener('click', async () => { if (await taskDialog(ctx, entity, { title: o.next_action || '' })) loadTasks(); });
  tasksBox.addEventListener('click', (e) => taskAction(e, loadTasks));

  // Contactos
  const cBox = $('#contacts', main);
  const loadContacts = () => loadInto(cBox, () => listContacts(o.lead_id ? { leadId: o.lead_id } : { organizationId: o.organization_id }), (list) => contactList(list), { empty: () => emptyView('Sin contactos') });
  $('#addContact', main)?.addEventListener('click', async () => { if (await contactDialog(ctx, { leadId: o.lead_id, organizationId: o.lead_id ? null : o.organization_id, label: o.company })) loadContacts(); });

  loadDiag(); loadActs(); loadTasks(); loadContacts();
}

export function taskList(list, editable) {
  return html`<div class="list">${list.map((t) => html`<div class="li"><div class="b"><div class="t1">${t.title}</div>
    <div class="t2"><span class="pill ${(PRIORITIES[t.priority] || ['', ''])[1]}">${(PRIORITIES[t.priority] || [t.priority])[0]}</span> Vence ${date(t.due_date)}${t.assignee_name ? ` · ${t.assignee_name}` : ''}${t.bucket === 'vencidas' ? html` · <b style="color:var(--bad)">Vencida</b>` : ''}${t.bucket === 'completadas' ? ' · Completada' : ''}</div></div>
    ${editable && t.status === 'abierta' ? html`<button class="btn sm" data-task="done" data-id="${t.id}">Completar</button>` : ''}</div>`)}</div>`;
}
export async function taskAction(e, reload) {
  const b = e.target.closest('[data-task]'); if (!b) return;
  await busy(b, async () => {
    try {
      if (b.dataset.task === 'done') await updateTask(b.dataset.id, { status: 'completada' });
      if (b.dataset.task === 'reopen') await updateTask(b.dataset.id, { status: 'abierta' });
      if (b.dataset.task === 'snooze') { const d = new Date(`${b.dataset.due}T00:00:00`); const base = d < new Date(new Date().toDateString()) ? new Date() : d; base.setDate(base.getDate() + 3); await updateTask(b.dataset.id, { due_date: base.toISOString().slice(0, 10) }); }
      toast('Tarea actualizada', 'ok'); reload();
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
}
export function contactList(list) {
  return html`<div class="list">${list.map((c) => { const wa = waLink(c.whatsapp); return html`<div class="li"><div class="b"><div class="t1">${c.full_name}${c.is_primary ? html` <span class="pill info">Principal</span>` : ''}</div>
    <div class="t2">${[c.role_title, phoneFmt(c.phone), c.email].filter(Boolean).join(' · ') || '—'}</div></div>${wa ? html`<a class="btn sm" href="${wa}" target="_blank" rel="noopener">WhatsApp</a>` : ''}</div>`; })}</div>`;
}
