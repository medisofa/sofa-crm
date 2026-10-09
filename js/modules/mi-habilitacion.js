/** SOFA · 3.8 · Iteración 48 · Habilitación vista por el cliente.
 *  Semáforo por área, qué falta y qué entregar; el cliente marca «lo entregué» y SOFA decide el color.
 *  Simulacro de inspección para imprimir (cliente y equipo SOFA). */
import { rpc, h, fmtDate, note, guarded, clientOptions, clientName } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const ST = { verde: 'Listo', amarillo: 'Corregible (menos de 15 días)', rojo: 'Requiere inversión u obra', pendiente: 'Pendiente' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const sel = h('select', { id: 'mh-org' }, h('option', { value: '' }, 'Elija un cliente'));
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, client ? 'Mi habilitación' : 'Habilitación vista por el cliente'),
    h('p', { class: 'i18-sub' }, 'Qué está listo, qué falta y qué debe entregar para habilitar su establecimiento ante el MISPAS.'),
    client ? null : h('div', { class: 'i18-bar' }, h('label', { for: 'mh-org' }, 'Cliente', sel)), box));
  if (!client) { try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (e) { box.replaceChildren(note(e.message, 'error')); } }

  async function load() {
    const org = client ? ctx.membership?.organization_id : sel.value;
    if (!org) { box.replaceChildren(note(client ? 'No se encontró su consultorio.' : 'Elija un cliente.')); return; }
    const d = await guarded(box, () => rpc('client_habilitation', { p_org: org }));
    if (!d) return;
    if (!d.length) { box.replaceChildren(note(client ? 'No tiene casos de habilitación con SOFA. Si lo necesita, pídalo en «Mi cuenta con SOFA».' : 'El cliente no tiene casos de habilitación.')); return; }
    box.replaceChildren(...d.map(caseCard));
  }

  function caseCard(c) {
    const k = c.counts; const pct = k.applicable ? Math.round((100 * k.verde) / k.applicable) : 0;
    const sim = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Simulacro de inspección (imprimir)');
    sim.addEventListener('click', () => simulacro(c));
    return h('section', { class: 'i18-card' }, h('h3', {}, `${c.name} · ${c.type}`),
      h('div', { class: 'i18-sub' }, `${c.folio || ''} · ${c.stage_label}${c.target_date ? ` · meta ${fmtDate(c.target_date)}` : ''}${c.license_valid_until ? ` · licencia vence ${fmtDate(c.license_valid_until)} (${c.license_days_left} días)` : ''}${c.pss_code ? ` · PSS ${c.pss_code}` : ''}`),
      h('div', { class: 'mh-bar', role: 'img', 'aria-label': `${pct} % listo` }, h('span', { style: `width:${pct}%` })),
      h('p', {}, `${pct} % listo · ${k.verde} listos · ${k.amarillo} corregibles · ${k.rojo} con obra · ${k.pendiente} pendientes${k.critical_open ? ` · ${k.critical_open} crítico(s) abiertos` : ''}`),
      h('div', { class: 'i18-bar' }, sim),
      ...(c.areas || []).map((a) => h('details', { open: a.items.some((i) => i.status !== 'verde') }, h('summary', {}, `${a.area} (${a.items.filter((i) => i.status === 'verde').length} de ${a.items.length})`),
        h('ul', { class: 'mh-items' }, a.items.map(itemRow)))));
  }

  function itemRow(i) {
    const kids = [h('span', { class: `ecf-l ${i.status === 'verde' ? 'verde' : i.status === 'pendiente' ? 'gris' : i.status === 'amarillo' ? 'amarillo' : 'rojo'}` }, ST[i.status] || i.status), ' ',
      h('strong', {}, i.requirement), i.critical ? h('span', { class: 'cs-over' }, ' · crítico') : null,
      i.hint ? h('div', { class: 'i18-sub' }, `Qué entregar: ${i.hint}`) : null, i.notes ? h('div', { class: 'i18-sub' }, `SOFA: ${i.notes}`) : null,
      i.submitted_at ? h('div', { class: 'i18-sub' }, `Entregado el ${fmtDate(i.submitted_at)}: ${i.client_note}`) : null];
    if (i.can_submit) {
      const t = h('input', { type: 'text', maxlength: '500', placeholder: 'Qué entregó y cómo', 'aria-label': 'Qué entregó' });
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Lo entregué');
      const o = h('div', { 'aria-live': 'polite' });
      b.addEventListener('click', async () => { b.disabled = true; try { await rpc('habilitation_item_submit', { p_item: i.id, p_note: t.value }); await load(); } catch (e) { o.replaceChildren(note(e.message, 'error')); b.disabled = false; } });
      kids.push(h('div', { class: 'i18-bar' }, t, b), o);
    }
    return h('li', {}, ...kids);
  }

  async function simulacro(c) {
    const w = openPrint();
    try {
      const s = await rpc('habilitation_mock_inspection', { p_case: c.id });
      const ok = fillPrint(w, `Simulacro de inspección · ${s.name}`, `${s.type} · ${s.stage_label} · ${s.folio || ''} · ${fmtDate(s.generated_on)}`, [
        s.unconfirmed_catalog ? { warn: 'Lista base de SOFA: confirme los requisitos vigentes con el MISPAS antes de la inspección.' } : null,
        { p: 'Recorra el establecimiento con esta lista como lo haría el inspector. Marque cada punto y anote lo que falte.' },
        { table: { head: ['✓', 'Área', 'Requisito', 'Crítico', 'Estado actual', 'Evidencia'], rows: s.items.map((i) => ['☐', i.area, i.requirement, i.critical ? 'Sí' : '', ST[i.status] || i.status, i.hint || '']) } }].filter(Boolean));
      if (!ok) box.prepend(note('El navegador bloqueó la ventana. Permita las ventanas emergentes de SOFA e intente de nuevo.', 'error'));
    } catch (e) { if (w) w.close(); box.prepend(note(e.message, 'error')); }
  }

  sel.addEventListener('change', load);
  await load();
}
export default render;
