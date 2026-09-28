/**
 * SOFA · Expediente digital en Supabase Storage (bucket privado).
 * Ruta obligatoria: {organization_id}/{submission_id}/{uuid}-{archivo}
 * Los archivos se abren con URLs firmadas de 5 minutos; nunca con enlaces públicos.
 */
import { sb } from '../supabase.js';
const BUCKET = 'claim-documents';
export const ALLOWED_TYPES = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
export const MAX_BYTES = 10 * 1024 * 1024;
const must = ({ data, error }) => { if (error) throw error; return data; };

export function safeName(name) {
  const base = String(name || 'documento').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  return base.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '').slice(-80) || 'documento';
}

/** Reduce fotos grandes del teléfono (máx. 1800 px, JPEG 82%) antes de subirlas */
export async function compressImage(file) {
  if (!/^image\/(jpeg|png|webp)$/.test(file.type) || file.size <= 1.5 * 1024 * 1024) return file;
  try {
    const bmp = await createImageBitmap(file);
    const scale = Math.min(1, 1800 / Math.max(bmp.width, bmp.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bmp.width * scale); canvas.height = Math.round(bmp.height * scale);
    canvas.getContext('2d').drawImage(bmp, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((res) => canvas.toBlob(res, 'image/jpeg', 0.82));
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], file.name.replace(/\.(png|webp|jpe?g)$/i, '') + '.jpg', { type: 'image/jpeg' });
  } catch { return file; }
}

/** Revisa tipo y tamaño; devuelve el texto del problema o null */
export function fileProblem(file) {
  if (!file) return 'Selecciona un archivo.';
  if (!ALLOWED_TYPES.includes(file.type)) return 'Solo se aceptan PDF, JPG, PNG o WEBP.';
  if (file.size > MAX_BYTES) return 'El archivo supera 10 MB.';
  return null;
}

export async function uploadDocument({ orgId, submissionId, lineId = null, docType = null, file }) {
  const ready = await compressImage(file);
  const prob = fileProblem(ready); if (prob) throw new Error(prob);
  const path = `${orgId}/${submissionId}/${crypto.randomUUID()}-${safeName(ready.name)}`;
  const up = await sb().storage.from(BUCKET).upload(path, ready, { contentType: ready.type, upsert: false, cacheControl: '3600' });
  if (up.error) throw up.error;
  const { data, error } = await sb().from('documents').insert({
    organization_id: orgId, entity_type: 'submission', entity_id: submissionId, service_line_id: lineId || null,
    document_type_code: docType || null, bucket: BUCKET, storage_path: path, file_name: ready.name, mime_type: ready.type, size_bytes: ready.size
  }).select('id').single();
  if (error) { await sb().storage.from(BUCKET).remove([path]).catch(() => {}); throw error; }
  return data;
}

export async function listDocuments({ submissionId = null, type = '', limit = 200 } = {}) {
  let q = sb().from('documents').select('id, organization_id, entity_type, entity_id, service_line_id, document_type_code, storage_path, file_name, mime_type, size_bytes, uploaded_at, uploaded_by, document_types(name)');
  if (submissionId) q = q.eq('entity_type', 'submission').eq('entity_id', submissionId);
  if (type) q = q.eq('document_type_code', type);
  return must(await q.order('uploaded_at', { ascending: false }).limit(limit));
}

/** Abre el documento con una URL firmada de 5 minutos */
export async function openDocument(doc) {
  const win = window.open('', '_blank');
  const { data, error } = await sb().storage.from(BUCKET).createSignedUrl(doc.storage_path, 300);
  if (error || !data?.signedUrl) { win?.close(); throw error || new Error('No se pudo generar el enlace del documento.'); }
  if (win) { win.opener = null; win.location.href = data.signedUrl; return null; }
  return data.signedUrl; // el navegador bloqueó la ventana: se muestra el enlace
}

export async function deleteDocument(doc) {
  const { error } = await sb().from('documents').delete().eq('id', doc.id);
  if (error) throw error;
  await sb().storage.from(BUCKET).remove([doc.storage_path]).catch(() => {});
}
export const sizeLabel = (b) => (b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`);
