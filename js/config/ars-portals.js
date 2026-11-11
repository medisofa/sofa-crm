/** SOFA · Mapa de URLs de portales PSS por código de ARS.
 *
 * Este archivo es el fallback estático: si una ARS tiene `portal_url` configurado
 * en la base de datos (tabla `ars`), esa URL tiene prioridad sobre este mapa.
 *
 * Los administradores pueden actualizar las URLs directamente desde el módulo
 * ARS y planes sin necesidad de un nuevo deploy.
 *
 * Formato: { [código ARS]: 'https://...' }
 */
export const ARS_PORTAL_DEFAULTS = {};
