/**
 * SOFA · Cámara y preparación de fotos de documentos (4.5.2).
 * - Abre la cámara trasera (getUserMedia); si no hay, el panel cae al <input type="file" capture>.
 * - Cada foto se redibuja en un canvas: máximo 1600 px, JPEG calidad 80. Al recodificar se pierden los metadatos
 *   (ubicación, modelo del teléfono, orientación EXIF); la orientación se aplica antes de recodificar.
 * - Huella SHA-256 para detectar fotos repetidas.
 * - Nada se guarda en la galería: las tomas viven solo en memoria hasta que se suben a Storage.
 * - Al cerrar se detienen todas las pistas de la cámara (se apaga la luz del dispositivo).
 */
import { sb } from '../supabase.js';
import { safeName } from './documents.js';

export const MAX_LADO = 1600;
export const CALIDAD = 0.8;
const BUCKET = 'claim-documents';

export const camaraEnVivoDisponible = () => !!(navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function') && window.isSecureContext !== false;

/** Abre la cámara trasera en un <video>. Devuelve {detener, foto()} */
export async function iniciarCamara(video) {
  if (!camaraEnVivoDisponible()) throw new Error('Este navegador no deja abrir la cámara (hace falta conexión segura). Usa «Tomar foto con el teléfono» o «Elegir imagen».');
  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
  } catch (err) {
    const n = err?.name || '';
    if (n === 'NotAllowedError' || n === 'SecurityError') throw new Error('SOFA no tiene permiso para usar la cámara. Permítelo en el candado de la barra de direcciones y vuelve a abrir, o usa «Elegir imagen».');
    if (n === 'NotFoundError' || n === 'OverconstrainedError') throw new Error('No se encontró una cámara en este equipo. Usa «Elegir imagen» con la foto o el archivo del escáner.');
    if (n === 'NotReadableError') throw new Error('La cámara está en uso por otra aplicación. Ciérrala y vuelve a intentar.');
    throw new Error('No se pudo abrir la cámara. Usa «Tomar foto con el teléfono» o «Elegir imagen».');
  }
  video.srcObject = stream; video.muted = true; video.setAttribute('playsinline', '');
  try { await video.play(); } catch { /* algunos navegadores arrancan solos */ }
  const detener = () => { stream.getTracks().forEach((t) => t.stop()); if (video.srcObject) video.srcObject = null; };
  const foto = () => {
    const w = video.videoWidth; const h = video.videoHeight;
    if (!w || !h) throw new Error('La cámara todavía no está lista. Espera un segundo y toca «Tomar foto» otra vez.');
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    c.getContext('2d').drawImage(video, 0, 0, w, h);
    return c;
  };
  return { detener, foto };
}

/** Convierte un File/Blob/canvas en un bitmap listo para dibujar, respetando la orientación del teléfono */
export async function aBitmap(fuente) {
  if (fuente instanceof HTMLCanvasElement) return fuente;
  if (typeof createImageBitmap === 'function') {
    try { return await createImageBitmap(fuente, { imageOrientation: 'from-image' }); } catch { /* cae al <img> */ }
  }
  const url = URL.createObjectURL(fuente);
  try {
    const img = new Image(); img.src = url; await img.decode();
    return img;
  } catch { throw new Error('No se pudo abrir la imagen. Toma la foto otra vez o elige un archivo JPG, PNG o WEBP.'); }
  finally { URL.revokeObjectURL(url); }
}
const dim = (b) => ({ w: b.naturalWidth || b.videoWidth || b.width, h: b.naturalHeight || b.videoHeight || b.height });

/**
 * Dibuja la imagen rotada (0/90/180/270) y recortada (fracciones 0..1 sobre la imagen ya rotada) en un canvas ≤ MAX_LADO.
 * @returns {HTMLCanvasElement}
 */
export function dibujar(bitmap, { rotacion = 0, recorte = null, maxLado = MAX_LADO } = {}) {
  const { w, h } = dim(bitmap);
  const rot = ((rotacion % 360) + 360) % 360;
  const rw = rot % 180 === 0 ? w : h; const rh = rot % 180 === 0 ? h : w;
  // 1) imagen rotada a tamaño completo
  const full = document.createElement('canvas'); full.width = rw; full.height = rh;
  const g = full.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, rw, rh);
  g.translate(rw / 2, rh / 2); g.rotate((rot * Math.PI) / 180); g.drawImage(bitmap, -w / 2, -h / 2); g.setTransform(1, 0, 0, 1, 0, 0);
  // 2) recorte
  const r = recorte || { x: 0, y: 0, w: 1, h: 1 };
  const sx = Math.round(Math.max(0, Math.min(0.9, r.x)) * rw); const sy = Math.round(Math.max(0, Math.min(0.9, r.y)) * rh);
  const sw = Math.max(16, Math.min(rw - sx, Math.round(r.w * rw))); const sh = Math.max(16, Math.min(rh - sy, Math.round(r.h * rh)));
  // 3) reducción
  const esc = Math.min(1, maxLado / Math.max(sw, sh));
  const out = document.createElement('canvas'); out.width = Math.max(1, Math.round(sw * esc)); out.height = Math.max(1, Math.round(sh * esc));
  const o = out.getContext('2d'); o.imageSmoothingQuality = 'high';
  o.drawImage(full, sx, sy, sw, sh, 0, 0, out.width, out.height);
  full.width = full.height = 0; // libera memoria
  return out;
}

/** Huella SHA-256 en hexadecimal minúsculas */
export async function sha256(blob) {
  if (!globalThis.crypto?.subtle) throw new Error('Este navegador no puede calcular la huella del documento (hace falta conexión segura). Abre SOFA desde su dirección https.');
  const buf = await blob.arrayBuffer();
  const h = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Canvas -> JPEG calidad 80 sin metadatos + huella. {blob, ancho, alto, sha256} */
export async function codificar(canvas) {
  const blob = await new Promise((res) => canvas.toBlob(res, 'image/jpeg', CALIDAD));
  if (!blob) throw new Error('No se pudo preparar la foto. Intenta de nuevo con una imagen más pequeña.');
  return { blob, ancho: canvas.width, alto: canvas.height, sha256: await sha256(blob) };
}

/** Atajo: fuente + ajustes -> foto lista para subir */
export async function procesarFoto(fuente, ajustes = {}) {
  const bmp = await aBitmap(fuente);
  const canvas = dibujar(bmp, ajustes);
  if (bmp.close) bmp.close();
  return { ...(await codificar(canvas)), canvas };
}

/**
 * Sube una página ya preparada: archivo a Storage (ruta org/reclamación/uuid-nombre) y luego la RPC register_captured_document.
 * Si la RPC rechaza el documento, borra el archivo recién subido.
 * @returns {Promise<string>} id del documento
 */
export async function subirCaptura({ orgId, submissionId, lineId = null, docType, blob, sha256: huella, origen = 'camara', nombre = 'documento', ocr = null }) {
  const fileName = `${safeName(nombre).replace(/\.jpe?g$/i, '')}.jpg`;
  const path = `${orgId}/${submissionId}/${crypto.randomUUID()}-${fileName}`;
  const up = await sb().storage.from(BUCKET).upload(path, blob, { contentType: 'image/jpeg', upsert: false, cacheControl: '3600' });
  if (up.error) throw up.error;
  const { data, error } = await sb().rpc('register_captured_document', {
    p_org: orgId, p_submission: submissionId, p_line: lineId, p_doc_type: docType, p_path: path, p_file_name: fileName,
    p_mime: 'image/jpeg', p_size: blob.size, p_sha256: huella, p_origin: origen, p_ocr: ocr && Object.keys(ocr).length ? ocr : null
  });
  if (error) { await sb().storage.from(BUCKET).remove([path]).catch(() => {}); throw error; }
  return data;
}

/** Confirma lo leído: campos = {campo: valorConfirmado} con TODOS los campos que traía la lectura */
export async function confirmarLectura(documentId, campos) {
  const { data, error } = await sb().rpc('confirm_document_ocr', { p_document: documentId, p_fields: campos });
  if (error) throw error;
  return data;
}
