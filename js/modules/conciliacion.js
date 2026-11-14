/** Mesa de conciliación: conserva el cruce bancario y separa la aplicación de pagos. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';
import { can, canOpen } from '../utils/permissions.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';
import { formDialog, confirmDialog, fieldError, busy, friendlyError } from '../utils/ui.js';
import { html } from '../utils/dom.js';
import { todayISO } from '../utils/formatters.js';
import { bankWorkspaceClaims } from '../services/reconciliation-workspace.js';
import { viewAsState } from '../utils/view-as-state.js';

const ALIASES = {
  fecha: ['fecha', 'fecha transaccion', 'fecha de transaccion', 'fecha valor', 'fecha efectiva', 'date'],
  descripcion: ['descripcion', 'concepto', 'detalle', 'description', 'transaccion', 'descripcion de la transaccion'],
  referencia: ['referencia', 'no referencia', 'num referencia', 'numero de referencia', 'documento', 'no documento', 'serial'],
  monto: ['monto', 'importe', 'valor', 'amount'],
  credito: ['credito', 'creditos', 'deposito', 'depositos', 'abono', 'abonos', 'entrada'],
  debito: ['debito', 'debitos', 'retiro', 'retiros', 'cargo', 'cargos', 'salida']
};
const BANKS = ['Banreservas', 'Banco Popular', 'BHD', 'Scotiabank', 'Banco Santa Cruz', 'Banesco', 'Banco Caribe', 'Banco Promerica', 'Banco BDI', 'Asociación Popular', 'Asociación Cibao', 'Banco Vimenca', 'Banco López de Haro', 'Citibank'];
const ST = { sin_conciliar: ['Sin conciliar', 'st-req'], conciliado: ['Conciliado', 'st-ok'], no_ars: ['No es de ARS', 'st-none'] };
const pill = (s) => h('span', { class: `ac-pill ${(ST[s] || [s, 'st-none'])[1]}` }, (ST[s] || [s])[0]);
const iso = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Santo_Domingo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
const norm = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const difference = (a, b) => Math.round((Number(a) - Number(b)) * 100) / 100;

export async function render(root, ctx = {}) {
  const write = can('bank.reconcile', ctx.role); const admin = can('bank.admin', ctx.role);
  const canWrite = () => write && !ctx.viewAs && !viewAsState.active;
  const canAdmin = () => admin && canWrite();
  let sequence = 0, data = null, selectedId = '', selectedPayment = '';
  let claimsHost = null, claimsRequest = 0, authorizationQuery = '';
  const claimsCache = new Map();
  root.replaceChildren();
  const wrap = h('div', { class: 'reconciliation-workspace' }); root.append(wrap);
  const top = h('div'); const body = h('div'); const message = h('div', { role: 'status', 'aria-live': 'polite' });
  wrap.append(h('div', { class: 'rw-page-head' }, h('div', {}, h('h2', {}, 'Mesa de conciliación'), h('p', { class: 'i18-sub' }, 'Compara depósitos y pagos de ARS; revisa por separado cómo se aplicó el pago a las reclamaciones.'))), top, message, body);
  const ov = await guarded(top, () => rpc('bank_overview'));
  if (!ov || !document.body.contains(wrap)) return;
  if (!ov.length) { top.replaceChildren(note('No hay clientes activos.')); return; }
  const org = h('select', { id: 'bk-org' }, ov.map((o) => h('option', { value: o.organization_id }, `${o.client}${o.pending ? ` · ${o.pending} pendiente(s)` : ''}`)));
  const from = h('input', { id: 'bk-from', type: 'date', value: iso(new Date(Date.now() - 90 * 864e5)) });
  const to = h('input', { id: 'bk-to', type: 'date', value: todayISO() });
  const query = h('input', { id: 'bk-query', type: 'search', placeholder: 'Referencia, folio o ARS', autocomplete: 'off' });
  const status = h('select', { id: 'bk-status' }, h('option', { value: '' }, 'Todos los estados'), Object.entries(ST).map(([v, [name]]) => h('option', { value: v }, name)));
  top.replaceChildren(h('section', { class: 'rw-filters', 'aria-label': 'Filtros de conciliación' },
    h('label', { for: 'bk-org' }, 'Cliente', org), h('label', { for: 'bk-from' }, 'Desde', from), h('label', { for: 'bk-to' }, 'Hasta', to), h('label', { for: 'bk-query' }, 'Buscar en los depósitos del período', query), h('label', { for: 'bk-status' }, 'Estado', status)));
  [org, from, to].forEach((x) => x.addEventListener('change', () => { selectedId = ''; selectedPayment = ''; draw(); }));
  [query, status].forEach((x) => x.addEventListener(x === query ? 'input' : 'change', () => renderWorkspace()));
  await draw();

  async function draw() {
    const request = ++sequence; const orgId = org.value; claimsRequest += 1; claimsCache.clear(); data = null;
    message.replaceChildren();
    if (from.value && to.value && from.value > to.value) { body.replaceChildren(note('La fecha Desde debe ser anterior o igual a Hasta.', 'error')); return; }
    body.replaceChildren(note('Actualizando conciliación…'));
    try {
      const result = await rpc('bank_reconciliation', { p_org: orgId, p_from: from.value || null, p_to: to.value || null });
      if (request !== sequence || !document.body.contains(wrap)) return;
      data = result; renderWorkspace();
    } catch (err) {
      if (request !== sequence || !document.body.contains(wrap)) return;
      data = null; body.replaceChildren(note(friendlyError(err), 'error'), h('button', { type: 'button', class: 'i18-btn', onclick: draw }, 'Reintentar conciliación'));
    }
  }
  function filteredMovements() {
    const q = norm(query.value.trim());
    return (data?.movements || []).filter((m) => (!status.value || m.status === status.value) && (!q || norm([m.reference, m.description, m.ars, m.payment?.folio, m.payment?.reference, ...(m.candidates || []).flatMap((c) => [c.folio, c.ars, c.reference])].join(' ')).includes(q)));
  }
  function renderWorkspace() {
    if (!data) return;
    const d = data; const s = d.summary; const list = filteredMovements();
    if (!list.some((m) => m.id === selectedId)) { selectedId = list[0]?.id || ''; selectedPayment = ''; }
    const current = list.find((m) => m.id === selectedId); const pane = h('div', { class: 'rw-register-pane', 'aria-live': 'polite' });
    claimsHost = h('div', { id: 'bk-claims', 'aria-live': 'polite' });
    const authSearch = h('input', { id: 'bk-authorization-search', type: 'search', value: authorizationQuery, placeholder: 'Autorización o folio (mínimo 3 caracteres)', autocomplete: 'off' });
    const searchClaims = () => { authorizationQuery = authSearch.value.trim(); if (authorizationQuery.length < 3) { claimsHost.replaceChildren(note('Escribe al menos 3 caracteres de la autorización o del folio.', 'error')); return; } loadClaimApplications(null, authorizationQuery); };
    authSearch.addEventListener('input', () => { authorizationQuery = authSearch.value; });
    authSearch.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); searchClaims(); } });
    const applicationPanel = h('section', { class: 'rw-panel rw-application' }, h('header', {}, h('h3', {}, '2 · Pago ↔ Reclamaciones')),
      h('div', { class: 'rw-panel-body' }, h('p', {}, 'Consulta los servicios ya asociados al pago seleccionado o busca una autorización en este cliente. Esta consulta no aplica ni reasigna pagos.'),
      h('div', { class: 'rw-claim-search' }, h('label', { for: 'bk-authorization-search' }, 'Buscar autorización o folio de reclamación', authSearch), h('button', { type: 'button', class: 'i18-btn i18-sec', id: 'bk-search-authorization', onclick: searchClaims }, 'Buscar reclamación')), claimsHost,
      h('div', { class: 'rw-links' }, canOpen('#/radicaciones', ctx.role) ? h('a', { class: 'i18-btn i18-sec', href: '#/radicaciones' }, 'Revisar radicaciones y reparto') : '', canOpen('#/pagos', ctx.role) ? h('a', { class: 'i18-btn i18-sec', href: '#/pagos' }, 'Ver pagos registrados') : ''), h('p', { class: 'i18-sub' }, 'La conciliación bancaria y la aplicación del pago son operaciones distintas. Buscar una autorización no confirma ninguna asociación.')));

    if (!current) claimsHost.replaceChildren(note('Busca una autorización o selecciona un depósito con pago asociado.'));
    const upload = canWrite() ? h('details', { class: 'rw-upload' }, h('summary', {}, 'Cargar estado de cuenta · Excel o CSV'), uploadCard()) : null;
    body.replaceChildren(
      h('div', { class: 'rw-kpis' }, [['Depósitos', `${s.deposits}`, money(s.deposits_amount)], ['Conciliados', `${s.matched}`, money(s.matched_amount)], ['Sin conciliar', `${s.pending}`, money(s.pending_amount)], ['Diferencias anotadas', money(s.differences), 'Del período seleccionado']].map(([l, v, help]) => h('div', { class: 'rw-kpi' }, h('span', {}, l), h('strong', {}, v), h('small', {}, help)))),
      !canWrite() ? note(ctx.viewAs || viewAsState.active ? 'Modo soporte: consulta de solo lectura.' : 'Consulta de conciliación. Las acciones dependen de los permisos de tu perfil.') : '',
      upload,
      h('div', { class: 'rw-stages' }, h('span', { class: 'rw-stage-current' }, '1 · Depósito ↔ Pago ARS'), h('span', {}, '2 · Pago ↔ Radicaciones y reclamaciones')),
      h('div', { class: 'rw-desk' }, h('section', { class: 'rw-panel rw-inbox', 'aria-label': 'Depósitos del período' }, h('header', {}, h('h3', {}, 'Depósitos del período'), h('span', { class: 'rw-count' }, String(list.length))),
        list.length ? h('div', { class: 'rw-movements' }, list.map((m) => h('button', { type: 'button', class: `rw-movement ${m.id === selectedId ? 'is-selected' : ''}`, 'data-movement': m.id, 'aria-pressed': String(m.id === selectedId), onclick: () => { selectedId = m.id; selectedPayment = ''; renderWorkspace(); } },
          h('div', { class: 'rw-movement-top' }, h('strong', {}, money(m.amount)), pill(m.status)), h('b', {}, m.description || 'Depósito sin descripción'), h('small', {}, `${fmtDate(m.date)} · ${m.ars || 'ARS por confirmar'}`), h('span', { class: 'rw-reference' }, m.reference || 'Sin referencia')))) : h('p', { class: 'rw-empty' }, 'No hay depósitos con estos filtros.')),
        h('section', { class: 'rw-panel rw-review', 'aria-label': 'Comparación de depósito y pago' }, h('header', {}, h('h3', {}, 'Comparar antes de confirmar')), current ? movementDetails(current, pane) : h('p', { class: 'rw-empty' }, 'Selecciona un depósito para ver sus datos y posibles pagos.'))),
      pane,
      applicationPanel,
      h('details', { class: 'rw-report', open: (d.payments_without_deposit || []).length > 0 }, h('summary', {}, `Pagos registrados sin depósito · ${(d.payments_without_deposit || []).length}`),
        d.payments_without_deposit.length ? simple(['Pago', 'ARS', 'Fecha', 'Monto', 'Referencia', 'Días'], d.payments_without_deposit.map((p) => [p.folio || '—', p.ars, fmtDate(p.paid_on), money(p.amount), p.reference || '—', String(p.days)])) : note('No hay pagos sin depósito identificado en el período cargado.')),
      h('details', { class: 'rw-report' }, h('summary', {}, `Radicaciones con pago parcial · ${(d.partial || []).length}`), d.partial.length ? simple(['Radicación', 'ARS', 'Enviada', 'Reclamado', 'Pagado', 'Glosa aceptada', 'Saldo', '% cobrado'], d.partial.map((p) => [submissionLink(p), p.ars, fmtDate(p.submitted_on), money(p.claimed), money(p.paid), money(p.glosa_accepted), money(p.balance), `${p.pct ?? 0} %`])) : note('No hay radicaciones con pago parcial.')),
      h('details', { class: 'rw-report' }, h('summary', {}, `Sin pago después de ${d.payment_term_days} días · ${(d.unpaid_overdue || []).length}`), d.unpaid_overdue.length ? simple(['Radicación', 'ARS', 'Enviada', 'Reclamado', 'Días'], d.unpaid_overdue.map((p) => [submissionLink(p), p.ars, fmtDate(p.submitted_on), money(p.claimed), String(p.days)])) : note('Ninguna radicación supera el plazo sin cobrar.')),
      h('details', { class: 'rw-report' }, h('summary', {}, `Estados de cuenta cargados · ${(d.statements || []).length}`), d.statements.length ? simple(['Fecha', 'Banco', 'Cuenta', 'Archivo', 'Período', 'Depósitos', 'Repetidos', 'Por'], d.statements.map((x) => [fmtDate(x.at), x.bank, x.account || '—', x.file || '—', `${fmtDate(x.from)} – ${fmtDate(x.to)}`, String(x.deposits), String(x.duplicates), x.by || '—'])) : note('No hay estados de cuenta cargados para este cliente.')));
  }
  async function loadClaimApplications(paymentId, search = '') {
    const target = claimsHost; const request = ++claimsRequest; const organizationId = org.value;
    target.replaceChildren(note(search ? 'Buscando reclamaciones por autorización o folio…' : 'Consultando aplicaciones del pago…'));
    try {
      const key = JSON.stringify([organizationId, paymentId, search]);
      if (!claimsCache.has(key)) claimsCache.set(key, bankWorkspaceClaims({ organizationId, paymentId, search }));
      let lines;
      try { lines = await claimsCache.get(key); } catch (err) { claimsCache.delete(key); throw err; }
      if (request !== claimsRequest || claimsHost !== target || org.value !== organizationId || !document.body.contains(target)) return;
      target.replaceChildren(h('p', { class: 'rw-claims-mode' }, search ? `Resultados por autorización o folio: ${search}` : 'Reclamaciones ya asociadas a este pago'),
        lines.length ? simple(['Reclamación / servicio', 'Autorización', 'Radicación', 'Reclamado', search ? 'Aplicado total' : 'Aplicado por este pago', 'Saldo actual'], lines.map((line) => [
          h('div', {}, canOpen('#/reclamaciones', ctx.role) ? h('a', { href: `#/reclamaciones/${line.line_id}` }, line.folio || 'Abrir reclamación') : line.folio || '—', h('div', { class: 'i18-sub' }, line.service_name || '—')),
          line.authorization_number || h('span', { class: 'ac-pill st-req' }, 'Sin registrar'),
          canOpen('#/radicaciones', ctx.role) && line.submission_id ? h('a', { href: `#/radicaciones/${line.submission_id}` }, line.submission_folio || 'Abrir lote') : line.submission_folio || '—',
          money(line.claimed), money(line.applied), money(line.balance)
        ])) : note(search ? 'No hay reclamaciones con esa autorización o folio en este cliente.' : 'Este pago no tiene aplicaciones a reclamaciones disponibles en esta consulta.'),
        h('p', { class: 'i18-sub' }, 'Se muestran hasta 100 reclamaciones. Los valores son de consulta; no se modifica ninguna asignación.'));
    } catch (err) {
      if (request !== claimsRequest || claimsHost !== target || org.value !== organizationId || !document.body.contains(target)) return;
      target.replaceChildren(note(friendlyError(err), 'error'), h('button', { type: 'button', class: 'i18-btn i18-sec', onclick: () => loadClaimApplications(paymentId, search) }, 'Reintentar consulta de reclamaciones'));
    }
  }
  function submissionLink(p) { return p.id && canOpen('#/radicaciones', ctx.role) ? h('a', { href: `#/radicaciones/${p.id}` }, p.folio || 'Abrir radicación') : p.folio || '—'; }
  function simple(cols, rows) {
    return h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, cols.map((c) => h('th', {}, c)))), h('tbody', {}, rows.map((r) => h('tr', {}, r.map((c) => h('td', {}, c)))))));
  }
  function dataCard(title, items) { return h('section', { class: 'rw-data-card' }, h('h4', {}, title), h('dl', {}, items.flatMap(([label, value]) => [h('dt', {}, label), h('dd', {}, value || '—')]))); }
  function movementDetails(m, pane) {
    const detail = h('div', { class: 'rw-panel-body' });
    const deposit = dataCard('Depósito bancario', [['Monto', money(m.amount)], ['Fecha', fmtDate(m.date)], ['Referencia', m.reference || 'Sin referencia'], ['Descripción', m.description || '—'], ['ARS probable', m.ars || 'Por confirmar']]);
    if (m.status !== 'sin_conciliar') {
      const p = m.payment;
      detail.append(h('div', { class: 'rw-comparison' }, deposit, m.status === 'conciliado' && p ? dataCard('Pago ARS asociado', [['Pago', p.folio || 'Pago'], ['Monto', money(p.amount)], ['Fecha', fmtDate(p.paid_on)], ['ARS', p.ars || '—']]) : dataCard('Clasificación', [['Estado', 'No es de ARS'], ['Motivo', m.note || 'Sin motivo disponible']])));
      if (m.status === 'conciliado') { const paymentId = p?.id || p?.payment_id || m.payment_id; if (paymentId) loadClaimApplications(paymentId); else claimsHost.replaceChildren(note('El pago asociado no aporta un identificador para consultar sus reclamaciones.')); } else claimsHost.replaceChildren(note('Este depósito está clasificado como no ARS. Puedes buscar una reclamación por separado.'));
      if (m.status === 'conciliado') detail.append(h('p', { class: 'rw-difference' }, `Diferencia anotada: ${money(m.difference || 0)}${m.note ? ` · ${m.note}` : ''}`));
      if (canAdmin()) detail.append(h('button', { type: 'button', class: 'i18-btn i18-sec', onclick: (event) => runButton(event.currentTarget, async () => { if (!(await confirmDialog('Deshacer conciliación', 'El depósito volverá a pendiente. El pago registrado y sus aplicaciones se conservan.', 'Deshacer'))) return; await act(() => rpc('bank_unmatch', { p_movement: m.id }), 'Movimiento devuelto a pendiente.'); }) }, 'Deshacer asociación'));
      return detail;
    }
    const candidates = m.candidates || [];
    const select = h('select', { id: 'bk-payment', 'aria-label': 'Pago para comparar' }, h('option', { value: '' }, candidates.length ? 'Selecciona un pago candidato…' : 'Sin pagos candidatos'), candidates.map((c) => h('option', { value: c.payment_id, selected: selectedPayment === c.payment_id }, `${c.folio || 'Pago'} · ${c.ars} · ${money(c.amount)}`)));
    const candidateBox = h('div');
    const go = h('button', { type: 'button', class: 'i18-btn', disabled: true, id: 'bk-confirm-match', onclick: (event) => runButton(event.currentTarget, async () => {
      const payment = candidates.find((c) => c.payment_id === select.value); if (!payment || !canWrite()) return;
      const delta = difference(m.amount, payment.amount); const mismatch = Math.abs(delta) > 0.01;
      const ok = await formDialog({ title: 'Confirmar asociación bancaria', submitLabel: 'Confirmar asociación', body: html`<p><b>Depósito:</b> ${money(m.amount)} · ${m.reference || 'Sin referencia'}</p><p><b>Pago:</b> ${payment.folio || payment.payment_id} · ${payment.ars} · ${money(payment.amount)}</p><div class="note ${mismatch ? 'warn' : ''}">Diferencia: ${money(delta)}. Esta acción asocia el depósito con el pago; no reparte importes entre reclamaciones.</div>${mismatch ? html`<div class="field"><label for="bk-difference-note">Motivo de la diferencia *</label><textarea id="bk-difference-note" name="reason" rows="3" maxlength="1000" placeholder="Ej.: retención documentada. Mínimo 10 caracteres."></textarea></div>` : ''}`, onSubmit: async (values, form) => {
        if (!canWrite()) throw new Error('Este contexto es de solo lectura.');
        const why = mismatch ? String(values.reason || '').trim() : null;
        if (mismatch && why.length < 10) { fieldError(form.elements.reason, 'Explica la diferencia con al menos 10 caracteres.'); return false; }
        await rpc('bank_match', { p_movement: m.id, p_payment: payment.payment_id, p_note: why }); return true;
      } });
      if (ok) { await draw(); message.replaceChildren(note('Depósito y pago asociados. Las aplicaciones a reclamaciones se conservan.', 'ok')); }
    }) }, 'Revisar y confirmar asociación');
    const update = () => {
      selectedPayment = select.value; const payment = candidates.find((c) => c.payment_id === select.value); go.disabled = !payment || !canWrite();
      if (!payment) { claimsRequest += 1; claimsHost.replaceChildren(note('Selecciona un pago para consultar las reclamaciones que ya tiene asociadas, o busca una autorización.')); candidateBox.replaceChildren(h('p', { class: 'rw-empty' }, 'Selecciona un candidato para comparar sus datos. No se ha asociado ningún pago.')); return; }
      loadClaimApplications(payment.payment_id);
      const delta = difference(m.amount, payment.amount); const sameAmount = Math.abs(delta) <= 0.01;
      const days = Math.abs(Math.round((new Date(`${m.date}T12:00:00`) - new Date(`${payment.paid_on}T12:00:00`)) / 864e5));
      candidateBox.replaceChildren(dataCard('Pago ARS candidato', [['Pago', payment.folio || '—'], ['Monto', money(payment.amount)], ['Fecha', fmtDate(payment.paid_on)], ['Referencia', payment.reference || 'No disponible en el candidato'], ['ARS', payment.ars || '—']]), h('p', { class: `rw-difference ${sameAmount ? '' : 'has-difference'}` }, `Depósito − pago: ${money(delta)}`), h('p', { class: 'i18-sub' }, `${sameAmount ? 'Mismo monto' : 'Monto distinto'}${Number.isFinite(days) ? ` · ${days} día(s) entre fechas` : ''}. La coincidencia propuesta requiere revisión antes de confirmar.`));
    };
    select.addEventListener('change', update); update();
    detail.append(h('div', { class: 'rw-comparison' }, deposit, h('div', { class: 'rw-candidate' }, h('label', { for: 'bk-payment' }, 'Pago para comparar', select), candidateBox)), h('div', { class: 'rw-actions' }, canWrite() ? go : ''));
    if (canWrite()) detail.append(h('div', { class: 'rw-secondary-actions' },
      canAdmin() ? h('button', { type: 'button', class: 'i18-btn i18-sec', onclick: (event) => runButton(event.currentTarget, () => registerForm(m, pane)) }, 'Registrar el pago de la ARS') : '',
      h('button', { type: 'button', class: 'i18-btn i18-sec', onclick: (event) => runButton(event.currentTarget, async () => {
        const ok = await formDialog({ title: 'Clasificar depósito como no ARS', submitLabel: 'Confirmar clasificación', body: html`<p>${m.description} · ${money(m.amount)}</p><div class="field"><label for="bk-ignore-reason">Origen o motivo *</label><textarea id="bk-ignore-reason" name="reason" rows="3" maxlength="1000" placeholder="Describe el origen del depósito (mínimo 10 caracteres)."></textarea></div>`, onSubmit: async (values, form) => { const why = String(values.reason || '').trim(); if (why.length < 10) { fieldError(form.elements.reason, 'Escribe un motivo de al menos 10 caracteres.'); return false; } if (!canWrite()) throw new Error('Este contexto es de solo lectura.'); await rpc('bank_ignore', { p_movement: m.id, p_reason: why }); return true; } });
        if (ok) { await draw(); message.replaceChildren(note('Depósito clasificado como «No es de ARS».', 'ok')); }
      }) }, 'No es de ARS')));
    return detail;
  }
  async function runButton(button, fn) { try { await busy(button, fn); } catch (err) { message.replaceChildren(note(friendlyError(err), 'error')); } }
  async function act(fn, ok) { if (!canWrite()) return; try { await fn(); await draw(); message.replaceChildren(note(ok, 'ok')); } catch (e) { message.replaceChildren(note(friendlyError(e), 'error')); } }

  async function registerForm(m, pane) {
    if (!canAdmin()) return;
    const contextOrg = org.value;
    const cat = await rpc('ars_catalog', { p_include_inactive: false });
    if (org.value !== contextOrg || !document.body.contains(pane)) return;
    const ars = h('select', { id: 'bk-ars' }, h('option', { value: '' }, 'Elija la ARS'), cat.map((a) => h('option', { value: a.id, selected: a.id === m.ars_guess }, a.name)));
    const subs = h('div', { 'aria-live': 'polite' }); const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Registrar y conciliar');
    let inputs = [], loadSequence = 0;
    async function loadSubs() {
      const request = ++loadSequence; const arsId = ars.value; inputs = []; save.disabled = true;
      if (!arsId) { subs.replaceChildren(); return; }
      const box = h('div'); subs.replaceChildren(box);
      const l = await guarded(box, () => rpc('bank_open_submissions', { p_org: contextOrg, p_ars: arsId }));
      if (!l || request !== loadSequence || org.value !== contextOrg || !document.body.contains(pane)) return;
      if (!l.length) { subs.replaceChildren(note('Esa ARS no tiene radicaciones enviadas con saldo para este cliente. Revise la ARS o registre primero la radicación.', 'error')); return; }
      let left = Number(m.amount);
      inputs = l.map((r) => { const v = Math.min(left, Number(r.balance)); left = Math.round((left - v) * 100) / 100; return [r, h('input', { type: 'number', min: '0', max: String(r.balance), step: '0.01', value: v > 0 ? v.toFixed(2) : '', 'aria-label': `Monto para ${r.folio}` })]; });
      const sum = h('strong'); const upd = () => { const t = inputs.reduce((a, [, i]) => a + (Number(i.value) || 0), 0); const invalid = inputs.some(([r, i]) => !Number.isFinite(Number(i.value)) || Number(i.value) < 0 || Number(i.value) > Number(r.balance)); sum.textContent = `Aplicado a radicaciones: ${money(t)} de ${money(m.amount)}`; save.disabled = invalid || Math.abs(t - Number(m.amount)) > 0.005; };
      inputs.forEach(([, i]) => i.addEventListener('input', upd));
      subs.replaceChildren(simple(['Radicación', 'Enviada', 'Médico', 'Saldo', 'Aplicar'], inputs.map(([r, i]) => [r.folio || '—', fmtDate(r.submitted_on), r.provider || '—', money(r.balance), i])), sum); upd();
    }
    ars.addEventListener('change', loadSubs);
    save.addEventListener('click', () => runButton(save, async () => {
      if (!canAdmin() || org.value !== contextOrg) throw new Error('El contexto cambió. Abre nuevamente el registro del pago.');
      const total = inputs.reduce((sum, [, input]) => sum + Number(input.value || 0), 0);
      if (!inputs.length || inputs.some(([row, input]) => !Number.isFinite(Number(input.value)) || Number(input.value) < 0 || Number(input.value) > Number(row.balance)) || Math.abs(total - Number(m.amount)) > 0.005) throw new Error('Revisa la aplicación: los montos deben respetar el saldo y sumar el importe del depósito.');
      const ok = await confirmDialog('Registrar pago y conciliar', `Se registrará ${money(m.amount)} y se aplicará a las radicaciones seleccionadas. Revisa los montos antes de confirmar.`, 'Registrar y conciliar'); if (!ok) return;
      try { await rpc('bank_register_payment', { p_movement: m.id, p_ars: ars.value, p_allocations: inputs.filter(([, i]) => Number(i.value) > 0).map(([r, i]) => ({ submission_id: r.id, amount: Number(i.value) })) }); pane.replaceChildren(); await draw(); message.replaceChildren(note('Pago registrado y depósito conciliado.', 'ok')); }
      catch (e) { msg.replaceChildren(note(friendlyError(e), 'error')); }
    }));
    pane.replaceChildren(h('section', { class: 'i18-card rw-register' }, h('header', {}, h('h3', {}, `Registrar pago de ${money(m.amount)}`), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')), note('Esta acción registra el pago y lo aplica a radicaciones; no es solo una asociación bancaria.'), h('label', { for: 'bk-ars' }, 'ARS que pagó', ars), subs, h('div', { class: 'i18-actions' }, save), msg));
    pane.scrollIntoView({ behavior: 'smooth', block: 'start' }); if (ars.value) loadSubs();
  }

  function uploadCard() {
    const bank = h('input', { id: 'bk-bank', list: 'bk-banks', placeholder: 'Ej.: Banreservas' });
    const acct = h('input', { id: 'bk-acct', maxlength: '20', placeholder: 'Últimos 4 dígitos' });
    const file = h('input', { id: 'bk-file', type: 'file', accept: '.xlsx,.csv,.txt' });
    // Guía de exportación por banco (para cuando el usuario tiene el estado de cuenta en PDF)
    const pdfGuide = h('details', { style: 'margin-top:8px;font-size:13px' },
      h('summary', { style: 'cursor:pointer;color:var(--link)' }, '¿El estado de cuenta es PDF? Ver cómo exportar a Excel por banco'),
      h('ul', { style: 'margin:8px 0 0 16px;line-height:1.8' },
        h('li', {}, 'Banreservas: Mi portal → Movimientos → Exportar → Excel (.xlsx)'),
        h('li', {}, 'Banco Popular: app/portal web → Mi cuenta → Exportar movimientos'),
        h('li', {}, 'BHD: portal web → Consultas → Descargar → Excel'),
        h('li', {}, 'Scotiabank: portal web → Movimientos → Exportar CSV'),
        h('li', {}, 'Banco Santa Cruz: portal → Estado de cuenta → Descargar Excel'),
        h('li', {}, 'Banesco: portal → Cuentas → Exportar → CSV o Excel')));
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar el archivo');
    const out = h('div', { 'aria-live': 'polite' });
    let rows = null; let fname = ''; let draft = null;
    [bank, acct, file].forEach((input) => input.addEventListener('change', () => { draft = null; out.replaceChildren(); }));
    go.addEventListener('click', async () => {
      out.replaceChildren();
      if (!canWrite()) return out.replaceChildren(note('Este contexto es de solo lectura.', 'error'));
      if (!file.files[0]) return out.replaceChildren(note('Elija el archivo del estado de cuenta.', 'error'));
      const context = { organizationId: org.value, bank: bank.value, account: acct.value };
      go.disabled = true;
      try {
        const t = await readTable(file.files[0]); fname = file.files[0].name;
        // Algunos bancos ponen líneas de encabezado antes de la tabla: se busca la fila de títulos
        let hi = -1; let map = null;
        for (let i = 0; i < Math.min(t.length, 20); i++) {
          const m = detectColumns(t[i], ALIASES);
          if (m.fecha != null && (m.monto != null || m.credito != null)) { hi = i; map = m; break; }
        }
        if (hi < 0) throw new Error('No se reconocieron las columnas. El archivo debe tener títulos como «Fecha», «Descripción» y «Monto» (o «Crédito» y «Débito»).');
        const g = (r, k) => (map[k] != null ? String(r[map[k]] ?? '').trim() : '');
        rows = t.slice(hi + 1).filter((r) => r.some((c) => String(c ?? '').trim())).map((r) => ({
          fecha: excelDate(g(r, 'fecha')), descripcion: g(r, 'descripcion'), referencia: g(r, 'referencia'),
          monto: g(r, 'monto') || undefined, credito: g(r, 'credito') || undefined, debito: g(r, 'debito') || undefined }));
        const rep = await rpc('bank_import', { p_org: context.organizationId, p_bank: context.bank, p_account: context.account, p_rows: rows, p_commit: false, p_file: fname });
        if (context.organizationId !== org.value || !document.body.contains(out)) return;
        draft = context; preview(rep);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
    });
    function preview(rep) {
      const reviewed = { ...draft, rows, fname };
      const save = h('button', { class: 'i18-btn', type: 'button', disabled: rep.errors.length > 0 || !rep.deposits }, `Confirmar: guardar ${rep.deposits} depósito(s) y conciliar`);
      save.addEventListener('click', async () => {
        if (!canWrite() || reviewed.organizationId !== org.value || !draft || reviewed.bank !== bank.value || reviewed.account !== acct.value) { out.replaceChildren(note('El contexto cambió. Revisa el archivo otra vez antes de guardar.', 'error')); return; }
        save.disabled = true;
        try { const r = await rpc('bank_import', { p_org: reviewed.organizationId, p_bank: reviewed.bank, p_account: reviewed.account, p_rows: reviewed.rows, p_commit: true, p_file: reviewed.fname });
          await draw(); message.replaceChildren(note(`Listo: ${r.deposits} depósito(s) guardados; ${r.auto_matched} conciliado(s) solos. Revise los pendientes abajo.`, 'ok')); }
        catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
      });
      out.replaceChildren(
        h('div', { class: 'ac-sum', style: 'margin:10px 0' }, h('span', { class: 'ac-pill st-prep' }, `${rep.deposits} depósitos nuevos`),
          h('span', { class: 'ac-pill st-none' }, `${rep.withdrawals_skipped} retiros o cargos omitidos`), h('span', { class: 'ac-pill st-none' }, `${rep.duplicates} ya cargados`),
          h('span', { class: `ac-pill ${rep.errors.length ? 'st-bad' : 'st-ok'}` }, `${rep.errors.length} con error`)),
        rep.errors.length ? simple(['Fila', 'Problema'], rep.errors.map((e) => [String(e.row + 1), e.errors.join(' · ')])) : '',
        rep.rows.length ? simple(['Fecha', 'Descripción', 'Referencia', 'Monto', 'ARS probable'], rep.rows.slice(0, 50).map((r) => [fmtDate(r.date), r.description, r.reference || '—', money(r.amount), r.ars || '—'])) : '',
        h('div', { class: 'i18-actions' }, save));
    }
    return h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, 'Cargar estado de cuenta'),
      h('datalist', { id: 'bk-banks' }, BANKS.map((b) => h('option', { value: b }))),
      h('div', { class: 'i18-bar' }, h('label', { for: 'bk-bank' }, 'Banco', bank), h('label', { for: 'bk-acct' }, 'Cuenta', acct), h('label', { for: 'bk-file' }, 'Archivo (.xlsx o .csv)', file), go), pdfGuide, out);
  }
}
