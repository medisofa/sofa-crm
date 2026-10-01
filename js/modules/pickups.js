/**
 * SOFA · Retiros físicos de reclamaciones (Iteración 12, §15).
 * Programar el retiro (médico + reclamaciones esperadas), confirmarlo en el consultorio
 * (recibidas, quién entrega, quién recibe, diferencias) y emitir el
 * “Reporte de Retiro de Reclamaciones” con folio RET imprimible / exportable.
 */
import { html, render as paint, $, $$ } from '../utils/dom.js';
import { loadInto, loadingView, emptyView, errorView, toast, friendlyError, opt, busy, formDialog, fieldError } from '../utils/ui.js';
import { money, num, date, dateTime } from '../utils/formatters.js';
import { PICKUP_STATUS, claimStatus } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { downloadCsv } from '../utils/filters.js';
import { CONFIG } from '../config.js';
import { pager } from './clients.js';
import {
  listPickups, getPickup, pickupItems, pendingPickupClaims, createPickup, confirmPickup, cancelPickup, captureProviders
} from '../services/claims.js';

export async function render(main, ctx) {
  if (ctx.arg) return renderDetail(main, ctx);
  const role = ctx.role; const manage = can('pickups.manage', role);
  const st = { status: '', providerId: '', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Retiros físicos</h2><p>Retiro de las reclamaciones en papel en cada consultorio, con folio RET, cantidades y responsables.</p></div>
      ${manage ? html`<button class="btn primary" id="new">+ Programar retiro</button>` : ''}</div>
    <div class="toolbar">
      <label class="sr-only" for="ps">Estado</label><select class="input" id="ps" style="width:auto"><option value="">Todos</option>${Object.entries(PICKUP_STATUS).map(([k, [l]]) => opt(k, l))}</select>
      <label class="sr-only" for="pp">Médico</label><select class="input" id="pp" style="width:auto"><option value="">Todos los médicos</option></select>
    </div>
    ${manage ? html`<div class="card" style="margin-bottom:14px"><h2>Pendientes de retiro por médico</h2><div id="pend"></div></div>` : ''}
    <div id="l"></div>`);
  const provs = await captureProviders().catch(() => []);
  paint($('#pp', main), html`<option value="">Todos los médicos</option>${provs.map((p) => opt(p.id, p.full_name))}`);

  const list = $('#l', main);
  const load = () => loadInto(list, () => listPickups({ ...st, size: CONFIG.PAGE_SIZE }), ({ data, count }) => html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Folio</th><th>Médico</th><th>Estado</th><th class="n">Esperadas</th><th class="n">Recibidas</th><th>Entregó / recibió</th><th>Fecha</th></tr></thead>
    <tbody>${data.map((r) => { const [l, c] = PICKUP_STATUS[r.status] || [r.status, '']; const diff = r.received_count != null && r.received_count !== r.expected_count; return html`<tr data-id="${r.id}" style="cursor:pointer">
      <td data-l="Folio"><a href="#/retiros/${r.id}"><b class="mono">${r.folio}</b></a></td>
      <td data-l="Médico">${r.providers?.full_name || '—'}${isStaff(role) ? html`<div class="small muted">${r.organizations?.legal_name || ''}</div>` : ''}</td>
      <td data-l="Estado"><span class="pill ${c}">${l}</span>${diff ? html` <span class="pill bad">Con diferencia</span>` : ''}</td>
      <td data-l="Esperadas" class="n">${num(r.expected_count)}</td><td data-l="Recibidas" class="n">${r.received_count == null ? '—' : num(r.received_count)}</td>
      <td data-l="Entregó / recibió">${r.delivered_by || '—'}<div class="small muted">${r.received_by_label || ''}</div></td>
      <td data-l="Fecha">${r.confirmed_at ? dateTime(r.confirmed_at) : date(r.received_on)}</td></tr>`; })}</tbody></table></div>${pager(count, st.page)}`,
  { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin retiros', 'No hay retiros registrados con estos filtros.') });

  async function loadPending() {
    const box = $('#pend', main); if (!box) return;
    paint(box, loadingView(2));
    try {
      const rows = (await Promise.all(provs.map(async (p) => ({ p, claims: await pendingPickupClaims(p.id) })))).filter((x) => x.claims.length);
      paint(box, rows.length ? html`<div class="list">${rows.map(({ p, claims }) => { const old = claims[0]; return html`<div class="li"><div class="b">
        <div class="t1">${p.full_name} · <b>${num(claims.length)}</b> reclamaciones · ${money(claims.reduce((t, c) => t + Number(c.claimed), 0))}</div>
        <div class="t2">La más antigua: ${date(old.service_date)} (${old.folio})</div></div><button class="btn" data-plan="${p.id}">Programar retiro</button></div>`; })}</div>`
        : html`<p class="small muted">No hay reclamaciones esperando retiro.</p>`);
    } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
  }

  async function plan(providerId) {
    try {
      const id = await newPickupDialog(provs, providerId);
      if (id) { toast('Retiro programado', 'ok'); location.hash = `#/retiros/${id}`; }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  }
  $('#new', main)?.addEventListener('click', () => plan(''));
  main.addEventListener('click', (e) => { const b = e.target.closest('[data-plan]'); if (b) plan(b.dataset.plan); });
  $('#ps', main).addEventListener('change', (e) => { st.status = e.target.value; st.page = 0; load(); });
  $('#pp', main).addEventListener('change', (e) => { st.providerId = e.target.value; st.page = 0; load(); });
  list.addEventListener('click', (e) => {
    const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
    const row = e.target.closest('tr[data-id]'); if (row && !e.target.closest('a')) location.hash = `#/retiros/${row.dataset.id}`;
  });
  load(); loadPending();
}

/** Programar: elegir médico y marcar las reclamaciones que se esperan en el consultorio */
function newPickupDialog(provs, providerId) {
  return formDialog({
    title: 'Programar retiro de reclamaciones', submitLabel: 'Programar retiro', wide: true,
    body: html`<div class="field"><label for="np_p">Médico *</label><select id="np_p" name="provider"><option value="">Seleccione…</option>${provs.map((p) => opt(p.id, p.full_name, providerId))}</select></div>
      <div id="np_l"></div><div class="field"><label for="np_n">Notas para el mensajero</label><input id="np_n" name="notes" maxlength="300"></div>`,
    onOpen: (form) => {
      const box = form.querySelector('#np_l');
      const draw = async () => {
        const p = form.elements.provider.value; if (!p) { paint(box, html`<p class="small muted">Seleccione el médico para ver sus reclamaciones pendientes.</p>`); return; }
        paint(box, loadingView(2));
        try {
          const rows = await pendingPickupClaims(p);
          paint(box, rows.length ? html`<p class="small"><label class="check"><input type="checkbox" id="np_all" checked> Todas (${num(rows.length)})</label></p>
            <div class="list" style="max-height:300px;overflow:auto">${rows.map((c) => html`<label class="li" style="cursor:pointer"><input type="checkbox" name="line" value="${c.id}" checked>
              <div class="b"><div class="t1"><span class="mono">${c.folio}</span> · ${c.patient_name}</div><div class="t2">${date(c.service_date)} · ${c.service_name} · ${c.ars_name} · ${claimStatus(c.claim_status)[0]}</div></div></label>`)}</div>`
            : html`<div class="note">Este médico no tiene reclamaciones capturadas pendientes de retiro.</div>`);
          form.querySelector('#np_all')?.addEventListener('change', (e) => $$('input[name=line]', form).forEach((c) => { c.checked = e.target.checked; }));
        } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); }
      };
      form.elements.provider.addEventListener('change', draw); draw();
    },
    onSubmit: async (d, form) => {
      if (!d.provider) { fieldError(form.elements.provider, 'Seleccione el médico'); return false; }
      const lines = $$('input[name=line]:checked', form).map((c) => c.value);
      if (!lines.length) { toast('Seleccione al menos una reclamación', 'bad'); return false; }
      return createPickup(d.provider, lines, d.notes || null);
    }
  });
}

async function renderDetail(main, ctx) {
  const id = ctx.arg; const role = ctx.role;
  paint(main, html`<div id="pk">${loadingView(5)}</div>`);
  const box = $('#pk', main);
  let S = {};
  async function refresh() {
    try {
      const r = await getPickup(id);
      if (!r) { paint(box, emptyView('Retiro no encontrado', 'No existe o no tienes acceso.', html`<a class="btn" href="#/retiros">Volver</a>`)); return; }
      S = { r, items: await pickupItems(id) }; draw();
    } catch (err) { paint(box, errorView(err, 'pk')); box.querySelector('[data-retry]')?.addEventListener('click', refresh); }
  }
  function draw() {
    const { r, items } = S; const [l, c] = PICKUP_STATUS[r.status] || [r.status, ''];
    ctx.setTitle(r.folio);
    const open = r.status === 'borrador'; const manage = can('pickups.manage', role);
    const total = items.reduce((t, i) => t + Number(i.claim?.claimed || 0), 0);
    paint(box, html`
      <div class="page-head no-print"><div class="t"><p><a href="#/retiros">← Retiros</a></p><h2><span class="mono">${r.folio}</span> <span class="pill ${c}">${l}</span></h2></div>
        <div class="toolbar" style="margin:0">
          ${open && manage ? html`<button class="btn primary" id="confirm">Confirmar retiro</button>` : ''}
          ${open && can('pickups.manage', role) && role !== 'assistant' ? html`<button class="btn danger" id="cancel">Anular</button>` : ''}
          <button class="btn" id="print">Imprimir / PDF</button><button class="btn" id="csv">Exportar CSV</button></div></div>
      <div class="card" id="report">
        <div style="display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:flex-start">
          <div><h2 style="margin:0">Reporte de Retiro de Reclamaciones</h2><div class="small muted">SOFA · Soluciones de Facturación Médica</div></div>
          <div style="text-align:right"><div class="mono" style="font-size:20px;font-weight:700">${r.folio}</div><div class="small">${r.status === 'confirmado' ? `Confirmado ${dateTime(r.confirmed_at)}` : `Programado ${date(r.received_on)}`}</div></div></div>
        <dl class="kv" style="margin-top:12px">
          <dt>Médico</dt><dd>${r.providers?.full_name || '—'}</dd><dt>Cliente</dt><dd>${r.organizations?.legal_name || '—'}</dd>
          <dt>Cantidad esperada</dt><dd>${num(r.expected_count)}</dd><dt>Cantidad recibida</dt><dd>${r.received_count == null ? '— (pendiente de confirmar)' : html`<b>${num(r.received_count)}</b>`}</dd>
          <dt>Entregó (consultorio)</dt><dd>${r.delivered_by || '______________________'}</dd><dt>Recibió (SOFA)</dt><dd>${r.received_by_label || '______________________'}</dd>
          <dt>Diferencias</dt><dd>${r.differences || (r.status === 'confirmado' ? 'Ninguna' : '')}</dd><dt>Observaciones</dt><dd>${r.notes || '—'}</dd>
          <dt>Monto total reclamado</dt><dd>${money(total)}</dd></dl>
        <div class="table-wrap" style="margin-top:10px"><table class="t"><thead><tr><th>#</th><th>Folio</th><th>Fecha</th><th>Paciente · NSS</th><th>Autorización</th><th>Servicio</th><th>ARS</th><th class="n">Monto</th><th>Recibida</th><th>Observación</th></tr></thead>
          <tbody>${items.map((i, n) => html`<tr><td>${n + 1}</td><td class="mono">${i.claim?.folio || '—'}</td><td>${date(i.claim?.service_date)}</td><td>${i.claim?.patient_name || ''}<div class="small muted">${i.claim?.member_number || ''}</div></td>
            <td class="mono">${i.claim?.authorization_number || '—'}</td><td>${i.claim?.service_name || ''}</td><td>${i.claim?.ars_name || ''}</td><td class="n">${money(i.claim?.claimed)}</td>
            <td>${i.received == null ? '☐' : i.received ? '✓ Sí' : html`<b style="color:var(--bad)">✕ No</b>`}</td><td>${i.observation || ''}</td></tr>`)}</tbody></table></div>
        <div class="grid two" style="margin-top:28px"><div style="border-top:1px solid #999;padding-top:6px" class="small">Firma de quien entrega</div><div style="border-top:1px solid #999;padding-top:6px" class="small">Firma de quien recibe (SOFA)</div></div>
      </div>`);
    $('#print', box).addEventListener('click', () => window.print());
    $('#csv', box).addEventListener('click', () => downloadCsv(`${r.folio}.csv`, ['Retiro', 'Folio', 'Fecha servicio', 'Paciente', 'NSS', 'Autorización', 'Servicio', 'ARS', 'Monto', 'Recibida', 'Observación'],
      items.map((i) => [r.folio, i.claim?.folio, i.claim?.service_date, i.claim?.patient_name, i.claim?.member_number, i.claim?.authorization_number, i.claim?.service_name, i.claim?.ars_name, i.claim?.claimed,
        i.received == null ? '' : i.received ? 'Sí' : 'No', i.observation])));
    $('#confirm', box)?.addEventListener('click', confirmFlow);
    $('#cancel', box)?.addEventListener('click', async (e) => {
      const reason = await formDialog({ title: `Anular ${r.folio}`, submitLabel: 'Anular retiro',
        body: html`<div class="field"><label for="cx">Motivo (mín. 5 caracteres) *</label><textarea id="cx" name="reason" rows="2" class="input"></textarea></div><p class="small muted">Las reclamaciones vuelven a quedar disponibles para otro retiro.</p>`,
        onSubmit: async (d, f) => { if ((d.reason || '').trim().length < 5) { fieldError(f.elements.reason, 'Mínimo 5 caracteres'); return false; } return d.reason.trim(); } });
      if (!reason) return;
      busy(e.target, async () => { try { await cancelPickup(id, reason); toast('Retiro anulado', 'ok'); refresh(); } catch (err) { toast(friendlyError(err), 'bad'); } });
    });
  }
  async function confirmFlow() {
    const { items } = S;
    const res = await formDialog({
      title: `Confirmar retiro ${S.r.folio}`, submitLabel: 'Confirmar recepción', wide: true,
      body: html`<p class="small">Marque cada reclamación entregada físicamente. Las no entregadas quedan pendientes con su observación.</p>
        <div class="table-wrap"><table class="t"><thead><tr><th>Recibida</th><th>Folio · paciente</th><th>Observación</th></tr></thead><tbody>
        ${items.map((i) => html`<tr><td><input type="checkbox" name="rc_${i.service_line_id}" checked aria-label="Recibida ${i.claim?.folio}"></td><td><span class="mono">${i.claim?.folio}</span> · ${i.claim?.patient_name}</td>
          <td><input name="ob_${i.service_line_id}" maxlength="200" style="width:100%" aria-label="Observación ${i.claim?.folio}"></td></tr>`)}</tbody></table></div>
        <div class="form-grid" style="margin-top:10px">
          <div class="field"><label for="cf_d">Quién entrega en el consultorio *</label><input id="cf_d" name="delivered" maxlength="120" required></div>
          <div class="field"><label for="cf_r">Quién recibe por SOFA</label><input id="cf_r" name="receiver" maxlength="120" placeholder="Por defecto, su usuario"></div>
          <div class="field"><label for="cf_l">Ubicación después del retiro</label><select id="cf_l" name="location">${opt('oficina_sofa', 'Oficina SOFA', 'oficina_sofa')}${opt('mensajero', 'En poder del mensajero')}</select></div>
          <div class="field" style="grid-column:1/-1"><label for="cf_x">Diferencias (obligatorio si falta alguna)</label><textarea id="cf_x" name="differences" rows="2" class="input"></textarea></div></div>
        <p class="small" id="cf_sum" aria-live="polite"></p>`,
      onOpen: (form) => { const sum = () => { const n = items.filter((i) => form.elements[`rc_${i.service_line_id}`].checked).length; form.querySelector('#cf_sum').textContent = `Esperadas ${items.length} · recibidas ${n}${n < items.length ? ` · faltan ${items.length - n}` : ''}`; }; form.addEventListener('change', sum); sum(); },
      onSubmit: async (d, form) => {
        if ((d.delivered || '').trim().length < 3) { fieldError(form.elements.delivered, 'Indique quién entrega'); return false; }
        const received = items.filter((i) => d[`rc_${i.service_line_id}`]).map((i) => i.service_line_id);
        if (!received.length) { toast('Marque al menos una reclamación recibida', 'bad'); return false; }
        if (received.length < items.length && (d.differences || '').trim().length < 5) { fieldError(form.elements.differences, 'Describa la diferencia'); return false; }
        const observations = Object.fromEntries(items.map((i) => [i.service_line_id, (d[`ob_${i.service_line_id}`] || '').trim()]).filter(([, v]) => v));
        return confirmPickup(id, { received, deliveredBy: d.delivered.trim(), receivedBy: d.receiver?.trim() || null, differences: d.differences?.trim() || null, location: d.location, observations });
      }
    });
    if (res) { toast(`Retiro confirmado: ${res.received} de ${res.expected} recibidas`, res.missing ? 'bad' : 'ok'); refresh(); }
  }
  refresh();
}
