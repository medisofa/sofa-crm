/** Corrección administrativa del identificador usado en la conciliación; no altera pagos. */
import { sb } from '../supabase.js';
export async function adminSetClaimAuthorization({ lineId, number, reason, expectedNumber }) {
  const { data, error } = await sb().rpc('admin_set_claim_authorization', {
    p_line: lineId, p_number: number, p_reason: reason, p_expected_number: expectedNumber ?? null
  });
  if (error) throw error;
  return data;
}

/** Últimas cien correcciones administrativas del caso; acceso verificado en el servidor. */
export async function listClaimAuthorizationHistory(lineId) {
  const { data, error } = await sb().rpc('claim_authorization_history', { p_line: lineId });
  if (error) throw error;
  return data || [];
}
