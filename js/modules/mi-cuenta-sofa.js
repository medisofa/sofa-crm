/** SOFA · 3.0 · Iteración 40 · «Mi cuenta con SOFA» (Médico o Centro): servicios contratados, facturas de SOFA
 *  con lo pagado y el saldo, y las solicitudes de servicio con el avance que SOFA comparte.
 *  5.31.0 · Ampliado con pagos recibidos, bitácora de actividad y resumen de ARS en uso. */
import { rpc, h, money, fmtDate, note, kpi, guarded } from '../services/iter18.js';
import { pill, caseDetail } from './casos-comun.js';
import { ecfSteps } from './ecf-comun.js';

const CONTRACT = { borrador: 'Borrador', enviado: 'Enviado para firma', firmado: 'Firmado', terminado: 'Terminado' };
const INVOICE = { emitida: 'Pendiente', pagada_parcial: 'Abonada', pagada: 'Pagada', anulada: 'Anulada' };
// 5.31.0 · Labels de bitácora y estado de códigos ARS, para presentar al cliente en castellano.
const FEED_KIND = { caso: 'Servicio', factura: 'Factura', pago: 'Pago' };
const ARS_STATUS = {
  aprobado: 'Con código', solicitado: 'Solicitado',
  pendiente_respuesta: 'Pendiente de respuesta', en_preparacion: 'En preparación',
  rechazado: 'Rechazado', cancelado: 'Cancelado'
};

function fmtDateTime(iso) { if (!iso) return '—'; return fmtDate(iso) + ' ' + String(iso).slice(11, 16); }

export async function render(root, ctx = {}) {
  const org = ctx.membership?.organization_id;
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { id: 'cs-detail' });
  const ecf = h('div', { id: 'cs-ecf', 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Mi cuenta con SOFA'),
    h('p', { class: 'i18-sub' }, 'Sus servicios con SOFA, sus facturas y el avance de lo que nos ha pedido.'), ecf, box, detail));
  if (!org) { box.replaceChildren(note('No se encontró su consultorio. Cierre la sesión y vuelva a entrar.', 'error')); return; }

  // 3.1 · Facturación electrónica (e-CF): pasos que faltan y lotes que se bloquearían
  async function loadEcf() {
    try {
      const s = await rpc('ecf_client_status', { p_org: org });
      const done = s.steps.filter((x) => x.done).length;
      ecf.replaceChildren(h('details', { class: `i18-card ecf-card ${s.status}`, open: s.status !== 'listo' && s.days_left <= 45 },
        h('summary', {}, h('strong', {}, 'Facturación electrónica (e-CF): '), s.status === 'listo' ? 'lista' : `${done} de ${s.steps.length} pasos · ${s.days_left < 0 ? 'obligación vencida' : `faltan ${s.days_left} días`}`),
        ecfSteps(s, loadEcf)));
    } catch (_) { ecf.replaceChildren(); }   // antes de la 140 no existe
  }
  loadEcf();

  async function load() {
    // 5.31.0 · Dos RPCs en paralelo: el contrato existente client_account + el nuevo
    // client_account_detail (pagos, actividad, ARS). Si el segundo falla (p.ej. la migración
    // aún no se aplicó en un entorno), se degrada mostrando solo lo histórico.
    const [d, detailData] = await Promise.all([
      guarded(box, () => rpc('client_account', { p_org: org })),
      rpc('client_account_detail', { p_org: org }).catch(() => null)
    ]);
    if (!d) return;
    const s = d.summary;
    const extra = detailData || { payments: [], activity: [], ars_summary: null };
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
      // 5.31.0 · Pagos recibidos (histórico aplicado por SOFA sobre las facturas)
      h('h3', {}, 'Pagos recibidos'),
      extra.payments?.length ? table(['Fecha', 'Factura', 'Período', 'Método', 'Referencia', 'Monto'],
        extra.payments.map((p) => [fmtDate(p.paid_on), p.folio || '—', String(p.period || '').slice(0, 7), p.method || '—', p.reference || '—', money(p.amount)]))
        : note('Aún no se han aplicado pagos a sus facturas de SOFA.'),
      // 5.31.0 · ARS en uso: resumen del estado de códigos que tienen sus médicos
      h('h3', {}, 'ARS en uso'),
      extra.ars_summary ? h('div', { class: 'cs-ars' },
        h('div', { class: 'i18-kpis' },
          kpi('Médico-ARS con código', String(extra.ars_summary.con_codigo)),
          kpi('En trámite', String(extra.ars_summary.en_tramite), extra.ars_summary.alertas ? `${extra.ars_summary.alertas} con alerta` : 'Sin alertas'),
          kpi('Con alerta (>30 días)', String(extra.ars_summary.alertas))),
        extra.ars_summary.items?.length
          ? table(['Médico', 'ARS', 'Estado'],
              extra.ars_summary.items.map((r) => [r.provider, r.ars,
                h('span', { class: r.alert ? 'cs-over' : '' }, ARS_STATUS[r.status] || r.status)]))
          : note('Sus médicos aún no tienen códigos de ARS registrados. Vaya a Códigos ARS para solicitarlos.'))
        : note('Esta sección requiere actualizar la base (migración pendiente). Pida a SOFA aplicar la 20261112.', 'info'),
      // 5.31.0 · Bitácora de actividad: avances de servicios + facturas + pagos (visible al cliente)
      h('h3', {}, 'Bitácora de actividad'),
      extra.activity?.length ? h('div', { class: 'i18-list cs-feed' }, extra.activity.map((e) => h('div', { class: 'i18-card cs-feed-row' },
        h('div', { class: 'i18-bar' },
          h('span', { class: 'i18-pill' }, FEED_KIND[e.kind] || e.kind),
          h('span', { class: 'i18-sub' }, fmtDateTime(e.at))),
        h('p', {}, e.description),
        e.ref ? h('div', { class: 'i18-sub' }, `Ref.: ${e.ref}`) : null)))
        : note('Aún no hay movimientos registrados en su cuenta con SOFA.'),
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
    return h('details', {},
      h('summary', { class: 'i18-sub', style: 'cursor:pointer;padding:6px 0;list-style:none' }, '＋ Pedir un servicio a SOFA'),
      h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Pedir un servicio a SOFA'),
        h('label', { for: 'cs-r-svc' }, 'Servicio'), svc, h('label', { for: 'cs-r-prov' }, 'Para'), prov,
        h('label', { for: 'cs-r-txt' }, 'Qué necesita'), txt, h('div', {}, send), out));
  }

  const table = (head, rows) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, head.map((x) => h('th', {}, x)))), h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x, ci) => h('td', { 'data-l': head[ci] || '' }, x)))))));

  await load();
  const want = String(ctx.arg || '');
  if (/^[0-9a-f-]{36}$/.test(want)) caseDetail(detail, want, { onChange: load });
}
export default render;
