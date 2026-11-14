/** Consultas de solo lectura, limitadas a cliente y permisos bancarios actuales. */
import { sb } from '../supabase.js';
export async function bankWorkspaceClaims({ organizationId, paymentId = null, search = '' }) {
  const { data, error } = await sb().rpc('bank_workspace_claims', { p_org: organizationId, p_payment: paymentId, p_search: search.trim() || null });
  if (error) throw error;
  return data || [];
}
