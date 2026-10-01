/**
 * SOFA · Reclamaciones individuales (Iteración 12, §12–§14 y §17).
 * Listado con filtros por estado, ubicación, médico, ARS y fechas; acciones masivas
 * (mover de estado con ubicación y responsable, auditar) y exportación CSV.
 */
import { html, render as paint, $, $$ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt, busy } from '../utils/ui.js';
import { money, num, date, dateTime, todayISO } from '../utils/formatters.js';
import { claimStatus, CLAIM_GROUPS, CLAIM_STATUS, CLAIM_MOVE_LABELS, DISCREPANCY_STATUS } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { downloadCsv } from '../utils/filters.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';
import { listClaims, claimCounts, claimLocations, claimTransitions, captureProviders, activeArs } from '../services/claims.js';

export async function render(main, ctx) {
  if (ctx.arg) { const m = await import('./claim.js'); return m.render(main, ctx); }
  const role = ctx.role;
  const staff = isStaff(role);
  const money_ = can('claims.money', role);
  const st = { dossier: '', group: role === 'auditor' ? 'custodia' : role === 'capturer' || role === 'client' ? 'captura' : 'todas', status: '', location: '', providerId: '', arsId: '', q: '', from: '', to: '', page: 0 };
  const sel = new Set();
  let rows = []; let transitions = []; let locations = [];

  paint(main, html`
    <div class="page-head"><div class="t"><h2>Reclamaciones</h2>
      <p>Cada servicio es una reclamación con folio, estado, ubicación física y responsable propios.</p></div>
      <div class="toolbar" style="margin:0">
        ${can('claims.capture', role) ? html`<a class="btn primary" href="#/captura">+ Captura rápida</a>` : ''}
        <button class="btn" id="csv">Exportar CSV</button></div></div>
    <div class="grid kpis" id="k"></div>
    <div class="tabs" id="tabs" role="group" aria-label="Grupo" style="margin-top:14px"></div>
    <div class="toolbar">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Folio, paciente, NSS, autorización o radicación">
      <label class="sr-only" for="fs">Estado</label><select class="input" id="fs" style="width:auto"><option value="">Todos los estados</option>${Object.entries(CLAIM_STATUS).map(([k, [l]]) => opt(k, l))}</select>
      <label class="sr-only" for="fl">Ubicación</label><select class="input" id="fl" style="width:auto"><option value="">Todas las ubicaciones</option></select>
      <label class="sr-only" for="fp">Médico</label><select class="input" id="fp" style="width:auto"><option value="">Todos los médicos</option></select>
      <label class="sr-only" for="fa">ARS</label><select class="input" id="fa" style="width:auto"><option value="">Todas las ARS</option></select>
      <label class="sr-only" for="fx">Expediente</label><select class="input" id="fx" style="width:auto"><option value="">Expediente: todos</option><option value="incompleto">Expediente incompleto</option><option value="completo">Expediente completo o con excepción</option></select>
      <label class="sr-only" for="ff">Desde</label><input class="input" id="ff" type="date" style="width:auto" max="${todayISO()}" title="Servicio desde">
      <label class="sr-only" for="ft">Hasta</label><input class="input" id="ft" type="date" style="width:auto" max="${todayISO()}" title="Servicio hasta">
    </div>
    <div id="bulk" class="no-print"></div>
    <div id="l"></div>`);

  const drawTabs = () => $('#tabs', main) && paint($('#tabs', main), html`${Object.entries(CLAIM_GROUPS).map(([k, g]) => html`<button data-g="${k}" aria-pressed="${st.group === k && !st.status}">${g.label}</button>`)}`);
  drawTabs();
  Promise.all([claimLocations(), claimTransitions(), captureProviders(), activeArs()]).then(([locs, trans, provs, ars]) => {
    locations = locs; transitions = trans;
    if (!$('#fl', main)) return;   // el usuario ya salió de la pantalla
    paint($('#fl', main), html`<option value="">Todas las ubicaciones</option>${locs.map((l) => opt(l.code, l.name))}`);
    paint($('#fp', main), html`<option value="">Todos los médicos</option>${provs.map((p) => opt(p.id, p.full_name))}`);
    paint($('#fa', main), html`<option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}`);
    drawBulk();
  }).catch((e) => toast(friendlyError(e), 'bad'));

  claimCounts().then((all) => {
    if (!$('#k', main)) return;
    const c = (list) => all.filter((r) => list.includes(r.claim_status)).length;
    paint($('#k', main), html`
      <div class="kpi"><div class="l">En captura / por retirar</div><div class="v">${num(c(CLAIM_GROUPS.captura.statuses))}</div></div>
      <div class="kpi"><div class="l">En SOFA / validación</div><div class="v">${num(c(CLAIM_GROUPS.custodia.statuses))}</div></div>
      <div class="kpi"><div class="l">En la ARS</div><div class="v">${num(c(CLAIM_GROUPS.ars.statuses))}</div></div>
      <div class="kpi"><div class="l">Requieren atención</div><div class="v" style="${c(CLAIM_GROUPS.atencion.statuses) ? 'color:var(--bad)' : ''}">${num(c(CLAIM_GROUPS.atencion.statuses))}</div><div class="h">Sin configurar, con inconsistencia o devueltas</div></div>`);
  }).catch(() => {});

  /** Acciones masivas: solo las transiciones que el rol puede hacer desde TODOS los estados seleccionados */
  function drawBulk() {
    const box = $('#bulk', main);
    if (!box) return;   // el usuario ya salió de la pantalla (la recarga terminó después)
    if (!sel.size) { paint(box, html``); return; }
    const chosen = rows.filter((r) => sel.has(r.id));
    const fromSet = [...new Set(chosen.map((r) => r.claim_status))];
    const targets = [...new Set(transitions.filter((t) => t.allowed_roles.includes(role)).map((t) => t.to_code))]
      .filter((to) => fromSet.every((f) => transitions.some((t) => t.from_code === f && t.to_code === to && t.allowed_roles.includes(role))));
    const auditable = can('claims.audit', role) && chosen.every((r) => ['retirada', 'en_validacion', 'con_inconsistencia', 'validada'].includes(r.claim_status));
    paint(box, html`<div class="note" style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">
      <b>${num(sel.size)} seleccionadas</b>
      ${targets.map((to) => html`<button class="btn" data-bulk="${to}">${CLAIM_MOVE_LABELS[to] || claimStatus(to)[0]}</button>`)}
      ${auditable ? html`<button class="btn primary" data-audit>Auditar selección</button>` : ''}
      ${can('claims.resubmit', role) && chosen.every((r) => r.claim_status === 'devuelta') && new Set(chosen.map((r) => r.submission_id)).size === 1 ? html`<button class="btn primary" data-rs>Reenviar en radicación complementaria</button>` : ''}
      ${can('dossier.exception', role) && chosen.some((r) => !r.dossier_ok) ? html`<button class="btn" data-dx>Excepción de expediente</button>` : ''}
      ${!targets.length && !auditable && !(can('dossier.exception', role) && chosen.some((r) => !r.dossier_ok)) ? html`<span class="small muted">No hay una acción común para los estados seleccionados.</span>` : ''}
      <button class="btn" data-clear>Quitar selección</button></div>`);
  }

  const list = $('#l', main);
  const load = () => loadInto(list, () => listClaims({ ...st, size: CONFIG.PAGE_SIZE }), (res) => {
    rows = res.data; [...sel].forEach((id) => { if (!rows.some((r) => r.id === id)) sel.delete(id); }); drawBulk();
    return html`<div class="table-wrap"><table class="t cards"><thead><tr>
      <th><label class="sr-only" for="all">Seleccionar todas</label><input type="checkbox" id="all"></th>
      <th>Folio</th><th>Servicio</th><th>Paciente</th>${staff || rows.some((r) => r.provider_name) ? html`<th>Médico · ARS</th>` : ''}<th class="n">Reclamado</th><th>Estado</th><th>Expediente</th><th>Dónde está · responsable</th>${money_ ? html`<th class="n">Saldo</th>` : ''}</tr></thead>
    <tbody>${rows.map((c) => { const [l, cl] = claimStatus(c.claim_status); return html`<tr data-id="${c.id}" style="cursor:pointer">
      <td data-l="Seleccionar"><input type="checkbox" data-sel="${c.id}" ${sel.has(c.id) ? 'checked' : ''} aria-label="Seleccionar ${c.folio}"></td>
      <td data-l="Folio"><a href="#/reclamaciones/${c.id}"><b class="mono">${c.folio}</b></a><div class="small muted">${date(c.service_date)}</div>${c.submission_folio ? html`<div class="small muted mono">${c.submission_folio}</div>` : ''}</td>
      <td data-l="Servicio">${c.service_name}<div class="small muted">${[c.simon && `SIMON ${c.simon}`, c.cups && `CUPS ${c.cups}`].filter(Boolean).join(' · ') || 'Sin códigos'}</div></td>
      <td data-l="Paciente">${c.patient_name}<div class="small muted">NSS ${c.member_number || '—'}${c.authorization_number ? ` · Aut. ${c.authorization_number}` : ''}</div></td>
      <td data-l="Médico · ARS">${c.provider_name}<div class="small muted">${c.ars_name}</div></td>
      <td data-l="Reclamado" class="n">${money(c.claimed)}${c.tariff_amount != null && Math.abs(Number(c.claimed) - Number(c.tariff_amount) * 1) > 0.005 && c.discrepancy_status ? html`<div><span class="pill ${DISCREPANCY_STATUS[c.discrepancy_status]?.[1] || ''}" title="Tarifa contractual ${money(c.tariff_amount)}">${DISCREPANCY_STATUS[c.discrepancy_status]?.[0] || ''}</span></div>` : ''}${!c.contracted ? html`<div><span class="pill bad">No contratado</span></div>` : ''}</td>
      <td data-l="Estado"><span class="pill ${cl}">${l}</span><div class="small muted">${dateTime(c.status_changed_at)}</div></td>
      <td data-l="Expediente">${c.dossier_ok ? (c.dossier_missing ? html`<span class="pill warn">Con excepción</span>` : html`<span class="pill ok">Completo</span>`) : html`<span class="pill bad">Faltan ${c.dossier_missing}</span>`}</td>
      <td data-l="Dónde está">${c.location_name || '—'}<div class="small muted">${c.custodian_name || 'Sin responsable asignado'}</div><div class="small">→ ${c.next_step}</div></td>
      ${money_ ? html`<td data-l="Saldo" class="n">${['radicada', 'en_proceso_ars', 'pago_parcial', 'glosada', 'pagada', 'cerrada', 'devuelta'].includes(c.claim_status) ? money(c.balance) : '—'}${Number(c.glosado) > 0 ? html`<div class="small" style="color:var(--bad)">Glosado ${money(c.glosado)}</div>` : ''}</td>` : ''}
    </tr>`; })}</tbody></table></div>${pager(res.count, st.page)}`;
  }, { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin reclamaciones', 'No hay reclamaciones con estos filtros.', can('claims.capture', role) ? html`<a class="btn primary" href="#/captura">Ir a Captura rápida</a>` : '') });

  // ------------------------------------------------------------ eventos
  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-g]'); if (!b) return; st.group = b.dataset.g; st.status = ''; $('#fs', main).value = ''; st.page = 0; drawTabs(); load(); });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
  [['#fx', 'dossier'], ['#fs', 'status'], ['#fl', 'location'], ['#fp', 'providerId'], ['#fa', 'arsId'], ['#ff', 'from'], ['#ft', 'to']].forEach(([s, k]) =>
    $(s, main).addEventListener('change', (e) => { st[k] = e.target.value; st.page = 0; if (k === 'status') drawTabs(); load(); }));
  list.addEventListener('change', (e) => {
    if (e.target.id === 'all') { $$('[data-sel]', list).forEach((c) => { c.checked = e.target.checked; if (c.checked) sel.add(c.dataset.sel); else sel.delete(c.dataset.sel); }); drawBulk(); return; }
    const c = e.target.closest('[data-sel]'); if (c) { if (c.checked) sel.add(c.dataset.sel); else sel.delete(c.dataset.sel); drawBulk(); }
  });
  list.addEventListener('click', (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    if (e.target.closest('input,a,label')) return;
    const row = e.target.closest('tr[data-id]'); if (row) location.hash = `#/reclamaciones/${row.dataset.id}`;
  });
  $('#bulk', main).addEventListener('click', async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.clear != null) { sel.clear(); $$('[data-sel]', list).forEach((c) => { c.checked = false; }); drawBulk(); return; }
    const { moveDialog, auditDialog } = await import('./claim-dialogs.js');
    try {
      if (b.dataset.bulk) {
        const done = await moveDialog([...sel], b.dataset.bulk, { role, transitions, locations, count: sel.size });
        if (done != null) { toast(`${num(done)} reclamaciones actualizadas`, 'ok'); sel.clear(); load(); }
      } else if (b.dataset.rs != null) {
        const { resubmitDialog } = await import('./claim-dialogs.js');
        const chosen = rows.filter((r) => sel.has(r.id));
        const sub = await resubmitDialog(chosen.map((r) => r.id), chosen[0]?.submission_folio);
        if (sub) { toast('Radicación complementaria creada', 'ok'); location.hash = `#/radicaciones/${sub}`; }
      } else if (b.dataset.dx != null) {
        const { exceptionDialog } = await import('./dossier-card.js');
        const n = await exceptionDialog(rows.filter((r) => sel.has(r.id) && !r.dossier_ok).map((r) => r.id));
        if (n != null) { toast(`Excepción registrada en ${num(n)} reclamaciones`, 'ok'); sel.clear(); load(); }
      } else if (b.dataset.audit != null) {
        const done = await auditDialog([...sel]);
        if (done != null) { toast(`${num(done)} reclamaciones auditadas`, 'ok'); sel.clear(); load(); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  $('#csv', main).addEventListener('click', (e) => busy(e.currentTarget, async () => {
    const all = []; let page = 0;
    for (;;) { const r = await listClaims({ ...st, page, size: 1000 }); all.push(...r.data); if (r.data.length < 1000 || all.length >= 20000) break; page += 1; }
    const head = ['Folio', 'Fecha servicio', 'Médico', 'ARS', 'Radicación', 'Paciente', 'NSS', 'Autorización', 'Servicio', 'SIMON', 'CUPS', 'Tarifa contractual', 'Reclamado', 'Expediente', 'Estado', 'Ubicación', 'Responsable', 'Próximo paso'];
    if (money_) head.push('Pagado', 'Glosado', 'Saldo');
    downloadCsv(`reclamaciones_${todayISO()}.csv`, head, all.map((c) => {
      const r = [c.folio, c.service_date, c.provider_name, c.ars_name, c.submission_folio, c.patient_name, c.member_number, c.authorization_number, c.service_name, c.simon, c.cups,
        c.tariff_amount, c.claimed, c.dossier_ok ? (c.dossier_missing ? 'Con excepción' : 'Completo') : `Faltan ${c.dossier_missing}`, claimStatus(c.claim_status)[0], c.location_name, c.custodian_name, c.next_step];
      if (money_) r.push(c.paid, c.glosado, c.balance);
      return r;
    }));
  }));
  load();
}
