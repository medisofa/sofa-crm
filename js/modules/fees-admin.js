/**
 * SOFA · Honorarios 1.7: esquema de facturación (fijo / % / mixto), servicios por proyecto con plan de pagos,
 * factura con varios conceptos y servicios, y limpieza del libro (Super Admin).
 * El NCF de las facturas de SOFA lo emite el sistema fiscal externo (decisión 02/10/2026).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, toast, friendlyError, opt, formDialog, fieldError } from '../utils/ui.js';
import { money, date, todayISO } from '../utils/formatters.js';
import { SERVICES, SERVICE_PLAN } from '../utils/constants.js';
import { can } from '../utils/permissions.js';
import { clientOptions } from '../services/bi.js';
import { feeScheme, setFeeScheme, listServiceContracts, createServiceContract, cancelServiceContract, createManualInvoice, pendingFeesOf, ledgerPreview, ledgerCleanup } from '../services/finance.js';

const PROJECT_SERVICES = SERVICES.filter((s) => s.code !== 'facturacion');
const svcName = (c) => SERVICES.find((s) => s.code === c)?.name || c;
const MODE = { fijo: 'Monto fijo mensual', porcentaje: '% de lo cobrado', mixto: 'Mixto: fijo + % de lo cobrado' };
const monthStart = (ym) => `${ym}-01`;

// ---------------------------------------------------------------- 1. Esquema de honorarios
export async function schemeDialog(ctx, org) {
  const s = await feeScheme(org.id);
  const cur = s?.fixed && s?.rate ? 'mixto' : s?.rate ? 'porcentaje' : 'fijo';
  return formDialog({
    title: `Esquema de honorarios · ${org.name}`, submitLabel: 'Aplicar esquema', wide: true,
    body: html`<p class="small">Vigente: ${s?.fixed || s?.rate ? html`<b>${[s.fixed && `fijo ${money(s.fixed)} al mes`, s.rate && `${s.rate} % de lo cobrado`].filter(Boolean).join(' + ')}</b>${s.since ? ` · desde ${date(s.since)}` : ''}` : 'sin esquema'}</p>
      <fieldset style="border:0;padding:0"><legend class="small" style="font-weight:600">Nuevo esquema</legend>
        ${Object.entries(MODE).map(([k, l]) => html`<label class="check" style="display:flex;margin:4px 0"><input type="radio" name="mode" value="${k}" ${k === cur ? 'checked' : ''}> ${l}</label>`)}</fieldset>
      <div class="form-grid">
        <div class="field"><label for="fs_f">Monto fijo mensual (RD$)</label><input id="fs_f" name="fixed" type="number" min="0" step="0.01" value="${s?.fixed || ''}"></div>
        <div class="field"><label for="fs_r">% de lo cobrado a las ARS</label><input id="fs_r" name="rate" type="number" min="0" max="100" step="0.01" value="${s?.rate || ''}"></div>
        <div class="field"><label for="fs_d">Rige desde *</label><input id="fs_d" name="from" type="date" value="${todayISO().slice(0, 8)}01"></div></div>
      <p class="small muted">La regla anterior se cierra el día antes y queda en el historial. Lo no facturado desde esa fecha se recalcula; un cambio a mitad de mes se prorratea. No se puede cambiar sobre meses ya facturados.</p>
      ${s?.history?.length ? html`<details><summary class="small">Historial (${s.history.length})</summary><div class="table-wrap"><table class="t"><thead><tr><th>Tipo</th><th class="n">Valor</th><th>Desde</th><th>Hasta</th></tr></thead><tbody>
        ${s.history.map((h) => html`<tr><td>${h.basis === 'cuota_mensual' ? 'Fijo mensual' : '% de lo cobrado'}</td><td class="n">${h.basis === 'cuota_mensual' ? money(h.fixed) : `${h.rate} %`}</td><td>${date(h.from)}</td><td>${h.to ? date(h.to) : 'vigente'}</td></tr>`)}</tbody></table></div></details>` : ''}`,
    onOpen: (f) => { const sync = () => { const m = f.elements.mode.value; f.elements.fixed.disabled = m === 'porcentaje'; f.elements.rate.disabled = m === 'fijo'; }; f.addEventListener('change', sync); sync(); },
    onSubmit: async (d, f) => {
      if (d.mode !== 'porcentaje' && !(Number(d.fixed) > 0)) { fieldError(f.elements.fixed, 'Indique el monto fijo'); return false; }
      if (d.mode !== 'fijo' && !(Number(d.rate) > 0 && Number(d.rate) <= 100)) { fieldError(f.elements.rate, 'Entre 0 y 100'); return false; }
      if (!d.from) { fieldError(f.elements.from, 'Indique la fecha'); return false; }
      return setFeeScheme(org.id, d.mode, d.mode === 'porcentaje' ? null : Number(d.fixed), d.mode === 'fijo' ? null : Number(d.rate), d.from);
    }
  });
}

// ---------------------------------------------------------------- 2. Servicios por proyecto
const schedulePreview = (total, plan, n, pcts, start) => {
  const T = Number(total) || 0; if (!T || !start) return [];
  const N = plan === 'unico' ? 1 : plan === 'cuotas' ? Math.max(0, Number(n) || 0) : 3;
  const P = plan === 'porcentajes' ? pcts.map(Number) : Array(N).fill(100 / (N || 1));
  const out = []; let acc = 0;
  for (let i = 0; i < N; i += 1) {
    const d = new Date(`${start}T12:00:00`); d.setMonth(d.getMonth() + i);
    const amt = i === N - 1 ? Math.round((T - acc) * 100) / 100 : plan === 'cuotas' ? Math.round((T / N) * 100) / 100 : Math.round(T * P[i]) / 100;
    acc += amt; out.push({ seq: i + 1, due: d.toISOString().slice(0, 10), pct: P[i], amount: amt });
  }
  return out;
};

export async function projectDialog(ctx, preOrg = null) {
  const clients = await clientOptions().catch(() => []);
  return formDialog({
    title: 'Nuevo servicio por proyecto', submitLabel: 'Crear y programar pagos', wide: true,
    body: html`<div class="form-grid">
      <div class="field" style="grid-column:1/-1"><label for="pj_o">Cliente *</label><select id="pj_o" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name, preOrg))}</select></div>
      <div class="field"><label for="pj_s">Servicio *</label><select id="pj_s" name="service">${PROJECT_SERVICES.map((s) => opt(s.code, s.name, 'codificacion'))}</select></div>
      <div class="field"><label for="pj_t">Monto total (RD$) *</label><input id="pj_t" name="total" type="number" min="0.01" step="0.01"></div>
      <div class="field" style="grid-column:1/-1"><label for="pj_d">Descripción *</label><input id="pj_d" name="description" maxlength="150" placeholder="Codificación de tarifarios ARS del consultorio"></div>
      <div class="field"><label for="pj_p">Plan de pagos *</label><select id="pj_p" name="plan">${Object.entries(SERVICE_PLAN).map(([k, l]) => opt(k, l, 'porcentajes'))}</select></div>
      <div class="field"><label for="pj_st">Primer pago *</label><input id="pj_st" name="start" type="date" value="${todayISO()}"></div>
      <div class="field" data-plan="cuotas"><label for="pj_n">Número de cuotas (2 a 24)</label><input id="pj_n" name="installments" type="number" min="2" max="24" value="3"></div>
      <div class="field" data-plan="porcentajes" style="grid-column:1/-1"><span class="small" style="font-weight:600">Porcentaje de cada pago (deben sumar 100)</span>
        <div style="display:flex;gap:8px">${[50, 25, 25].map((v, i) => html`<label class="sr-only" for="pj_p${i}">Pago ${i + 1}</label><input class="input" id="pj_p${i}" name="p${i}" type="number" min="1" max="98" step="0.5" value="${v}" style="width:90px">`)}</div></div>
      </div><div id="pj_prev" aria-live="polite"></div>`,
    onOpen: (f) => {
      const upd = () => {
        const plan = f.elements.plan.value; f.querySelectorAll('[data-plan]').forEach((el) => { el.style.display = el.dataset.plan === plan ? '' : 'none'; });
        const pcts = [0, 1, 2].map((i) => Number(f.elements[`p${i}`].value || 0)); const sum = pcts.reduce((a, b) => a + b, 0);
        const rows = schedulePreview(f.elements.total.value, plan, f.elements.installments.value, pcts, f.elements.start.value);
        paint(f.querySelector('#pj_prev'), rows.length ? html`<div class="table-wrap"><table class="t"><thead><tr><th>Pago</th><th>Vence</th><th class="n">%</th><th class="n">Monto</th></tr></thead><tbody>
          ${rows.map((r) => html`<tr><td>${r.seq} de ${rows.length}</td><td>${date(r.due)}</td><td class="n">${Math.round(r.pct * 100) / 100} %</td><td class="n">${money(r.amount)}</td></tr>`)}</tbody></table></div>
          ${plan === 'porcentajes' && Math.abs(sum - 100) > 0.001 ? html`<p class="small" style="color:var(--bad)">Los porcentajes suman ${sum} %: deben sumar 100.</p>` : ''}
          <p class="small muted">Cada pago entra en la factura de SOFA del mes en que vence, junto con los demás servicios del cliente.</p>` : html``);
      };
      f.addEventListener('input', upd); f.addEventListener('change', upd); upd();
    },
    onSubmit: async (d, f) => {
      if (!d.org) { fieldError(f.elements.org, 'Elija el cliente'); return false; }
      if (!(Number(d.total) > 0)) { fieldError(f.elements.total, 'Indique el monto'); return false; }
      if ((d.description || '').trim().length < 3) { fieldError(f.elements.description, 'Describa el servicio'); return false; }
      const pcts = [d.p0, d.p1, d.p2].map(Number);
      if (d.plan === 'porcentajes' && Math.abs(pcts.reduce((a, b) => a + b, 0) - 100) > 0.001) { fieldError(f.elements.p0, 'Deben sumar 100'); return false; }
      if (d.plan === 'cuotas' && !(Number(d.installments) >= 2 && Number(d.installments) <= 24)) { fieldError(f.elements.installments, 'De 2 a 24'); return false; }
      return createServiceContract({ org: d.org, service: d.service, description: d.description.trim(), total: d.total, plan: d.plan, installments: d.installments, pcts, start: d.start });
    }
  });
}

export function renderProjects(box, ctx) {
  const manage = can('fees.manage', ctx.role);
  const load = () => loadInto(box, () => listServiceContracts(), (rows) => html`
    ${manage ? html`<button class="btn primary sm" id="pj_new" style="margin-bottom:8px">+ Servicio por proyecto</button>` : ''}
    ${rows.length ? html`<div class="list">${rows.map((c) => html`<div class="li" style="align-items:flex-start"><div class="b">
        <div class="t1"><span class="mono">${c.folio}</span> · ${c.legal_name} · <b>${c.service_name}</b> · ${money(c.total_amount)} ${c.status === 'cancelado' ? html`<span class="pill bad">Cancelado</span>` : ''}</div>
        <div class="t2">${c.description} · ${SERVICE_PLAN[c.plan]} · facturado ${money(c.invoiced)}${c.cancel_reason ? ` · ${c.cancel_reason}` : ''}</div>
        <div class="t2">${(c.schedule || []).map((s) => html`<span class="pill ${s.status === 'cancelado' ? '' : s.invoice_id ? 'ok' : 'info'}" style="margin:2px 4px 0 0" title="${s.invoice_folio || ''}">${s.seq}/${s.n} · ${date(s.due_on)} · ${money(s.amount)}${s.invoice_folio ? ` · ${s.invoice_folio}` : s.status === 'cancelado' ? ' · cancelado' : ''}</span>`)}</div></div>
        ${manage && c.status === 'activo' ? html`<button class="btn sm" data-cancel-pj="${c.id}">Cancelar</button>` : ''}</div>`)}</div>`
      : html`<p class="small muted">Sin servicios por proyecto. Úsalos para Codificación, Habilitación y otros cobros independientes de la facturación de reclamaciones.</p>`}`,
    { isEmpty: () => false });
  box.addEventListener('click', async (e) => {
    try {
      if (e.target.closest('#pj_new')) { if (await projectDialog(ctx)) { toast('Servicio creado y pagos programados', 'ok'); load(); } }
      const b = e.target.closest('[data-cancel-pj]');
      if (b) {
        const r = await formDialog({ title: 'Cancelar servicio por proyecto', submitLabel: 'Cancelar servicio',
          body: html`<p class="small">Se quitan los pagos que aún no se facturaron; lo ya facturado se conserva.</p><div class="field"><label for="cp_r">Motivo (mínimo 10 caracteres) *</label><textarea id="cp_r" name="reason" rows="2" class="input"></textarea></div>`,
          onSubmit: async (d, f) => { if ((d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; } await cancelServiceContract(b.dataset.cancelPj, d.reason.trim()); return true; } });
        if (r) { toast('Servicio cancelado', 'ok'); load(); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
  return { reload: load };
}

// ---------------------------------------------------------------- 3. Factura con varios conceptos y servicios
export async function manualInvoiceDialog(ctx) {
  const clients = await clientOptions().catch(() => []);
  let pending = [];
  const itemRow = (i) => html`<div class="form-grid" data-item="${i}" style="grid-template-columns:1.2fr 2fr .6fr 1fr auto;align-items:end;margin-bottom:6px">
    <div class="field"><label for="it_s${i}">Servicio</label><select id="it_s${i}" name="s${i}">${SERVICES.map((s) => opt(s.code, s.name, 'codificacion'))}</select></div>
    <div class="field"><label for="it_d${i}">Descripción</label><input id="it_d${i}" name="d${i}" maxlength="150"></div>
    <div class="field"><label for="it_q${i}">Cant.</label><input id="it_q${i}" name="q${i}" type="number" min="1" step="1" value="1"></div>
    <div class="field"><label for="it_u${i}">Precio (RD$)</label><input id="it_u${i}" name="u${i}" type="number" min="0.01" step="0.01"></div>
    <button type="button" class="btn sm" data-del-item="${i}" aria-label="Quitar concepto">×</button></div>`;
  return formDialog({
    title: 'Nueva factura de SOFA', submitLabel: 'Emitir factura', wide: true,
    body: html`<div class="form-grid"><div class="field"><label for="mi_o">Cliente *</label><select id="mi_o" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name))}</select></div>
      <div class="field"><label for="mi_m">Mes de la factura *</label><input id="mi_m" name="month" type="month" value="${todayISO().slice(0, 7)}"></div></div>
      <label class="check"><input type="checkbox" name="pending" id="mi_p" checked> Incluir lo pendiente del cliente hasta ese mes <span id="mi_pa" class="small muted"></span></label>
      <h3 class="small" style="margin-top:10px">Conceptos adicionales (pueden ser de distintos servicios)</h3><div id="mi_items">${itemRow(0)}</div>
      <button type="button" class="btn sm" id="mi_add">+ Concepto</button><p id="mi_tot" class="small" aria-live="polite"></p>
      <p class="small muted">Documento de cobro de SOFA. El comprobante fiscal (NCF / e-CF) se emite en el sistema fiscal.</p>`,
    onOpen: (f) => {
      let n = 1;
      const upd = () => {
        let t = 0; f.querySelectorAll('[data-item]').forEach((r) => { const i = r.dataset.item; t += Number(f.elements[`q${i}`].value || 0) * Number(f.elements[`u${i}`].value || 0); });
        const ym = f.elements.month.value; const pend = f.elements.pending.checked ? pending.filter((p) => p.period <= `${ym}-01`).reduce((a, p) => a + Number(p.amount), 0) : 0;
        f.querySelector('#mi_pa').textContent = f.elements.org.value ? `(${money(pending.filter((p) => p.period <= `${ym}-01`).reduce((a, p) => a + Number(p.amount), 0))})` : '';
        f.querySelector('#mi_tot').innerHTML = `Total de la factura: <b>${money(t + pend)}</b>`;
      };
      f.elements.org.addEventListener('change', async () => { pending = f.elements.org.value ? await pendingFeesOf(f.elements.org.value).catch(() => []) : []; upd(); });
      f.querySelector('#mi_add').addEventListener('click', () => { f.querySelector('#mi_items').insertAdjacentHTML('beforeend', itemRow(n).s); n += 1; upd(); });
      f.addEventListener('click', (e) => { const b = e.target.closest('[data-del-item]'); if (b) { b.closest('[data-item]').remove(); upd(); } });
      f.addEventListener('input', upd); f.addEventListener('change', upd); upd();
    },
    onSubmit: async (d, f) => {
      if (!d.org) { fieldError(f.elements.org, 'Elija el cliente'); return false; }
      const items = [];
      for (const r of f.querySelectorAll('[data-item]')) {
        const i = r.dataset.item; const desc = (d[`d${i}`] || '').trim(); const u = Number(d[`u${i}`] || 0); const q = Number(d[`q${i}`] || 0);
        if (!desc && !u) continue;   // fila vacía
        if (desc.length < 3) { fieldError(f.elements[`d${i}`], 'Describa el concepto'); return false; }
        if (!(u > 0)) { fieldError(f.elements[`u${i}`], 'Precio mayor que cero'); return false; }
        if (!(q >= 1 && Number.isInteger(q))) { fieldError(f.elements[`q${i}`], 'Cantidad entera'); return false; }
        items.push({ service_code: d[`s${i}`], description: desc, quantity: q, unit_amount: u });
      }
      if (!items.length && !d.pending) { toast('Agrega al menos un concepto o incluye lo pendiente', 'bad'); return false; }
      return createManualInvoice(d.org, monthStart(d.month), !!d.pending, items);
    }
  });
}

// ---------------------------------------------------------------- 4. Limpieza del libro (Super Admin)
export async function cleanupWizard(ctx) {
  const clients = await clientOptions().catch(() => []);
  let preview = null;
  const result = await formDialog({
    title: 'Limpieza del libro de honorarios', submitLabel: 'Ejecutar limpieza', wide: true,
    body: html`<div class="note warn small">Haz un respaldo antes. Todo queda en la bitácora. Una factura con NCF del sistema fiscal nunca se borra: se anula y debe anularse también allí (nota de crédito).</div>
      <div class="form-grid"><div class="field" style="grid-column:1/-1"><label for="lc_o">Cliente *</label><select id="lc_o" name="org"><option value="">Seleccione…</option>${clients.map((c) => opt(c.id, c.legal_name))}</select></div>
        <div class="field"><label for="lc_f">Desde (mes) *</label><input id="lc_f" name="from" type="month"></div><div class="field"><label for="lc_t">Hasta (mes) *</label><input id="lc_t" name="to" type="month" value="${todayISO().slice(0, 7)}"></div></div>
      <button type="button" class="btn sm" id="lc_prev">Ver qué se afectaría</button><div id="lc_box" aria-live="polite" style="margin-top:8px"></div>
      <fieldset style="border:0;padding:0;margin-top:8px"><legend class="small" style="font-weight:600">Modo</legend>
        <label class="check" style="display:flex;margin:4px 0"><input type="radio" name="mode" value="recalcular" checked> <span><b>Recalcular</b>: anula las facturas sin cobros y vuelve a calcular cuotas, % de pagos y radicaciones con las reglas actuales. Las facturas con cobros se conservan.</span></label>
        <label class="check" style="display:flex;margin:4px 0"><input type="radio" name="mode" value="purgar"> <span><b>Purgar datos de prueba</b>: borra cobros y facturas sin NCF del rango y recalcula. Las que tienen NCF se anulan.</span></label></fieldset>
      <div class="field"><label for="lc_r">Motivo (mínimo 10 caracteres) *</label><textarea id="lc_r" name="reason" rows="2" class="input"></textarea></div>
      <div class="field"><label for="lc_c">Para confirmar, escribe el nombre exacto del cliente *</label><input id="lc_c" name="confirm" autocomplete="off"></div>`,
    onOpen: (f) => {
      f.querySelector('#lc_prev').addEventListener('click', async () => {
        const d = Object.fromEntries(new FormData(f).entries());
        if (!d.org || !d.from || !d.to) { toast('Elige cliente y meses', 'bad'); return; }
        try {
          preview = await ledgerPreview(d.org, monthStart(d.from), monthStart(d.to)); const p = preview;
          paint(f.querySelector('#lc_box'), html`<dl class="kv"><dt>Facturas en el rango</dt><dd>${p.invoices.total} · sin cobros ${p.invoices.emitidas_sin_cobro} · con cobros ${p.invoices.con_cobros} · anuladas ${p.invoices.anuladas} · con NCF ${p.invoices.con_ncf} · ${money(p.invoices.monto)}</dd>
            <dt>Cobros registrados</dt><dd>${p.payments.count} · ${money(p.payments.amount)}</dd>
            <dt>Honorarios</dt><dd>no facturados ${p.fees.no_facturados} (${money(p.fees.monto_no_facturado)}) · facturados ${p.fees.facturados}</dd></dl>
            <p class="small">Escribe para confirmar: <b>${p.client}</b></p>`);
        } catch (err) { toast(friendlyError(err), 'bad'); }
      });
    },
    onSubmit: async (d, f) => {
      if (!preview) { toast('Primero revisa qué se afectaría', 'bad'); return false; }
      if ((d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; }
      if ((d.confirm || '').trim().toLowerCase() !== String(preview.client).trim().toLowerCase()) { fieldError(f.elements.confirm, 'Escribe el nombre exacto del cliente'); return false; }
      return ledgerCleanup(d.org, monthStart(d.from), monthStart(d.to), d.mode, d.reason.trim(), d.confirm.trim());
    }
  });
  if (result) {
    const r = result; const rc = r.recalculo || {};
    toast(`Limpieza hecha: ${r.facturas_anuladas} anulada(s), ${r.facturas_eliminadas} eliminada(s), ${r.cobros_eliminados} cobro(s) eliminado(s); recalculados ${(rc.cuotas || 0) + (rc.pagos || 0) + (rc.radicaciones || 0)} honorario(s)`, 'ok');
  }
  return result;
}

