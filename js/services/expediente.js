/** SOFA · 5.2 · I62 · Servicio del expediente digital por reclamación.
 *  Solo llama funciones de la base (RPC) y sube archivos al bucket claim-documents; nunca escribe tablas directo.
 *  La foto y la subida con cámara reutilizan js/services/camera.js y la RPC register_captured_document (172). */
import { rpc, supabase } from './iter18.js';
import { procesarFoto, subirCaptura, sha256 } from './camera.js';
import { safeName } from './documents.js';

const BUCKET = 'claim-documents';
export const MAX_BYTES = 10 * 1024 * 1024;

export const SEMAFORO = {
  completo: { texto: 'Completo', clase: 'st-ok', icono: '●' },
  parcial: { texto: 'Parcial', clase: 'st-req', icono: '◐' },
  vacio: { texto: 'Vacío', clase: 'st-bad', icono: '○' }
};
export const ESTADO_ESPACIO = {
  sin_limite: { texto: 'Sin límite', clase: 'st-none' },
  ok: { texto: 'En orden', clase: 'st-ok' },
  aviso: { texto: 'Cerca del límite', clase: 'st-req' },
  excedido: { texto: 'Pasó el límite', clase: 'st-bad' }
};
export const EXIGENCIA = { obligatorio: 'Obligatorio', opcional: 'Opcional', no_requerido: 'No se pide' };
export const MODALIDAD = { '': 'Todas las modalidades', ambulatorio: 'Ambulatorio', emergencia: 'Emergencia', internamiento: 'Internamiento' };

export const listarExpedientes = (org, { submission = null, semaforo = null, limit = 50, offset = 0 } = {}) =>
  rpc('dossier_list', { p_org: org || null, p_submission: submission, p_semaforo: semaforo, p_limit: limit, p_offset: offset });
export const detalleExpediente = (line) => rpc('dossier_detail', { p_line: line });
export const indicadorExpediente = (org, desde = null, hasta = null) => rpc('dossier_indicator', { p_org: org || null, p_from: desde, p_to: hasta });
export const parametros = (org = null) => rpc('dossier_params_get', { p_org: org || null });
export const guardarParametros = (p) => rpc('dossier_params_set', { p_block: p.bloqueo, p_retention_years: p.anios, p_default_limit_mb: p.limiteMb, p_warn_pct: p.aviso, p_target_pct: p.meta });
export const reglasDeArs = (ars) => rpc('dossier_rules_for_ars', { p_ars: ars });
export const guardarRegla = (ars, tipo, exigencia, modalidad = null) => rpc('dossier_rule_set', { p_ars: ars, p_doc_type: tipo, p_requirement: exigencia, p_care_mode: modalidad || null });
export const reporteEspacio = () => rpc('storage_usage_report');
export const espacioDeCliente = (org) => rpc('storage_usage_org', { p_org: org });
export const fijarLimiteCliente = (org, mb, nota = null) => rpc('client_storage_limit_set', { p_org: org, p_limit_mb: mb, p_note: nota });
export const pedirExcepcion = (lineas, motivo) => rpc('authorize_dossier_exception', { p_lines: lineas, p_reason: motivo });

/** ARS activas para elegir al configurar documentos requeridos */
export async function listarArs() {
  const { data, error } = await supabase.from('ars').select('id, name').eq('is_active', true).order('name');
  if (error) throw new Error(error.message || 'No se pudo leer la lista de ARS. Intente de nuevo.');
  return data || [];
}

/** Lista de radicaciones de un cliente para filtrar el expediente (solo lectura con RLS) */
export async function listarRadicaciones(org) {
  const { data, error } = await supabase.from('submissions').select('id, folio, period').eq('organization_id', org).order('period', { ascending: false }).limit(60);
  if (error) throw new Error(error.message || 'No se pudo leer la lista de radicaciones. Intente de nuevo.');
  return data || [];
}

/** Sube un archivo del expediente: foto (se reduce y limpia en el dispositivo) o PDF. Siempre pasa por register_captured_document. */
export async function subirDocumento({ orgId, submissionId, lineId, docType, file, origen = 'archivo' }) {
  if (!file) throw new Error('Elija una foto o un archivo PDF.');
  const esImagen = /^image\/(jpeg|png|webp)$/.test(file.type);
  const esPdf = file.type === 'application/pdf';
  if (!esImagen && !esPdf) throw new Error('Solo se aceptan fotos (JPG, PNG, WEBP) o archivos PDF. Elija otro archivo.');
  if (esImagen) {
    const f = await procesarFoto(file);
    return subirCaptura({ orgId, submissionId, lineId, docType, blob: f.blob, sha256: f.sha256, origen, nombre: file.name || 'foto' });
  }
  if (file.size > MAX_BYTES) throw new Error('El PDF pesa más de 10 MB. Reduzca su tamaño o divídalo en partes y súbalo otra vez.');
  const huella = await sha256(file);
  const nombre = safeName(file.name || 'documento.pdf');
  const path = `${orgId}/${submissionId}/${crypto.randomUUID()}-${nombre}`;
  const up = await supabase.storage.from(BUCKET).upload(path, file, { contentType: 'application/pdf', upsert: false, cacheControl: '3600' });
  if (up.error) throw new Error(up.error.message || 'No se pudo subir el archivo. Revise su conexión e intente de nuevo.');
  const { data, error } = await supabase.rpc('register_captured_document', {
    p_org: orgId, p_submission: submissionId, p_line: lineId, p_doc_type: docType, p_path: path, p_file_name: nombre,
    p_mime: 'application/pdf', p_size: file.size, p_sha256: huella, p_origin: origen, p_ocr: null
  });
  if (error) { await supabase.storage.from(BUCKET).remove([path]).catch(() => {}); throw new Error(error.message || 'No se pudo registrar el documento. Intente de nuevo.'); }
  return data;
}
