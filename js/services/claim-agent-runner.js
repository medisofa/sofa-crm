/**
 * SOFA: puente de lectura para la preauditoría administrativa.
 * No guarda auditorías, no envía a ARS y no llama a proveedores de IA.
 */
import { sb } from '../supabase.js';
import { claimDuplicateCandidates } from './claims.js';
import { preauditClaim } from './claim-audit-agents.js';

export async function runClaimPreaudit(claim) {
  if (!claim?.id || !claim.organization_id) throw new Error('Reclamación u organización no identificada');
  // is_demo se obtiene de Supabase con RLS, jamás de un valor suministrado por UI.
  const { data: org, error: orgError } = await sb().from('organizations')
    .select('id, is_demo').eq('id', claim.organization_id).maybeSingle();
  if (orgError) throw orgError;
  if (!org || typeof org.is_demo !== 'boolean') {
    throw new Error('No se pudo comprobar el tipo de organización. Preauditoría detenida.');
  }
  const candidates = await claimDuplicateCandidates([claim.id]);
  if (!Array.isArray(candidates)) throw new Error('No se obtuvo el resultado del detector de duplicados');
  return preauditClaim({
    ...claim,
    amount: claim.claimed,
    authorization_date: claim.authorization_date || null,
  }, {
    isDemo: org.is_demo,
    duplicateCandidates: candidates,
    arsCoverage: null, // Una consulta al catálogo/ARS nunca se debe presumir.
  });
}
