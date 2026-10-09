/** SOFA · 3.1 · Iteración 41 · Preparación e-CF de los clientes (equipo SOFA).
 *  Desde la fecha de obligación (general 15/11/2026) un lote sin e-NCF E31 aceptado por la DGII no se radica.
 *  Semáforo por cliente, pasos, simulacro de lotes bloqueados y proveedores recomendados. */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';
import { ecfSteps } from './ecf-comun.js';

const LIGHT = { verde: 'Listo', amarillo: 'En proceso', rojo: 'Atención' };
const STATUS = { no_iniciado: 'No iniciado', en_proceso: 'En proceso', listo: 'Listo' };

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { id: 'ecf-detail' });
  const prov = h('div');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Preparación e-CF de los clientes'),
    h('p', { class: 'i18-sub' }, 'Desde la fecha de obligación, un lote sin e-NCF E31 aceptado por la DGII no se puede radicar. Aquí se ve quién está listo, qué paso le falta y qué lotes quedarían bloqueados.'),
    box, detail, prov));

  async function load() {
    const d = await guarded(box, () => rpc('ecf_readiness_board'));
    if (!d) return;
    const n = (l) => d.clients.filter((c) => c.light === l).length;
    box.replaceChildren(
      h('div', { class: 'i18-kpis' }, kpiBox('Listos', n('verde'), 'ok'), kpiBox('En proceso', n('amarillo'), 'warn'), kpiBox('Atención', n('rojo'), 'bad'),
        kpiBox('Lotes que se bloquearían', d.clients.reduce((a, c) => a + Number(c.blocked_lots || 0), 0), 'bad')),
      d.clients.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Cliente', 'Semáforo', 'Estado', 'Pasos', 'Siguiente paso', 'Obligado desde', 'Faltan', 'Lotes bloqueados', ''].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.clients.map((c) => {
          const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver');
          b.addEventListener('click', () => openClient(c, d.can_edit));
          return h('tr', {}, h('td', {}, c.client), h('td', {}, h('span', { class: `ecf-l ${c.light}` }, LIGHT[c.light])), h('td', {}, STATUS[c.status] || c.status),
            h('td', {}, `${c.steps_done} de ${c.steps_total}`), h('td', {}, c.next_step || '—'), h('td', {}, fmtDate(c.required_from)),
            h('td', { class: c.days_left <= 15 && c.status !== 'listo' ? 'cs-over' : '' }, c.days_left < 0 ? `venció hace ${-c.days_left} días` : `${c.days_left} días`),
            h('td', { class: 'i18-r' }, String(c.blocked_lots)), h('td', {}, b));
        })))) : note('No hay clientes activos.'));
    drawProviders(d);
  }

  async function openClient(c, canEdit) {
    detail.replaceChildren(note('Cargando…'));
    const s = await guarded(detail, () => rpc('ecf_client_status', { p_org: c.organization_id }));
    if (!s) return;
    const kids = [h('h3', {}, `${s.client} · e-CF`), ecfSteps(s, () => openClient(c, canEdit).then(load))];
    if (canEdit && s.status !== 'listo') {
      const prov = h('input', { type: 'text', id: 'ecf-l-prov', value: s.provider || '', maxlength: '120' });
      const day = h('input', { type: 'date', id: 'ecf-l-day', value: new Date().toISOString().slice(0, 10) });
      const go = h('button', { class: 'i18-btn', type: 'button' }, 'Marcar cliente «Listo»');
      const out = h('div', { 'aria-live': 'polite' });
      go.addEventListener('click', async () => {
        go.disabled = true; out.replaceChildren();
        try { await rpc('set_client_ecf', { p_org: c.organization_id, p_status: 'listo', p_provider: prov.value.trim(), p_required_from: s.required_from, p_ready_on: day.value }); await openClient(c, canEdit); await load(); }
        catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
      });
      kids.push(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Cuando el primer E31 fue aceptado'),
        h('label', { for: 'ecf-l-prov' }, 'Proveedor o sistema de e-CF'), prov, h('label', { for: 'ecf-l-day' }, 'Fecha en que quedó listo'), day, h('div', {}, go), out));
    }
    detail.replaceChildren(h('div', { class: 'i18-card' }, ...kids));
    detail.scrollIntoView({ behavior: 'smooth' });
  }

  function drawProviders(d) {
    const list = d.providers.length ? h('ul', {}, d.providers.map((p) => h('li', {}, `${p.name}${p.is_active ? '' : ' (inactivo)'}`, p.website ? ` · ${p.website}` : '', p.notes ? ` · ${p.notes}` : '')))
      : note('Todavía no hay proveedores en la lista. Agregue los que SOFA recomienda a sus médicos.');
    const name = h('input', { type: 'text', id: 'ecf-p-name', maxlength: '120' });
    const web = h('input', { type: 'url', id: 'ecf-p-web', maxlength: '200', placeholder: 'https://' });
    const notes = h('input', { type: 'text', id: 'ecf-p-notes', maxlength: '200' });
    const add = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Agregar proveedor');
    const out = h('div', { 'aria-live': 'polite' });
    add.addEventListener('click', async () => {
      add.disabled = true; out.replaceChildren();
      try { await rpc('ecf_provider_save', { p_id: null, p_name: name.value, p_website: web.value || null, p_notes: notes.value || null, p_active: true }); await load(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); add.disabled = false; }
    });
    prov.replaceChildren(h('details', { class: 'i18-card' }, h('summary', {}, `Proveedores de facturación electrónica recomendados (${d.providers.length})`), list,
      h('div', { class: 'i18-form' }, h('label', { for: 'ecf-p-name' }, 'Nombre'), name, h('label', { for: 'ecf-p-web' }, 'Sitio web'), web,
        h('label', { for: 'ecf-p-notes' }, 'Nota'), notes, h('div', {}, add), out)));
  }
  const kpiBox = (label, v, cls) => h('div', { class: `i18-kpi ecf-k ${cls}` }, h('div', { class: 'i18-kpi-v' }, String(v)), h('div', { class: 'i18-kpi-l' }, label));

  await load();
}
export default render;
