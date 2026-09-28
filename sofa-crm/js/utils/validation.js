/** SOFA · Validaciones de formulario (la base de datos vuelve a validar todo) */
export const isEmail = (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(v || '').trim());
export const isTaxId = (v) => /^(\d{9}|\d{11})$/.test(String(v || '').replace(/\D/g, ''));
export const isNCF = (v) => /^(B\d{10}|E\d{12})$/.test(String(v || '').trim().toUpperCase());
export const isPhone = (v) => !v || /^\+?\d{10,15}$/.test(String(v).replace(/[\s()-]/g, ''));
/** Reglas de contraseña: 10+ caracteres, letras y números */
export function passwordProblem(p) {
  if (!p || p.length < 10) return 'Usa al menos 10 caracteres.';
  if (!/[A-Za-zÁÉÍÓÚÑáéíóúñ]/.test(p) || !/\d/.test(p)) return 'Combina letras y números.';
  return null;
}
