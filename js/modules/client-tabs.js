/** SOFA · 2.1 · Iteración 31 · Pestañas de la ficha del cliente y paneles nuevos (tarifario por ARS y documentos del cliente).
 *  client.js pinta sus tarjetas como antes; aquí se agrupan en pestañas según su título, sin tocar su lógica. */
import { rpc, supabase, h, fmtDate, note, guarded } from '../services/iter18.js';
import { can } from '../utils/permissions.js';
import { mountTariffImport } from './tarifario-import.js';

const TABS = [
  ['resumen', 'Resumen'], ['codigos', 'Códigos ARS'], ['tarifario', 'Tarifario'], ['documentos', 'Documentos'],
  ['radicaciones', 'Radicaciones'], ['habilitacion', 'Habilitación'], ['crm', 'CRM y tareas'], ['usuarios', 'Usuarios']
];
// Título de la tarjeta (h2) → pestaña
const RULES = [
  [/^Códigos de prestador/i, 'codigos'], [/^Tarifas negociadas/i, 'tarifario'], [/^Documentos/i, 'documentos'],
  [/^Radicaciones/i, 'radicaciones'], [/^Habilitación/i, 'habilitacion'], [/^Usuarios del consultorio/i, 'usuarios'],
  [/^(Oportunidades|Tareas|Historial|Contactos)/i, 'crm']
];
const KEY = 'sofa.ficha.pestana';

export function setupClientTabs(main, org, role = null) {
  const grid = main.querySelector('.grid.two');
  if (!grid || main.querySelector('.ct-tabs')) return;
  const cards = [...grid.children];
  for (const c of cards) {
    const t = c.querySelector('h2')?.textContent.trim() || '';
    c.dataset.tab = (RULES.find(([re]) => re.test(t)) || [null, 'resumen'])[1];
  }
  // Paneles nuevos
  const tarif = h('div', { class: 'card', style: 'grid-column:1/-1', 'data-tab': 'tarifario' }, h('h2', {}, 'Tarifario según contrato, por ARS'),
    h('p', { class: 'sub' }, 'Cuántas tarifas vigentes tiene el cliente con cada ARS, el contrato que las respalda y si ya tiene código.'), h('div', { id: 'ctTarif' }), h('div', { id: 'ctTarifImp', style: 'margin-top:16px' }));
  const docs = h('div', { class: 'card', style: 'grid-column:1/-1', 'data-tab': 'documentos' }, h('h2', {}, 'Archivos del cliente'),
    h('p', { class: 'sub' }, 'Todos los archivos subidos a los expedientes de este cliente (radicaciones, reclamaciones y otros).'), h('div', { id: 'ctDocs' }));
  grid.prepend(tarif); grid.append(docs);
  const present = new Set([...grid.children].map((c) => c.dataset.tab));
  const tabs = TABS.filter(([k]) => present.has(k));
  let current = sessionStorage.getItem(KEY);
  if (!tabs.some(([k]) => k === current)) current = 'resumen';
  const bar = h('div', { class: 'ct-tabs', role: 'tablist', 'aria-label': 'Secciones de la ficha' });
  const loaded = new Set();
  const show = (k) => {
    current = k; try { sessionStorage.setItem(KEY, k); } catch (_) { /* sin almacenamiento */ }
    bar.querySelectorAll('[role=tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.k === k)));
    [...grid.children].forEach((c) => { c.hidden = c.dataset.tab !== k; });
    if (k === 'tarifario' && !loaded.has(k)) { loaded.add(k); drawTariffs(tarif.querySelector('#ctTarif'), org.id); mountTariffImport(tarif.querySelector('#ctTarifImp'), { orgId: org.id, canEdit: can('contracts.edit', role) }); }
    if (k === 'documentos' && !loaded.has(k)) { loaded.add(k); drawDocs(docs.querySelector('#ctDocs'), org.id); }
  };
  bar.append(...tabs.map(([k, l]) => h('button', { type: 'button', role: 'tab', 'data-k': k, onclick: () => show(k) }, l)));
  bar.addEventListener('keydown', (e) => {
    if (!['ArrowRight', 'ArrowLeft'].includes(e.key)) return;
    const i = tabs.findIndex(([k]) => k === current); const n = tabs[(i + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length][0];
    show(n); bar.querySelector(`[data-k="${n}"]`).focus();
  });
  grid.before(bar);
  show(current);
}

async function drawTariffs(box, orgId) {
  const rows = await guarded(box, () => rpc('client_tariff_summary', { p_org: orgId }));
  if (!rows) return;
  const withNeg = rows.filter((r) => r.negotiated > 0).length;
  box.replaceChildren(h('p', { class: 'i18-sub' }, `${withNeg} de ${rows.length} ARS con tarifas negociadas vigentes. Donde no hay, se usa la tarifa general de la ARS.`),
    h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['ARS', 'Código', 'Tarifas negociadas', 'Tarifas generales', 'Vigentes hasta', 'Contrato'].map((t) => h('th', {}, t)))),
      h('tbody', {}, rows.map((r) => h('tr', {},
        h('td', {}, h('strong', {}, r.ars)),
        h('td', {}, r.codes ? h('span', { class: 'ac-pill st-ok' }, 'Codificado') : h('span', { class: 'ac-pill st-none' }, 'Sin código')),
        h('td', { class: 'i18-r' }, r.negotiated || '—'), h('td', { class: 'i18-r' }, r.general || '—'),
        h('td', {}, r.valid_to ? fmtDate(r.valid_to) : r.negotiated ? 'Sin fecha de fin' : '—'),
        h('td', {}, (r.contracts || []).join(', ') || '—')))))),
    h('div', { class: 'i18-actions' }, h('a', { class: 'i18-btn i18-sec', href: '#/contratos' }, 'Abrir el Tarifario contractual')));
}

async function drawDocs(box, orgId) {
  const d = await guarded(box, () => rpc('client_documents', { p_org: orgId }));
  if (!d) return;
  const open = async (f) => {
    const { data, error } = await supabase.storage.from(f.bucket || 'claim-documents').createSignedUrl(f.path, 120);
    if (error) { box.prepend(note('No se pudo abrir el archivo. Intente de nuevo.', 'error')); return; }
    window.open(data.signedUrl, '_blank', 'noopener');
  };
  const ENT = { submission: (id) => `#/radicaciones/${id}` };
  box.replaceChildren(
    d.files.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Archivo', 'Tipo', 'Expediente', 'Fecha', ''].map((t) => h('th', {}, t)))),
      h('tbody', {}, d.files.map((f) => h('tr', {},
        h('td', {}, f.name), h('td', {}, f.type || '—'),
        h('td', {}, ENT[f.entity] ? h('a', { href: ENT[f.entity](f.entity_id) }, 'Ver radicación') : (f.entity || '—')),
        h('td', {}, fmtDate(f.at)), h('td', {}, h('button', { class: 'i18-link', type: 'button', onclick: () => open(f) }, 'Abrir'))))))) : note('Este cliente todavía no tiene archivos subidos.'),
    d.commercial.length ? h('p', { class: 'i18-sub' }, `Documentos comerciales A–E: ${d.commercial.map((c) => `${c.code} ${c.status || ''}`.trim()).join(' · ')}`) : '');
}
