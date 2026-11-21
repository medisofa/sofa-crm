/**
 * SOFA · Catálogo de especialidades (migración 262). Lectura para cualquier usuario autenticado; nadie lo
 * modifica desde la aplicación. `template_code` es la plantilla de historia clínica que abre por defecto.
 */
import { sb } from '../supabase.js';

const must = ({ data, error }) => { if (error) throw error; return data; };

let cache = null;
/** @returns {Promise<{code:string, name:string, template_code:string|null}[]>} */
export async function listSpecialties() {
  if (!cache) cache = must(await sb().from('specialties').select('code, name, template_code').order('sort_order'));
  return cache;
}
