/**
 * SOFA · Reglas de extracción sobre el texto leído de un documento (4.5.2).
 * Módulo PURO: no toca el DOM ni la red, se puede importar y probar en node.
 * Devuelve para cada campo {valor, confianza (0..1), revisar}. Lo que queda con confianza < UMBRAL
 * NO se prellena en el formulario: se muestra marcado para revisar y la persona lo escribe o lo corrige.
 */
export const UMBRAL = 0.6;
export const CAMPOS = ['cedula', 'numero_autorizacion', 'fecha', 'afiliado', 'ars', 'procedimiento'];
const MAX_VALOR = 120;

const clamp = (n) => Math.max(0, Math.min(1, Math.round(n * 100) / 100));
const sinTildes = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
const norm = (s) => sinTildes(s).toLowerCase().replace(/[^a-z0-9ñ]+/g, ' ').trim();
const vacio = () => ({ valor: '', confianza: 0, revisar: true });
const campo = (valor, conf) => {
  const c = clamp(conf);
  return valor ? { valor: String(valor).slice(0, MAX_VALOR), confianza: c, revisar: c < UMBRAL } : vacio();
};

/** Limpia el texto del OCR: espacios raros, guiones tipográficos y comillas */
export function limpiarTexto(t) {
  return String(t || '').normalize('NFC').replace(/\r/g, '\n').replace(/[ \t]+/g, ' ').replace(/[–—−‐‑]/g, '-')
    .replace(/[ ]{2,}/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
}

// ------------------------------------------------------------------ cédula
/** Letras que el OCR confunde con dígitos */
const DIG = { O: '0', o: '0', Q: '0', D: '0', l: '1', I: '1', i: '1', '|': '1', '!': '1', Z: '2', z: '2', S: '5', s: '5', B: '8', b: '6', G: '6' };
const CLASE = '[0-9OoQDlIi|!ZzSsBbG]';
const aDigitos = (s) => { let cambios = 0; const out = String(s).replace(/[^0-9]/g, (c) => { if (DIG[c] !== undefined) { cambios += 1; return DIG[c]; } return ''; }); return { out, cambios }; };

/** Dígito verificador de la cédula dominicana (módulo 10 con pesos 1,2) */
export function cedulaValida(c11) {
  const d = String(c11).replace(/\D/g, '');
  if (d.length !== 11) return false;
  let suma = 0;
  for (let i = 0; i < 10; i += 1) { let p = Number(d[i]) * (i % 2 === 0 ? 1 : 2); if (p > 9) p = Math.floor(p / 10) + (p % 10); suma += p; }
  return (10 - (suma % 10)) % 10 === Number(d[10]);
}
export const formatearCedula = (d) => `${d.slice(0, 3)}-${d.slice(3, 10)}-${d.slice(10)}`;

export function extraerCedula(texto) {
  const re = new RegExp(`(?<![0-9A-Za-z])(${CLASE}{3})([\\s.\\-]{0,2})(${CLASE}{7})([\\s.\\-]{0,2})(${CLASE})(?![0-9A-Za-z])`, 'g');
  let mejor = null;
  for (const m of texto.matchAll(re)) {
    const crudo = m[0];
    const { out, cambios } = aDigitos(crudo);
    if (out.length !== 11) continue;
    // exige que sea mayormente números: máximo 2 caracteres corregidos
    if (cambios > 2) continue;
    const conGuiones = m[2].includes('-') && m[4].includes('-');
    const ctx = texto.slice(Math.max(0, m.index - 40), m.index).toLowerCase();
    const etiqueta = /c[eé]dula|c[eé]d\.|\bid\b|identidad/.test(ctx);
    let conf = conGuiones ? 0.92 : 0.8;
    conf -= cambios * 0.1;
    if (etiqueta) conf += 0.05;
    if (!cedulaValida(out)) conf = Math.min(conf, 0.5); // dígito verificador no cuadra: a revisar
    if (!mejor || conf > mejor.conf) mejor = { valor: formatearCedula(out), conf };
  }
  return mejor ? campo(mejor.valor, mejor.conf) : vacio();
}

// ------------------------------------------------------------------ fecha
const MESES = { enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6, julio: 7, agosto: 8, septiembre: 9, setiembre: 9, octubre: 10, noviembre: 11, diciembre: 12 };
const CD = '[0-9OoIl|]';
const aNum = (s) => Number(String(s).replace(/[Oo]/g, '0').replace(/[Il|]/g, '1'));
const iso = (y, m, d) => `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
const fechaReal = (y, m, d) => { const f = new Date(Date.UTC(y, m - 1, d)); return f.getUTCFullYear() === y && f.getUTCMonth() === m - 1 && f.getUTCDate() === d; };

/** Todas las fechas del texto con su posición: dd/mm/aaaa, dd-mm-aa, dd.mm.aaaa y «15 de octubre de 2026» */
export function listarFechas(texto, hoy = new Date()) {
  const out = []; const limite = hoy.getUTCFullYear() + 1;
  const re1 = new RegExp(`(?<![0-9A-Za-z])(${CD}{1,2})\\s?([/\\-.])\\s?(${CD}{1,2})\\s?\\2\\s?(${CD}{4}|${CD}{2})(?![0-9A-Za-z])`, 'g');
  for (const m of texto.matchAll(re1)) {
    const d = aNum(m[1]); const mo = aNum(m[3]); let y = aNum(m[4]);
    const dosDigitos = m[4].length === 2; if (dosDigitos) y += 2000;
    if (!fechaReal(y, mo, d) || y < 2000 || y > limite) continue;
    const cambios = (m[0].match(/[OoIl|]/g) || []).length;
    out.push({ iso: iso(y, mo, d), pos: m.index, conf: 0.93 - (dosDigitos ? 0.12 : 0) - cambios * 0.08 });
  }
  const re2 = /(?<![0-9A-Za-z])(\d{1,2})\s+de\s+([a-záéíóú]+)\s+(?:de|del)\s+(\d{4})(?![0-9])/gi;
  for (const m of texto.matchAll(re2)) {
    const mo = MESES[sinTildes(m[2]).toLowerCase()]; if (!mo) continue;
    const d = Number(m[1]); const y = Number(m[3]);
    if (!fechaReal(y, mo, d) || y < 2000 || y > limite) continue;
    out.push({ iso: iso(y, mo, d), pos: m.index, conf: 0.9 });
  }
  return out.sort((a, b) => a.pos - b.pos);
}

export function extraerFecha(texto, hoy = new Date()) {
  const todas = listarFechas(texto, hoy);
  if (!todas.length) return vacio();
  const hoyIso = hoy.toISOString().slice(0, 10);
  const etiquetadas = todas.filter((f) => /fecha|emisi[oó]n|emitid|aprobaci[oó]n|autoriz|vigencia|servicio/i.test(texto.slice(Math.max(0, f.pos - 45), f.pos)));
  const elegida = (etiquetadas[0] || todas[0]);
  let conf = elegida.conf + (etiquetadas.length ? 0.04 : 0);
  const distintas = new Set(todas.map((f) => f.iso));
  if (distintas.size > 1 && !etiquetadas.length) conf -= 0.2; // varias fechas y ninguna con rótulo: duda
  if (elegida.iso > hoyIso) conf = Math.min(conf, 0.3); // futura: no puede ser la de una autorización ya emitida
  return campo(elegida.iso, conf);
}

// ------------------------------------------------------------------ número de autorización
const ETIQ_AUT = /(?:n[uú]mero|n[oº°]\.?|nro\.?|num\.?|c[oó]digo|cod\.?|#)?\s*(?:de\s+)?(?:pre-?\s?)?(?:autorizaci[oó]n|autorizacion|aprobaci[oó]n|aut\.?(?![a-zñáéíóú]))\s*(?:n[uú]mero|n[oº°]\.?|nro\.?|num\.?|#)?\s*[:#.\-]*\s*/i;

export function extraerAutorizacion(texto) {
  const lineas = texto.split('\n');
  const re = new RegExp(`${ETIQ_AUT.source}([A-Za-z0-9][A-Za-z0-9\\-/]{3,23})`, 'i');
  let mejor = null;
  const considerar = (token, mismaLinea) => {
    let t = token.replace(/^[-/]+|[-/]+$/g, '');
    const digitos = (t.match(/[0-9OoIl|]/g) || []).length;
    if (t.length < 5 || digitos / t.length < 0.6) return false; // una palabra como «Autorización: pendiente» no es un número
    let cambios = 0;
    // si es casi todo números, corrige letras confundidas con dígitos
    if (/^[0-9OoIlSB\-/]+$/.test(t) && /[0-9]/.test(t)) t = t.replace(/[OoIlSB]/g, (c) => { cambios += 1; return DIG[c]; });
    if (!/[0-9]{3,}/.test(t.replace(/[-/]/g, ''))) return false;
    let conf = mismaLinea ? 0.9 : 0.72;
    conf -= cambios * 0.1;
    if (t.length < 6) conf -= 0.1;
    if (!mejor || conf > mejor.conf) mejor = { valor: t.toUpperCase(), conf };
    return true;
  };
  lineas.forEach((ln, i) => {
    const m = ln.match(re);
    if (m && considerar(m[1], true)) return;
    // rótulo solo en la línea y el número en la siguiente
    if (new RegExp(`${ETIQ_AUT.source}$`, 'i').test(ln.trim()) && /autoriz|aprobaci|aut\b/i.test(ln) && lineas[i + 1]) {
      const sig = lineas[i + 1].trim().match(/^([A-Za-z0-9][A-Za-z0-9\-/]{3,23})\b/);
      if (sig) considerar(sig[1], false);
    }
  });
  return mejor ? campo(mejor.valor, mejor.conf) : vacio();
}

// ------------------------------------------------------------------ afiliado
const PARTICULAS = new Set(['de', 'del', 'la', 'las', 'los', 'y', 'e', 'da', 'di']);
export function extraerAfiliado(texto) {
  const re = /(?:nombre\s+del\s+(?:afiliado|paciente|beneficiario|asegurado)|afiliado(?:\s*\(a\))?|paciente|beneficiari[oa]|titular|asegurad[oa]|nombre)\s*[:\-]\s*([^\n]{3,90})/i;
  const lineas = texto.split('\n');
  let mejor = null;
  for (const ln of lineas) {
    const m = ln.match(re); if (!m) continue;
    // corta al llegar a otro rótulo o a un número largo (cédula, NSS, fecha)
    let nom = m[1].split(/\s{2,}|\s(?:c[eé]dula|nss|n[oº°]\.?|nro|id|fecha|ars|plan|sexo|edad|tel[eé]fono|parentesco)\b|[0-9]{3,}|\|/i)[0];
    nom = nom.replace(/[^\p{L}\s.'\-]/gu, ' ').replace(/\s+/g, ' ').trim();
    const pal = nom.split(' ').filter(Boolean);
    const reales = pal.filter((p) => !PARTICULAS.has(p.toLowerCase()) && p.replace(/[.'\-]/g, '').length >= 2);
    if (reales.length < 2) continue;
    let conf = 0.85;
    if (pal.some((p) => p.length === 1 && !PARTICULAS.has(p.toLowerCase()))) conf -= 0.2; // letras sueltas: ruido
    if (reales.length > 5) conf -= 0.2;
    if (/[0-9]/.test(m[1].slice(0, nom.length + 2))) conf -= 0.25; // números pegados al nombre
    if (!mejor || conf > mejor.conf) mejor = { valor: pal.join(' '), conf };
  }
  return mejor ? campo(mejor.valor, mejor.conf) : vacio();
}

// ------------------------------------------------------------------ ARS (contra la lista que pasa quien llama)
const RUIDO_ARS = new Set(['ars', 'seguros', 'seguro', 'salud', 'sa', 's', 'a', 'de', 'del', 'la', 'plan', 'planes', 'y', 'dominicana', 'dominicano', 'rd']);
const claveARS = (n) => norm(n).split(' ').filter((w) => w && !RUIDO_ARS.has(w));

function distancia(a, b) {
  const m = a.length; const n = b.length; if (Math.abs(m - n) > 2) return 9;
  const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 1; j <= n; j += 1) d[0][j] = j;
  for (let i = 1; i <= m; i += 1) for (let j = 1; j <= n; j += 1) d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[m][n];
}

/** lista: ['SENASA', 'ARS Humano', ...] o [{id, name}]. Devuelve valor = nombre tal como viene en la lista (y id si lo traía). */
export function extraerARS(texto, lista = []) {
  const items = (lista || []).map((x) => (typeof x === 'string' ? { name: x } : x)).filter((x) => x && x.name);
  const palabras = norm(texto).split(' ').filter(Boolean);
  const textoN = ` ${palabras.join(' ')} `;
  const puntajes = [];
  for (const it of items) {
    const clave = claveARS(it.name); if (!clave.length) continue;
    const completo = norm(it.name);
    let conf = 0;
    if (textoN.includes(` ${completo} `)) conf = 0.95;
    else if (clave.every((w) => textoN.includes(` ${w} `))) conf = clave.join('').length <= 4 ? 0.8 : 0.88;
    else if (clave.length === 1 && clave[0].length >= 5) {
      const cercano = palabras.some((p) => p.length >= 5 && distancia(p, clave[0]) <= 1); // una letra mal leída
      if (cercano) conf = 0.68;
    }
    if (conf) puntajes.push({ it, conf });
  }
  if (!puntajes.length) return vacio();
  puntajes.sort((a, b) => b.conf - a.conf || claveARS(b.it.name).join('').length - claveARS(a.it.name).join('').length);
  let { it, conf } = puntajes[0];
  const empate = puntajes.filter((p) => p.conf === conf && p.it.name !== it.name);
  // dos ARS distintas con la misma coincidencia (ej. «Plan Salud» y «Plan Salud Banreservas»): queda la de nombre más largo; si no hay diferencia, duda
  if (empate.length && claveARS(empate[0].it.name).join('').length === claveARS(it.name).join('').length) conf = 0.45;
  const r = campo(it.name, conf); if (it.id) r.id = it.id;
  return r;
}

// ------------------------------------------------------------------ procedimiento
export function extraerProcedimiento(texto) {
  const re = /(?:procedimiento|servicio\s+(?:autorizado|solicitado)|servicio|prestaci[oó]n|estudio|descripci[oó]n(?:\s+del\s+servicio)?|concepto)\s*[:\-]\s*([^\n]{4,160})/i;
  for (const ln of texto.split('\n')) {
    const m = ln.match(re); if (!m) continue;
    let v = m[1].split(/\s{3,}|\s(?:c[uú]ps|cod(?:igo)?|monto|valor|cantidad|fecha)\b\s*[:.]/i)[0].replace(/\s+/g, ' ').trim().replace(/[.,;:\-\s]+$/, '');
    if (v.length < 4 || (v.match(/\p{L}/gu) || []).length < 4) continue;
    let conf = 0.82;
    if (v.length > MAX_VALOR) { v = v.slice(0, MAX_VALOR).trim(); conf -= 0.2; }
    if ((v.match(/[0-9]/g) || []).length > v.length / 2) conf -= 0.3; // casi todo números: no es una descripción
    return campo(v, conf);
  }
  return vacio();
}

// ------------------------------------------------------------------ conjunto
/**
 * @param {string} textoCrudo texto leído por el OCR
 * @param {{ars?: Array, hoy?: Date, tipo?: string}} opciones
 */
export function extraerCampos(textoCrudo, { ars = [], hoy = new Date() } = {}) {
  const t = limpiarTexto(textoCrudo);
  return {
    cedula: extraerCedula(t),
    numero_autorizacion: extraerAutorizacion(t),
    fecha: extraerFecha(t, hoy),
    afiliado: extraerAfiliado(t),
    ars: extraerARS(t, ars),
    procedimiento: extraerProcedimiento(t)
  };
}

/** Solo los campos con confianza suficiente: lo único que se puede prellenar */
export function paraPrellenar(campos) {
  const out = {};
  for (const k of CAMPOS) { const c = campos?.[k]; if (c && c.valor && c.confianza >= UMBRAL) out[k] = c.valor; }
  return out;
}

/** Formato de la RPC register_captured_document: campo -> {valor, confianza}; solo lo que se leyó */
export function paraRegistrar(campos) {
  const out = {};
  for (const k of CAMPOS) { const c = campos?.[k]; if (c && c.valor) out[k] = { valor: String(c.valor).slice(0, MAX_VALOR), confianza: clamp(c.confianza) }; }
  return out;
}
