/** SOFA · Conteos respetando RLS (cada rol ve cifras distintas) */
import { sb } from '../supabase.js';
export async function headCount(table, apply) {
  let q = sb().from(table).select('*', { count: 'exact', head: true });
  if (apply) q = apply(q);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}
