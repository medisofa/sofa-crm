/** SOFA · Ficha 360° del cliente PSS */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, formDialog, requireFields, fieldError } from '../utils/ui.js';
import { getClient, updateClient, listProviders, saveProvider, listCodes, saveCode } from '../services/clients.js';
import { listArs } from '../services/catalog.js';
import { listContacts, listActivities, addActivity, listOpportunities, createOpportunityForClient } from '../services/crm.js';
import { listTasks } from '../services/tasks.js';
import { listSubmissions } from '../services/submissions.js';
import { listCurrentTariffs } from '../services/tariffs.js';
import { ORG_TYPES, ORG_STATUS, PROVIDER_TYPES, CODE_STATUS, SERVICES, ACTIVITY_TYPES, stageLabel, serviceName, subStatus } from '../utils/constants.js';
import { money, date, dateTime, num, todayISO, period as periodLabel } from '../utils/formatters.js';
import { waLink, phoneFmt } from '../utils/whatsapp.js';
import { can, isStaff } from '../utils/permissions.js';
import { isTaxId, isEmail, isPhone } from '../utils/validation.js';
import { contactDialog, taskDialog } from './crm-dialogs.js';
import { taskList, taskAction, contactList } from './opportunity.js';

const kv = (pairs) => html`<dl class="kv">${pairs.filter(([, v]) => v !== undefined).map(([k, v]) => html`<dt>${k}</dt><dd>${v || '—'}</dd>`)}</dl>`;

export async function render(main, ctx) {
  const id = ctx.arg;
  paint(main, html`<div id="cl"></div>`);
  const box = $('#cl', main);
  const res = await loadInto(box, () => getClient(id), () => html``, { isEmpty: (d) => !d.org, empty: () => emptyView('Cliente no encontrado', 'No existe o tu rol no tiene acceso.', html`<a class="btn" href="#/clientes">Volver</a>`) });
  if (!res?.org) return;
  const { org, stats: s } = res;
  ctx.setTitle(org.legal_name);
  const staff = isStaff(ctx.role), editOrg = can('clients.edit', ctx.role), editCodes = can('codes.edit', ctx.role), crm = can('crm.edit', ctx.role);
  const [stLabel, stCls] = ORG_STATUS[org.status] || [org.status, ''];
  const wa = waLink(org.whatsapp);
  const entity = { type: 'organization', id: org.id, label: org.legal_name, organizationId: org.id };

  paint(box, html`
    <div class="page-head"><div class="t">${staff ? html`<p><a href="#/clientes">← Clientes</a></p>` : ''}<h2>${org.legal_name}</h2>
      <p><span class="pill ${stCls}">${stLabel}</span> · ${org.org_type || '—'}${org.specialty ? ` · ${org.specialty}` : ''}${org.started_on ? ` · cliente desde ${date(org.started_on)}` : ''}</p></div>
      ${wa ? html`<a class="btn" href="${wa}" target="_blank" rel="noopener">WhatsApp</a>` : ''}${editOrg ? html`<button class="btn" id="editOrg">Editar datos</button>` : ''}</div>
    <div class="grid kpis">
      <div class="kpi"><div class="l">Radicado</div><div class="v">${money(s?.radicado)}</div><div class="h">${num(s?.submitted)} radicaciones</div></div>
      <div class="kpi"><div class="l">Pagado</div><div class="v" style="color:var(--ok)">${money(s?.pagado)}</div><div class="h">${s?.tasa_pago == null ? 'Sin datos aún' : `${s.tasa_pago}% de lo radicado`}</div></div>
      <div class="kpi"><div class="l">Saldo por cobrar</div><div class="v">${money(s?.saldo)}</div><div class="h">${num(s?.vencidas)} vencidas</div></div>
      <div class="kpi"><div class="l">Tasa de glosa</div><div class="v">${s?.tasa_glosa == null ? '—' : `${s.tasa_glosa}%`}</div><div class="h">${s?.dias_promedio_cobro ? `${s.dias_promedio_cobro} días promedio de cobro` : 'Radicaciones: Iteración 5'}</div></div>
    </div>
    <div class="grid two" style="margin-top:14px">
      <div class="card"><h2>Datos generales</h2>${kv([['RNC / cédula', org.tax_id], ['Teléfono', phoneFmt(org.phone)], ['WhatsApp', phoneFmt(org.whatsapp)], ['Correo', org.email], ['Dirección', [org.address, org.city].filter(Boolean).join(', ')], ['Notas', org.notes]])}</div>
      <div class="card"><h2>Prestadores</h2><p class="sub">Médicos o centros que facturan a las ARS bajo este cliente.</p>${editOrg ? html`<button class="btn sm" id="addProv">+ Prestador</button>` : ''}<div id="provs"></div></div>
      <div class="card" style="grid-column:1/-1"><h2>Códigos de prestador por ARS</h2><p class="sub">Sin código asignado, la ARS no paga. Lleva aquí las solicitudes pendientes.</p>${editCodes ? html`<button class="btn sm" id="addCode">+ Código ARS</button>` : ''}<div id="codes"></div></div>
      <div class="card"><h2>Contactos</h2>${crm ? html`<button class="btn sm" id="addContact">+ Contacto</button>` : ''}<div id="contacts"></div></div>
      <div class="card" style="grid-column:1/-1"><h2>Radicaciones</h2><p class="sub">Las más recientes de este cliente.</p>${can('subs.create', ctx.role) ? html`<button class="btn sm" id="addSub">+ Nueva radicación</button> ` : ''}<a class="btn sm" href="#/radicaciones">Ver todas</a><div id="subs" style="margin-top:8px"></div></div>
      <div class="card" style="grid-column:1/-1"><h2>Tarifas negociadas</h2><p class="sub">Tarifas pactadas por sus prestadores con cada ARS. Tienen prioridad sobre la tarifa general.</p>${can('tariffs.edit', ctx.role) ? html`<button class="btn sm" id="addNeg">+ Tarifa negociada</button>` : ''}<div id="neg" style="margin-top:8px"></div></div>
      ${staff ? html`<div class="card"><h2>Oportunidades con este cliente</h2><p class="sub">Venta cruzada: codificación, glosas, habilitación…</p>${crm ? html`<button class="btn sm" id="addOpp">+ Oportunidad</button>` : ''}<div id="opps"></div></div>
      <div class="card"><h2>Tareas</h2>${can('tasks.edit', ctx.role) ? html`<button class="btn sm" id="addTask">+ Tarea</button>` : ''}<div id="tasks"></div></div>
      <div class="card"><h2>Historial</h2>${can('tasks.edit', ctx.role) ? html`<form id="fa" class="inline-form row3" novalidate><label class="sr-only" for="atype">Tipo</label><select class="input" id="atype" name="type">${Object.entries(ACTIVITY_TYPES).filter(([k]) => k !== 'sistema').map(([k, l]) => opt(k, l, 'llamada'))}</select><label class="sr-only" for="abody">Qué pasó</label><input class="input" id="abody" name="body" placeholder="Llamada, acuerdo, entrega de documentos…" maxlength="1000"><button class="btn" type="submit">Registrar</button></form>` : ''}<div id="acts" class="timeline"></div></div>` : ''}
      ${editOrg ? html`<div class="card" style="grid-column:1/-1"><h2>Acceso del cliente a SOFA</h2><p class="sub">Para que el médico o su secretaria vean sus radicaciones, pagos y glosas: 1) crea su usuario en Supabase (Authentication › Users › Add user, con Auto Confirm); 2) ejecuta esta línea en el SQL Editor, cambiando el correo.</p>
        <pre class="mono" id="grantSql" style="white-space:pre-wrap;background:var(--surface-2);padding:10px;border-radius:6px;margin:0 0 10px">select app.grant_role('correo.del.cliente@gmail.com', 'client', '${org.id}');</pre>
        <button class="btn sm" id="copyGrant" type="button">Copiar</button> <span class="small muted">Id de este cliente: <span class="mono">${org.id}</span></span></div>` : ''}
    </div>`);

  $('#copyGrant', main)?.addEventListener('click', async (e) => {
    const txt = $('#grantSql', main).textContent;
    try { await navigator.clipboard.writeText(txt); toast('Copiado. Pégalo en el SQL Editor y cambia el correo.', 'ok'); }
    catch { const r = document.createRange(); r.selectNodeContents($('#grantSql', main)); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); toast('Texto seleccionado: cópialo con Ctrl + C.'); }
  });

  // ---- Datos del cliente
  $('#editOrg', main)?.addEventListener('click', async () => {
    const f = (n, l, input) => html`<div class="field"><label for="e_${n}">${l}</label>${input}</div>`;
    const t = (n, v = '', a = '') => html`<input id="e_${n}" name="${n}" value="${v ?? ''}" ${raw(a)}>`;
    const ok = await formDialog({ title: 'Editar cliente', wide: true, body: html`<div class="form-grid">
      ${f('legal_name', 'Nombre o razón social *', t('legal_name', org.legal_name, 'required'))}${f('trade_name', 'Nombre comercial', t('trade_name', org.trade_name))}
      ${f('tax_id', 'RNC / cédula', t('tax_id', org.tax_id, 'inputmode="numeric"'))}${f('org_type', 'Tipo', html`<select id="e_org_type" name="org_type">${ORG_TYPES.map((x) => opt(x, x, org.org_type))}</select>`)}
      ${f('specialty', 'Especialidad', t('specialty', org.specialty))}${f('status', 'Estado', html`<select id="e_status" name="status">${Object.entries(ORG_STATUS).map(([k, [l]]) => opt(k, l, org.status))}</select>`)}
      ${f('whatsapp', 'WhatsApp', t('whatsapp', org.whatsapp, 'inputmode="tel"'))}${f('phone', 'Teléfono', t('phone', org.phone, 'inputmode="tel"'))}
      ${f('email', 'Correo', t('email', org.email, 'type="email"'))}${f('city', 'Ciudad', t('city', org.city))}
      ${f('address', 'Dirección', t('address', org.address))}</div>${f('notes', 'Notas', html`<textarea id="e_notes" name="notes" rows="2">${org.notes || ''}</textarea>`)}`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['legal_name'])) return false;
      if (v.tax_id && !isTaxId(v.tax_id)) { fieldError(form.elements.tax_id, 'RNC 9 dígitos o cédula 11.'); return false; }
      if (v.email && !isEmail(v.email)) { fieldError(form.elements.email, 'Correo no válido.'); return false; }
      if (v.whatsapp && !isPhone(v.whatsapp)) { fieldError(form.elements.whatsapp, 'Solo números.'); return false; }
      await updateClient(org.id, v); toast('Cliente actualizado', 'ok'); return true;
    } });
    if (ok) render(main, ctx);
  });

  // ---- Prestadores
  let providers = [];
  const provBox = $('#provs', main);
  const loadProv = () => loadInto(provBox, async () => { providers = await listProviders(org.id); return providers; }, (list) => html`<div class="list">${list.map((p) => html`<div class="li"><div class="b"><div class="t1">${p.full_name}${p.is_active ? '' : html` <span class="pill">Inactivo</span>`}</div>
    <div class="t2">${[PROVIDER_TYPES[p.provider_type], p.specialty, p.exequatur ? `Exequátur ${p.exequatur}` : null, p.tax_id].filter(Boolean).join(' · ')}</div></div>${editOrg ? html`<button class="btn sm" data-prov="${p.id}">Editar</button>` : ''}</div>`)}</div>`,
  { empty: () => emptyView('Sin prestadores', editOrg ? 'Agrega al menos uno: las radicaciones se hacen a nombre de un prestador.' : '') });
  const provDialog = async (p = null) => {
    const x = p || { provider_type: org.org_type === 'Laboratorio' ? 'laboratorio' : 'medico', is_active: true };
    return formDialog({ title: p ? 'Editar prestador' : 'Nuevo prestador', body: html`<div class="form-grid">
      <div class="field"><label for="p_full_name">Nombre *</label><input id="p_full_name" name="full_name" value="${x.full_name || ''}" required></div>
      <div class="field"><label for="p_type">Tipo</label><select id="p_type" name="provider_type">${Object.entries(PROVIDER_TYPES).map(([k, l]) => opt(k, l, x.provider_type))}</select></div>
      <div class="field"><label for="p_specialty">Especialidad</label><input id="p_specialty" name="specialty" value="${x.specialty || ''}"></div>
      <div class="field"><label for="p_exequatur">Exequátur</label><input id="p_exequatur" name="exequatur" value="${x.exequatur || ''}"></div>
      <div class="field"><label for="p_tax">Cédula o RNC</label><input id="p_tax" name="tax_id" value="${x.tax_id || ''}" inputmode="numeric"></div></div>
      <label class="check small"><input type="checkbox" name="is_active" ${x.is_active ? raw('checked') : ''}> Activo</label>`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['full_name'])) return false;
      if (v.tax_id && !isTaxId(v.tax_id)) { fieldError(form.elements.tax_id, 'RNC 9 dígitos o cédula 11.'); return false; }
      await saveProvider(org.id, v, p?.id); toast('Prestador guardado', 'ok'); return true;
    } });
  };
  $('#addProv', main)?.addEventListener('click', async () => { if (await provDialog()) { loadProv(); loadCodes(); } });
  provBox.addEventListener('click', async (e) => { const b = e.target.closest('[data-prov]'); if (b && await provDialog(providers.find((p) => p.id === b.dataset.prov))) { loadProv(); loadCodes(); } });

  // ---- Códigos ARS
  let codes = [], arsList = [];
  const codesBox = $('#codes', main);
  const loadCodes = () => loadInto(codesBox, async () => { codes = await listCodes(org.id); return codes; }, (list) => {
    const done = list.filter((c) => c.status === 'codificado').length;
    return html`<p class="small">${num(done)} de ${num(list.length)} códigos asignados${list.length && done < list.length ? html` · <b style="color:var(--warn)">${list.length - done} pendientes</b>` : ''}</p>
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Prestador</th><th>ARS</th><th>Código</th><th>Estado</th><th>Solicitado</th><th></th></tr></thead>
    <tbody>${list.map((c) => { const [l, cls] = CODE_STATUS[c.status] || [c.status, '']; return html`<tr><td data-l="Prestador">${c.providers?.full_name || '—'}</td><td data-l="ARS">${c.ars?.name || '—'}</td><td data-l="Código" class="mono">${c.code || '—'}</td>
      <td data-l="Estado"><span class="pill ${cls}">${l}</span></td><td data-l="Solicitado">${date(c.requested_on)}</td><td data-l="">${editCodes ? html`<button class="btn sm" data-code="${c.id}">Actualizar</button>` : ''}</td></tr>`; })}</tbody></table></div>`;
  }, { empty: () => emptyView('Sin códigos registrados', editCodes ? 'Registra cada ARS con la que trabaja el prestador, aunque el código esté en trámite.' : '') });
  const codeDialog = async (c = null) => {
    if (!providers.length) { toast('Primero agrega un prestador.', 'bad'); return false; }
    if (!arsList.length) { try { arsList = await listArs(); } catch (err) { toast(friendlyError(err), 'bad'); return false; } }
    const x = c || { status: 'solicitado', requested_on: todayISO() };
    return formDialog({ title: c ? `Código · ${c.ars?.name}` : 'Nuevo código ARS', body: html`<div class="form-grid">
      ${c ? '' : html`<div class="field"><label for="c_prov">Prestador *</label><select id="c_prov" name="provider_id">${providers.map((p) => opt(p.id, p.full_name))}</select></div>
      <div class="field"><label for="c_ars">ARS *</label><select id="c_ars" name="ars_id">${arsList.filter((a) => a.is_active).map((a) => opt(a.id, a.name))}</select></div>`}
      <div class="field"><label for="c_status">Estado</label><select id="c_status" name="status">${Object.entries(CODE_STATUS).map(([k, [l]]) => opt(k, l, x.status))}</select></div>
      <div class="field"><label for="c_code">Código asignado</label><input id="c_code" name="code" value="${x.code || ''}"></div>
      <div class="field"><label for="c_req">Fecha de solicitud</label><input id="c_req" name="requested_on" type="date" value="${x.requested_on || ''}"></div>
      <div class="field"><label for="c_granted">Fecha de asignación</label><input id="c_granted" name="granted_on" type="date" value="${x.granted_on || ''}"></div></div>`,
    onSubmit: async (v, form) => {
      if (v.status === 'codificado' && !v.code.trim()) { fieldError(form.elements.code, 'Escribe el código asignado.'); return false; }
      if (!c && codes.some((k) => k.provider_id === v.provider_id && k.ars_id === v.ars_id)) { fieldError(form.elements.ars_id, 'Ese prestador ya tiene esta ARS registrada.'); return false; }
      await saveCode(org.id, v, c?.id); toast('Código guardado', 'ok'); return true;
    } });
  };
  $('#addCode', main)?.addEventListener('click', async () => { if (await codeDialog()) loadCodes(); });
  codesBox.addEventListener('click', async (e) => { const b = e.target.closest('[data-code]'); if (b && await codeDialog(codes.find((c) => c.id === b.dataset.code))) loadCodes(); });

  // ---- Contactos
  const cBox = $('#contacts', main);
  const loadContacts = () => loadInto(cBox, () => listContacts({ organizationId: org.id }), contactList, { empty: () => emptyView('Sin contactos') });
  $('#addContact', main)?.addEventListener('click', async () => { if (await contactDialog(ctx, { organizationId: org.id, label: org.legal_name })) loadContacts(); });

  loadProv(); loadCodes(); loadContacts();
  if (!staff) return;

  // ---- Oportunidades (venta cruzada)
  const oBox = $('#opps', main);
  const loadOpps = () => loadInto(oBox, () => listOpportunities({ organizationId: org.id, includeClosed: true }), (list) => html`<div class="list">${list.map((o) => html`<div class="li"><div class="b"><div class="t1"><a href="#/oportunidades/${o.id}">${serviceName(o.service_code)}</a></div><div class="t2">${stageLabel(o.stage)} · ${money(o.estimated_value)}/mes</div></div></div>`)}</div>`, { empty: () => emptyView('Sin oportunidades') });
  $('#addOpp', main)?.addEventListener('click', async () => {
    const id2 = await formDialog({ title: `Nueva oportunidad · ${org.legal_name}`, body: html`<div class="form-grid">
      <div class="field"><label for="o_svc">Servicio *</label><select id="o_svc" name="service_code">${SERVICES.map((x) => opt(x.code, x.name, 'codificacion'))}</select></div>
      <div class="field"><label for="o_val">Valor mensual (RD$)</label><input id="o_val" name="estimated_value" type="number" min="0" step="100" value="3000"></div>
      <div class="field"><label for="o_next">Próxima acción</label><input id="o_next" name="next_action" value="Presentar propuesta"></div>
      <div class="field"><label for="o_date">Fecha</label><input id="o_date" name="next_action_date" type="date" value="${todayISO()}"></div></div>`,
    onSubmit: async (v) => { const r = await createOpportunityForClient(ctx.operatorId, org.id, v); toast('Oportunidad creada', 'ok'); return r.id; } });
    if (id2) location.hash = `#/oportunidades/${id2}`;
  });

  // ---- Tareas
  const tBox = $('#tasks', main);
  const loadTasks = () => loadInto(tBox, () => listTasks({ entityType: 'organization', entityId: org.id }), (list) => taskList(list, can('tasks.edit', ctx.role)), { empty: () => emptyView('Sin tareas') });
  $('#addTask', main)?.addEventListener('click', async () => { if (await taskDialog(ctx, entity)) loadTasks(); });
  tBox.addEventListener('click', (e) => taskAction(e, loadTasks));

  // ---- Historial (todas las actividades del cliente)
  const aBox = $('#acts', main);
  const loadActs = () => loadInto(aBox, () => listActivities({ organizationId: org.id }), (list) => html`<div class="list">${list.map((a) => html`<div class="li"><div class="b"><div class="t1">${ACTIVITY_TYPES[a.activity_type] || a.activity_type} · <span class="small muted">${dateTime(a.occurred_at)}</span></div><div class="t2">${a.body}</div></div></div>`)}</div>`, { empty: () => emptyView('Sin historial') });
  $('#fa', main)?.addEventListener('submit', async (e) => {
    e.preventDefault(); const f = e.target; const body = f.body.value.trim();
    if (body.length < 3) { toast('Escribe qué pasó.', 'bad'); return; }
    try { await addActivity(ctx.operatorId, { entityType: 'organization', entityId: org.id, organizationId: org.id }, f.type.value, body); f.body.value = ''; toast('Registrado', 'ok'); loadActs(); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  });
  const loadSubs = () => loadInto($('#subs', main), async () => (await listSubmissions({ orgId: org.id, size: 8 })).data,
    (rows) => html`<div class="list">${rows.map((x) => { const [l, c] = subStatus(x.display_status); return html`<div class="li"><div class="b"><div class="t1"><a href="#/radicaciones/${x.id}" class="mono">${x.folio}</a> · ${x.ars_name} · ${periodLabel(x.period)}</div><div class="t2">${x.provider_name} · ${num(x.lines)} servicios · ${money(x.claimed)}</div></div><span class="pill ${c}">${l}</span></div>`; })}</div>`,
    { empty: () => html`<p class="small muted">Sin radicaciones todavía.</p>` });
  $('#addSub', main)?.addEventListener('click', async () => {
    const { newSubmissionDialog } = await import('./submission-dialogs.js');
    try { const sid = await newSubmissionDialog(org.id); if (sid) location.hash = `#/radicaciones/${sid}`; } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  const loadNeg = () => loadInto($('#neg', main), async () => (await listCurrentTariffs({ orgId: org.id, scope: 'prestador', size: 100 })).data,
    (rows) => html`<div class="list">${rows.map((x) => html`<div class="li"><div class="b"><div class="t1"><a href="#/codificacion/${x.procedure_id}">${x.description}</a> · <b>${money(x.amount)}</b></div><div class="t2">${x.ars_name} · ${x.provider_name} · desde ${date(x.valid_from)}</div></div></div>`)}</div>`,
    { empty: () => html`<p class="small muted">Sin tarifas negociadas: se aplica la tarifa general de cada ARS.</p>` });
  $('#addNeg', main)?.addEventListener('click', async () => {
    const { tariffDialog } = await import('./tariff-dialogs.js');
    try { if (await tariffDialog({ orgId: org.id })) { toast('Tarifa negociada registrada', 'ok'); loadNeg(); } } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  loadNeg(); loadSubs(); loadOpps(); loadTasks(); loadActs();
}
