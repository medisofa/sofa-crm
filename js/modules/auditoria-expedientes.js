/** SOFA · 3.6 · Iteración 46 · Auditoría preventiva del expediente.
 *  Equipo SOFA: activar por cliente, seleccionar la muestra y revisar con el checklist médico-legal.
 *  Médico: su informe con las 5 omisiones más frecuentes y la plantilla de nota que las evita. */
import { rpc, h, money, fmtDate, note, guarded, kpi, clientOptions, clientName } from '../services/iter18.js';

const REASON = { alto_valor: 'Alto valor', aleatoria: 'Aleatoria', manual: 'Manual' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (ctx.role === 'client') return report(root, ctx.membership?.organization_id, true);
  const canEdit = ['super_admin', 'admin', 'auditor'].includes(ctx.role);
  const canSet = ['super_admin', 'admin'].includes(ctx.role);
  const sel = h('select', { id: 'au-org' }, h('option', { value: '' }, 'Todos los clientes'));
  const st = h('select', { id: 'au-st' }, [['pendiente', 'Pendientes'], ['con_omisiones', 'Con omisiones'], ['conforme', 'Conformes']].map(([v, t]) => h('option', { value: v }, t)));
  const sample = h('button', { class: 'i18-btn', type: 'button', disabled: !canEdit }, 'Seleccionar muestra ahora');
  const msg = h('div', { 'aria-live': 'polite' });
  const settings = h('div');
  const box = h('div', { 'aria-live': 'polite' });
  const rep = h('div');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Auditoría preventiva de expedientes'),
    h('p', { class: 'i18-sub' }, 'Auditar antes de facturar: 100 % de las reclamaciones de alto valor y una muestra al azar del resto, con el checklist médico-legal. No cambia el estado de la reclamación.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'au-org' }, 'Cliente', sel), h('label', { for: 'au-st' }, 'Estado', st), sample), msg, settings, box, rep));
  try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { msg.replaceChildren(note(e.message, 'error')); }

  sample.addEventListener('click', async () => {
    sample.disabled = true; msg.replaceChildren();
    try { const r = await rpc('legal_audit_sample', { p_org: sel.value || null }); msg.replaceChildren(note(`Muestra: ${r.alto_valor} de alto valor y ${r.aleatoria} al azar.`)); await load(); }
    catch (e) { msg.replaceChildren(note(e.message, 'error')); } finally { sample.disabled = !canEdit; }
  });

  async function load() {
    const d = await guarded(box, () => rpc('legal_audit_queue', { p_org: sel.value || null, p_status: st.value }));
    if (!d) return;
    drawSettings(d);
    box.replaceChildren(d.items.length ? h('div', { class: 'i18-list' }, d.items.map((i) => item(i, d))) : note(st.value === 'pendiente' ? 'No hay expedientes por revisar. Active la auditoría del cliente y seleccione la muestra.' : 'No hay expedientes con ese estado.'));
    if (sel.value) report(rep, sel.value, false); else rep.replaceChildren();
  }

  function drawSettings(d) {
    const org = sel.value;
    if (!org || !canSet) { settings.replaceChildren(); return; }
    const cur = d.clients.find((c) => c.organization_id === org) || { active: false, high_value_from: 10000, random_pct: 10 };
    const act = h('input', { type: 'checkbox', id: 'au-s-act', checked: cur.active });
    const hv = h('input', { type: 'number', id: 'au-s-hv', min: '0', step: '500', value: String(cur.high_value_from), style: 'width:9rem' });
    const pct = h('input', { type: 'number', id: 'au-s-pct', min: '1', max: '100', value: String(cur.random_pct), style: 'width:5rem' });
    const save = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      try { await rpc('legal_audit_settings_save', { p_org: org, p_active: act.checked, p_high_value: Number(hv.value), p_random_pct: Number(pct.value) }); out.replaceChildren(note('Guardado. La muestra se selecciona sola cada día hábil a las 8:10 a. m.')); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    settings.replaceChildren(h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Servicio para este cliente'),
      h('div', { class: 'i18-bar' }, h('label', { class: 'i18-chk' }, act, ' Auditoría activa'), h('label', { for: 'au-s-hv' }, 'Alto valor desde (RD$)', hv),
        h('label', { for: 'au-s-pct' }, 'Muestra al azar (%)', pct), save), out));
  }

  function item(i, d) {
    const head = h('div', {}, h('strong', {}, `${i.folio || 'Sin folio'} · ${i.patient} · ${money(i.amount)}`),
      h('div', { class: 'i18-sub' }, `${i.client} · ${i.provider || '—'} · ${i.service || ''} · ${fmtDate(i.service_date)} · ${REASON[i.reason]}`));
    if (i.status !== 'pendiente') {
      return h('div', { class: 'i18-card' }, head, h('p', {}, i.status === 'conforme' ? 'Conforme.' : `Omisiones: ${i.omissions.map((o) => d.checklist.find((c) => c.code === o)?.label || o).join('; ')}`),
        i.note ? h('p', { class: 'i18-sub' }, i.note) : null);
    }
    if (!canEdit) return h('div', { class: 'i18-card' }, head);
    const checks = d.checklist.map((c) => ({ c, box: h('input', { type: 'checkbox', checked: true, id: `au-${i.id}-${c.code}` }) }));
    const txt = h('input', { type: 'text', maxlength: '500', placeholder: 'Qué falta exactamente (si algo falta)', 'aria-label': 'Nota', style: 'min-width:280px;flex:1' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar revisión');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      save.disabled = true; out.replaceChildren();
      try { await rpc('legal_audit_review', { p_id: i.id, p_missing: checks.filter((x) => !x.box.checked).map((x) => x.c.code), p_note: txt.value || null }); await load(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    return h('div', { class: 'i18-card' }, head, h('p', { class: 'i18-sub' }, 'Desmarque lo que falta en el expediente:'),
      h('div', { class: 'au-checks' }, checks.map((x) => h('label', { class: 'i18-chk', for: x.box.id }, x.box, ' ', x.c.label))), h('div', { class: 'i18-bar' }, txt, save), out);
  }

  st.addEventListener('change', load); sel.addEventListener('change', load);
  await load();
}

/** Informe de documentación por médico (lo ve el Médico y el equipo SOFA). */
async function report(box, org, own) {
  if (!org) { box.replaceChildren(note('No se encontró su consultorio. Cierre la sesión y vuelva a entrar.', 'error')); return; }
  const d = await guarded(box, () => rpc('legal_audit_report', { p_org: org, p_days: 90 }));
  if (!d) return;
  const kids = [h('h3', {}, own ? 'Calidad de la documentación de sus expedientes (90 días)' : 'Informe por médico (90 días)')];
  if (!d.active && own) kids.push(note('La auditoría preventiva de expedientes es un servicio de SOFA. Pídalo en «Mi cuenta con SOFA» › Pedir un servicio.'));
  if (!d.providers.length) kids.push(note('Todavía no hay expedientes revisados.'));
  d.providers.forEach((p) => kids.push(h('section', { class: 'i18-card' }, h('h4', {}, p.provider || 'Sin médico'),
    h('div', { class: 'i18-kpis' }, kpi('Expedientes revisados', String(p.reviewed)), kpi('Conformes', p.pct == null ? '—' : `${p.pct} %`)),
    p.top && p.top.length ? [h('p', {}, h('strong', {}, 'Sus omisiones más frecuentes y cómo evitarlas:')),
      h('ol', {}, p.top.map((t) => h('li', {}, h('strong', {}, `${t.label} (${t.times})`), h('div', { class: 'i18-sub' }, `Plantilla: ${t.template}`))))] : h('p', {}, 'Sin omisiones. ¡Bien!'))));
  if (own) box.replaceChildren(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Auditoría de mis expedientes'), ...kids));
  else box.replaceChildren(...kids);
}
export default render;
