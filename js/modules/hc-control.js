/** SOFA · 2.0 · Historia clínica: control (solo Super Admin).
 *  Modo por consultorio (desactivada / prueba / activa), verificación en dos pasos obligatoria,
 *  bitácora de accesos y verificación de integridad de la bitácora. No muestra datos clínicos.
 *  2.6.1: aquí el Super Admin importa las historias que el consultorio trae de otro sistema (a nombre del médico). */
import { rpc, clientOptions, clientName, h, note, guarded, table } from '../services/iter18.js';
import { importPanel } from './hc-importar.js';

const MODE = { desactivada: 'Desactivada', prueba: 'Prueba (solo pacientes ficticios)', activa: 'Activa (pacientes reales)' };
const fmtTs = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const body = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Historia clínica: control'),
    note('Aquí se decide en qué consultorios funciona la historia clínica. Usted no ve datos clínicos desde esta pantalla.'), top, body);
  const orgs = await guarded(top, clientOptions);
  if (!orgs) return;
  if (!orgs.length) { top.replaceChildren(note('No hay consultorios clientes todavía.')); return; }
  const sel = h('select', { id: 'hcc-org' }, orgs.map((o) => h('option', { value: o.id }, clientName(o))));
  const verify = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Verificar integridad de la bitácora');
  const vmsg = h('div', { 'aria-live': 'polite' });
  verify.addEventListener('click', async () => {
    const r = await guarded(vmsg, () => rpc('clinical_verify_log'));
    if (r) vmsg.replaceChildren(note(r.ok ? `Bitácora íntegra: ${r.rows} registros verificados.` : `ALERTA: la bitácora fue alterada a partir del registro ${r.first_bad_id}. Avise de inmediato.`, r.ok ? 'ok' : 'error'));
  });
  top.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'hcc-org' }, 'Consultorio', sel), verify), vmsg);
  sel.addEventListener('change', draw);
  await draw();

  async function draw() {
    const org = sel.value;
    const st = await guarded(body, () => rpc('clinical_status', { p_org: org }));
    if (!st) return;
    const mode = h('select', { id: 'hcc-mode' }, Object.entries(MODE).map(([k, v]) => h('option', { value: k, selected: st.mode === k }, v)));
    const mfa = h('input', { id: 'hcc-mfa', type: 'checkbox', checked: st.require_mfa });
    const ack = h('textarea', { id: 'hcc-ack', rows: '3', maxlength: '1000', style: 'width:100%', placeholder: 'Ej.: Revisado por Lic. ____, abogado de salud, el __/__/2026; memo de consentimiento y conservación v1.' });
    const ackWrap = h('label', { for: 'hcc-ack' }, 'Constancia de revisión legal (obligatoria para «Activa»)', ack);
    const toggle = () => { ackWrap.hidden = mode.value !== 'activa'; };
    mode.addEventListener('change', toggle); toggle();
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar');
    save.addEventListener('click', async () => {
      if (mode.value === 'activa' && !confirm('Modo ACTIVA: el consultorio podrá registrar pacientes reales. ¿Confirma que la revisión legal está hecha?')) return;
      save.disabled = true;
      try { await rpc('clinical_set_mode', { p_org: org, p_mode: mode.value, p_require_mfa: mfa.checked, p_legal_ack: ack.value || null }); await draw(); body.prepend(note('Guardado.', 'ok')); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    const logBox = h('div', { 'aria-live': 'polite' });
    const showLog = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Ver bitácora (30 días)');
    showLog.addEventListener('click', async () => {
      const rows = await guarded(logBox, () => rpc('clinical_access_report', { p_org: org }));
      if (rows) logBox.replaceChildren(table([{ label: 'Fecha', get: (r) => fmtTs(r.at) }, { label: 'Usuario', get: (r) => r.user },
        { label: 'Acción', get: (r) => (r.emergency ? '⚠ ' : '') + r.action }, { label: 'Paciente', get: (r) => r.patient || '—' }], rows));
    });
    body.replaceChildren(h('section', { class: 'i18-card i18-form' },
      h('p', {}, 'Modo actual: ', h('strong', {}, MODE[st.mode])),
      h('label', { for: 'hcc-mode' }, 'Modo', mode),
      h('label', { class: 'i18-chk', for: 'hcc-mfa' }, mfa, ' Exigir verificación en dos pasos al médico para abrir la historia (recomendado)'),
      ackWrap, h('div', { class: 'i18-actions' }, save, showLog), msg),
      note('Recomendación: deje «Prueba» hasta que un abogado de salud revise el consentimiento, la conservación y la seguridad. En prueba, use solo pacientes ficticios.'),
      logBox, importSection(org, st.mode));
  }

  // 2.6.1 · Importar historias de otro sistema: solo el Super Admin, a nombre del médico del consultorio
  function importSection(org, mode) {
    const box = h('section', { class: 'i18-card', id: 'hcc-import' }, h('h3', { style: 'margin-top:0' }, 'Importar historias de otro sistema'));
    if (mode === 'desactivada') { box.append(note('Active primero la historia clínica en este consultorio (modo Prueba o Activa) para poder importar.')); return box; }
    const pane = h('div');
    const author = h('select', { id: 'hcc-author' });
    const start = h('button', { class: 'i18-btn', type: 'button' }, 'Preparar la importación');
    const hist = h('div', { 'aria-live': 'polite' });
    box.append(note('Pida al consultorio el Excel o CSV que exporta su sistema anterior (una fila por consulta). Las notas quedan a nombre del médico que elija, con el sello «Importada por SOFA». Todo queda en la bitácora que ve el médico.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'hcc-author' }, 'A nombre de', author), start), pane, h('h4', {}, 'Importaciones anteriores'), hist);
    guarded(hist, () => rpc('clinical_import_authors', { p_org: org })).then((d) => {
      if (!d) return;
      author.replaceChildren(...(d.authors.length ? d.authors.map((a) => h('option', { value: a.id }, a.name)) : [h('option', { value: '' }, 'El consultorio no tiene médicos con usuario')]));
      start.disabled = !d.authors.length;
      hist.replaceChildren(d.batches.length ? table([{ label: 'Fecha', get: (r) => fmtTs(r.at) }, { label: 'Sistema', get: (r) => r.source },
        { label: 'Archivo', get: (r) => r.file || '—' }, { label: 'Notas', right: true, get: (r) => r.notes }, { label: 'Pacientes nuevos', right: true, get: (r) => r.patients },
        { label: 'Por', get: (r) => r.by || '—' }], d.batches) : note('Este consultorio no tiene importaciones.'));
    });
    start.addEventListener('click', () => importPanel(pane, org, rpc, { author: author.value, authorName: author.selectedOptions[0]?.textContent }));
    return box;
  }
}
