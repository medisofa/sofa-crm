/** SOFA · 29/10/2026 · Puesta al día: captura masiva o manual de reclamaciones que ya ocurrieron
 *  fuera de SOFA (Excel, papel, WhatsApp, o ya capturadas pero mal). Reutiliza capture_claim_dx
 *  (misma calidad de dato y bloqueo de duplicados que el resto de SOFA) — no inventa un motor nuevo.
 *  La Radicación exige NCF y factura fiscal reales (change_submission_status); este flujo NO la
 *  fuerza: agrupa las reclamaciones por su lote automático y lleva al usuario a radicarlo de verdad. */
import { sb } from '../supabase.js';

const must = ({ data, error }) => { if (error) throw error; return data; };

export async function findDuplicateClaim({ providerId, memberNumber, serviceDate, authorization }) {
  let q = sb().from('v_claims').select('id, folio, patient_name, service_date, claim_status, submission_id, submission_folio')
    .eq('provider_id', providerId).neq('claim_status', 'cerrada').limit(5);
  if (authorization) q = q.or(`member_number.eq.${memberNumber},authorization_number.eq.${authorization}`);
  else q = q.eq('member_number', memberNumber);
  const rows = must(await q);
  return rows.find((r) => r.service_date === serviceDate) || rows[0] || null;
}

export async function pendingSubmissionsSummary(batchSubmissionIds) {
  if (!batchSubmissionIds.length) return [];
  return must(await sb().from('v_submissions').select('id, folio, status, status_name, provider_name, ars_name, period, lines, claimed')
    .in('id', [...new Set(batchSubmissionIds)]));
}
