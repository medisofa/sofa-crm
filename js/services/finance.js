/** SOFA · Glosas, pagos de ARS y honorarios de SOFA */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const withCount = ({ data, error, count }) => { if (error) throw error; return { data, count: count ?? data.length }; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();

export const GLOSA_OPEN = ['pendiente', 'analizada', 'apelada', 'en_revision'];

// ---- Glosas
export async function listGlosas({ group = 'abiertas', arsId = '', q = '', submissionId = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_glosas').select('*', { count: 'exact' });
  if (group === 'abiertas') query = query.in('status', GLOSA_OPEN);
  if (group === 'resueltas') query = query.not('status', 'in', `(${GLOSA_OPEN.join(',')})`);
  if (arsId) query = query.eq('ars_id', arsId);
  if (submissionId) query = query.eq('submission_id', submissionId);
  const t = clean(q); if (t) query = query.or(`folio.ilike.%${t}%,provider_name.ilike.%${t}%,client_name.ilike.%${t}%,ars_reference.ilike.%${t}%`);
  return withCount(await query.order('appeal_deadline', { ascending: group === 'abiertas' }).range(page * size, page * size + size - 1));
}
export async function glosaSummary() { return must(await sb().from('v_glosas').select('status, amount, accepted, recovered, in_dispute, days_left').limit(5000)); }
export async function glosaPareto() { return must(await sb().from('v_glosa_pareto').select('*').limit(5000)); }
export async function arsReconciliation() { return must(await sb().from('v_ars_reconciliation').select('*').limit(5000)); }
export async function getGlosa(id) { return must(await sb().from('v_glosas').select('*').eq('id', id).maybeSingle()); }
export async function glosaItems(id) {
  return must(await sb().from('glosa_items').select('id, service_line_id, reason_code, amount, accepted_amount, recovered_amount, notes, glosa_reasons(name, category), service_lines(patient_name, service_date, member_number, procedures(description))').eq('glosa_id', id));
}
export async function glosaAppeals(id) { return must(await sb().from('glosa_appeals').select('*').eq('glosa_id', id).order('submitted_on', { ascending: false })); }
export async function glosaHistory(id) { return must(await sb().from('glosa_status_history').select('*').eq('glosa_id', id).order('changed_at', { ascending: false })); }
export async function glosaReasons() { return must(await sb().from('glosa_reasons').select('code, name, category').eq('is_active', true).order('name')); }
export async function glosadoByLine(lineIds) {
  if (!lineIds.length) return {};
  const rows = must(await sb().from('glosa_items').select('service_line_id, amount').in('service_line_id', lineIds));
  return rows.reduce((m, r) => { m[r.service_line_id] = (m[r.service_line_id] || 0) + Number(r.amount); return m; }, {});
}
export async function registerGlosa(submissionId, notifiedOn, items, arsReference, notes) {
  return must(await sb().rpc('register_glosa', { p_submission: submissionId, p_notified_on: notifiedOn, p_items: items, p_ars_reference: arsReference || null, p_notes: notes || null }));
}
export async function changeGlosaStatus(id, to, comment = null) { return must(await sb().rpc('change_glosa_status', { p_glosa: id, p_to: to, p_comment: comment })); }
export async function appealGlosa(id, argument, submittedOn) { return must(await sb().rpc('appeal_glosa', { p_glosa: id, p_argument: argument, p_submitted_on: submittedOn })); }
export async function resolveGlosa(id, items, comment = null) { return must(await sb().rpc('resolve_glosa', { p_glosa: id, p_items: items, p_comment: comment })); }

// ---- Pagos de ARS
export async function listPayments({ arsId = '', orgId = '', q = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_payments').select('*', { count: 'exact' });
  if (arsId) query = query.eq('ars_id', arsId);
  if (orgId) query = query.eq('organization_id', orgId);
  const t = clean(q); if (t) query = query.or(`reference.ilike.%${t}%,client_name.ilike.%${t}%,folios.ilike.%${t}%`);
  return withCount(await query.order('paid_on', { ascending: false }).order('created_at', { ascending: false }).range(page * size, page * size + size - 1));
}
export async function openSubmissions(orgId, arsId) {
  return must(await sb().from('v_submissions').select('id, folio, provider_name, period, submitted_on, claimed, paid, glosa_accepted, glosa_in_dispute, balance, payment_deadline')
    .eq('organization_id', orgId).eq('ars_id', arsId).in('status', ['radicada', 'en_auditoria_ars']).gt('balance', 0).order('submitted_on'));
}
export async function clientsWithOpenBalance() {
  const rows = must(await sb().from('v_submissions').select('organization_id, client_name, ars_id, ars_name, balance').in('status', ['radicada', 'en_auditoria_ars']).gt('balance', 0).limit(5000));
  return rows;
}
export async function registerPayment({ orgId, arsId, paidOn, amount, method, reference, allocations, notes }) {
  return must(await sb().rpc('register_payment', { p_org: orgId, p_ars: arsId, p_paid_on: paidOn, p_amount: amount, p_method: method, p_reference: reference, p_allocations: allocations, p_notes: notes || null }));
}
export async function voidPayment(id) { const { error, count } = await sb().from('payments').delete({ count: 'exact' }).eq('id', id); if (error) throw error; if (!count) throw new Error('No tienes permiso para anular pagos (solo Super Admin).'); }
export async function submissionPayments(submissionId) {
  return must(await sb().from('payment_allocations').select('id, amount, payments(id, paid_on, reference, method)').eq('submission_id', submissionId));
}

// ---- Honorarios SOFA
export async function feeSummary() { return must(await sb().from('v_fee_summary').select('*').order('client_name')); }
export async function listInvoices({ status = '', page = 0, size = 25 } = {}) {
  let q = sb().from('v_sofa_invoices').select('*', { count: 'exact' });
  if (status === 'pendientes') q = q.in('status', ['emitida', 'pagada_parcial']);
  if (status === 'pagadas') q = q.eq('status', 'pagada');
  if (status === 'anuladas') q = q.eq('status', 'anulada');
  return withCount(await q.order('issued_on', { ascending: false }).range(page * size, page * size + size - 1));
}
export async function listFees(limit = 100) {
  return must(await sb().from('sofa_fees').select('id, organization_id, source_type, period, base_amount, rate, amount, calculated_at, sofa_invoice_id, organizations(legal_name), sofa_invoices(folio)').order('calculated_at', { ascending: false }).limit(limit));
}
export async function generateMonthlyFees(period) { return must(await sb().rpc('generate_monthly_fees', { p_period: period })); }
export async function generateInvoices(period, dueDays = 15) { return must(await sb().rpc('generate_sofa_invoices', { p_period: period, p_due_days: dueDays })); }
export async function recordInvoicePayment(inv, { paidOn, amount, method, reference }) {
  return must(await sb().from('sofa_invoice_payments').insert({ sofa_invoice_id: inv.id, organization_id: inv.organization_id, paid_on: paidOn, amount, method, reference: reference || null }).select('id').single());
}
/** 1.5: valida formato, que no se repita y el vencimiento de la secuencia (public.set_sofa_invoice_ncf) */
export async function setInvoiceNcf(id, ncf, validUntil = null) { must(await sb().rpc('set_sofa_invoice_ncf', { p_invoice: id, p_ncf: ncf, p_valid_until: validUntil || null })); return true; }   // la función no devuelve datos: el diálogo necesita una confirmación
export async function setInvoiceNcfLegacy(id, ncf) { return must(await sb().from('sofa_invoices').update({ ncf }).eq('id', id).select('id').single()); }
export async function voidInvoice(id, reason) { return must(await sb().rpc('void_sofa_invoice', { p_invoice: id, p_reason: reason })); }

/** 1.4.1 · Documento completo de una factura de honorarios (emisor, cliente, conceptos, cobros) */
export async function invoiceDocument(id) { return must(await sb().rpc('sofa_invoice_document', { p_invoice: id })); }
/** Datos fiscales de SOFA (operador) y su edición (solo Super Admin) */
export async function operatorProfile() { return must(await sb().rpc('operator_profile')); }
export async function updateOperatorProfile(v) {
  return must(await sb().rpc('update_operator_profile', { p_legal_name: v.legal_name, p_trade_name: v.trade_name || null, p_tax_id: v.tax_id || null,
    p_address: v.address || null, p_city: v.city || null, p_phone: v.phone || null, p_email: v.email || null,
    p_bank_name: v.bank_name || null, p_bank_account_type: v.bank_account_type || null, p_bank_account: v.bank_account || null, p_bank_holder: v.bank_holder || null, p_terms: v.terms || null }));
}
