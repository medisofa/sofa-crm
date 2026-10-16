/**
 * SOFA · Motor de lectura de texto (OCR) que corre EN el dispositivo (4.5.2).
 * Usa tesseract.js autoalojado en vendor/tesseract/: ninguna llamada a servidores de terceros.
 * El worker, el núcleo WebAssembly y el idioma español salen del mismo origen que la aplicación.
 *
 * CSP: con la política de index.html (etiqueta <meta>) NO hace falta ningún permiso nuevo: el worker se carga como archivo del
 * mismo origen (worker-src 'self') y una etiqueta <meta> no se hereda a un worker de URL. Si el hosting agrega la política como
 * ENCABEZADO HTTP, el worker sí la hereda y compilar el núcleo WebAssembly exige 'wasm-unsafe-eval' en script-src (solo eso; ni
 * 'unsafe-eval' ni blob:). Sin ese permiso la lectura falla con un mensaje claro y la captura sigue a mano.
 *
 * HOOK para cambiar de motor sin tocar la pantalla: registrarMotor(async (imagen, {onProgreso}) => ({texto, confianza}))
 *   · imagen es un Blob/Canvas; confianza es opcional (0..1).
 *   · Con un motor registrado no se carga tesseract. Quitar el hook: registrarMotor(null).
 *   · Si algún día se agrega un lector en la nube, entra por aquí, apagado por defecto y como interruptor por cliente.
 */
const BASE = new URL('../../vendor/tesseract/', import.meta.url).href;
let hook = null; let worker = null; let cargando = null;

export function registrarMotor(fn) { hook = typeof fn === 'function' ? fn : null; }

/** true si este navegador puede correr el motor local (o hay un motor registrado) */
export function motorDisponible() {
  return !!hook || (typeof Worker === 'function' && typeof WebAssembly === 'object');
}

async function crearWorker(onProgreso) {
  const T = await import(`${BASE}tesseract.esm.min.js`);
  const lib = T.default || T;
  let fallo; const cayo = new Promise((_, rej) => { fallo = rej; });
  const listo = lib.createWorker('spa', 1 /* solo LSTM */, {
    workerPath: `${BASE}worker.min.js`,
    corePath: BASE,           // carpeta: elige tesseract-core-simd-lstm.wasm.js o tesseract-core-lstm.wasm.js
    langPath: BASE,           // spa.traineddata.gz
    workerBlobURL: false,     // el worker se carga como archivo del mismo origen, no como blob:
    cacheMethod: 'none',
    gzip: true,
    errorHandler: (e) => fallo(e instanceof Error ? e : new Error(String(e))),
    logger: (m) => { if (m && m.status && typeof m.progress === 'number') onProgreso?.(m.status, m.progress); }
  });
  let reloj; const tarde = new Promise((_, rej) => { reloj = setTimeout(() => rej(new Error('tiempo agotado')), 120000); });
  try { return await Promise.race([listo, cayo, tarde]); } finally { clearTimeout(reloj); }
}

/** Lee el texto de la imagen. Devuelve {texto, confianza}. Lanza un Error con el paso a seguir si algo falla. */
export async function leerTexto(imagen, { onProgreso } = {}) {
  if (hook) return hook(imagen, { onProgreso });
  if (!motorDisponible()) throw new Error('Este navegador no puede leer el texto de la foto. Escribe los datos a mano o abre SOFA en Chrome, Edge o Safari actualizados.');
  try {
    if (!worker) {
      cargando ||= crearWorker(onProgreso).then((w) => { worker = w; return w; }).finally(() => { cargando = null; });
      await cargando;
    }
    const { data } = await Promise.race([worker.recognize(imagen), new Promise((_, rej) => setTimeout(() => rej(new Error('tiempo agotado')), 120000))]);
    return { texto: String(data?.text || ''), confianza: typeof data?.confidence === 'number' ? data.confidence / 100 : null };
  } catch (err) {
    console.warn('OCR', err);
    await liberarMotor();
    if (/wasm|WebAssembly|unsafe-eval|CompileError/i.test(String(err?.message || err))) {
      throw new Error("La política de seguridad del servidor bloquea la lectura en el dispositivo (falta 'wasm-unsafe-eval' en script-src). Avisa al administrador de SOFA; mientras tanto escribe los datos a mano.");
    }
    throw new Error('No se pudo leer el texto de la foto. Toma la foto de nuevo con buena luz y el papel derecho, o escribe los datos a mano.');
  }
}

/** Libera memoria del motor (al cerrar el panel) */
export async function liberarMotor() {
  const w = worker; worker = null; cargando = null;
  try { await w?.terminate(); } catch { /* ya estaba cerrado */ }
}
