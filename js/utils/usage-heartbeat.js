/** SOFA · Latido de conexión: un aviso por minuto mientras la app está abierta con sesión.
 *  «Activo» = pestaña visible y alguna pulsación, tecla o desplazamiento en los últimos 5 minutos.
 *  Medir nunca estorba: si falla (sin internet, migración sin aplicar) no se avisa al usuario. */
import { usagePing } from '../services/usage.js';

const IDLE_MS = 5 * 60 * 1000;
let timer = null;

export function startUsageHeartbeat({ ping = usagePing, everyMs = 60000 } = {}) {
  if (timer) return;
  let lastInput = Date.now();
  const mark = () => { lastInput = Date.now(); };
  ['pointerdown', 'keydown', 'scroll', 'touchstart'].forEach((ev) => window.addEventListener(ev, mark, { passive: true, capture: true }));
  const beat = () => Promise.resolve()
    .then(() => ping(!document.hidden && Date.now() - lastInput < IDLE_MS))
    .catch((e) => console.debug('latido de conexión', e?.message || e));
  beat();
  timer = setInterval(beat, everyMs);
}
