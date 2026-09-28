/** SOFA · Clientes PSS (vista v_client_360: respeta RLS y no incluye honorarios) */
import { sb } from '../supabase.js';
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();
export async function listClients({ q = '', status = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_client_360')
    .select('organization_id, legal_name, status, started_on, submissions, submitted, radicado, pagado, glosado, saldo, tasa_pago, tasa_glosa, vencidas, codigos_pendientes', { count: 'exact' });
  const t = clean(q);
  if (t) query = query.ilike('legal_name', `%${t}%`);
  if (status) query = query.eq('status', status);
  const { data, error, count } = await query.order('legal_name').range(page * size, page * size + size - 1);
  if (error) throw error;
  return { data, count };
}
