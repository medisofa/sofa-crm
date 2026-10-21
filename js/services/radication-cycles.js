/** SOFA · Ciclos sugeridos de radicación */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };

export async function listCycleSuggestions({ providerId = '', arsId = '', period = '' } = {}) {
  let q = sb().from('v_claim_cycle_suggestions').select('*');
  if (providerId) q = q.eq('provider_id', providerId);
  if (arsId) q = q.eq('ars_id', arsId);
  if (period) q = q.eq('period', `${period}-01`);
  return must(await q.order('period', { ascending: false }).order('provider_name').order('ars_name'));
}

export async function listCycleClaims({ providerId, arsId, period }) {
  const from = period;
  const d = new Date(`${period}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + 1);
  const to = d.toISOString().slice(0, 10);
  const { data, error } = await sb().from('v_claims')
    .select('id,folio,service_date,patient_name,member_number,authorization_number,service_name,claimed,claim_status,status_name,dossier_ok,dossier_missing,contracted,amount_ok,next_step')
    .eq('provider_id', providerId)
    .eq('ars_id', arsId)
    .is('submission_id', null)
    .gte('service_date', from)
    .lt('service_date', to)
    .order('service_date')
    .order('folio');
  if (error) throw error;
  return data;
}

export async function createSubmissionFromClaims(ids, notes = null) {
  return must(await sb().rpc('create_submission_from_claims', { p_claims: ids, p_notes: notes }));
}
