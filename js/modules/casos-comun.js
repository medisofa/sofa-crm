/** SOFA · 3.0 · Iteración 40 · Piezas comunes de los casos de servicio (cliente y equipo SOFA). */
import { rpc, h, money, fmtDate, note } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

export const STATUS = { solicitado: 'Solicitado', en_proceso: 'En proceso', en_espera_cliente: 'Esperando documentos suyos', presentado: 'Presentado a la ARS',
  aprobado: 'Aprobado', rechazado: 'Rechazado', cerrado: 'Cerrado', cancelado: 'Cancelado' };
export const pill = (s, label) => h('span', { class: `cs-st ${s}` }, label || STATUS[s] || s);
const when = (iso) => (iso ? `${fmtDate(iso)} ${String(iso).slice(11, 16)}` : '');

/** Muestra el caso con su bitácora. staff=true agrega el formulario para actualizarlo. onChange se llama tras guardar. */
export async function caseDetail(box, id, { staff = false, onChange = null } = {}) {
  box.replaceChildren(note('Cargando…'));
  let c;
  try { c = await rpc('service_case_detail', { p_case: id }); } catch (e) { box.replaceChildren(note(e.message, 'error')); return; }
  const kids = [
    h('h3', {}, `${c.folio} · ${c.title}`),
    h('div', { class: 'i18-bar' }, pill(c.status, c.status_label), h('span', { class: 'i18-sub' }, `${c.service}${staff ? ` · ${c.client}` : ''}`)),
    h('p', { class: 'i18-sub' }, [c.provider ? `Médico: ${c.provider}` : '', c.ars ? `ARS: ${c.ars}${c.plan ? ` (${c.plan})` : ''}` : '',
      c.owner ? `Responsable SOFA: ${c.owner}` : '', c.due_date ? `Fecha compromiso: ${fmtDate(c.due_date)}` : '',
      c.fee_amount != null ? `Honorario propuesto: ${money(c.fee_amount)}${c.fee_note ? ` (${c.fee_note})` : ''}` : ''].filter(Boolean).join(' · ')),
    c.detail ? h('p', {}, c.detail) : null,
    h('ol', { class: 'cs-tl', 'aria-label': 'Bitácora del caso' }, c.events.map((e) => h('li', { class: e.visible ? '' : 'cs-int' },
      h('strong', {}, when(e.at)), e.to ? [' · ', pill(e.to, e.to_label)] : '', e.note ? ` · ${e.note}` : '', e.by ? h('span', { class: 'i18-sub' }, ` — ${e.by}`) : '',
      e.visible ? '' : h('span', { class: 'i18-sub' }, ' (interna)'))))];
  if (staff && c.service_code === 'renegociacion' && c.provider && c.ars) kids.push(folderButton(c, () => caseDetail(box, id, { staff, onChange })));
  if (staff) kids.push(updateForm(c, () => { caseDetail(box, id, { staff, onChange }); if (onChange) onChange(); }));
  else if (c.status === 'solicitado') {
    const cancel = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Cancelar mi solicitud');
    const out = h('div', { 'aria-live': 'polite' });
    cancel.addEventListener('click', async () => {
      if (!confirm('¿Cancelar esta solicitud?')) return;
      cancel.disabled = true;
      try { await rpc('service_case_cancel', { p_case: id, p_reason: 'Cancelada por el cliente' }); caseDetail(box, id, { onChange }); if (onChange) onChange(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); cancel.disabled = false; }
    });
    kids.push(h('div', { class: 'i18-bar' }, cancel), out);
  }
  box.replaceChildren(h('div', { class: 'i18-card' }, ...kids));
}

/** 3.5 · Carpeta de negociación (renegociación de tarifarios): tarifas actuales, propuesta, volumen y glosas. */
function folderButton(c, refresh) {
  const b = h('button', { class: 'i18-btn', type: 'button' }, 'Generar carpeta de negociación');
  const out = h('div', { 'aria-live': 'polite' });
  b.addEventListener('click', async () => {
    const w = openPrint();
    try {
      const f = await rpc('negotiation_folder', { p_case: c.id });
      const v = f.volume || {};
      const ok = fillPrint(w, `Carpeta de negociación · ${f.ars}`, `${f.provider}${f.specialty ? ` (${f.specialty})` : ''} · ${f.client} · caso ${f.folio} · ${fmtDate(f.generated_on)}`, [
        { h: 'Resumen' }, { big: `Aumento anual estimado: ${money(f.annual_increase)}` },
        { p: `Volumen aportado a ${f.ars} en 12 meses: ${v.claims || 0} reclamaciones por ${money(v.claimed || 0)}; tasa de glosa ${v.glosa_pct == null ? '—' : v.glosa_pct + ' %'}.` },
        { h: 'Tarifas actuales y propuesta' },
        f.tariffs.length ? { table: { head: ['Procedimiento', 'Tarifa actual', 'Propuesta', 'Cant. 12 meses', 'Aumento anual'], right: [1, 2, 3, 4],
          rows: f.tariffs.map((t) => [`${t.code ? t.code + ' · ' : ''}${t.procedure}`, money(t.current), money(t.proposed), String(t.qty12), money((t.proposed - t.current) * t.qty12)]) } }
          : { p: 'El médico no tiene tarifas vigentes con esta ARS.' },
        f.not_contracted.length ? { h: 'Procedimientos que conviene contratar' } : null,
        f.not_contracted.length ? { table: { head: ['Procedimiento', 'Referencia (su mejor tarifa)'], right: [1],
          rows: f.not_contracted.map((n) => [`${n.code ? n.code + ' · ' : ''}${n.procedure}`, n.reference ? money(n.reference) : '—']) } } : null,
        { h: 'Método' }, { p: f.method }].filter(Boolean));
      if (!ok) { out.replaceChildren(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error')); return; }
      refresh();
    } catch (e) { if (w) w.close(); out.replaceChildren(note(e.message, 'error')); }
  });
  return h('div', {}, h('div', { class: 'i18-bar' }, b), out);
}

function updateForm(c, done) {
  const st = h('select', { id: 'cs-u-st' }, Object.entries(STATUS).map(([k, v]) => h('option', { value: k, selected: k === c.status }, v)));
  const txt = h('textarea', { id: 'cs-u-note', rows: '3', maxlength: '1000', style: 'width:100%', placeholder: 'Qué se hizo o qué falta. Si es visible, el cliente recibe un aviso con este texto.' });
  const vis = h('input', { type: 'checkbox', id: 'cs-u-vis', checked: true });
  const fee = h('input', { type: 'number', min: '0', step: '100', id: 'cs-u-fee', style: 'width:9rem', value: c.fee_amount ?? '' });
  const feeNote = h('input', { type: 'text', id: 'cs-u-feen', maxlength: '120', value: c.fee_note || '', placeholder: 'Ej.: pago único, 10 % de la mejora' });
  const due = h('input', { type: 'date', id: 'cs-u-due', value: c.due_date || '' });
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar avance');
  const out = h('div', { 'aria-live': 'polite' });
  save.addEventListener('click', async () => {
    save.disabled = true; out.replaceChildren();
    const feeVal = fee.value === '' ? null : Number(fee.value);
    try {
      await rpc('service_case_update', { p_case: c.id, p_status: st.value, p_note: txt.value.trim() || null, p_visible: vis.checked,
        p_fee: feeVal === c.fee_amount ? null : feeVal, p_fee_note: feeNote.value.trim() || null, p_owner: null, p_due: due.value && due.value !== c.due_date ? due.value : null });
      done();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
  });
  return h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Actualizar el caso'),
    h('label', { for: 'cs-u-st' }, 'Estado'), st, h('label', { for: 'cs-u-note' }, 'Nota'), txt,
    h('label', { class: 'i18-chk' }, vis, ' Visible para el cliente (le llega como notificación)'),
    h('label', { for: 'cs-u-fee' }, 'Honorario propuesto (RD$)'), fee, h('label', { for: 'cs-u-feen' }, 'Condición del honorario'), feeNote,
    h('label', { for: 'cs-u-due' }, 'Fecha compromiso'), due, h('div', {}, save), out);
}
