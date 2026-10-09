/** SOFA · 2.0 · Iteración 29 · Historia clínica.
 *  Solo el Médico del consultorio lee y escribe. La Secretaria y el personal de SOFA no ven datos clínicos;
 *  el Super Admin solo con «acceso de emergencia» (motivo obligatorio, 60 min, solo lectura, queda en la bitácora).
 *  Todo pasa por funciones de la base (110_historia_clinica.sql): cifrado, firma con huella, adendas y bitácora.
 *  La pantalla se bloquea sola tras 5 minutos sin uso y no guarda datos clínicos en el navegador. */
import { rpc, supabase, providerOptions, clientOptions, clientName, h, fmtDate, note, guarded, table } from '../services/iter18.js';
import { mfaState, verifyStep } from './seguridad.js';
import { orderForm, ordersList, printOrder } from './hc-ordenes.js';
import { importPanel } from './hc-importar.js';

const LOCK_MS = 5 * 60 * 1000;
const KIND = { historia_externa: 'Historia de otro sistema', resultado: 'Resultado', imagen: 'Imagen', otro: 'Otro' };
const CONSENT = { tratamiento_datos: 'Tratamiento de datos de salud', compartir_ars: 'Compartir con la ARS', telemedicina: 'Telemedicina' };
const METHOD = { firma_papel: 'Firma en papel', firma_digital: 'Firma digital', verbal_con_testigo: 'Verbal con testigo' };
const SECTION = { S: 'Subjetivo', O: 'Objetivo', A: 'Evaluación', P: 'Plan' };
const fmtTs = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');

export async function render(root, ctx = {}) {
  let lockTimer = null; let alive = true;
  const stopLock = () => { alive = false; clearTimeout(lockTimer); ['click', 'keydown', 'pointermove'].forEach((ev) => root.removeEventListener(ev, bump)); window.removeEventListener('hashchange', stopLock); };
  const bump = () => { if (!alive) return; clearTimeout(lockTimer); lockTimer = setTimeout(lock, LOCK_MS); };
  function lock() {
    root.replaceChildren(h('div', { class: 'hc-locked' }, h('h2', {}, 'Historia clínica bloqueada'),
      h('p', {}, 'Se ocultó por 5 minutos sin uso, para proteger los datos del paciente.'),
      h('button', { class: 'i18-btn', type: 'button', onclick: () => { stopLock(); render(root, ctx); } }, 'Continuar')));
    stopLock();
  }
  ['click', 'keydown', 'pointermove'].forEach((ev) => root.addEventListener(ev, bump, { passive: true }));
  window.addEventListener('hashchange', stopLock);
  bump();

  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const body = h('div');
  root.append(h('h2', {}, 'Historia clínica'), top, body);

  const isSA = ctx.role === 'super_admin';
  const list = await guarded(top, () => (isSA ? clientOptions() : providerOptions()));
  if (!list) return;
  const orgs = isSA ? list.map((c) => [c.id, clientName(c)]) : [...new Map(list.map((p) => [p.organization_id, p.full_name])).entries()];
  if (!orgs.length) { top.replaceChildren(note('No tiene consultorios asignados. Pida al Administrador que le asigne uno.')); return; }
  const templates = await guarded(top, () => rpc('clinical_templates_list'));
  if (!templates) return;
  const tplByCode = Object.fromEntries(templates.map((t) => [t.code, t]));

  const orgSel = h('select', { id: 'hc-org' }, orgs.map(([id, name]) => h('option', { value: id }, name)));
  orgSel.addEventListener('change', () => openOrg());
  top.replaceChildren(orgs.length > 1 ? h('div', { class: 'i18-bar' }, h('label', { for: 'hc-org' }, 'Consultorio', orgSel)) : '');
  await openOrg();

  async function openOrg() {
    const org = orgSel.value;
    body.replaceChildren();
    const st = await guarded(body, () => rpc('clinical_status', { p_org: org }));
    if (!st) return;
    if (st.mode === 'desactivada') {
      body.replaceChildren(note('La historia clínica todavía no está activada en este consultorio. La activa el Super Admin en «Historia clínica: control».'));
      return;
    }
    if (!st.role && isSA) { emergencyForm(org); return; }
    if (!st.role) { body.replaceChildren(note('Sin acceso a la historia clínica: solo el médico del consultorio la consulta.', 'error')); return; }
    if (st.require_mfa && st.aal !== 'aal2') { await mfaGate(); return; }

    const banners = [];
    if (st.mode === 'prueba') banners.push(h('div', { class: 'hc-banner prueba', role: 'status' }, 'MODO PRUEBA · Use solo pacientes ficticios. No registre datos reales hasta la revisión legal.'));
    if (st.role === 'emergencia') banners.push(h('div', { class: 'hc-banner emergencia', role: 'status' }, `ACCESO DE EMERGENCIA · Solo lectura hasta las ${fmtTs(st.emergency_until)}. Todo queda en la bitácora que ve el médico.`));

    const q = h('input', { id: 'hc-q', type: 'search', placeholder: 'Nombre, cédula o afiliado' });
    const results = h('div', { class: 'hc-results', 'aria-live': 'polite' });
    const main = h('div', { 'aria-live': 'polite' }, note('Busque un paciente para abrir su historia.'));
    const logBtn = st.can_write ? h('div', { class: 'hc-side' }, h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => accessLog(org, main) }, '¿Quién vio mis historias?'),
      h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => importPanel(main, org, rpc) }, 'Importar historias de otro sistema')) : '';
    body.replaceChildren(...banners, h('div', { class: 'hc-layout' },
      h('aside', { class: 'hc-side' }, h('label', { for: 'hc-q' }, 'Buscar paciente'), q, results, logBtn),
      main));
    async function search() {
      const rows = await guarded(results, () => rpc('search_patients', { p_org: org, p_q: q.value }));
      if (!rows) return;
      results.replaceChildren(...(rows.length ? rows.map((r) => h('button', { type: 'button', 'aria-pressed': 'false', onclick: (e) => {
        results.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', 'false'));
        e.currentTarget.setAttribute('aria-pressed', 'true');
        openPatient(r.id, main, st);
      } }, r.name, h('div', { class: 'i18-sub' }, r.doc || r.member || ''))) : [note('Sin resultados. Si es nuevo, créelo en «Pacientes».')]));
    }
    q.addEventListener('keydown', (e) => { if (e.key === 'Enter') search(); });
    q.addEventListener('input', () => { clearTimeout(q._t); if (q.value.trim().length >= 2) q._t = setTimeout(search, 350); });
    q.focus();
  }

  async function mfaGate() {
    let s;
    try { s = await mfaState(); } catch (e) { body.replaceChildren(note(e.message, 'error')); return; }
    const box = h('div');
    if (!s.factor) {
      body.replaceChildren(note('Este consultorio exige verificación en dos pasos para la historia clínica. Actívela en Mi cuenta › Seguridad y vuelva aquí.', 'error'),
        h('div', { class: 'i18-actions' }, h('a', { class: 'i18-btn', href: '#/seguridad' }, 'Ir a Seguridad')));
      return;
    }
    body.replaceChildren(note('Este consultorio exige el segundo paso. Escriba el código de su app autenticadora.'), box);
    verifyStep(box, s.factor.id, () => openOrg());
  }

  function emergencyForm(org) {
    const reason = h('textarea', { id: 'hc-reason', rows: '3', maxlength: '500', style: 'width:100%' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Pedir acceso de emergencia (60 min)');
    const msg = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      go.disabled = true;
      try { await rpc('clinical_break_glass', { p_org: org, p_reason: reason.value }); openOrg(); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    body.replaceChildren(note('Como Super Admin no ve datos clínicos. Solo en una emergencia puede pedir acceso de lectura por 60 minutos. El motivo queda en la bitácora y el médico lo ve.'),
      h('div', { class: 'i18-form' }, h('label', { for: 'hc-reason' }, 'Motivo (mínimo 20 caracteres)'), reason, h('div', {}, go), msg));
  }

  async function openPatient(id, main, st) {
    const rec = await guarded(main, () => rpc('clinical_record', { p_patient: id }));
    if (!rec) return;
    const w = st.can_write;
    const p = rec.patient;
    const age = p.birth_date ? Math.floor((Date.now() - new Date(p.birth_date)) / 31557600000) : null;
    const pane = h('div', { 'aria-live': 'polite' });
    const actions = h('div', { class: 'i18-actions hc-actions' },
      w ? h('button', { class: 'i18-btn', type: 'button', onclick: () => noteForm(id, null, pane, main, st) }, 'Nueva nota') : '',
      w ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => summaryForm(id, rec, pane, main, st) }, 'Resumen clínico') : '',
      w ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => consentForm(id, pane, main, st) }, 'Consentimiento') : '',
      w ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => orderForm(pane, id, null, rpc, () => openPatient(id, main, st)) }, 'Receta u orden') : '',
      w ? h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => uploadForm(id, pane, main, st) }, 'Adjuntar historia anterior') : '',
      h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => exportRecord(id, pane) }, 'Exportar / imprimir'));
    const sum = rec.summary || {};
    const consentOk = rec.consents.some((c) => c.kind === 'tratamiento_datos' && !c.revoked_at);
    main.replaceChildren(
      h('div', { class: 'hc-head' }, h('h3', {}, p.name), h('span', { class: 'i18-sub' }, [p.doc, age != null ? `${age} años` : null, p.sex].filter(Boolean).join(' · '))),
      actions,
      consentOk ? '' : note(rec.mode === 'activa' ? 'Falta el consentimiento del paciente: regístrelo antes de escribir notas.' : 'Sin consentimiento registrado (en modo prueba no se exige).', rec.mode === 'activa' ? 'error' : 'info'),
      h('section', { class: 'i18-card' }, h('h4', { class: 'hc-sec' }, `Resumen clínico${rec.summary_at ? ' · ' + fmtTs(rec.summary_at) : ''}`),
        h('dl', { class: 'hc-dl' },
          h('dt', {}, 'Alergias'), h('dd', {}, sum.alergias || 'No registradas'),
          h('dt', {}, 'Antecedentes'), h('dd', {}, sum.antecedentes || '—'),
          h('dt', {}, 'Medicamentos actuales'), h('dd', {}, sum.medicamentos || '—'))),
      pane,
      h('h4', { class: 'hc-sec' }, `Notas (${rec.notes.length})`),
      h('div', { class: 'hc-notes' }, rec.notes.length ? rec.notes.map((n) => h('article', { class: 'hc-note' },
        h('header', {}, h('strong', {}, `${fmtDate(n.date)} · ${n.template_name}`),
          h('span', { class: `i18-badge ${n.status === 'firmada' ? 'i18-proximo' : 'i18-esta_semana'}` }, n.status === 'firmada' ? `Firmada${n.addenda ? ` · ${n.addenda} adenda(s)` : ''}` : 'Borrador'),
          h('button', { class: 'i18-link', type: 'button', onclick: () => viewNote(n.id, pane, main, st, id) }, 'Abrir')),
        h('div', { class: 'i18-sub' }, n.author || ''))) : note('Todavía no hay notas.')),
      h('h4', { class: 'hc-sec' }, 'Recetas y órdenes'), ordersList(id, pane, rpc),
      h('h4', { class: 'hc-sec' }, `Adjuntos (${rec.attachments.length})`),
      rec.attachments.length ? table([
        { label: 'Archivo', get: (a) => h('button', { class: 'i18-link', type: 'button', onclick: () => download(a.id, a.name) }, a.name) },
        { label: 'Tipo', get: (a) => KIND[a.kind] || a.kind },
        { label: 'Descripción', get: (a) => a.description || '—' },
        { label: 'Fecha', get: (a) => fmtTs(a.at) }], rec.attachments) : note('Sin adjuntos. Puede adjuntar la historia que el paciente traiga de otro sistema (PDF o foto).'));
    return pane;   // 2.4 · la orden recién firmada se muestra en el panel nuevo
  }

  async function viewNote(noteId, pane, main, st, patientId) {
    const n = await guarded(pane, () => rpc('clinical_note', { p_id: noteId }));
    if (!n) return;
    const t = tplByCode[n.template] || { fields: [], name: n.template };
    const secs = ['S', 'O', 'A', 'P'].map((k) => {
      const fs = t.fields.filter((f) => (f.section || 'S') === k && n.content[f.key]);
      return fs.length ? [h('h5', { class: 'hc-sec' }, SECTION[k]), h('dl', { class: 'hc-dl' }, fs.flatMap((f) => [h('dt', {}, f.label), h('dd', {}, String(n.content[f.key]))]))] : [];
    }).flat();
    const add = h('div');
    const btns = h('div', { class: 'i18-actions' });
    if (st.can_write && n.status === 'borrador' && n.mine) {
      btns.append(h('button', { class: 'i18-btn', type: 'button', onclick: () => noteForm(patientId, n, pane, main, st) }, 'Editar borrador'),
        h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: async () => {
          if (!confirm('¿Borrar este borrador? No se puede deshacer.')) return;
          try { await rpc('delete_clinical_draft', { p_id: n.id }); openPatient(patientId, main, st); } catch (e) { pane.prepend(note(e.message, 'error')); }
        } }, 'Borrar borrador'));
    }
    if (st.can_write && n.status === 'firmada') {
      btns.append(h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => orderForm(pane, patientId, n.id, rpc, () => openPatient(patientId, main, st)) }, 'Receta u orden de esta consulta'));
      if (n.content.diagnosticos) {
        const dx = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Pasar diagnóstico a la reclamación');
        dx.addEventListener('click', async () => {
          dx.disabled = true;
          try { const r = await rpc('note_diagnosis_to_claim', { p_note: n.id }); add.prepend(note(`Listo: la reclamación de la cita lleva ${r.codes}.`, 'ok')); }
          catch (e) { add.prepend(note(e.message, 'error')); } finally { dx.disabled = false; }
        });
        btns.append(dx);
      }
    }
    if (st.can_write && n.status === 'firmada') {
      const txt = h('textarea', { id: 'hc-add', rows: '3', maxlength: '4000', style: 'width:100%' });
      const go = h('button', { class: 'i18-btn', type: 'button' }, 'Firmar adenda');
      go.addEventListener('click', async () => {
        go.disabled = true;
        try { await rpc('add_clinical_addendum', { p_note: n.id, p_text: txt.value }); viewNote(n.id, pane, main, st, patientId); }
        catch (e) { add.prepend(note(e.message, 'error')); go.disabled = false; }
      });
      add.append(h('div', { class: 'hc-form' }, h('label', { for: 'hc-add' }, 'Agregar adenda (corrección o aclaración; la nota original no cambia)'), txt, h('div', {}, go)));
    }
    pane.replaceChildren(h('section', { class: 'hc-note' },
      h('header', {}, h('strong', {}, `${fmtDate(n.date)} · ${t.name}`), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cerrar')),
      ...secs,
      n.status === 'firmada' ? h('p', { class: 'i18-sub' }, `Firmada por ${n.signed_by} · ${fmtTs(n.signed_at)} · `,
        n.hash_ok ? '✔ Huella verificada: no ha cambiado desde la firma.' : '✖ La huella NO coincide: avise al Super Admin.', h('div', { class: 'hc-hash' }, n.hash)) : h('p', { class: 'i18-sub' }, 'Borrador sin firmar.'),
      n.addenda.length ? [h('h5', { class: 'hc-sec' }, 'Adendas'), ...n.addenda.map((a) => h('div', { class: 'i18-card' }, h('div', { class: 'i18-sub' }, `${fmtTs(a.at)} · ${a.by}`), h('p', { style: 'white-space:pre-wrap;margin:4px 0' }, a.text)))] : '',
      btns, add));
    pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function noteForm(patientId, existing, pane, main, st) {
    const tpl = h('select', { id: 'hc-tpl' }, templates.filter((t) => t.code !== 'historia_importada').map((t) => h('option', { value: t.code, selected: existing?.template === t.code }, `${t.specialty} · ${t.name}`)));
    const date = h('input', { id: 'hc-date', type: 'date', value: existing?.date || new Date().toISOString().slice(0, 10) });
    const apt = h('select', { id: 'hc-apt' }, h('option', { value: '' }, 'Sin cita'));
    rpc('clinical_appointments', { p_patient: patientId }).then((l) => apt.append(...l.map((a) => h('option', { value: a.id, selected: existing?.appointment_id === a.id },
      `${fmtDate(a.date)} ${String(a.time || '').slice(0, 5)} · ${a.reason || a.status}${a.has_claim ? ' · con reclamación' : ''}`)))).catch(() => {});
    const fieldsBox = h('div');
    const inputs = {};
    const msg = h('div', { 'aria-live': 'polite' });
    function drawFields() {
      const t = tplByCode[tpl.value];
      const prev = Object.fromEntries(Object.entries(inputs).map(([k, el]) => [k, el.value]));
      Object.keys(inputs).forEach((k) => delete inputs[k]);
      fieldsBox.replaceChildren(...['S', 'O', 'A', 'P'].map((k) => {
        const fs = t.fields.filter((f) => (f.section || 'S') === k);
        if (!fs.length) return '';
        return h('fieldset', { class: 'i18-fs' }, h('legend', {}, SECTION[k]), h('div', { class: k === 'O' ? 'hc-grid' : '' }, fs.map((f) => {
          const id = `hc-f-${f.key}`;
          const val = prev[f.key] ?? existing?.content?.[f.key] ?? '';
          let el;
          if (f.type === 'textarea') el = h('textarea', { id, rows: '3', maxlength: '8000' }, val);
          else if (f.type === 'select') el = h('select', { id }, h('option', { value: '' }, '—'), (f.options || []).map((o) => h('option', { value: o, selected: val === o }, o)));
          else el = h('input', { id, type: f.type === 'date' ? 'date' : 'text', inputmode: f.type === 'number' ? 'decimal' : null, value: val, placeholder: f.type === 'cie10' ? 'Ej.: I10, E11.9' : null });
          inputs[f.key] = el;
          return h('label', { for: id, class: f.type === 'textarea' ? 'hc-wide' : '' }, h('span', { class: f.required ? 'hc-req' : '' }, f.label), el);
        })));
      }));
    }
    tpl.addEventListener('change', drawFields);
    drawFields();
    const content = () => Object.fromEntries(Object.entries(inputs).map(([k, el]) => [k, el.value.trim()]).filter(([, v]) => v !== ''));
    async function save() {
      return rpc('save_clinical_note', { p_id: existing?.id || null, p_patient: patientId, p_template: tpl.value, p_content: content(), p_encounter: date.value || null, p_appointment: apt.value || null });
    }
    const bSave = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar borrador');
    const bSign = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar y firmar');
    bSave.addEventListener('click', async () => {
      bSave.disabled = true;
      try { const id = await save(); existing = { ...(existing || {}), id, template: tpl.value, content: content() }; msg.replaceChildren(note('Borrador guardado.', 'ok')); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); }
      finally { bSave.disabled = false; }
    });
    bSign.addEventListener('click', async () => {
      if (!confirm('Al firmar, la nota queda bloqueada: solo podrá corregirse con adendas. ¿Firmar ahora?')) return;
      bSign.disabled = true;
      try { const id = await save(); existing = { ...(existing || {}), id }; await rpc('sign_clinical_note', { p_id: id }); await openPatient(patientId, main, st); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); bSign.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'hc-note hc-form' },
      h('header', {}, h('strong', {}, existing ? 'Editar borrador' : 'Nueva nota'), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('div', { class: 'hc-grid' }, h('label', { for: 'hc-tpl' }, 'Plantilla', tpl), h('label', { for: 'hc-date' }, 'Fecha de la consulta', date), h('label', { for: 'hc-apt' }, 'Cita (para pasar el diagnóstico a la reclamación)', apt)),
      fieldsBox, h('p', { class: 'i18-sub' }, 'Los campos con * son obligatorios para firmar. El borrador puede guardarse incompleto.'),
      h('div', { class: 'i18-actions' }, bSave, bSign), msg));
    pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function summaryForm(patientId, rec, pane, main, st) {
    const s = rec.summary || {};
    const mk = (k, label) => { const el = h('textarea', { id: `hc-s-${k}`, rows: '2', maxlength: '4000' }, s[k] || ''); return [h('label', { for: `hc-s-${k}` }, label, el), el]; };
    const [l1, a] = mk('alergias', 'Alergias'); const [l2, b] = mk('antecedentes', 'Antecedentes (personales, familiares, quirúrgicos)'); const [l3, c] = mk('medicamentos', 'Medicamentos actuales');
    const msg = h('div', { 'aria-live': 'polite' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar resumen');
    go.addEventListener('click', async () => {
      go.disabled = true;
      try { await rpc('save_clinical_summary', { p_patient: patientId, p_content: { alergias: a.value.trim(), antecedentes: b.value.trim(), medicamentos: c.value.trim() } }); openPatient(patientId, main, st); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'hc-note hc-form' }, h('header', {}, h('strong', {}, 'Resumen clínico'), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('p', { class: 'i18-sub' }, 'Cada cambio guarda una versión nueva; las anteriores se conservan.'), l1, l2, l3, h('div', { class: 'i18-actions' }, go), msg));
  }

  function consentForm(patientId, pane, main, st) {
    const kind = h('select', { id: 'hc-ck' }, Object.entries(CONSENT).map(([k, v]) => h('option', { value: k }, v)));
    const method = h('select', { id: 'hc-cm' }, Object.entries(METHOD).map(([k, v]) => h('option', { value: k }, v)));
    const witness = h('input', { id: 'hc-cw', placeholder: 'Solo si es verbal' });
    const msg = h('div', { 'aria-live': 'polite' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Registrar consentimiento');
    go.addEventListener('click', async () => {
      go.disabled = true;
      try { await rpc('record_clinical_consent', { p_patient: patientId, p_kind: kind.value, p_method: method.value, p_witness: witness.value || null }); openPatient(patientId, main, st); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'hc-note hc-form' }, h('header', {}, h('strong', {}, 'Consentimiento del paciente'), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('p', { class: 'i18-sub' }, 'Registre que el paciente autorizó el uso de sus datos de salud. Guarde el papel firmado en el consultorio o adjúntelo como «Otro».'),
      h('label', { for: 'hc-ck' }, 'Tipo', kind), h('label', { for: 'hc-cm' }, 'Cómo lo dio', method), h('label', { for: 'hc-cw' }, 'Testigo', witness),
      h('div', { class: 'i18-actions' }, go), msg));
  }

  function uploadForm(patientId, pane, main, st) {
    const org = orgSel.value;
    const file = h('input', { id: 'hc-file', type: 'file', accept: 'application/pdf,image/jpeg,image/png' });
    const kind = h('select', { id: 'hc-fk' }, Object.entries(KIND).map(([k, v]) => h('option', { value: k }, v)));
    const desc = h('input', { id: 'hc-fd', maxlength: '300', placeholder: 'Ej.: Historia del Dr. X, 2019-2025' });
    const msg = h('div', { 'aria-live': 'polite' });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Subir');
    go.addEventListener('click', async () => {
      const f = file.files[0];
      if (!f) { msg.replaceChildren(note('Elija un archivo PDF, JPG o PNG.', 'error')); return; }
      if (f.size > 20 * 1024 * 1024) { msg.replaceChildren(note('El archivo pasa de 20 MB. Divídalo o redúzcalo e intente de nuevo.', 'error')); return; }
      if (!['application/pdf', 'image/jpeg', 'image/png'].includes(f.type)) { msg.replaceChildren(note('Solo se aceptan PDF, JPG o PNG.', 'error')); return; }
      go.disabled = true; msg.replaceChildren(note('Subiendo…'));
      const ext = f.type === 'application/pdf' ? 'pdf' : f.type === 'image/png' ? 'png' : 'jpg';
      const path = `${org}/${patientId}/${crypto.randomUUID()}.${ext}`;
      try {
        const { error } = await supabase.storage.from('clinical-records').upload(path, f, { contentType: f.type, upsert: false });
        if (error) throw new Error('No se pudo subir el archivo. Revise su conexión e intente de nuevo.');
        await rpc('register_clinical_attachment', { p_patient: patientId, p_path: path, p_file_name: f.name, p_kind: kind.value, p_description: desc.value || null });
        openPatient(patientId, main, st);
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'hc-note hc-form' }, h('header', {}, h('strong', {}, 'Adjuntar documento'), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')),
      h('p', { class: 'i18-sub' }, 'Para pacientes que traen su historia de otro sistema: súbala en PDF o foto. Los adjuntos no se pueden borrar ni reemplazar.'),
      h('label', { for: 'hc-file' }, 'Archivo (PDF, JPG o PNG, máximo 20 MB)', file), h('label', { for: 'hc-fk' }, 'Tipo', kind), h('label', { for: 'hc-fd' }, 'Descripción', desc),
      h('div', { class: 'i18-actions' }, go), msg));
  }

  async function download(id, name) {
    try {
      const path = await rpc('log_clinical_download', { p_attachment: id });
      const { data, error } = await supabase.storage.from('clinical-records').createSignedUrl(path, 60);
      if (error) throw new Error('No se pudo abrir el archivo. Intente de nuevo.');
      window.open(data.signedUrl, '_blank', 'noopener');
    } catch (e) { alert(e.message || `No se pudo abrir ${name}.`); }
  }

  async function exportRecord(patientId, pane) {
    const x = await guarded(pane, () => rpc('clinical_export', { p_patient: patientId }));
    if (!x) return;
    const notes = x.notes.map((n) => h('article', { class: 'hc-note' },
      h('header', {}, h('strong', {}, `${fmtDate(n.date)} · ${n.template}`)),
      h('dl', { class: 'hc-dl' }, (n.fields || []).filter((f) => n.content[f.key]).flatMap((f) => [h('dt', {}, f.label), h('dd', {}, String(n.content[f.key]))])),
      h('p', { class: 'i18-sub' }, `Firmada por ${n.signed_by} el ${fmtTs(n.signed_at)}`, h('div', { class: 'hc-hash' }, n.hash)),
      n.addenda.map((a) => h('div', { class: 'i18-card' }, h('div', { class: 'i18-sub' }, `Adenda · ${fmtTs(a.at)} · ${a.by}`), h('p', { style: 'white-space:pre-wrap;margin:4px 0' }, a.text)))));
    const s = x.summary || {};
    pane.replaceChildren(h('section', {},
      h('div', { class: 'i18-actions hc-actions' }, h('button', { class: 'i18-btn', type: 'button', onclick: () => window.print() }, 'Imprimir o guardar en PDF'),
        h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cerrar')),
      h('h3', {}, `Historia clínica · ${x.patient.name}`),
      h('p', { class: 'i18-sub' }, `${x.organization} · Documento ${x.patient.doc || '—'} · Generada el ${fmtTs(x.generated_at)} por ${x.generated_by}. CONFIDENCIAL: datos de salud.`),
      h('dl', { class: 'hc-dl' }, h('dt', {}, 'Alergias'), h('dd', {}, s.alergias || '—'), h('dt', {}, 'Antecedentes'), h('dd', {}, s.antecedentes || '—'), h('dt', {}, 'Medicamentos'), h('dd', {}, s.medicamentos || '—')),
      ...notes,
      x.attachments.length ? h('p', { class: 'i18-sub' }, `Adjuntos en SOFA: ${x.attachments.map((a) => a.name).join(', ')}`) : ''));
    pane.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  async function accessLog(org, main) {
    const rows = await guarded(main, () => rpc('clinical_access_report', { p_org: org }));
    if (!rows) return;
    const ACT = { ver: 'Vio', crear: 'Creó nota', editar: 'Editó borrador', firmar: 'Firmó', adenda: 'Adenda', exportar: 'Exportó', adjuntar: 'Adjuntó', descargar: 'Abrió adjunto',
      consentimiento: 'Consentimiento', resumen: 'Resumen', borrar_borrador: 'Borró borrador', acceso_emergencia: '⚠ Acceso de emergencia', modo: 'Cambio de modo' };
    main.replaceChildren(h('h3', {}, 'Bitácora de accesos (últimos 30 días)'),
      note('Cada vez que alguien ve, escribe o exporta una historia queda registrado aquí. La bitácora no se puede borrar ni modificar.'),
      table([{ label: 'Fecha', get: (r) => fmtTs(r.at) }, { label: 'Usuario', get: (r) => r.user }, { label: 'Acción', get: (r) => ACT[r.action] || r.action },
        { label: 'Paciente', get: (r) => r.patient || '—' }, { label: 'Detalle', get: (r) => (r.action === 'firmar' ? '' : r.detail) || '' }], rows));
  }
}
