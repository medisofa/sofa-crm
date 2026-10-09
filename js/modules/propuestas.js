/** SOFA · 4.1 · Iteración 51 · Diagnóstico de fugas y propuesta con ROI (equipo comercial).
 *  Con 4 datos del prospecto calcula cuánto pierde y arma la propuesta para imprimir: «por cada RD$1 que usted nos paga, le generamos RD$X». */
import { rpc, h, money, fmtDate, note, guarded } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const ST = { borrador: 'Borrador', enviada: 'Enviada', aceptada: 'Aceptada', rechazada: 'Rechazada' };

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const form = h('div');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Diagnóstico de fugas y propuestas'),
    h('p', { class: 'i18-sub' }, 'Auditoría gratuita en 4 datos: cuánto factura, cuánto le glosan, cuánto se podría recuperar y cuántos días tarda en cobrar. De ahí sale la propuesta con el retorno.'),
    form, box));

  async function load() {
    const d = await guarded(box, () => rpc('leak_pipeline'));
    if (!d) return;
    drawForm(d);
    const s = d.summary || {};
    box.replaceChildren(h('p', { class: 'i18-sub' }, `Últimos 6 meses: ${s.sent || 0} propuesta(s) enviadas · ${s.accepted || 0} aceptadas · ${s.rejected || 0} rechazadas.`),
      d.diagnostics.length ? h('div', { class: 'i18-list' }, d.diagnostics.map(diagCard)) : note('Todavía no hay diagnósticos.'));
  }

  function drawForm(d) {
    const lead = h('select', { id: 'pr-lead' }, h('option', { value: '' }, 'Elija el prospecto'), d.leads.map((l) => h('option', { value: l.id }, `${l.company}${l.specialty ? ` · ${l.specialty}` : ''}`)));
    const bill = h('input', { type: 'number', id: 'pr-bill', min: '0', step: '1000', placeholder: 'Ej.: 150000' });
    const gl = h('input', { type: 'number', id: 'pr-gl', min: '0', max: '100', value: '20' });
    const rec = h('input', { type: 'number', id: 'pr-rec', min: '0', max: '100', value: '50' });
    const dso = h('input', { type: 'number', id: 'pr-dso', min: '0', max: '720', value: '90' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Calcular diagnóstico');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      go.disabled = true; out.replaceChildren();
      try { await rpc('leak_diagnostic_create', { p_lead: lead.value || null, p_monthly_billing: Number(bill.value), p_glosa_pct: Number(gl.value), p_recoverable_pct: Number(rec.value), p_dso_days: Number(dso.value) }); await load(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    form.replaceChildren(h('details', { class: 'i18-card', open: !d.diagnostics.length }, h('summary', {}, 'Nuevo diagnóstico'),
      h('div', { class: 'i18-form' }, h('label', { for: 'pr-lead' }, 'Prospecto'), lead, h('label', { for: 'pr-bill' }, 'Facturación mensual a las ARS (RD$, aproximado)'), bill,
        h('label', { for: 'pr-gl' }, 'Glosa (% de lo facturado)'), gl, h('label', { for: 'pr-rec' }, 'De lo glosado, % que se podría recuperar'), rec,
        h('label', { for: 'pr-dso' }, 'Días que tarda en cobrar'), dso, h('div', {}, go), out)));
  }

  function diagCard(d) {
    const fee = h('input', { type: 'number', min: '0', step: '500', value: '5000', 'aria-label': 'Cuota mensual', style: 'width:8rem' });
    const mk = h('button', { class: 'i18-btn', type: 'button' }, 'Crear propuesta');
    const out = h('div', { 'aria-live': 'polite' });
    mk.addEventListener('click', async () => { try { const p = await rpc('leak_proposal_create', { p_diagnostic: d.id, p_monthly_fee: Number(fee.value), p_setup_fee: 0, p_services: ['facturacion'], p_valid_days: 15 }); printProposal(p); load(); } catch (e) { out.replaceChildren(note(e.message, 'error')); } });
    return h('div', { class: 'i18-card' }, h('strong', {}, `${d.company || 'Prospecto'} · ${fmtDate(d.created_at)}`),
      h('p', {}, `Factura ${money(d.monthly_billing)} al mes · glosa ${d.glosa_pct} % (${money(d.glosa_monthly)}) · recuperable ${money(d.recoverable_monthly)} · ${d.dso_days} días para cobrar (${money(d.trapped_by_dso)} atrapados).`),
      h('p', { class: 'i18-sub' }, `Ganancia estimada: ${money(d.gain_monthly)} al mes.`),
      d.proposals.length ? h('ul', {}, d.proposals.map((p) => propRow(p))) : null,
      h('div', { class: 'i18-bar' }, h('label', {}, 'Cuota mensual (RD$)', fee), mk), out);
  }

  function propRow(p) {
    const view = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Imprimir');
    view.addEventListener('click', async () => { const w = openPrint(); try { fillProposal(w, await rpc('leak_proposal_get', { p_id: p.id })); } catch (e) { if (w) w.close(); box.prepend(note(e.message, 'error')); } });
    const acts = [view];
    if (['borrador', 'enviada'].includes(p.status)) {
      const nt = h('input', { type: 'text', maxlength: '200', placeholder: 'Motivo (si la rechaza)', 'aria-label': 'Motivo' });
      const o = h('div', { 'aria-live': 'polite' });
      const set = (st) => async () => { try { await rpc('leak_proposal_set_status', { p_id: p.id, p_status: st, p_note: nt.value || null }); load(); } catch (e) { o.replaceChildren(note(e.message, 'error')); } };
      [['enviada', 'Marcar enviada'], ['aceptada', 'Aceptada'], ['rechazada', 'Rechazada']].forEach(([st, t]) => { if (!(st === 'enviada' && p.status === 'enviada')) { const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, t); b.addEventListener('click', set(st)); acts.push(b); } });
      acts.push(nt, o);
    }
    return h('li', {}, `${p.folio} · ${ST[p.status]} · ${money(p.monthly_fee)}/mes · vence ${fmtDate(p.valid_until)}${p.expired ? ' (vencida)' : ''} `, h('div', { class: 'i18-bar' }, ...acts));
  }

  function printProposal(p) { const w = openPrint(); fillProposal(w, p); }
  function fillProposal(w, p) {
    const m = p.math; const l = p.lead || {};
    if (!fillPrint(w, `Propuesta ${p.folio} · ${l.company || ''}`, `Para ${l.contact || ''}${l.specialty ? ` (${l.specialty})` : ''} · válida hasta ${fmtDate(p.valid_until)}`, [
      { big: `Por cada RD$1 que usted nos paga, le generamos RD$${m.roi ?? '—'}` },
      { h: 'Lo que hoy pierde' },
      { table: { head: ['Concepto', 'Al mes'], right: [1], rows: [['Facturación a las ARS', money(m.monthly_billing)], [`Glosa (${m.glosa_pct} %)`, money(m.glosa_monthly)],
        [`Recuperable de esa glosa (${m.recoverable_pct} %)`, money(m.recoverable_monthly)], ['Glosa evitable si baja a 5 %', money(m.prevented_monthly)]] } },
      { p: `Además tiene ${money(m.cash_release)} atrapados por cobrar después de 60 días (cobra en ${m.dso_days} días). Bajar a menos de 60 días libera ese dinero.` },
      { h: 'Nuestra propuesta' },
      { table: { head: ['Servicio', 'Cuota'], right: [1], rows: [...(p.services || []).map((s) => [s.name, '']), ['Cuota mensual', money(p.monthly_fee)], ...(Number(p.setup_fee) ? [['Pago inicial', money(p.setup_fee)]] : [])] } },
      { p: `Ganancia estimada para usted: ${money(m.gain_monthly)} al mes.` },
      { h: 'Cómo se calculó' }, { p: p.basis },
      { p: 'Soluciones de Facturación Médica (SOFA) · Santiago de los Caballeros' }])) {
      box.prepend(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error'));
    }
  }

  await load();
}
export default render;
