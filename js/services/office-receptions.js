/** Lotes recibidos en oficina: no crean reclamaciones ni cuentas por cobrar. */
import { sb } from '../supabase.js';
import { compressImage, fileProblem, safeName } from './documents.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const HEADER = 'id,organization_id,provider_id,folio,received_on,service_period,delivered_by,received_by_label,notes,status,cancelled_reason,created_at,organizations(legal_name),providers(full_name),office_reception_lines(id,ars_id,service_label,declared_count,declared_amount,ars(name))';
export const officeReceptionRoles = ['super_admin', 'admin', 'operations', 'billing', 'assistant'];
export async function receptionClients() {
  return must(await sb().from('sofa_real_client_organizations').select('id,legal_name').order('legal_name')) || [];
}
export async function listOfficeReceptions({ org = '', page = 0 } = {}) {
  let q = sb().from('office_receptions').select(HEADER, { count: 'exact' });
  if (org) q = q.eq('organization_id', org);
  const r = await q.order('created_at', { ascending: false }).order('id').range(page * 25, page * 25 + 24);
  must(r); return { data: r.data || [], count: r.count || 0 };
}
export async function getOfficeReception(id) {
  const header = must(await sb().from('office_receptions').select(HEADER).eq('id', id).single());
  const ids = header.office_reception_lines.map(l => l.id);
  const links = ids.length ? must(await sb().from('office_reception_claims').select('service_line_id,reception_line_id,linked_at,service_lines(claim_folio,patient_name,service_name_snapshot,amount,claim_status)').in('reception_line_id', ids)) : [];
  return { ...header, links: links || [] };
}
export const createOfficeReception = (id, payload) => sb().rpc('office_reception_create', { p_id: id, p_payload: payload }).then(must);
export const assignOfficeClaim = (item, claim, remove = false) => sb().rpc('office_reception_assign', { p_item: item, p_claim: claim, p_remove: remove }).then(must);
export const cancelOfficeReception = (id, reason) => sb().rpc('office_reception_cancel', { p_id: id, p_reason: reason }).then(must);
export async function receptionCandidates(header, item, search = '', page = 0) {
  let q = sb().from('v_claims').select('id,folio,patient_name,service_name,claimed,service_date', { count: 'exact' })
    .eq('organization_id', header.organization_id).eq('ars_id', item.ars_id);
  if (header.provider_id) q = q.eq('provider_id', header.provider_id);
  const clean = search.replace(/[%*,()\\]/g, ' ').trim();
  if (clean) q = q.or(`folio.ilike.%${clean}%,patient_name.ilike.%${clean}%,member_number.ilike.%${clean}%`);
  const r = await q.order('service_date', { ascending: false }).order('id').range(page * 25, page * 25 + 24);
  must(r); return { data: r.data || [], count: r.count || 0 };
}
const bucket = () => sb().storage.from('office-receptions');
export async function uploadReceptionFile(header, file) {
  const ready = await compressImage(file); const problem = fileProblem(ready);
  if (problem) throw new Error(problem);
  const path = `${header.organization_id}/${header.id}/${crypto.randomUUID()}-${safeName(ready.name)}`;
  must(await bucket().upload(path, ready, { contentType: ready.type, upsert: false }));
}
export async function receptionFiles(header) {
  return must(await bucket().list(`${header.organization_id}/${header.id}`, { limit: 100, sortBy: { column: 'created_at', order: 'desc' } })) || [];
}
export async function receptionFileUrl(header, name) {
  const d = must(await bucket().createSignedUrl(`${header.organization_id}/${header.id}/${name}`, 300));
  return d.signedUrl;
}
