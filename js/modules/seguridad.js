/** SOFA · 2.0 · Seguridad: verificación en dos pasos (MFA con app autenticadora, TOTP).
 *  La historia clínica puede exigirla por consultorio. Usa Supabase Auth (auth.mfa); no guarda secretos en SOFA. */
import { supabase, h, note } from '../services/iter18.js';

const mfa = () => supabase.auth.mfa;
const err = (e) => (e && e.message) || 'No se pudo completar. Intente de nuevo.';

/** Estado actual: ¿tiene factor verificado? ¿esta sesión ya pasó el segundo paso? */
export async function mfaState() {
  const [{ data: f, error: e1 }, { data: a, error: e2 }] = await Promise.all([mfa().listFactors(), mfa().getAuthenticatorAssuranceLevel()]);
  if (e1 || e2) throw new Error('No se pudo leer la verificación en dos pasos. Recargue la página.');
  const totp = (f?.totp || []).filter((x) => x.status === 'verified');
  return { factor: totp[0] || null, current: a?.currentLevel || 'aal1', next: a?.nextLevel || 'aal1' };
}

/** Pide el código de 6 dígitos y eleva la sesión a aal2. onDone() al terminar. */
export function verifyStep(box, factorId, onDone) {
  const code = h('input', { id: 'mfa-code', inputmode: 'numeric', autocomplete: 'one-time-code', maxlength: '6', pattern: '\\d{6}', placeholder: '000000', style: 'max-width:9rem;font-size:1.2rem;letter-spacing:.2em' });
  const ok = h('button', { class: 'i18-btn', type: 'button' }, 'Verificar');
  const msg = h('div', { 'aria-live': 'polite' });
  async function go() {
    if (!/^\d{6}$/.test(code.value.trim())) { msg.replaceChildren(note('Escriba los 6 números que muestra su app autenticadora.', 'error')); return; }
    ok.disabled = true;
    try {
      const { error } = await mfa().challengeAndVerify({ factorId, code: code.value.trim() });
      if (error) throw error;
      msg.replaceChildren(note('Verificado. Esta sesión ya tiene el segundo paso.', 'ok'));
      onDone && onDone();
    } catch (e) {
      msg.replaceChildren(note(/invalid|expired/i.test(err(e)) ? 'El código no es válido o ya venció. Espere el siguiente código de la app y vuelva a intentar.' : err(e), 'error'));
    } finally { ok.disabled = false; }
  }
  ok.addEventListener('click', go);
  code.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
  box.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'mfa-code' }, 'Código de 6 dígitos de su app autenticadora'), code, h('div', {}, ok), msg));
  setTimeout(() => code.focus(), 0);
}

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Seguridad: verificación en dos pasos'),
    note('Con la verificación en dos pasos, además de su contraseña se pide un código de una app autenticadora (Google Authenticator, Microsoft Authenticator, Authy). Protege la historia clínica aunque alguien conozca su contraseña.'),
    box);
  await draw();

  async function draw() {
    let st;
    try { st = await mfaState(); } catch (e) { box.replaceChildren(note(err(e), 'error')); return; }
    if (st.factor) {
      const verify = h('div');
      const off = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Quitar la verificación en dos pasos');
      off.addEventListener('click', async () => {
        if (!confirm('¿Quitar la verificación en dos pasos? Si su consultorio la exige, no podrá abrir la historia clínica hasta activarla de nuevo.')) return;
        const { error } = await mfa().unenroll({ factorId: st.factor.id });
        if (error) { box.prepend(note(/aal2/i.test(err(error)) ? 'Para quitarla primero verifique esta sesión con un código.' : err(error), 'error')); return; }
        draw();
      });
      box.replaceChildren(
        note(`Activada (${st.factor.friendly_name || 'app autenticadora'}). Esta sesión: ${st.current === 'aal2' ? 'verificada con código' : 'solo con contraseña'}.`, 'ok'),
        st.current === 'aal2' ? '' : h('div', {}, h('h3', {}, 'Verificar esta sesión'), verify),
        h('div', { class: 'i18-actions' }, off));
      if (st.current !== 'aal2') verifyStep(verify, st.factor.id, draw);
      return;
    }
    const start = h('button', { class: 'i18-btn', type: 'button' }, 'Activar verificación en dos pasos');
    box.replaceChildren(note('Todavía no está activada.'), h('div', { class: 'i18-actions' }, start));
    start.addEventListener('click', async () => {
      start.disabled = true;
      // Limpia intentos anteriores sin terminar
      const { data: f } = await mfa().listFactors();
      for (const x of (f?.all || []).filter((x) => x.status !== 'verified')) await mfa().unenroll({ factorId: x.id });
      const { data, error } = await mfa().enroll({ factorType: 'totp', friendlyName: 'SOFA ' + new Date().toISOString().slice(0, 10) });
      if (error) { box.replaceChildren(note(/disabled|not enabled/i.test(err(error)) ? 'La verificación en dos pasos no está habilitada en Supabase. El Administrador debe activarla en Authentication › Multi-Factor (TOTP).' : err(error), 'error')); return; }
      const verify = h('div');
      box.replaceChildren(
        h('ol', {}, h('li', {}, 'Abra su app autenticadora y escanee este código QR.'),
          h('li', {}, 'Si no puede escanear, escriba esta clave en la app: ', h('code', {}, data.totp.secret)),
          h('li', {}, 'Escriba abajo el código de 6 dígitos que aparece en la app.')),
        h('img', { src: data.totp.qr_code, alt: 'Código QR para la app autenticadora', width: '200', height: '200', style: 'background:#fff;padding:8px;border-radius:8px' }),
        verify);
      verifyStep(verify, data.id, draw);
    });
  }
}
