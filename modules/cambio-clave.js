/** SOFA · Cambio obligatorio de clave en el primer acceso.
 *  Uso en el arranque de la app, justo después de iniciar sesión:
 *    import { needsPasswordChange, render as cambioClave } from './modules/cambio-clave.js';
 *    if (await needsPasswordChange()) return cambioClave(root, { onDone: () => location.reload() });
 */
import { supabase, rpc, h, note } from '../services/iter18.js';

export async function needsPasswordChange() {
  try { const s = await rpc('my_security_state'); return Boolean(s && s.must_change_password); } catch (_) { return false; }
}

const reglas = (p) => {
  const f = [];
  if (p.length < 10) f.push('al menos 10 caracteres');
  if (!/[a-z]/.test(p)) f.push('una minúscula');
  if (!/[A-Z]/.test(p)) f.push('una mayúscula');
  if (!/\d/.test(p)) f.push('un número');
  if (!/[^A-Za-z0-9]/.test(p)) f.push('un símbolo');
  return f;
};

export async function render(root, { onDone } = {}) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const a = h('input', { type: 'password', id: 'i18-cc-a', autocomplete: 'new-password', required: true });
  const b = h('input', { type: 'password', id: 'i18-cc-b', autocomplete: 'new-password', required: true });
  const btn = h('button', { class: 'i18-btn', type: 'submit' }, 'Guardar contraseña nueva');
  const form = h('form', { class: 'i18-form', novalidate: true },
    h('label', {}, 'Contraseña nueva', a), h('label', {}, 'Repita la contraseña', b), btn);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); out.replaceChildren();
    const falta = reglas(a.value);
    if (falta.length) return out.replaceChildren(note('La contraseña necesita ' + falta.join(', ') + '.', 'error'));
    if (a.value !== b.value) return out.replaceChildren(note('Las dos contraseñas no coinciden. Escríbalas de nuevo.', 'error'));
    btn.disabled = true;
    try {
      const u = await supabase.auth.updateUser({ password: a.value });
      if (u.error) throw new Error(u.error.message.toLowerCase().includes('same') ? 'Elija una contraseña distinta a la temporal.' : 'No se pudo guardar la contraseña: ' + u.error.message);
      await rpc('confirm_password_changed');
      out.replaceChildren(note('Contraseña cambiada. Entrando al sistema…'));
      if (onDone) onDone();
    } catch (e) { out.replaceChildren(note(e.message, 'error')); btn.disabled = false; }
  });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Cambie su contraseña'),
    note('Es su primer acceso. Por seguridad debe reemplazar la contraseña temporal antes de usar el sistema.'), form, out));
}
export default render;
export const mount = render;
