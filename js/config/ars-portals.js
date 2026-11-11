/**
 * SOFA · URLs por defecto de portales PSS.
 * Fallback cuando portal_url en la tabla ars es NULL.
 *
 * Para configurar las URLs reales: Admin → ARS → Editar → campo "URL del Portal PSS".
 * No se hardcodean URLs aquí porque cambian y requieren un deploy para actualizarse.
 *
 * Estructura de cada entrada (si se agrega en el futuro):
 *   '<ars_code>': 'https://portal.arsejemplo.com.do/login'
 */
export const ARS_PORTAL_DEFAULTS = {};
