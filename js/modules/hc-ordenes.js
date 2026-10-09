/** SOFA · 2.4 · Iteración 34 · Recetas, órdenes de laboratorio e imágenes y referimientos (historia clínica fase C).
 *  Se firman al guardar (huella SHA-256) y no se modifican. Se imprimen con los datos del médico y del paciente. */
import { h, fmtDate, note, guarded } from '../services/iter18.js';

const KINDS = { receta: 'Receta', laboratorio: 'Laboratorio', imagen: 'Imágenes', referimiento: 'Referimiento' };
const fmtTs = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');

/** Lista de órdenes del paciente (se pinta sola dentro del contenedor que devuelve) */
export function ordersList(patientId, pane, rpc) {
  const box = h('div', { 'aria-live': 'polite' });
  guarded(box, () => rpc('clinical_orders_for', { p_patient: patientId })).then((l) => {
    if (!l) return;
    box.replaceChildren(l.length ? h('div', { class: 'hc-notes' }, l.map((o) => h('article', { class: 'hc-note' },
      h('header', {}, h('strong', {}, `${KINDS[o.kind] || o.kind} · ${fmtTs(o.at)}`),
        h('button', { class: 'i18-link', type: 'button', onclick: () => printOrder(pane, o.id, rpc) }, 'Ver e imprimir')),
      h('div', { class: 'i18-sub' }, [o.summary, o.by].filter(Boolean).join(' · '))))) : note('Sin recetas ni órdenes.'));
  });
  return box;
}

/** Formulario: receta (varios medicamentos), laboratorio o imágenes (varios estudios) o referimiento */
export function orderForm(pane, patientId, noteId, rpc, onDone) {
  const kind = h('select', { id: 'or-kind' }, Object.entries(KINDS).map(([k, v]) => h('option', { value: k }, v)));
  const itemsBox = h('div', { class: 'hc-notes' });
  const extra = h('div');
  const msg = h('div', { 'aria-live': 'polite' });
  const items = [];
  const field = (id, label, attrs = {}) => { const el = h('input', { id, ...attrs }); return [h('label', { for: id }, label, el), el]; };
  function addItem() {
    const k = kind.value; const n = items.length; const row = {};
    let el;
    if (k === 'receta') {
      const [l1, a] = field(`or-m-${n}`, 'Medicamento y presentación', { placeholder: 'Ej.: Amoxicilina 500 mg cápsulas' });
      const [l2, b] = field(`or-d-${n}`, 'Dosis', { placeholder: '1 cápsula' });
      const [l3, c] = field(`or-f-${n}`, 'Frecuencia', { placeholder: 'cada 8 horas' });
      const [l4, d] = field(`or-u-${n}`, 'Duración', { placeholder: '7 días' });
      const [l5, e] = field(`or-c-${n}`, 'Cantidad a dispensar', { placeholder: '21' });
      Object.assign(row, { medicamento: a, dosis: b, frecuencia: c, duracion: d, cantidad: e });
      el = h('div', { class: 'hc-grid' }, l1, l2, l3, l4, l5);
    } else {
      const [l1, a] = field(`or-e-${n}`, 'Estudio', { placeholder: k === 'imagen' ? 'Ej.: Sonografía abdominal' : 'Ej.: Hemograma completo' });
      Object.assign(row, { estudio: a });
      el = h('div', { class: 'hc-grid' }, l1);
    }
    items.push(row); itemsBox.append(h('div', { class: 'i18-card' }, el));
  }
  const addBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: addItem }, '+ Agregar otro');
  function draw() {
    items.length = 0; itemsBox.replaceChildren(); extra.replaceChildren();
    if (kind.value === 'referimiento') {
      addBtn.hidden = true;
      extra.append(h('label', { for: 'or-esp' }, 'Especialidad o centro', h('input', { id: 'or-esp', placeholder: 'Ej.: Cardiología' })),
        h('label', { for: 'or-mot' }, 'Motivo del referimiento', h('textarea', { id: 'or-mot', rows: '3' })));
    } else {
      addBtn.hidden = false; addItem();
      extra.append(h('label', { for: 'or-ind' }, kind.value === 'receta' ? 'Indicaciones generales' : 'Indicación clínica (diagnóstico o sospecha)', h('textarea', { id: 'or-ind', rows: '2' })));
    }
  }
  kind.addEventListener('change', draw); draw();
  const save = h('button', { class: 'i18-btn', type: 'button' }, 'Firmar y guardar');
  save.addEventListener('click', async () => {
    const k = kind.value; let c;
    if (k === 'referimiento') c = { especialidad: pane.querySelector('#or-esp').value.trim(), motivo: pane.querySelector('#or-mot').value.trim() };
    else {
      const its = items.map((r) => Object.fromEntries(Object.entries(r).map(([key, el]) => [key, el.value.trim()]).filter(([, v]) => v))).filter((x) => Object.keys(x).length);
      c = { items: its, [k === 'receta' ? 'indicaciones' : 'indicacion']: pane.querySelector('#or-ind').value.trim() };
    }
    if (!confirm('Al firmar, la orden queda guardada y no se puede modificar. ¿Firmar ahora?')) return;
    save.disabled = true;
    try { const r = await rpc('create_clinical_order', { p_patient: patientId, p_kind: k, p_content: c, p_note: noteId }); const np = await onDone?.(); printOrder(np && np.isConnected ? np : pane, r.id, rpc); }
    catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
  });
  pane.replaceChildren(h('section', { class: 'hc-note hc-form' },
    h('header', {}, h('strong', {}, noteId ? 'Receta u orden de esta consulta' : 'Receta u orden'), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
    h('label', { for: 'or-kind' }, 'Tipo', kind), itemsBox, addBtn, extra, h('div', { class: 'i18-actions' }, save), msg));
  pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/** Vista para imprimir (solo la orden sale en el papel) */
export async function printOrder(pane, id, rpc) {
  const o = await guarded(pane, () => rpc('clinical_order', { p_id: id }));
  if (!o) return;
  const c = o.content || {}; const p = o.patient || {}; const d = o.doctor || {}; const org = o.organization || {};
  const age = p.birth_date ? Math.floor((Date.now() - new Date(p.birth_date)) / 31557600000) : null;
  let body;
  if (o.kind === 'receta') body = [h('p', { class: 'or-rx' }, 'Rx'), h('ol', {}, (c.items || []).map((i) => h('li', {}, h('strong', {}, i.medicamento),
    h('div', {}, [i.dosis, i.frecuencia, i.duracion].filter(Boolean).join(' · ')), i.cantidad ? h('div', { class: 'i18-sub' }, `Cantidad: ${i.cantidad}`) : ''))),
    c.indicaciones ? h('p', {}, h('strong', {}, 'Indicaciones: '), c.indicaciones) : ''];
  else if (o.kind === 'referimiento') body = [h('p', {}, h('strong', {}, 'Referido a: '), c.especialidad), h('p', { style: 'white-space:pre-wrap' }, h('strong', {}, 'Motivo: '), c.motivo)];
  else body = [h('p', {}, h('strong', {}, o.kind === 'imagen' ? 'Estudios de imágenes:' : 'Estudios de laboratorio:')), h('ul', {}, (c.items || []).map((i) => h('li', {}, i.estudio))),
    c.indicacion ? h('p', {}, h('strong', {}, 'Indicación clínica: '), c.indicacion) : ''];
  pane.replaceChildren(h('section', { class: 'i18-card' },
    h('div', { class: 'i18-actions hc-actions' }, h('button', { class: 'i18-btn', type: 'button', onclick: () => window.print() }, 'Imprimir o guardar en PDF'),
      h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cerrar')),
    h('article', { class: 'sofa-print or-sheet' },
      h('header', { class: 'or-head' }, h('div', {}, h('strong', {}, d.name || ''), h('div', {}, [d.specialty, d.exequatur ? `Exequátur ${d.exequatur}` : null].filter(Boolean).join(' · '))),
        h('div', { style: 'text-align:right' }, h('strong', {}, org.name || ''), h('div', {}, [org.address, org.phone].filter(Boolean).join(' · ')))),
      h('h3', {}, KINDS[o.kind] || o.kind),
      h('p', {}, h('strong', {}, 'Paciente: '), p.name, p.doc ? ` · ${p.doc}` : '', age != null ? ` · ${age} años` : '', h('span', { style: 'float:right' }, fmtDate(o.at))),
      ...body,
      h('footer', { class: 'or-foot' }, h('div', { class: 'or-sign' }, '______________________________', h('br'), d.name || 'Firma del médico'),
        h('div', { class: 'hc-hash' }, `Firmada electrónicamente ${fmtTs(o.at)} · ${o.hash_ok ? 'huella verificada' : 'HUELLA NO COINCIDE'} · ${o.hash}`)))));
  pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
