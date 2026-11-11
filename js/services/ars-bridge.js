/**
 * SOFA · ARS Portal Bridge
 * Copia los datos de la reclamación al portapapeles y abre el portal PSS de la ARS.
 * No modifica ningún estado persistente; es un helper puramente de salida.
 */
import { ARS_PORTAL_DEFAULTS } from '../config/ars-portals.js';

/**
 * Construye el texto plano que se copia al portapapeles.
 * Solo incluye los campos que tienen valor.
 *
 * @param {{ name: string, code?: string }} ars
 * @param {{ member?: string, patientDoc?: string, patientName?: string, serviceDate?: string,
 *           diagnosis?: string, procedureName?: string, simon?: string, cups?: string }} claim
 * @returns {string}
 */
export function buildPortalPayload(ars, claim) {
  const lines = [`SOFA · Autorización ARS — ${ars.name}`];
  if (claim.serviceDate)   lines.push(`Fecha del servicio: ${claim.serviceDate}`);
  if (claim.patientName)   lines.push(`Paciente: ${claim.patientName}`);
  if (claim.member)        lines.push(`NSS / No. afiliado: ${claim.member}`);
  if (claim.patientDoc)    lines.push(`Cédula: ${claim.patientDoc}`);
  if (claim.diagnosis)     lines.push(`Diagnóstico CIE-10: ${claim.diagnosis}`);
  if (claim.procedureName) lines.push(`Servicio: ${claim.procedureName}`);
  if (claim.simon)         lines.push(`SIMON: ${claim.simon}`);
  if (claim.cups)          lines.push(`CUPS: ${claim.cups}`);
  return lines.join('\n');
}

/**
 * Copia payload al portapapeles — intenta la API moderna y hace fallback a execCommand.
 * @param {string} text
 * @returns {Promise<boolean>} true si se copió correctamente
 */
async function copyToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    try { await navigator.clipboard.writeText(text); return true; } catch (_) { /* fallback */ }
  }
  // Fallback legacy: textarea temporal fuera de pantalla
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0';
  document.body.appendChild(ta);
  ta.focus(); ta.select();
  const ok = document.execCommand('copy');
  document.body.removeChild(ta);
  return ok;
}

/**
 * Resuelve la URL del portal para una ARS dada.
 * Prioridad: portal_url de la tabla ars → ARS_PORTAL_DEFAULTS → null
 *
 * @param {{ code?: string, portal_url?: string }} ars
 * @returns {string|null}
 */
export function resolvePortalUrl(ars) {
  if (ars.portal_url) return ars.portal_url;
  if (ars.code && ARS_PORTAL_DEFAULTS[ars.code]) return ARS_PORTAL_DEFAULTS[ars.code];
  return null;
}

/**
 * Lanza el portal PSS de la ARS:
 *  1. Construye el payload de texto.
 *  2. Copia al portapapeles.
 *  3. Abre el portal en nueva pestaña (con fallback si el popup está bloqueado).
 *  4. Muestra un toast informativo.
 *
 * @param {{ id: string, name: string, code?: string, portal_url?: string }} ars
 * @param {{ member?: string, patientDoc?: string, patientName?: string, serviceDate?: string,
 *           diagnosis?: string, procedureName?: string, simon?: string, cups?: string }} claim
 * @returns {Promise<boolean>} true si se pudo abrir la pestaña
 */
export async function launchARSPortal(ars, claim) {
  const { toast } = await import('../utils/ui.js');
  const url = resolvePortalUrl(ars);

  const payload = buildPortalPayload(ars, claim);
  const copied = await copyToClipboard(payload);

  let opened = false;
  if (url) {
    const win = window.open(url, '_blank', 'noopener,noreferrer');
    opened = !!win;
    if (!opened) {
      // Popup bloqueado: informar al usuario para que lo abra manualmente
      toast(`Portal bloqueado por el navegador. Ábrelo manualmente: ${url}`, 'bad');
      return false;
    }
  }

  if (copied) {
    const msg = url
      ? `Datos copiados al portapapeles — Portal PSS ${ars.name} abierto`
      : `Datos copiados al portapapeles (configura la URL del portal en Admin → ARS)`;
    toast(msg, 'ok');
  } else {
    toast('No se pudo copiar al portapapeles — pega los datos manualmente', 'bad');
  }

  return opened;
}
