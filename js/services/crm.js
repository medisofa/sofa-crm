/** SOFA · CRM: prospectos, oportunidades, diagnósticos, actividades, contactos y aliados */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

// ---- Oportunidades
export async function listOpportunities({ q = '', owner = '', service = '', includeClosed = false, organizationId = null } = {}) {
  let query = sb().from('v_opportunities').select('*');
  if (!includeClosed) query = query.not('stage', 'in', '(cliente,perdido)');
  if (q) query = query.ilike('company', `%${clean(q)}%`);
  if (owner) query = query.eq('owner_id', owner);
  if (service) query = query.eq('service_code', service);
  if (organizationId) query = query.eq('organization_id', organizationId);
  return must(await query.order('next_action_date', { ascending: true, nullsFirst: false }).limit(500));
}
export async function getOpportunity(id) { return must(await sb().from('v_opportunities').select('*').eq('id', id).maybeSingle()); }
export async function updateOpportunity(id, values) { return must(await sb().from('opportunities').update(values).eq('id', id).select('id, stage, probability').single()); }
export async function createOpportunityForClient(operatorId, organizationId, v) {
  return must(await sb().from('opportunities').insert({ operator_id: operatorId, organization_id: organizationId, service_code: v.service_code,
    estimated_value: Number(v.estimated_value || 0), next_action: v.next_action || null, next_action_date: v.next_action_date || null }).select('id').single());
}
export async function newProspect(v) {
  return must(await sb().rpc('crm_new_prospect', {
    p_company: v.company, p_service_code: v.service_code, p_contact_name: v.contact_name || null, p_phone: v.phone || null,
    p_whatsapp: v.whatsapp || null, p_email: v.email || null, p_specialty: v.specialty || null, p_source: v.source || 'Otro',
    p_referral_partner: v.referral_partner_id || null, p_estimated_value: Number(v.estimated_value || 0),
    p_next_action: v.next_action || null, p_next_action_date: v.next_action_date || null, p_notes: v.notes || null }));
}
export async function findDuplicates(company, whatsapp, email) {
  return must(await sb().rpc('crm_find_duplicates', { p_company: company || '', p_whatsapp: whatsapp || null, p_email: email || null }));
}
export async function convertOpportunity(id, v) {
  return must(await sb().rpc('convert_opportunity', { p_opportunity: id, p_legal_name: v.legal_name || null, p_tax_id: v.tax_id || null,
    p_org_type: v.org_type, p_monthly_fee: Number(v.monthly_fee || 0), p_success_pct: Number(v.success_pct || 0), p_start: v.start || null }));
}

// ---- Prospectos
export async function listLeads({ q = '', source = '' } = {}) {
  let query = sb().from('leads').select('id, company, contact_name, whatsapp, phone, email, specialty, source, created_at, converted_org_id, referral_partners(full_name), opportunities(id, stage, service_code, estimated_value, updated_at)');
  if (q) query = query.or(`company.ilike.%${clean(q)}%,contact_name.ilike.%${clean(q)}%`);
  if (source) query = query.eq('source', source);
  return must(await query.order('created_at', { ascending: false }).limit(300));
}
export async function updateLead(id, values) { return must(await sb().from('leads').update(values).eq('id', id).select('id').single()); }

// ---- Diagnóstico de fugas
export async function listDiagnostics({ leadId, organizationId }) {
  let q = sb().from('leak_diagnostics').select('*').order('created_at', { ascending: false }).limit(5);
  q = leadId ? q.eq('lead_id', leadId) : q.eq('organization_id', organizationId);
  return must(await q);
}
export async function addDiagnostic(operatorId, { leadId, organizationId }, v) {
  return must(await sb().from('leak_diagnostics').insert({ operator_id: operatorId, lead_id: leadId || null, organization_id: leadId ? null : organizationId,
    monthly_billing: Number(v.monthly_billing), glosa_pct: Number(v.glosa_pct), recoverable_pct: Number(v.recoverable_pct), dso_days: Number(v.dso_days) }).select('*').single());
}

// ---- Actividades
export async function listActivities({ entityType, entityId, organizationId }) {
  let q = sb().from('activities').select('id, entity_type, entity_id, activity_type, body, occurred_at, created_by').order('occurred_at', { ascending: false }).limit(100);
  q = organizationId ? q.eq('organization_id', organizationId) : q.eq('entity_type', entityType).eq('entity_id', entityId);
  return must(await q);
}
export async function addActivity(operatorId, { entityType, entityId, organizationId = null }, type, body) {
  return must(await sb().from('activities').insert({ operator_id: operatorId, organization_id: organizationId, entity_type: entityType, entity_id: entityId, activity_type: type, body }).select('id').single());
}

// ---- Contactos
export async function listContacts({ q = '', leadId = null, organizationId = null } = {}) {
  let query = sb().from('contacts').select('id, full_name, role_title, phone, whatsapp, email, is_primary, lead_id, organization_id, leads(company), organizations!contacts_organization_id_fkey(legal_name)');
  if (leadId) query = query.eq('lead_id', leadId);
  if (organizationId) query = query.eq('organization_id', organizationId);
  if (q) query = query.ilike('full_name', `%${clean(q)}%`);
  return must(await query.order('is_primary', { ascending: false }).order('full_name').limit(300));
}
export async function saveContact(operatorId, v, id = null) {
  const row = { full_name: v.full_name.trim(), role_title: v.role_title || null, phone: v.phone || null, whatsapp: v.whatsapp ? v.whatsapp.replace(/\D/g, '') : null,
    email: v.email ? v.email.trim().toLowerCase() : null, is_primary: !!v.is_primary };
  if (id) return must(await sb().from('contacts').update(row).eq('id', id).select('id').single());
  return must(await sb().from('contacts').insert({ ...row, operator_id: operatorId, lead_id: v.lead_id || null, organization_id: v.lead_id ? null : (v.organization_id || null) }).select('id').single());
}
export async function deleteContact(id) { const { error } = await sb().from('contacts').delete().eq('id', id); if (error) throw error; }

// ---- Aliados referidores
export async function listPartners() { return must(await sb().from('v_referral_stats').select('*').order('full_name')); }
export async function activePartners() { return must(await sb().from('referral_partners').select('id, full_name').eq('is_active', true).order('full_name')); }
export async function savePartner(operatorId, v, id = null) {
  const row = { full_name: v.full_name.trim(), partner_type: v.partner_type, phone: v.phone || null, commission_rate: Number(v.commission_rate || 0), is_active: v.is_active !== false };
  if (id) return must(await sb().from('referral_partners').update(row).eq('id', id).select('id').single());
  return must(await sb().from('referral_partners').insert({ ...row, operator_id: operatorId }).select('id').single());
}

// ---- Personal (responsables)
export async function listStaff() { return must(await sb().from('v_staff').select('id, full_name, role_name').order('full_name')); }
