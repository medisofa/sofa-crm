/** SOFA · 3.0 · Iteración 40 · Casos de servicio (equipo SOFA): solicitudes de los clientes y servicios en curso,
 *  incluida la renegociación de tarifarios. Cada avance «visible» le llega al cliente como notificación. */
import { rpc, h, money, fmtDate, note, guarded, clientOptions, clientName } from '../services/iter18.js';
import { STATUS, pill, caseDetail } from './casos-comun.js';

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const fStatus = h('select', { id: 'cs-f-st' }, h('option', { value: 'abiertos' }, 'Abiertos'), Object.entries(STATUS).map(([k, v]) => h('option', { value: k }, v)), h('option', { value: '' }, 'Todos'));
  const fService = h('select', { id: 'cs-f-svc' }, h('option', { value: '' }, 'Todos los servicios'));
  const box = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { id: 'cs-detail' });
  const openBox = h('div');
  const newBtn = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Abrir un caso');
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Casos de servicio'),
    h('p', { class: 'i18-sub' }, 'Lo que los clientes piden a SOFA y los servicios en curso (renegociación de tarifarios, códigos ARS, habilitación…). Las solicitudes nuevas aparecen primero.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'cs-f-st' }, 'Estado', fStatus), h('label', { for: 'cs-f-svc' }, 'Servicio', fService), newBtn), openBox, box, detail));
  let services = [];

  async function load() {
    const d = await guarded(box, () => rpc('service_cases_board', { p_status: fStatus.value || null, p_service: fService.value || null, p_org: null }));
    if (!d) return;
    const sum = d.summary || {};
    box.replaceChildren(
      h('p', { class: 'i18-sub' }, Object.entries(STATUS).filter(([k]) => sum[k]).map(([k, v]) => `${v}: ${sum[k]}`).join(' · ') || 'Sin casos todavía.'),
      d.cases.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Folio', 'Cliente', 'Servicio', 'Caso', 'Estado', 'Responsable', 'Compromiso', 'Honorario', ''].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.cases.map((c) => {
          const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Abrir');
          b.addEventListener('click', () => { caseDetail(detail, c.id, { staff: true, onChange: load }); detail.scrollIntoView({ behavior: 'smooth' }); });
          return h('tr', {}, h('td', {}, c.folio), h('td', {}, h('a', { href: `#/clientes/${c.organization_id}` }, c.client)), h('td', {}, c.service), h('td', {}, c.title),
            h('td', {}, pill(c.status, c.status_label)), h('td', {}, c.owner || '—'), h('td', { class: c.overdue ? 'cs-over' : '' }, c.due_date ? fmtDate(c.due_date) : '—'),
            h('td', { class: 'i18-r' }, c.fee_amount != null ? money(c.fee_amount) : '—'), h('td', {}, b));
        })))) : note('No hay casos con ese filtro.'));
  }

  newBtn.addEventListener('click', async () => {
    if (openBox.childElementCount) { openBox.replaceChildren(); return; }
    let clients = [];
    try { clients = await clientOptions(); } catch (e) { openBox.replaceChildren(note(e.message, 'error')); return; }
    const cl = h('select', { id: 'cs-o-cl' }, clients.map((c) => h('option', { value: c.id }, clientName(c))));
    const sv = h('select', { id: 'cs-o-svc' }, services.map((s) => h('option', { value: s.code }, s.name)));
    const ti = h('input', { type: 'text', id: 'cs-o-ti', maxlength: '200', placeholder: 'Ej.: Habilitación de la sala de procedimientos' });
    const de = h('textarea', { id: 'cs-o-de', rows: '2', maxlength: '2000', style: 'width:100%' });
    const du = h('input', { type: 'date', id: 'cs-o-du' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Abrir caso');
    const out = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      go.disabled = true; out.replaceChildren();
      try {
        const r = await rpc('service_case_open', { p_org: cl.value, p_service: sv.value, p_title: ti.value.trim(), p_detail: de.value.trim() || null, p_due: du.value || null });
        openBox.replaceChildren(); await load(); caseDetail(detail, r.id, { staff: true, onChange: load });
      } catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    openBox.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Nuevo caso de servicio'),
      h('label', { for: 'cs-o-cl' }, 'Cliente'), cl, h('label', { for: 'cs-o-svc' }, 'Servicio'), sv, h('label', { for: 'cs-o-ti' }, 'Título'), ti,
      h('label', { for: 'cs-o-de' }, 'Detalle'), de, h('label', { for: 'cs-o-du' }, 'Fecha compromiso'), du, h('div', {}, go), out));
  });

  fStatus.addEventListener('change', load);
  fService.addEventListener('change', load);
  try {   // catálogo de servicios desde la tabla (lectura con RLS)
    const { sb } = await import('../supabase.js');
    const { data } = await sb().from('sofa_services').select('code, name, sort_order').order('sort_order');
    services = data || [];
    fService.append(...services.map((s) => h('option', { value: s.code }, s.name)));
  } catch { /* el filtro queda con «Todos» */ }
  await load();
  const want = String(ctx.arg || '');
  if (/^[0-9a-f-]{36}$/.test(want)) caseDetail(detail, want, { staff: true, onChange: load });
}
export default render;
