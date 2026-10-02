/** SOFA · Diálogos reutilizables del CRM */
import { html, render as paint, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError, toast } from '../utils/ui.js';
import { SOURCES, SERVICES, ORG_TYPES, PARTNER_TYPES, LOST_REASONS, PRIORITIES, STAGES, stageLabel, ACTIVITY_TYPES, COMMERCIAL_DOCS, CONTACT_ROLES } from '../utils/constants.js';
import { isEmail, isTaxId, isPhone } from '../utils/validation.js';
import { newProspect, findDuplicates, convertOpportunity, activePartners, listStaff, saveContact, savePartner, addActivity } from '../services/crm.js';
import { createTask } from '../services/tasks.js';
import { createClient } from '../services/clients.js';
import { todayISO, money } from '../utils/formatters.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };

function checkContactFields(form) {
  let ok = true;
  const e = form.elements.email, w = form.elements.whatsapp, p = form.elements.phone;
  if (e && e.value && !isEmail(e.value)) { fieldError(e, 'Correo no válido.'); ok = false; } else if (e) fieldError(e, null);
  if (w && w.value && !isPhone(w.value)) { fieldError(w, 'Solo números: 10 a 15 dígitos.'); ok = false; } else if (w) fieldError(w, null);
  if (p && p.value && !isPhone(p.value)) { fieldError(p, 'Solo números: 10 a 15 dígitos.'); ok = false; } else if (p) fieldError(p, null);
  return ok;
}

/** Nuevo prospecto con advertencia de duplicados. Devuelve el id de la oportunidad creada. */
export async function newProspectDialog() {
  let partners = [];
  try { partners = await activePartners(); } catch { /* sin aliados visibles */ }
  return formDialog({
    title: 'Nuevo prospecto', submitLabel: 'Registrar prospecto', wide: true,
    body: html`<div id="dups"></div><div class="form-grid">
      ${f('company', 'Médico o centro *', text('company', '', 'required maxlength="200" autocomplete="off"'))}
      ${f('specialty', 'Especialidad', text('specialty'))}
      ${f('contact_name', 'Persona de contacto', text('contact_name'))}
      ${f('whatsapp', 'WhatsApp', text('whatsapp', '', 'inputmode="tel" placeholder="8095551234"'))}
      ${f('phone', 'Teléfono', text('phone', '', 'inputmode="tel"'))}
      ${f('email', 'Correo', text('email', '', 'type="email"'))}
      ${f('source', 'Canal de origen', html`<select id="f_source" name="source">${SOURCES.map((s) => opt(s, s, 'Instagram'))}</select>`)}
      ${f('referral_partner_id', 'Aliado que lo refirió', html`<select id="f_referral_partner_id" name="referral_partner_id"><option value="">Ninguno</option>${partners.map((p) => opt(p.id, p.full_name))}</select>`)}
      ${f('service_code', 'Servicio de interés *', html`<select id="f_service_code" name="service_code">${SERVICES.map((s) => opt(s.code, s.name, 'facturacion'))}</select>`)}
      ${f('estimated_value', 'Valor mensual estimado (RD$)', text('estimated_value', '5000', 'type="number" min="0" step="100"'))}
      ${f('next_action', 'Próxima acción', text('next_action', 'Agendar diagnóstico de fugas gratuito'))}
      ${f('next_action_date', 'Fecha', text('next_action_date', addDays(1), 'type="date"'))}
    </div>${f('notes', 'Notas', html`<textarea id="f_notes" name="notes" rows="2"></textarea>`)}`,
    onOpen: (form) => {
      const box = form.querySelector('#dups');
      const check = async () => {
        const c = form.elements.company.value, w = form.elements.whatsapp.value, e = form.elements.email.value;
        if (c.trim().length < 4 && w.replace(/\D/g, '').length < 10 && !isEmail(e)) { paint(box, html``); return; }
        try {
          const d = await findDuplicates(c, w, e);
          paint(box, d.length ? html`<div class="dup-box" role="status"><b>Posible duplicado:</b> ${d.map((x) => html`<div>${x.company}${x.contact_name ? ` · ${x.contact_name}` : ''}${x.converted ? ' · ya es cliente' : ''}</div>`)}<span class="small">Revisa antes de registrar otro.</span></div>` : html``);
        } catch { paint(box, html``); }
      };
      ['company', 'whatsapp', 'email'].forEach((n) => form.elements[n].addEventListener('change', check));
    },
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['company', 'service_code']) || !checkContactFields(form)) return false;
      const id = await newProspect(v);
      toast('Prospecto registrado', 'ok');
      return id;
    }
  });
}

/** Marcar oportunidad como perdida (exige motivo). Devuelve el motivo o null. */
export function lostDialog() {
  return formDialog({
    title: 'Marcar como perdida', submitLabel: 'Marcar perdida',
    body: html`${f('reason', 'Motivo *', html`<select id="f_reason" name="reason">${LOST_REASONS.map((r) => opt(r))}</select>`)}${f('detail', 'Detalle', html`<textarea id="f_detail" name="detail" rows="2" placeholder="Qué dijo y cuándo conviene volver a contactarlo"></textarea>`)}`,
    onSubmit: async (v) => (v.detail ? `${v.reason}: ${v.detail.trim()}` : v.reason)
  });
}

/** Convertir oportunidad en cliente PSS. Devuelve el id de la organización creada. */
export function convertDialog(opp) {
  return formDialog({
    title: 'Convertir en cliente PSS', submitLabel: 'Crear cliente', wide: true,
    body: html`<p class="small muted" style="margin-top:0">Se crea el cliente con sus reglas de honorario. Si es médico independiente, también se crea su prestador. Los contactos y diagnósticos del prospecto pasan al cliente.</p>
      <div class="form-grid">
      ${f('legal_name', 'Nombre o razón social *', text('legal_name', opp.company, 'required'))}
      ${f('tax_id', 'RNC (9) o cédula (11)', text('tax_id', '', 'inputmode="numeric"'))}
      ${f('org_type', 'Tipo *', html`<select id="f_org_type" name="org_type">${ORG_TYPES.map((t) => opt(t, t, 'Médico independiente'))}</select>`)}
      ${f('start', 'Fecha de inicio', text('start', todayISO(), 'type="date"'))}
      ${f('monthly_fee', 'Cuota mensual (RD$)', text('monthly_fee', opp.estimated_value || 0, 'type="number" min="0" step="100"'))}
      ${f('success_pct', '% sobre lo cobrado', text('success_pct', '5', 'type="number" min="0" max="30" step="0.5"'))}
      </div>`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['legal_name', 'org_type'])) return false;
      if (v.tax_id && !isTaxId(v.tax_id)) { fieldError(form.elements.tax_id, 'El RNC lleva 9 dígitos y la cédula 11.'); return false; }
      const orgId = await convertOpportunity(opp.id, v);
      toast('Cliente contratado: su implementación (onboarding de 9 pasos) ya está abierta.', 'ok');
      return orgId;
    }
  });
}

/** Alta directa de cliente PSS (para clientes que ya trabajaban con SOFA) */
export function clientDialog() {
  return formDialog({
    title: 'Nuevo cliente PSS', submitLabel: 'Crear cliente', wide: true,
    body: html`<div class="form-grid">
      ${f('legal_name', 'Nombre o razón social *', text('legal_name', '', 'required'))}
      ${f('tax_id', 'RNC (9) o cédula (11) *', text('tax_id', '', 'inputmode="numeric" required'))}
      ${f('org_type', 'Tipo *', html`<select id="f_org_type" name="org_type">${ORG_TYPES.map((t) => opt(t, t, 'Médico independiente'))}</select>`)}
      ${f('specialty', 'Especialidad', text('specialty'))}
      ${f('whatsapp', 'WhatsApp', text('whatsapp', '', 'inputmode="tel"'))}
      ${f('phone', 'Teléfono', text('phone', '', 'inputmode="tel"'))}
      ${f('email', 'Correo', text('email', '', 'type="email"'))}
      ${f('city', 'Ciudad', text('city', 'Santiago'))}
      ${f('started_on', 'Inicio del servicio', text('started_on', todayISO(), 'type="date"'))}
      ${f('monthly_fee', 'Cuota mensual (RD$)', text('monthly_fee', '5000', 'type="number" min="0" step="100"'))}
      ${f('success_pct', '% sobre lo cobrado', text('success_pct', '5', 'type="number" min="0" max="30" step="0.5"'))}
      ${f('provider_name', 'Prestador principal', text('provider_name'), 'Si es médico independiente, se usa su nombre.')}
      ${f('exequatur', 'Exequátur', text('exequatur'))}
      </div>`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['legal_name', 'tax_id', 'org_type']) || !checkContactFields(form)) return false;
      if (!isTaxId(v.tax_id)) { fieldError(form.elements.tax_id, 'El RNC lleva 9 dígitos y la cédula 11.'); return false; }
      const id = await createClient(v);
      toast('Cliente creado', 'ok');
      return id;
    }
  });
}

/** Nueva tarea, opcionalmente ligada a una entidad */
export async function taskDialog(ctx, entity = null, preset = {}) {
  let staff = [];
  try { staff = await listStaff(); } catch { /* sin lista */ }
  return formDialog({
    title: entity?.label ? `Nueva tarea · ${entity.label}` : 'Nueva tarea', submitLabel: 'Crear tarea',
    body: html`${f('title', 'Qué hay que hacer *', text('title', preset.title || '', 'required maxlength="200"'))}
      <div class="form-grid">
      ${f('due_date', 'Vence *', text('due_date', preset.due_date || addDays(1), 'type="date" required'))}
      ${f('priority', 'Prioridad', html`<select id="f_priority" name="priority">${Object.entries(PRIORITIES).map(([k, [l]]) => opt(k, l, preset.priority || 'media'))}</select>`)}
      ${f('assignee_id', 'Responsable', html`<select id="f_assignee_id" name="assignee_id"><option value="">Sin asignar</option>${staff.map((s) => opt(s.id, `${s.full_name || 'Sin nombre'} · ${s.role_name}`, ctx.session.user.id))}</select>`)}
      </div>${f('notes', 'Notas', html`<textarea id="f_notes" name="notes" rows="2"></textarea>`)}`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['title', 'due_date'])) return false;
      if (v.title.trim().length < 3) { fieldError(form.elements.title, 'Describe la tarea (mínimo 3 caracteres).'); return false; }
      await createTask(ctx.operatorId, v, entity);
      toast('Tarea creada', 'ok');
      return true;
    }
  });
}

/** Contacto de un prospecto o cliente */
export function contactDialog(ctx, parent, contact = null) {
  const c = contact || {};
  return formDialog({
    title: contact ? 'Editar contacto' : `Nuevo contacto${parent?.label ? ` · ${parent.label}` : ''}`,
    body: html`<div class="form-grid">
      ${f('full_name', 'Nombre *', text('full_name', c.full_name, 'required'))}
      ${f('role_title', 'Cargo', text('role_title', c.role_title, 'placeholder="Secretaria, administrador…"'))}
      ${f('whatsapp', 'WhatsApp', text('whatsapp', c.whatsapp, 'inputmode="tel"'))}
      ${f('phone', 'Teléfono', text('phone', c.phone, 'inputmode="tel"'))}
      ${f('email', 'Correo', text('email', c.email, 'type="email"'))}
      ${parent?.organizationId ? html`${f('contact_role', 'Rol', html`<select id="f_contact_role" name="contact_role">${Object.entries(CONTACT_ROLES).map(([k, l]) => opt(k, l, c.contact_role || 'otro'))}</select>`)}
      ${parent?.providers?.length ? f('provider_id', 'Médico al que asiste', html`<select id="f_provider_id" name="provider_id"><option value="">—</option>${parent.providers.map((p) => opt(p.id, p.full_name, c.provider_id))}</select>`) : ''}
      ${f('clinic_name', 'Clínica o consultorio', text('clinic_name', c.clinic_name, 'maxlength="120"'))}
      ${f('inducted_on', 'Fecha de inducción en SOFA', text('inducted_on', c.inducted_on, 'type="date"'), 'Secretaria: cuándo recibió la capacitación para registrar reclamaciones')}` : ''}
      </div><label class="check small"><input type="checkbox" name="is_primary" ${c.is_primary ? raw('checked') : ''}> Contacto principal</label>`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['full_name']) || !checkContactFields(form)) return false;
      await saveContact(ctx.operatorId, { ...v, lead_id: parent?.leadId, organization_id: parent?.organizationId }, contact?.id || null);
      toast('Contacto guardado', 'ok');
      return true;
    }
  });
}

/** Aliado referidor */
export function partnerDialog(ctx, p = null) {
  const x = p || { commission_rate: 10, partner_type: 'Contador', is_active: true };
  return formDialog({
    title: p ? 'Editar aliado' : 'Nuevo aliado referidor',
    body: html`<div class="form-grid">
      ${f('full_name', 'Nombre *', text('full_name', x.full_name, 'required'))}
      ${f('partner_type', 'Tipo', html`<select id="f_partner_type" name="partner_type">${PARTNER_TYPES.map((t) => opt(t, t, x.partner_type))}</select>`)}
      ${f('phone', 'Teléfono o WhatsApp', text('phone', x.phone, 'inputmode="tel"'))}
      ${f('commission_rate', 'Comisión (% del primer año)', text('commission_rate', x.commission_rate, 'type="number" min="0" max="50" step="0.5"'))}
      </div><label class="check small"><input type="checkbox" name="is_active" ${x.is_active ? raw('checked') : ''}> Activo</label>`,
    onSubmit: async (v, form) => {
      if (!requireFields(form, ['full_name'])) return false;
      await savePartner(ctx.operatorId, v, p?.id || null);
      toast('Aliado guardado', 'ok');
      return true;
    }
  });
}

export const stageOptions = (selected) => STAGES.map((s) => opt(s.code, s.label, selected));
export { stageLabel, money };

/** 1.5 · Interacción completa: canal, persona contactada, resultado, próximo paso y documentos enviados (A–E) */
export function interactionDialog(ctx, entity) {
  return formDialog({
    title: 'Registrar interacción', submitLabel: 'Registrar', wide: true,
    body: html`<div class="form-grid">
      <div class="field"><label for="i_type">Canal *</label><select id="i_type" name="type">${Object.entries(ACTIVITY_TYPES).filter(([k]) => k !== 'sistema').map(([k, l]) => opt(k, l, 'presencial'))}</select></div>
      <div class="field"><label for="i_who">Persona contactada</label><input id="i_who" name="who" maxlength="120"></div>
      <div class="field" style="grid-column:1/-1"><label for="i_body">Qué se habló *</label><textarea id="i_body" name="body" rows="3" class="input" maxlength="2000"></textarea></div>
      <div class="field" style="grid-column:1/-1"><label for="i_out">Resultado</label><input id="i_out" name="outcome" maxlength="300" placeholder="Interesado, pide propuesta, no por ahora…"></div>
      <div class="field"><label for="i_next">Próximo paso</label><input id="i_next" name="next" maxlength="200"></div>
      <div class="field"><label for="i_date">Fecha del próximo paso</label><input id="i_date" name="date" type="date"></div>
      <fieldset class="field" style="grid-column:1/-1;border:0;padding:0"><legend class="small" style="font-weight:600">Documentos enviados</legend>
        ${Object.entries(COMMERCIAL_DOCS).map(([k, l]) => html`<label class="check" style="display:inline-flex;margin-right:14px"><input type="checkbox" name="doc_${k}"> ${k} · ${l}</label>`)}</fieldset></div>`,
    onSubmit: async (d, form) => {
      if ((d.body || '').trim().length < 3) { fieldError(form.elements.body, 'Describe la interacción'); return false; }
      if (d.date && !(d.next || '').trim()) { fieldError(form.elements.next, 'Indica el próximo paso'); return false; }
      const docs = Object.keys(COMMERCIAL_DOCS).filter((k) => d[`doc_${k}`]);
      return addActivity(ctx.operatorId, entity, d.type, d.body.trim(), { outcome: d.outcome?.trim(), nextStep: d.next?.trim(), nextStepDate: d.date || null, contactPerson: d.who?.trim(), documentsSent: docs });
    }
  });
}
/** Detalle extra de una interacción para el historial */
export const activityExtra = (a) => [a.contact_person && `con ${a.contact_person}`, a.outcome && `Resultado: ${a.outcome}`,
  a.next_step && `Próximo paso: ${a.next_step}${a.next_step_date ? ` (${a.next_step_date.split('-').reverse().join('/')})` : ''}`,
  a.documents_sent?.length && `Documentos: ${a.documents_sent.join(', ')}`].filter(Boolean).join(' · ');
