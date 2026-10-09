/** SOFA · 2.7 · Iteración 37 · Conciliación bancaria de los pagos de las ARS (equipo SOFA).
 *  1) Cargar el estado de cuenta del banco del médico (Excel o CSV): se guardan solo los depósitos, sin duplicados.
 *  2) Cruce automático con los pagos de ARS registrados (mismo monto, fecha a ± 7 días).
 *  3) Lo pendiente: conciliar a mano, registrar el pago desde el depósito o marcar «no es de ARS».
 *  4) Pagos registrados que no aparecen en el banco, radicaciones con pago parcial y sin pago vencidas. */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

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
const iso = (d) => d.toISOString().slice(0, 10);

export async function render(root, ctx = {}) {
  const write = can('bank.reconcile', ctx.role); const admin = can('bank.admin', ctx.role);
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' }); const body = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Conciliación bancaria'),
    h('p', { class: 'i18-sub' }, 'Cruce del estado de cuenta del médico con los pagos de las ARS. Se cargan solo los depósitos; los repetidos se omiten solos.'), top, body);
  const ov = await guarded(top, () => rpc('bank_overview'));
  if (!ov) return;
  if (!ov.length) { top.replaceChildren(note('No hay clientes activos.')); return; }
  const org = h('select', { id: 'bk-org' }, ov.map((o) => h('option', { value: o.organization_id }, `${o.client}${o.pending ? ` · ${o.pending} pendiente(s)` : ''}`)));
  const from = h('input', { id: 'bk-from', type: 'date', value: iso(new Date(Date.now() - 90 * 864e5)) });
  const to = h('input', { id: 'bk-to', type: 'date', value: iso(new Date()) });
  top.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'bk-org' }, 'Cliente', org), h('label', { for: 'bk-from' }, 'Desde', from), h('label', { for: 'bk-to' }, 'Hasta', to)));
  [org, from, to].forEach((x) => x.addEventListener('change', draw));
  await draw();

  async function draw() {
    const d = await guarded(body, () => rpc('bank_reconciliation', { p_org: org.value, p_from: from.value || null, p_to: to.value || null }));
    if (!d) return;
    const s = d.summary; const pane = h('div', { 'aria-live': 'polite' });
    body.replaceChildren(
      h('div', { class: 'i18-kpis' }, [['Depósitos', `${s.deposits} · ${money(s.deposits_amount)}`], ['Conciliados', `${s.matched} · ${money(s.matched_amount)}`],
        ['Sin conciliar', `${s.pending} · ${money(s.pending_amount)}`, s.pending ? 'i18-lvl-critico' : ''], ['Diferencias anotadas', money(s.differences)]].map(([l, v, c]) =>
        h('div', { class: `i18-kpi ${c || ''}` }, h('div', { class: 'i18-kpi-v' }, v), h('div', { class: 'i18-kpi-l' }, l)))),
      write ? uploadCard() : '', pane,
      h('h3', {}, 'Depósitos del período'), movements(d.movements, pane),
      h('h3', {}, 'Pagos registrados que no aparecen en el banco'),
      d.payments_without_deposit.length ? simple(['Pago', 'ARS', 'Fecha', 'Monto', 'Referencia', 'Días'], d.payments_without_deposit.map((p) => [p.folio || '—', p.ars, fmtDate(p.paid_on), money(p.amount), p.reference || '—', String(p.days)]))
        : note('Todos los pagos registrados del período aparecen en el banco (o todavía no se ha cargado el estado de cuenta de esas fechas).'),
      h('h3', {}, 'Radicaciones con pago parcial'),
      d.partial.length ? simple(['Radicación', 'ARS', 'Enviada', 'Reclamado', 'Pagado', 'Glosa aceptada', 'Saldo', '% cobrado'], d.partial.map((p) => [p.folio || '—', p.ars, fmtDate(p.submitted_on), money(p.claimed), money(p.paid), money(p.glosa_accepted), money(p.balance), `${p.pct ?? 0} %`]))
        : note('No hay radicaciones con pago parcial.'),
      h('h3', {}, `Radicaciones sin ningún pago después de ${d.payment_term_days} días`),
      d.unpaid_overdue.length ? simple(['Radicación', 'ARS', 'Enviada', 'Reclamado', 'Días'], d.unpaid_overdue.map((p) => [p.folio || '—', p.ars, fmtDate(p.submitted_on), money(p.claimed), String(p.days)]))
        : note('Ninguna radicación pasa del plazo de pago sin cobrar.'),
      h('h3', {}, 'Estados de cuenta cargados'),
      d.statements.length ? simple(['Fecha', 'Banco', 'Cuenta', 'Archivo', 'Período', 'Depósitos', 'Repetidos', 'Por'], d.statements.map((x) => [fmtDate(x.at), x.bank, x.account || '—', x.file || '—', `${fmtDate(x.from)} – ${fmtDate(x.to)}`, String(x.deposits), String(x.duplicates), x.by || '—']))
        : note('Todavía no hay estados de cuenta cargados para este cliente.'));
  }

  function simple(cols, rows) {
    return h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, cols.map((c) => h('th', {}, c)))),
      h('tbody', {}, rows.map((r) => h('tr', {}, r.map((c) => h('td', {}, c)))))));
  }

  function movements(list, pane) {
    if (!list.length) return note('No hay depósitos cargados en este período.');
    return h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table bk-table' },
      h('thead', {}, h('tr', {}, ['Fecha', 'Descripción', 'Monto', 'ARS probable', 'Estado', 'Pago / acción'].map((c) => h('th', {}, c)))),
      h('tbody', {}, list.map((m) => h('tr', { class: m.status === 'sin_conciliar' ? 'bk-pending' : '' },
        h('td', {}, fmtDate(m.date)), h('td', {}, m.description, m.reference ? h('div', { class: 'i18-sub' }, `Ref. ${m.reference}`) : ''),
        h('td', { class: 'i18-r' }, money(m.amount)), h('td', {}, m.ars || '—'), h('td', {}, pill(m.status)),
        h('td', {}, actions(m, pane)))))));
  }

  function actions(m, pane) {
    if (m.status === 'conciliado') {
      const p = m.payment || {};
      return [h('div', {}, `${p.folio || 'Pago'} · ${p.ars || ''} · ${fmtDate(p.paid_on)} · ${money(p.amount)}`),
        m.difference ? h('div', { class: 'i18-sub' }, `Diferencia ${money(m.difference)}${m.note ? ` · ${m.note}` : ''}`) : '',
        admin ? h('button', { class: 'i18-link', type: 'button', onclick: () => act(() => rpc('bank_unmatch', { p_movement: m.id }), 'Conciliación deshecha.') }, 'Deshacer') : ''];
    }
    if (m.status === 'no_ars') return [h('div', { class: 'i18-sub' }, m.note || ''), admin ? h('button', { class: 'i18-link', type: 'button', onclick: () => act(() => rpc('bank_unmatch', { p_movement: m.id }), 'Movimiento devuelto a pendiente.') }, 'Deshacer') : ''];
    if (!write) return h('span', { class: 'i18-sub' }, 'Pendiente');
    const cands = m.candidates || [];
    const sel = h('select', { 'aria-label': 'Pago para conciliar' }, h('option', { value: '' }, cands.length ? 'Elija el pago…' : 'Sin pagos parecidos'),
      cands.map((c) => h('option', { value: c.payment_id, 'data-amount': c.amount }, `${c.folio || 'Pago'} · ${c.ars} · ${fmtDate(c.paid_on)} · ${money(c.amount)}`)));
    const go = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !cands.length }, 'Conciliar');
    go.addEventListener('click', () => {
      if (!sel.value) return;
      const amt = Number(sel.selectedOptions[0].dataset.amount);
      let why = null;
      if (Math.abs(amt - m.amount) > 0.01) { why = prompt(`El depósito (${money(m.amount)}) y el pago (${money(amt)}) no coinciden. ¿Por qué? (por ejemplo: retención del ISR)`); if (why === null) return; }
      act(() => rpc('bank_match', { p_movement: m.id, p_payment: sel.value, p_note: why }), 'Depósito conciliado.');
    });
    return [h('div', { class: 'bk-actions' }, sel, go),
      h('div', { class: 'bk-actions' },
        admin ? h('button', { class: 'i18-link', type: 'button', onclick: () => registerForm(m, pane) }, 'Registrar el pago de la ARS') : '',
        h('button', { class: 'i18-link', type: 'button', onclick: () => {
          const why = prompt('¿De dónde viene este depósito? (por ejemplo: pago de paciente privado)'); if (why === null) return;
          act(() => rpc('bank_ignore', { p_movement: m.id, p_reason: why }), 'Marcado como «no es de ARS».');
        } }, 'No es de ARS'))];
  }

  async function act(fn, ok) {
    try { await fn(); await draw(); body.prepend(note(ok, 'ok')); } catch (e) { body.prepend(note(e.message, 'error')); window.scrollTo({ top: 0, behavior: 'smooth' }); }
  }

  async function registerForm(m, pane) {
    const cat = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);
    const ars = h('select', { id: 'bk-ars' }, h('option', { value: '' }, 'Elija la ARS'), cat.map((a) => h('option', { value: a.id, selected: a.id === m.ars_guess }, a.name)));
    const subs = h('div', { 'aria-live': 'polite' }); const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Registrar y conciliar');
    let inputs = [];
    async function loadSubs() {
      inputs = []; save.disabled = true;
      if (!ars.value) { subs.replaceChildren(); return; }
      const l = await guarded(subs, () => rpc('bank_open_submissions', { p_org: org.value, p_ars: ars.value }));
      if (!l) return;
      if (!l.length) { subs.replaceChildren(note('Esa ARS no tiene radicaciones enviadas con saldo para este cliente. Revise la ARS o registre primero la radicación.', 'error')); return; }
      let left = m.amount;
      inputs = l.map((r) => { const v = Math.min(left, Number(r.balance)); left = Math.round((left - v) * 100) / 100; return [r, h('input', { type: 'number', min: '0', step: '0.01', value: v > 0 ? v.toFixed(2) : '', 'aria-label': `Monto para ${r.folio}` })]; });
      const sum = h('strong'); const upd = () => { const t = inputs.reduce((a, [, i]) => a + (Number(i.value) || 0), 0); sum.textContent = `Aplicado: ${money(t)} de ${money(m.amount)}`; save.disabled = Math.abs(t - m.amount) > 0.005; };
      inputs.forEach(([, i]) => i.addEventListener('input', upd));
      subs.replaceChildren(simple(['Radicación', 'Enviada', 'Médico', 'Saldo', 'Aplicar'], inputs.map(([r, i]) => [r.folio || '—', fmtDate(r.submitted_on), r.provider || '—', money(r.balance), i])), sum);
      upd();
    }
    ars.addEventListener('change', loadSubs);
    save.addEventListener('click', async () => {
      save.disabled = true;
      try {
        await rpc('bank_register_payment', { p_movement: m.id, p_ars: ars.value,
          p_allocations: inputs.filter(([, i]) => Number(i.value) > 0).map(([r, i]) => ({ submission_id: r.id, amount: Number(i.value) })) });
        pane.replaceChildren(); await draw(); body.prepend(note('Pago registrado y depósito conciliado.', 'ok'));
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'i18-card hc-form' }, h('header', { class: 'hc-head' }, h('strong', {}, `Registrar el pago de ${money(m.amount)} del ${fmtDate(m.date)}`),
      h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      note('Aplique el depósito a las radicaciones que paga. El total aplicado debe ser igual al depósito.'),
      h('label', { for: 'bk-ars' }, 'ARS que pagó', ars), subs, h('div', { class: 'i18-actions' }, save), msg));
    pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (ars.value) loadSubs();
  }

  function uploadCard() {
    const bank = h('input', { id: 'bk-bank', list: 'bk-banks', placeholder: 'Ej.: Banreservas' });
    const acct = h('input', { id: 'bk-acct', maxlength: '20', placeholder: 'Últimos 4 dígitos' });
    const file = h('input', { id: 'bk-file', type: 'file', accept: '.xlsx,.csv,.txt' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar el archivo');
    const out = h('div', { 'aria-live': 'polite' });
    let rows = null; let fname = '';
    go.addEventListener('click', async () => {
      out.replaceChildren();
      if (!file.files[0]) return out.replaceChildren(note('Elija el archivo del estado de cuenta.', 'error'));
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
        const rep = await rpc('bank_import', { p_org: org.value, p_bank: bank.value, p_account: acct.value, p_rows: rows, p_commit: false, p_file: fname });
        preview(rep);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
    });
    function preview(rep) {
      const save = h('button', { class: 'i18-btn', type: 'button', disabled: rep.errors.length > 0 || !rep.deposits }, `Confirmar: guardar ${rep.deposits} depósito(s) y conciliar`);
      save.addEventListener('click', async () => {
        save.disabled = true;
        try { const r = await rpc('bank_import', { p_org: org.value, p_bank: bank.value, p_account: acct.value, p_rows: rows, p_commit: true, p_file: fname });
          await draw(); body.prepend(note(`Listo: ${r.deposits} depósito(s) guardados; ${r.auto_matched} conciliado(s) solos. Revise los pendientes abajo.`, 'ok')); }
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
      h('div', { class: 'i18-bar' }, h('label', { for: 'bk-bank' }, 'Banco', bank), h('label', { for: 'bk-acct' }, 'Cuenta', acct), h('label', { for: 'bk-file' }, 'Archivo (.xlsx o .csv)', file), go), out);
  }
}
