/** Completa MFA antes de cambiar contraseña. No recibe ni conserva contraseñas. */
import { mfaState, verifyStep } from '../modules/seguridad.js';
import { h, note } from '../services/iter18.js';
export async function passwordMfaReady(box) {
  try {
    const state = await mfaState();
    if (state.current === 'aal2' || (!state.factor && state.next !== 'aal2')) {
      box.replaceChildren(); return true;
    }
    if (!state.factor) {
      box.replaceChildren(note('Esta cuenta requiere otro método de verificación. Contacta al administrador para recuperar el acceso de forma segura.', 'error'));
      return false;
    }
    const challenge = h('div');
    box.replaceChildren(note('Antes de guardar la contraseña, verifica el código de tu app autenticadora.'), challenge);
    verifyStep(challenge, state.factor.id, () => {
      box.replaceChildren(note('Verificación completada. Pulsa Guardar contraseña para continuar.', 'ok'));
    });
    return false;
  } catch (_) {
    box.replaceChildren(note('No se pudo comprobar la verificación en dos pasos. Intenta guardar de nuevo cuando recuperes la conexión.', 'error'));
    return false;
  }
}
