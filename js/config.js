/**
 * SOFA · Configuración pública del frontend.
 *
 * Aquí SOLO van la URL del proyecto y la clave PUBLICABLE de Supabase.
 * Ambas son públicas por diseño: sin una sesión válida no dan acceso a datos
 * (lo garantiza RLS en PostgreSQL).
 *
 * NUNCA pegues aquí: la contraseña de la base de datos, la Secret key
 * (sb_secret_...) ni la service_role. La aplicación se niega a arrancar si
 * detecta una de esas claves.
 */
export const CONFIG = Object.freeze({
  SUPABASE_URL: 'https://bpwjhgpzhzhiocoxrvzq.supabase.co/rest/v1/',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_AVyjtcY8xkF-m0JJ7EmgGQ_nB7eM4R-',
  APP_NAME: 'SOFA',
  APP_VERSION: '0.3.0',
  // Cierre automático de sesión por inactividad (datos de salud y financieros)
  INACTIVITY_MINUTES: 30,
  // Tamaño de página por defecto en listados
  PAGE_SIZE: 25
});
