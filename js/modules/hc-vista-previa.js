/**
 * SOFA · Vista previa de plantillas de historia clínica (Super Admin).
 *
 * Permite ver y llenar cualquier plantilla de cualquier especialidad con un paciente de ejemplo para revisar
 * campos y cálculos (IMC, ICT, bioimpedancia, puntaje Z). No toca pacientes ni guarda nada: todo vive en la
 * memoria de esta pantalla y desaparece al cerrarla. Por eso no necesita acceso a la historia de ningún
 * consultorio (decisión del 20/11/2026: el Super Admin no lee historias reales desde aquí).
 */
import { h, note } from '../services/iter18.js';
import { listSpecialties } from '../services/especialidades.js';
import { computeAll, needsWho, loadWho } from '../utils/antropometria.js';

const SECTION = { S: 'S · Subjetivo', O: 'O · Objetivo', A: 'A · Análisis', P: 'P · Plan' };

/**
 * @param {HTMLElement} box  contenedor donde se dibuja
 * @param {{code:string, name:string, specialty:string, fields:object[]}[]} templates  de clinical_templates_list
 */
export async function templatePreview(box, templates) {
  let specialties = [];
  try { specialties = await listSpecialties(); } catch { /* el selector de plantilla funciona igual */ }
  const tplByCode = Object.fromEntries(templates.map((t) => [t.code, t]));
  const usable = templates.filter((t) => t.code !== 'historia_importada');

  const spec = h('select', { id: 'hp-spec' }, h('option', { value: '' }, 'Todas las especialidades'),
    specialties.map((s) => h('option', { value: s.code }, s.name)));
  const tpl = h('select', { id: 'hp-tpl' });
  const birth = h('input', { id: 'hp-birth', type: 'date', value: new Date(Date.now() - 3 * 365.25 * 864e5).toISOString().slice(0, 10) });
  const sex = h('select', { id: 'hp-sex' }, h('option', { value: 'F' }, 'Femenino'), h('option', { value: 'M' }, 'Masculino'));
  const fieldsBox = h('div');
  const msg = h('div', { 'aria-live': 'polite' });
  const inputs = {};
  let who = null; let whoLoading = false;

  function fillTemplates() {
    const s = specialties.find((x) => x.code === spec.value);
    const list = s ? usable.filter((t) => t.code === s.template_code) : usable;
    tpl.replaceChildren(...list.map((t) => h('option', { value: t.code }, `${t.specialty} · ${t.name}`)));
    draw();
  }

  function draw() {
    const t = tplByCode[tpl.value];
    const prev = Object.fromEntries(Object.entries(inputs).map(([k, el]) => [k, el.value]));
    Object.keys(inputs).forEach((k) => delete inputs[k]);
    if (!t) { fieldsBox.replaceChildren(note('Esa especialidad no tiene plantilla asignada.')); return; }
    fieldsBox.replaceChildren(...['S', 'O', 'A', 'P'].map((k) => {
      const fs = t.fields.filter((f) => (f.section || 'S') === k);
      if (!fs.length) return '';
      return h('fieldset', { class: 'i18-fs' }, h('legend', {}, SECTION[k]), h('div', { class: k === 'O' ? 'hc-grid' : '' }, fs.map((f) => {
        if (f.type === 'heading') return h('h5', { class: 'hc-sec hc-wide hc-subhead' }, f.label);
        const id = `hp-f-${f.key}`;
        let el;
        if (f.type === 'calc') {
          el = h('output', { id, class: 'hc-calc' }, '');
          el.value = '';
          inputs[f.key] = el;
          return h('label', { for: id }, h('span', {}, f.label, h('small', { class: 'i18-sub' }, ' · automático')), el);
        }
        const val = prev[f.key] ?? '';
        if (f.type === 'textarea') el = h('textarea', { id, rows: '2' }, val);
        else if (f.type === 'select') el = h('select', { id }, h('option', { value: '' }, '—'), (f.options || []).map((o) => h('option', { value: o, selected: val === o }, o)));
        else el = h('input', { id, type: f.type === 'date' ? 'date' : 'text', inputmode: f.type === 'number' ? 'decimal' : null, value: val, placeholder: f.type === 'cie10' ? 'Ej.: E66.0' : null });
        inputs[f.key] = el;
        return h('label', { for: id, class: f.type === 'textarea' ? 'hc-wide' : '' }, h('span', { class: f.required ? 'hc-req' : '' }, f.label), el);
      })));
    }));
    recalc();
  }

  function recalc() {
    const t = tplByCode[tpl.value];
    if (!t || !t.fields.some((f) => f.type === 'calc')) return;
    if (needsWho(t.fields) && !who && !whoLoading) {
      whoLoading = true;
      loadWho().then((w) => { who = w; recalc(); })
        .catch(() => msg.replaceChildren(note('No se pudieron cargar las tablas de la OMS. Revise la conexión y recargue; el resto se calcula igual.', 'error')));
    }
    const vals = Object.fromEntries(Object.entries(inputs).map(([k, el]) => [k, el.value]));
    const out = computeAll(t.fields, vals, { birth_date: birth.value || null, sex: sex.value }, new Date().toISOString().slice(0, 10), who);
    for (const f of t.fields) {
      if (f.type !== 'calc' || !inputs[f.key]) continue;
      const v = out[f.key] || (!who && String(f.formula).startsWith('z_') && (vals.peso || vals.talla) ? 'Cargando tablas de la OMS…' : '');
      inputs[f.key].value = v; inputs[f.key].textContent = v;
    }
  }

  spec.addEventListener('change', fillTemplates);
  tpl.addEventListener('change', draw);
  [birth, sex].forEach((el) => el.addEventListener('change', recalc));
  fieldsBox.addEventListener('input', recalc);
  fieldsBox.addEventListener('change', recalc);
  const clear = h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => { Object.keys(inputs).forEach((k) => delete inputs[k]); draw(); } }, 'Limpiar');

  box.replaceChildren(h('section', { class: 'hc-note hc-form' },
    h('div', { class: 'hc-banner prueba', role: 'status' }, 'VISTA PREVIA · Paciente de ejemplo. Nada de esto se guarda ni toca pacientes reales.'),
    h('div', { class: 'hc-grid' },
      h('label', { for: 'hp-spec' }, 'Especialidad', spec),
      h('label', { for: 'hp-tpl' }, 'Plantilla', tpl),
      h('label', { for: 'hp-birth' }, 'Nacimiento del paciente de ejemplo', birth),
      h('label', { for: 'hp-sex' }, 'Sexo', sex)),
    fieldsBox, h('div', { class: 'i18-actions' }, clear), msg));
  fillTemplates();
}
