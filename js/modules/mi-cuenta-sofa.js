/** SOFA · 3.0 · Iteración 40 · «Mi cuenta con SOFA» (Médico o Centro): servicios contratados, facturas de SOFA
 *  con lo pagado y el saldo, y las solicitudes de servicio con el avance que SOFA comparte. */
import { rpc, h, money, fmtDate, note, kpi, guarded } from '../services/iter18.js';
import { pill, caseDetail } from './casos-comun.js';

const CONTRACT = { borrador: 'Borrador', enviado: 'Enviado para firma', firmado: 'Firmado', terminado: 'Terminado' };
const INVOICE = { emitida: 'Pendiente', pagada_parcial: 'Abonada', pagada: 'Pagada', anulada: 'Anulada' };

export async function render(root, ctx = {}) {
  const org = ctx.membership?.organization_id;
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { id: 'cs-detail' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Mi cuenta con SOFA'),
    h('p', { class: 'i18-sub' }, 'Sus servicios con SOFA, sus facturas y el avance de lo que nos ha pedido.'), box, detail));
  if (!org) { box.replaceChildren(note('No se encontró su consultorio. Cierre la sesión y vuelva a entrar.', 'error')); return; }

  async function load() {
    const d = await guarded(box, () => rpc('client_account', { p_org: org }));
    if (!d) return;
    const s = d.summary;
    box.replaceChildren(
      h('div', { class: 'i18-kpis' }, kpi('Saldo con SOFA', money(s.balance)), kpi('Vencido', money(s.overdue), s.overdue_count ? `${s.overdue_count} factura(s)` : 'Al día'),
        kpi('Servicios contratados', String(d.contracts.length)), kpi('Solicitudes abiertas', String(s.open_cases))),
      h('h3', {}, 'Servicios contratados'),
      d.contracts.length ? table(['Servicio', 'Contrato', 'Estado', 'Desde', 'Hasta'], d.contracts.map((c) => [c.service, c.folio || '—', CONTRACT[c.status] || c.status,
        fmtDate(c.start_date), c.end_date ? fmtDate(c.end_date) : 'Indefinido'])) : note('Aún no tiene contratos registrados. Su contacto en SOFA los carga al firmar.'),
      h('h3', {}, 'Facturas de SOFA'),
      d.invoices.length ? table(['Factura', 'NCF', 'Período', 'Emitida', 'Vence', 'Total', 'Pagado', 'Saldo', 'Estado'], d.invoices.map((i) => [i.folio || '—', i.ncf || '—',
        String(i.period || '').slice(0, 7), fmtDate(i.issued_on), fmtDate(i.due_on), money(i.total), money(i.paid), money(i.balance),
        i.overdue ? h('span', { class: 'cs-over' }, 'Vencida') : (INVOICE[i.status] || i.status)])) : note('No tiene facturas de SOFA.'),
      s.overdue > 0 ? note('Tiene facturas vencidas. Si ya pagó, envíe el comprobante a su contacto en SOFA para aplicarlo.', 'warn') : null,
      h('h3', {}, 'Mis solicitudes de servicio'),
      d.cases.length ? h('div', { class: 'i18-list' }, d.cases.map((c) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver avance');
        b.addEventListener('click', () => { caseDetail(detail, c.id, { onChange: load }); detail.scrollIntoView({ behavior: 'smooth' }); });
        return h('div', { class: 'i18-card' }, h('div', { class: 'i18-bar' }, h('strong', {}, `${c.folio} · ${c.title}`), pill(c.status, c.status_label)),
          h('div', { class: 'i18-sub' }, `Pedida el ${fmtDate(c.opened_at)}${c.due_date ? ` · compromiso ${fmtDate(c.due_date)}` : ''}${c.fee_amount != null ? ` · honorario propuesto ${money(c.fee_amount)}` : ''}`),
          c.last?.note ? h('p', {}, `Último avance (${fmtDate(c.last.at)}): ${c.last.note}`) : null, b);
      })) : note('Aún no ha pedido servicios.'),
      requestForm(d));
  }

  function requestForm(d) {
    const svc = h('select', { id: 'cs-r-svc' }, d.services.map((s) => h('option', { value: s.code, selected: s.code === 'renegociacion' }, s.name)));
    const prov = h('select', { id: 'cs-r-prov' }, h('option', { value: '' }, 'Todo el consultorio'), d.providers.map((p) => h('option', { value: p.id }, p.name)));
    const txt = h('textarea', { id: 'cs-r-txt', rows: '3', maxlength: '2000', style: 'width:100%', placeholder: 'Ej.: quiero renegociar las tarifas de Humano para el plan Royal.' });
    const send = h('button', { class: 'i18-btn', type: 'button' }, 'Enviar solicitud');
    const out = h('div', { 'aria-live': 'polite' });
    send.addEventListener('click', async () => {
      send.disabled = true; out.replaceChildren();
      try {
        const r = await rpc('service_case_request', { p_org: org, p_service: svc.value, p_detail: txt.value.trim(), p_provider: prov.value || null, p_ars: null });
        txt.value = '';
        await load();
        detail.replaceChildren(note(`Solicitud ${r.folio} enviada. SOFA le avisará aquí y en sus notificaciones cada vez que haya un avance.`));
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      finally { send.disabled = false; }
    });
    return h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Pedir un servicio a SOFA'),
      h('label', { for: 'cs-r-svc' }, 'Servicio'), svc, h('label', { for: 'cs-r-prov' }, 'Para'), prov,
      h('label', { for: 'cs-r-txt' }, 'Qué necesita'), txt, h('div', {}, send), out);
  }

  const table = (head, rows) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x) => h('th', {}, x)))), h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x) => h('td', {}, x)))))));

  await load();
  const want = String(ctx.arg || '');
  if (/^[0-9a-f-]{36}$/.test(want)) caseDetail(detail, want, { onChange: load });
}
export default render;
