/** SOFA · 22 · Pacientes del consultorio (ficha administrativa, sin datos clínicos).
 *  Buscar, crear/editar la ficha y ver su historial de citas y reclamaciones. Cada apertura queda en la bitácora.
 *  2.6.1: ARS y PLAN del paciente; sus reclamaciones se tarifan con la tarifa del plan cuando existe. */
import { rpc, providerOptions, h, money, fmtDate, note, guarded, table } from '../services/iter18.js';

const SEX = { F: 'Femenino', M: 'Masculino', X: 'No especificado' };

/** 2.8 · Portal del paciente: enlace personal (sin usuario) para ver citas, recetas y saldo desde el teléfono */
function portalBox(patientId, p) {
  const box = h('section', { class: 'i18-card pt-admin' }, h('h4', { style: 'margin-top:0' }, 'Portal del paciente'));
  const out = h('div', { 'aria-live': 'polite' });
  const fmt = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');
  async function draw() {
    let st;
    try { st = await rpc('portal_link_status', { p_patient: patientId }); } catch (e) { box.replaceChildren(h('h4', { style: 'margin-top:0' }, 'Portal del paciente'), note(e.message, 'error')); return; }
    const days = h('select', { 'aria-label': 'Duración del enlace' }, [7, 30, 60, 90].map((d) => h('option', { value: String(d), selected: d === 30 }, `${d} días`)));
    const orders = h('input', { type: 'checkbox', checked: true });
    const create = h('button', { class: 'i18-btn i18-sec', type: 'button' }, st.active ? 'Crear enlace nuevo' : 'Crear enlace');
    create.addEventListener('click', async () => {
      if (st.active && !confirm('El enlace anterior dejará de funcionar. ¿Crear uno nuevo?')) return;
      create.disabled = true;
      try { const r = await rpc('portal_link_create', { p_patient: patientId, p_days: Number(days.value), p_show_orders: orders.checked }); show(r); await draw(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); create.disabled = false; }
    });
    const revoke = st.active ? h('button', { class: 'i18-link', type: 'button', onclick: async () => {
      if (!confirm('El paciente ya no podrá abrir su enlace. ¿Anularlo?')) return;
      try { await rpc('portal_link_revoke', { p_patient: patientId }); out.replaceChildren(note('Enlace anulado.', 'ok')); await draw(); } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    } }, 'Anular enlace') : '';
    box.replaceChildren(h('h4', { style: 'margin-top:0' }, 'Portal del paciente'),
      ...(st.mode === 'desactivada' ? [note('El portal se habilita junto con la historia clínica de su consultorio. Pídalo a SOFA.')] : [
        st.mode === 'prueba' ? note('Modo prueba: úselo solo con pacientes ficticios hasta la revisión legal.') : '',
        h('p', { class: 'i18-sub' }, st.active ? `Enlace vigente hasta ${fmt(st.expires_at)} · abierto ${st.views} vez/veces${st.last_view_at ? ` (último: ${fmt(st.last_view_at)})` : ''}${st.show_orders ? '' : ' · sin recetas'}`
          : st.expired ? 'El último enlace venció.' : 'El paciente todavía no tiene enlace. Con él ve sus próximas citas, recetas y saldo desde su teléfono, sin usuario ni clave.'),
        h('div', { class: 'i18-bar' }, h('label', {}, 'Dura', days), h('label', { class: 'i18-chk' }, orders, ' Mostrar recetas y órdenes'), create, revoke)]),
      out);
  }
  function show(r) {
    const url = new URL('portal.html', location.href); url.hash = `t=${r.token}`; const link = url.toString();
    const phone = String(r.phone || p.phone || '').replace(/\D/g, '');
    const text = `Hola ${String(p.name || '').split(' ')[0]}, este es su enlace personal para ver sus citas, recetas y saldo: ${link} (no lo comparta)`;
    const copy = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Copiar enlace');
    copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(link); copy.textContent = 'Copiado'; } catch (_) { copy.textContent = 'Selecciónelo y copie'; } });
    out.replaceChildren(h('div', { class: 'i18-card', role: 'status' }, h('strong', {}, 'Enlace creado (se muestra una sola vez)'), h('pre', { class: 'i18-pre' }, link),
      h('div', { class: 'i18-actions' }, copy, phone ? h('a', { class: 'i18-btn', href: `https://wa.me/${phone.length === 10 ? `1${phone}` : phone}?text=${encodeURIComponent(text)}`, target: '_blank', rel: 'noopener' }, 'Enviar por WhatsApp') : ''),
      r.test_mode ? note('Modo prueba: envíelo solo a pacientes ficticios.') : ''));
  }
  draw();
  return box;
}

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
  const cat = await rpc('ars_catalog', { p_include_inactive: false }).catch(() => []);

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
    const ars = h('select', { id: 'px-ars' }, h('option', { value: '' }, 'Sin seguro (privado)'), cat.map((a) => h('option', { value: a.id, selected: (p?.ars_id || '') === a.id }, a.name)));
    const plan = h('select', { id: 'px-plan' });
    const fillPlans = (sel) => {
      const a = cat.find((x) => x.id === ars.value);
      plan.replaceChildren(h('option', { value: '' }, a ? 'Plan no indicado (tarifa general)' : '—'),
        ...((a && a.plans) || []).map((x) => h('option', { value: x.id, selected: sel === x.id }, x.name)));
      plan.disabled = !a;
    };
    ars.addEventListener('change', () => fillPlans(null));
    fillPlans(p?.plan_id || null);
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar ficha');
    save.addEventListener('click', async () => {
      save.disabled = true; msg.replaceChildren();
      try {
        const id = await rpc('save_patient', { p_id: p?.id || null, p_org: org.value, p_full_name: name.value, p_doc: doc.value || null,
          p_birth: birth.value || null, p_sex: sex.value || null, p_phone: phone.value || null, p_email: mail.value || null,
          p_ars: ars.value || null, p_member: mem.value || null, p_notes: notes.value || null });
        await rpc('set_patient_plan', { p_patient: id, p_ars: ars.value || null, p_plan: plan.value || null });
        await open(id);
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    card.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, p ? 'Editar ficha' : 'Nuevo paciente'),
      h('div', { class: 'i18-form' }, lName, name, lDoc, doc, lBirth, birth, h('label', { for: 'px-sex' }, 'Sexo'), sex, lPhone, phone, lMail, mail,
        h('label', { for: 'px-ars' }, 'ARS'), ars, h('label', { for: 'px-plan' }, 'Plan de la ARS'), plan, lMem, mem,
        h('label', { for: 'px-notes' }, 'Notas administrativas (no clínicas)'), notes, save), msg));
  }

  async function open(id) {
    const d = await guarded(card, () => rpc('patient_card', { p_patient: id }));
    if (!d) return;
    const p = d.patient;
    const ins = await rpc('patient_plan', { p_patient: id }).catch(() => null);
    if (ins) Object.assign(p, { ars_id: ins.ars_id, plan_id: ins.plan_id });
    const edit = h('button', { class: 'i18-btn i18-sec', type: 'button', onclick: () => form(p) }, 'Editar');
    card.replaceChildren(h('section', { class: 'i18-card' }, h('h3', {}, p.name), edit,
      h('p', { class: 'i18-sub' }, `Documento: ${p.doc || '—'} · Nacimiento: ${fmtDate(p.birth_date)} · Sexo: ${SEX[p.sex] || '—'} · Tel.: ${p.phone || '—'} · Afiliado: ${p.member || '—'}`),
      h('p', { class: 'i18-sub' }, `Seguro: ${ins?.ars ? `${ins.ars} · ${ins.plan || 'plan no indicado'}` : 'sin seguro registrado'}`),
      portalBox(id, p),
      p.notes ? note(p.notes) : null,
      h('h4', {}, 'Citas'), table([
        { label: 'Fecha', get: (r) => fmtDate(r.date) }, { label: 'Hora', get: (r) => (r.time || '').slice(0, 5) || '—' },
        { label: 'Estado', get: (r) => r.status }, { label: 'Motivo', get: (r) => r.reason || '—' }, { label: 'Médico', get: (r) => r.provider }], d.appointments),
      h('h4', {}, 'Reclamaciones'), table([
        { label: 'Folio', get: (r) => r.folio }, { label: 'Fecha', get: (r) => fmtDate(r.date) }, { label: 'Servicio', get: (r) => r.service || '—' },
        { label: 'Estado', get: (r) => r.status }, { label: 'Monto', right: true, get: (r) => money(r.amount) }], d.claims)));
  }
}
