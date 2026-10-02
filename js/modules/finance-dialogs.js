/** SOFA · Diálogos de glosas, pagos y honorarios */
import { html, render as paint, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { money, todayISO, date, period as periodLabel } from '../utils/formatters.js';
import { PAYMENT_METHODS } from '../utils/constants.js';
import { isNCF } from '../utils/validation.js';
import { listArs } from '../services/catalog.js';
import {
  glosaReasons, glosadoByLine, registerGlosa, appealGlosa, resolveGlosa,
  openSubmissions, clientsWithOpenBalance, registerPayment, recordInvoicePayment, setInvoiceNcf, voidInvoice
} from '../services/finance.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
const round2 = (n) => Math.round(Number(n || 0) * 100) / 100;

/** Registrar una glosa sobre servicios de una radicación. Devuelve el id de la glosa. */
export async function glosaDialog(sub, lines) {
  const [reasons, glosado] = await Promise.all([glosaReasons(), glosadoByLine(lines.map((l) => l.id))]);
  const avail = (l) => round2(Number(l.amount) - (glosado[l.id] || 0));
  const candidates = lines.filter((l) => avail(l) > 0);
  if (!candidates.length) throw new Error('Todos los servicios de esta radicación ya están glosados por completo.');
  return formDialog({
    title: `Registrar glosa · ${sub.folio}`, submitLabel: 'Registrar glosa', wide: true,
    body: html`<div class="form-grid">
      ${f('notified_on', 'Fecha de notificación de la ARS *', text('notified_on', todayISO(), `type="date" required max="${todayISO()}"`))}
      ${f('ars_reference', 'Referencia de la ARS', text('ars_reference', '', 'maxlength="60" placeholder="No. de comunicación"'))}</div>
      <p class="small muted">Marca los servicios glosados. El monto sugerido es lo que falta por glosar del servicio; cámbialo si la ARS glosó solo una parte.</p>
      <div class="table-wrap"><table class="t cards"><thead><tr><th></th><th>Servicio</th><th>Motivo</th><th class="n">Monto glosado</th></tr></thead><tbody>
      ${candidates.map((l) => html`<tr>
        <td data-l=""><input type="checkbox" data-line="${l.id}" aria-label="Glosar servicio de ${l.patient_name}"></td>
        <td data-l="Servicio">${date(l.service_date)} · ${l.patient_name}<div class="small muted">${l.procedures?.description} · ${money(l.amount)}</div></td>
        <td data-l="Motivo"><select class="input" data-reason="${l.id}" aria-label="Motivo">${reasons.map((r) => opt(r.code, r.name, 'documentacion'))}</select></td>
        <td data-l="Monto" class="n"><input class="input" style="max-width:130px" type="number" min="0.01" step="0.01" max="${avail(l)}" value="${avail(l)}" data-amt="${l.id}" aria-label="Monto glosado"></td></tr>`)}
      </tbody></table></div>
      ${f('notes', 'Notas', text('notes', '', 'maxlength="300"'))}`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['notified_on'])) return false;
      const items = [...form.querySelectorAll('[data-line]:checked')].map((cb) => {
        const id = cb.dataset.line;
        return { service_line_id: id, reason_code: form.querySelector(`[data-reason="${id}"]`).value, amount: Number(form.querySelector(`[data-amt="${id}"]`).value) };
      });
      if (!items.length) throw new Error('Marca al menos un servicio glosado.');
      const bad = items.find((i) => !(i.amount > 0));
      if (bad) throw new Error('Cada monto glosado debe ser mayor que cero.');
      return registerGlosa(sub.id, d.notified_on, items, d.ars_reference, d.notes);
    }
  });
}

export function appealDialog(glosa) {
  return formDialog({
    title: `Apelar glosa · ${glosa.folio}`, submitLabel: 'Registrar apelación', wide: true,
    body: html`<p class="small muted" style="margin-top:0">Plazo para responder: <b>${date(glosa.appeal_deadline)}</b>. Adjunta los soportes en el expediente de la radicación.</p>
      ${f('submitted_on', 'Fecha de envío a la ARS *', text('submitted_on', todayISO(), `type="date" required max="${todayISO()}"`))}
      ${f('argument', 'Argumento de la apelación *', html`<textarea id="f_argument" name="argument" rows="6" class="input" required placeholder="Se anexa la indicación médica firmada y sellada, y la tarifa contratada vigente a la fecha del servicio."></textarea>`)}`,
    onSubmit: async (d, form) => {
      if (!d.argument || d.argument.trim().length < 10) { fieldError(form.elements.argument, 'Mínimo 10 caracteres.'); return false; }
      return appealGlosa(glosa.id, d.argument.trim(), d.submitted_on);
    }
  });
}

/** Resultado de la glosa: cuánto reconoce la ARS en cada servicio */
export function resolveDialog(glosa, items) {
  return formDialog({
    title: `Resultado de la glosa · ${glosa.folio}`, submitLabel: 'Guardar resultado', wide: true,
    body: html`<p class="small muted" style="margin-top:0">Escribe cuánto <b>reconoce la ARS</b> (recuperado) en cada servicio. Lo que no se recupera queda como glosa aceptada y se descuenta del saldo.</p>
      <div class="toolbar"><button type="button" class="btn sm" data-all="rec">Todo recuperado</button><button type="button" class="btn sm" data-all="acc">Nada recuperado</button></div>
      <div class="table-wrap"><table class="t cards"><thead><tr><th>Servicio</th><th>Motivo</th><th class="n">Glosado</th><th class="n">Recuperado</th></tr></thead><tbody>
      ${items.map((i) => html`<tr><td data-l="Servicio">${i.service_lines?.patient_name}<div class="small muted">${date(i.service_lines?.service_date)} · ${i.service_lines?.procedures?.description}</div></td>
        <td data-l="Motivo">${i.glosa_reasons?.name}</td><td data-l="Glosado" class="n">${money(i.amount)}</td>
        <td data-l="Recuperado" class="n"><input class="input" style="max-width:130px" type="number" min="0" step="0.01" max="${i.amount}" value="${i.recovered_amount || 0}" data-rec="${i.id}" data-max="${i.amount}" aria-label="Recuperado"></td></tr>`)}
      </tbody></table></div>
      ${f('comment', 'Comentario', text('comment', '', 'maxlength="300" placeholder="Comunicación ARS No. …"'))}
      <p class="small" id="resSum"></p>`,
    onOpen: (form) => {
      const sum = () => {
        const tot = items.reduce((t, i) => t + Number(i.amount), 0);
        const rec = [...form.querySelectorAll('[data-rec]')].reduce((t, x) => t + Number(x.value || 0), 0);
        form.querySelector('#resSum').textContent = `Recuperado ${money(rec)} de ${money(tot)} · pérdida ${money(tot - rec)}`;
      };
      form.addEventListener('input', sum);
      form.querySelectorAll('[data-all]').forEach((b) => b.addEventListener('click', () => {
        form.querySelectorAll('[data-rec]').forEach((x) => { x.value = b.dataset.all === 'rec' ? x.dataset.max : 0; }); sum();
      }));
      sum();
    },
    onSubmit: async (d, form) => {
      const payload = [...form.querySelectorAll('[data-rec]')].map((x) => ({ id: x.dataset.rec, recovered_amount: Number(x.value || 0) }));
      const bad = payload.find((p, k) => p.recovered_amount < 0 || p.recovered_amount > Number(items[k].amount));
      if (bad) throw new Error('Lo recuperado debe estar entre 0 y el monto glosado de cada servicio.');
      return resolveGlosa(glosa.id, payload, d.comment || null);
    }
  });
}

/**
 * Registrar un pago de ARS y repartirlo entre radicaciones abiertas del mismo cliente y ARS.
 * preset: { orgId, arsId, submissionId }
 */
export async function paymentDialog(preset = {}) {
  const [open, ars] = await Promise.all([clientsWithOpenBalance(), listArs()]);
  const clients = {}; open.forEach((r) => { clients[r.organization_id] = r.client_name; });
  if (!Object.keys(clients).length) throw new Error('No hay radicaciones con saldo pendiente de cobro.');
  let rows = [];
  return formDialog({
    title: 'Registrar pago de ARS', submitLabel: 'Registrar pago', wide: true,
    body: html`<div class="form-grid">
      ${f('org', 'Cliente *', html`<select id="f_org" name="org" required>${Object.entries(clients).sort((a, b) => a[1].localeCompare(b[1])).map(([id, n]) => opt(id, n, preset.orgId))}</select>`)}
      ${f('ars', 'ARS *', html`<select id="f_ars" name="ars" required></select>`)}
      ${f('paid_on', 'Fecha del pago *', text('paid_on', todayISO(), `type="date" required max="${todayISO()}"`))}
      ${f('amount', 'Monto recibido (RD$) *', text('amount', '', 'type="number" min="0.01" step="0.01" required'))}
      ${f('method', 'Forma de pago', html`<select id="f_method" name="method">${PAYMENT_METHODS.map(([v, l]) => opt(v, l, 'transferencia'))}</select>`)}
      ${f('reference', 'Referencia *', text('reference', '', 'required maxlength="60" placeholder="No. de transferencia o cheque"'))}</div>
      <div class="toolbar" style="margin-top:4px"><b style="flex:1">Aplicar a radicaciones</b><button type="button" class="btn sm" id="auto">Repartir automáticamente</button></div>
      <div id="alloc"></div><p class="small" id="allocSum"></p>
      ${f('notes', 'Notas', text('notes', '', 'maxlength="300"'))}`,
    onOpen: (form) => {
      const arsSel = form.elements.ars, box = form.querySelector('#alloc'), sumEl = form.querySelector('#allocSum');
      const fillArs = () => {
        const ids = [...new Set(open.filter((r) => r.organization_id === form.elements.org.value).map((r) => r.ars_id))];
        paint(arsSel, html`${ars.filter((a) => ids.includes(a.id)).map((a) => opt(a.id, a.name, preset.arsId))}`);
      };
      const total = () => [...box.querySelectorAll('[data-sub]')].reduce((t, x) => t + (x.closest('tr').querySelector('[data-use]').checked ? Number(x.value || 0) : 0), 0);
      const showSum = () => {
        const a = round2(total()), p = round2(form.elements.amount.value);
        sumEl.innerHTML = '';
        sumEl.append(`Aplicado ${money(a)} de ${money(p)}`);
        sumEl.style.color = a === p && p > 0 ? 'var(--ok)' : 'var(--warn)';
      };
      const loadRows = async () => {
        paint(box, html`<p class="small muted">Cargando…</p>`);
        rows = await openSubmissions(form.elements.org.value, arsSel.value);
        paint(box, rows.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th></th><th>Radicación</th><th>Período</th><th class="n">Saldo</th><th class="n">Aplicar</th></tr></thead><tbody>
          ${rows.map((r) => html`<tr><td data-l=""><input type="checkbox" data-use="${r.id}" ${r.id === preset.submissionId ? raw('checked') : ''} aria-label="Aplicar a ${r.folio}"></td>
            <td data-l="Radicación"><b class="mono">${r.folio}</b><div class="small muted">${r.provider_name} · radicada ${date(r.submitted_on)}</div></td>
            <td data-l="Período">${periodLabel(r.period)}</td><td data-l="Saldo" class="n">${money(r.balance)}${Number(r.glosa_in_dispute) > 0 ? html`<div class="small muted">${money(r.glosa_in_dispute)} en disputa</div>` : ''}</td>
            <td data-l="Aplicar" class="n"><input class="input" style="max-width:130px" type="number" min="0" step="0.01" max="${r.balance}" value="${r.id === preset.submissionId ? r.balance : ''}" data-sub="${r.id}" aria-label="Monto aplicado a ${r.folio}"></td></tr>`)}
          </tbody></table></div>` : html`<p class="small muted">Sin radicaciones con saldo para este cliente y ARS.</p>`);
        if (preset.submissionId && !form.elements.amount.value) {
          const r = rows.find((x) => x.id === preset.submissionId); if (r) form.elements.amount.value = r.balance;
        }
        showSum();
      };
      form.elements.org.addEventListener('change', () => { fillArs(); loadRows(); });
      arsSel.addEventListener('change', loadRows);
      box.addEventListener('input', (e) => { const x = e.target.closest('[data-sub]'); if (x) x.closest('tr').querySelector('[data-use]').checked = Number(x.value) > 0; showSum(); });
      box.addEventListener('change', (e) => { const cb = e.target.closest('[data-use]'); if (cb) { const inp = box.querySelector(`[data-sub="${cb.dataset.use}"]`); if (cb.checked && !inp.value) inp.value = rows.find((r) => r.id === cb.dataset.use).balance; if (!cb.checked) inp.value = ''; } showSum(); });
      form.elements.amount.addEventListener('input', showSum);
      form.querySelector('#auto').addEventListener('click', () => {
        let left = round2(form.elements.amount.value);
        // Primero la radicación desde la que se abrió el pago; luego las más antiguas
        [...rows].sort((a, b) => (b.id === preset.submissionId) - (a.id === preset.submissionId)).forEach((r) => {
          const inp = box.querySelector(`[data-sub="${r.id}"]`), cb = box.querySelector(`[data-use="${r.id}"]`);
          const take = round2(Math.min(left, Number(r.balance))); left = round2(left - take);
          inp.value = take > 0 ? take : ''; cb.checked = take > 0;
        });
        showSum();
      });
      fillArs(); loadRows();
    },
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['org', 'ars', 'paid_on', 'amount', 'reference'])) return false;
      const amount = round2(d.amount);
      const allocations = [...form.querySelectorAll('[data-use]:checked')].map((cb) => ({ submission_id: cb.dataset.use, amount: round2(form.querySelector(`[data-sub="${cb.dataset.use}"]`).value) })).filter((a) => a.amount > 0);
      if (!allocations.length) throw new Error('Aplica el pago al menos a una radicación.');
      const sum = round2(allocations.reduce((t, a) => t + a.amount, 0));
      if (sum !== amount) throw new Error(`Lo aplicado (${money(sum)}) debe ser igual al monto recibido (${money(amount)}).`);
      return registerPayment({ orgId: d.org, arsId: d.ars, paidOn: d.paid_on, amount, method: d.method, reference: d.reference.trim(), allocations, notes: d.notes });
    }
  });
}

export function invoicePaymentDialog(inv) {
  return formDialog({
    title: `Cobro de la factura ${inv.folio}`, submitLabel: 'Registrar cobro',
    body: html`<p class="small muted" style="margin-top:0">${inv.client_name} · saldo ${money(inv.balance)}</p><div class="form-grid">
      ${f('paid_on', 'Fecha *', text('paid_on', todayISO(), `type="date" required max="${todayISO()}"`))}
      ${f('amount', 'Monto (RD$) *', text('amount', inv.balance, `type="number" min="0.01" step="0.01" max="${inv.balance}" required`))}
      ${f('method', 'Forma de pago', html`<select id="f_method" name="method">${[['transferencia', 'Transferencia'], ['cheque', 'Cheque'], ['deposito', 'Depósito'], ['efectivo', 'Efectivo'], ['otro', 'Otro']].map(([v, l]) => opt(v, l, 'transferencia'))}</select>`)}
      ${f('reference', 'Referencia', text('reference', '', 'maxlength="60"'))}</div>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['paid_on', 'amount'])) return false;
      const a = round2(d.amount);
      if (!(a > 0) || a > round2(inv.balance)) { fieldError(form.elements.amount, `Entre 0.01 y ${money(inv.balance)}.`); return false; }
      return recordInvoicePayment(inv, { paidOn: d.paid_on, amount: a, method: d.method, reference: d.reference });
    }
  });
}

export function ncfDialog(inv) {
  return formDialog({
    title: `NCF de la factura ${inv.folio}`, submitLabel: 'Guardar',
    body: html`${f('ncf', 'NCF *', text('ncf', inv.ncf || '', 'required maxlength="13" placeholder="B0100000125"'), 'B01 crédito fiscal (clientes con RNC) · B02 consumo · e-CF E31–E34')}
      ${f('valid', 'Válido hasta (vencimiento de la secuencia)', text('valid', inv.ncf_valid_until || '', 'type="date"'), 'Aparece en la factura impresa y en el PDF')}`,
    onSubmit: async (d, form) => {
      const v = (d.ncf || '').trim().toUpperCase();
      if (!isNCF(v)) { fieldError(form.elements.ncf, 'Formato: B + 10 dígitos o E + 12 dígitos.'); return false; }
      return setInvoiceNcf(inv.id, v, d.valid || null);
    }
  });
}

export function voidInvoiceDialog(inv) {
  return formDialog({
    title: `Anular factura ${inv.folio}`, submitLabel: 'Anular factura',
    body: html`<div class="note warn">Sus honorarios quedan libres para facturarlos de nuevo.</div>${f('reason', 'Motivo *', html`<textarea id="f_reason" name="reason" rows="3" class="input" required></textarea>`)}`,
    onSubmit: async (d, form) => {
      if (!d.reason || d.reason.trim().length < 5) { fieldError(form.elements.reason, 'Escribe el motivo.'); return false; }
      await voidInvoice(inv.id, d.reason.trim()); return true;
    }
  });
}
