/** SOFA · ARS Portal Bridge (5.40.0)
 * Funciones para abrir el portal PSS de una ARS y copiar los datos del paciente
 * al portapapeles con un solo clic desde la pantalla de captura.
 */
import { ARS_PORTAL_DEFAULTS } from '../config/ars-portals.js';

/**
 * Resuelve la URL del portal PSS para una ARS.
 * Prioridad: portal_url de BD → ARS_PORTAL_DEFAULTS → null
 * @param {{ code?: string, portal_url?: string }} ars
 * @returns {string|null}
 */
export function resolvePortalUrl(ars) {
  if (ars?.portal_url) return ars.portal_url;
  if (ars?.code && ARS_PORTAL_DEFAULTS[ars.code]) return ARS_PORTAL_DEFAULTS[ars.code];
  return null;
}

/**
 * Construye el payload de texto plano con los datos relevantes del claim.
 * Los campos vacíos se omiten.
 * @param {{ name: string }} ars
 * @param {{ member?: string, patientDoc?: string, patientName?: string, serviceDate?: string, diagnosis?: string, procedureName?: string, simon?: string, cups?: string }} claim
 * @returns {string}
 */
export function buildPortalPayload(ars, claim = {}) {
  const lines = [`ARS: ${ars?.name || ''}`];
  if (claim.member)        lines.push(`NSS: ${claim.member}`);
  if (claim.patientDoc)    lines.push(`Cédula: ${claim.patientDoc}`);
  if (claim.patientName)   lines.push(`Paciente: ${claim.patientName}`);
  if (claim.serviceDate)   lines.push(`Fecha: ${claim.serviceDate}`);
  if (claim.diagnosis)     lines.push(`Diagnóstico CIE-10: ${claim.diagnosis}`);
  if (claim.procedureName) lines.push(`Servicio: ${claim.procedureName}`);
  if (claim.simon)         lines.push(`SIMON: ${claim.simon}`);
  if (claim.cups)          lines.push(`CUPS: ${claim.cups}`);
  return lines.join('\n');
}

/**
 * Copia texto al portapapeles.
 * Intenta navigator.clipboard primero; si rechaza, usa execCommand como fallback.
 * @param {string} text
 * @returns {Promise<void>}
 */
async function copyToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    try { await navigator.clipboard.writeText(text); return; } catch (_) { /* fallback */ }
  }
  // Fallback: textarea temporal fuera de pantalla
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); } finally { document.body.removeChild(ta); }
}

/**
 * Lanza el portal PSS de la ARS:
 * 1. Copia el payload al portapapeles.
 * 2. Abre el portal en una nueva pestaña.
 * 3. Muestra un toast de confirmación (o de error si el popup está bloqueado).
 *
 * @param {{ name: string, code?: string, portal_url?: string }} ars
 * @param {{ member?: string, patientDoc?: string, patientName?: string, serviceDate?: string, diagnosis?: string, procedureName?: string, simon?: string, cups?: string }} claim
 * @returns {Promise<boolean>} true si el portal se abrió con éxito
 */
export async function launchARSPortal(ars, claim = {}) {
  const { toast } = await import('../utils/ui.js');
  const url = resolvePortalUrl(ars);
  if (!url) {
    toast('Esta ARS no tiene portal configurado.', 'warn');
    return false;
  }
  const payload = buildPortalPayload(ars, claim);
  try { await copyToClipboard(payload); } catch (_) { /* continúa aunque falle el clipboard */ }
  const tab = window.open(url, '_blank', 'noopener,noreferrer');
  if (tab) {
    toast(`Datos copiados al portapapeles — Portal PSS ${ars.name} abierto`, 'ok');
    return true;
  }
  // Popup bloqueado: dar la URL al operador para abrir manualmente
  toast(`Popup bloqueado. Abra manualmente: ${url}`, 'warn');
  return false;
}
