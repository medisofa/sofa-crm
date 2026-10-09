/** SOFA · 22 · Pacientes del consultorio (ficha administrativa, sin datos clínicos).
 *  Buscar, crear/editar la ficha y ver su historial de citas y reclamaciones. Cada apertura queda en la bitácora. */
import { rpc, providerOptions, h, money, fmtDate, note, guarded, table } from '../services/iter18.js';

const SEX = { F: 'Femenino', M: 'Masculino', X: 'No especificado' };

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const res = h('div', { 'aria-live': 'polite' });
  const card = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Pacientes'), top, res, card);
  const provs = await guarded(top, providerOptions);
  if (!provs) return;
  const orgs = [...new Map(provs.map((p) => [p.organization_id, p.full_name])).entries()];
  if (!orgs.length) { top.replaceChildren(note('No tiene consultorios asignados. Pida al Administrador que le asigne uno.')); return; }

  const org = h('select', { id: 'px-org' }, orgs.map(([id, name]) => h('option', { value: id }, name)));
  const q = h('input', { id: 'px-q', type: 'search', placeholder: 'Nombre, cédula o número de afiliado', style: 'min-width:16rem' });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Buscar');
  const nuevo = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Nuevo paciente');
  const link = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Crear fichas desde el historial');
  top.replaceChildren(h('div', { class: 'i18-form' },
    orgs.length > 1 ? [h('label', { for: 'px-org' }, 'Consultorio'), org] : null,
    h('label', { for: 'px-q' }, 'Buscar paciente'), q, h('div', {}, go, ' ', nuevo, ' ', link)));

  async function search() {
    card.replaceChildren();
    const rows = await guarded(res, () => rpc('search_patients', { p_org: org.value, p_q: q.value }));
    if (!rows) return;
    res.replaceChildren(table([
      { label: 'Paciente', get: (r) => h('button', { class: 'i18-link', type: 'button', onclick: () => open(r.id) }, r.name) },
      { label: 'Documento', get: (r) => r.doc || '—' },
      { label: 'Afiliado', get: (r) => r.member || '—' },
      { label: 'Teléfono', get: (r) => r.phone || '—' }], rows));
  }
  go.addEventListener('click', search);
  q.addEventListener('keydown', (e) => { if (e.key === 'Enter') search(); });

  link.addEventListener('click', async () => {
    link.disabled = true;
    try {
      const r = await rpc('link_patients', { p_org: org.value });
      res.replaceChildren(note(`Listo: ${r.created} ficha(s) nueva(s), ${r.linked_appointments} cita(s) y ${r.linked_claims} reclamación(es) vinculadas.`));
    } catch (e) { res.replaceChildren(note(e.message, 'error')); }
    finally { link.disabled = false; }
  });

  nuevo.addEventListener('click', () => form(null));

  function form(p) {
    const f = (id, label, attrs = {}) => { const i = h('input', { id, ...attrs }); return [h('label', { for: id }, label), i]; };
    const [lName, name] = f('px-name', 'Nombre completo *', { value: p?.name || '' });
    const [lDoc, doc] = f('px-doc', 'Cédula o pasaporte', { value: p?.doc || '' });
    const [lBirth, birth] = f('px-birth', 'Fecha de nacimiento', { type: 'date', value: p?.birth_date || '' });
    const sex = h('select', { id: 'px-sex' }, h('option', { value: '' }, '—'), Object.entries(SEX).map(([k, v]) => h('option', { value: k, selected: p?.sex === k }, v)));
    const [lPhone, phone] = f('px-phone', 'Teléfono (WhatsApp)', { value: p?.phone || '' });
    const [lMail, mail] = f('px-mail', 'Correo', { type: 'email', value: p?.email || '' });
    const [lMem, mem] = f('px-mem', 'Número de afiliado', { value: p?.member || '' });
    const notes = h('textarea', { id: 'px-notes', rows: '2', maxlength: '500', style: 'width:100%' }, p?.notes || '');
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar ficha');
    save.addEventListener('click', async () => {
      save.disabled = true; msg.replaceChildren();
      try {
        const id = await rpc('save_patient', { p_id: p?.id || null, p_org: org.value, p_full_name: name.value, p_doc: doc.value || null,
          p_birth: birth.value || null, p_sex: sex.value || null, p_phone: phone.value || null, p_email: mail.value || null,
          p_ars: p?.ars_id || null, p_member: mem.value || null, p_notes: notes.value || null });
        await open(id);
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    card.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, p ? 'Editar ficha' : 'Nuevo paciente'),
      h('div', { class: 'i18-form' }, lName, name, lDoc, doc, lBirth, birth, h('label', { for: 'px-sex' }, 'Sexo'), sex, lPhone, phone, lMail, mail, lMem, mem,
        h('label', { for: 'px-notes' }, 'Notas administrativas (no clínicas)'), notes, save), msg));
  }

  async function open(id) {
    const d = await guarded(card, () => rpc('patient_card', { p_patient: id }));
    if (!d) return;
    const p = d.patient;
    const edit = h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => form(p) }, 'Editar');
    card.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, p.name), edit,
      h('p', { class: 'i18-sub' }, `Documento: ${p.doc || '—'} · Nacimiento: ${fmtDate(p.birth_date)} · Sexo: ${SEX[p.sex] || '—'} · Tel.: ${p.phone || '—'} · Afiliado: ${p.member || '—'}`),
      p.notes ? note(p.notes) : null,
      h('h4', {}, 'Citas'), table([
        { label: 'Fecha', get: (r) => fmtDate(r.date) }, { label: 'Hora', get: (r) => (r.time || '').slice(0, 5) || '—' },
        { label: 'Estado', get: (r) => r.status }, { label: 'Motivo', get: (r) => r.reason || '—' }, { label: 'Médico', get: (r) => r.provider }], d.appointments),
      h('h4', {}, 'Reclamaciones'), table([
        { label: 'Folio', get: (r) => r.folio }, { label: 'Fecha', get: (r) => fmtDate(r.date) }, { label: 'Servicio', get: (r) => r.service || '—' },
        { label: 'Estado', get: (r) => r.status }, { label: 'Monto', right: true, get: (r) => money(r.amount) }], d.claims)));
  }
}
