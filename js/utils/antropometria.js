/**
 * SOFA · Cálculos antropométricos para la historia clínica (nutrición, pediatría y consulta general).
 *
 * Todo se calcula en el navegador a partir de lo que escribe el médico; el resultado se guarda en la nota
 * (cifrada) como texto, igual que cualquier otro campo. Nada sale del equipo para calcularse.
 *
 * Puntaje Z (niños): método LMS de la OMS (z = ((X/M)^L − 1) / (L·S)), con la corrección oficial de la OMS
 * más allá de ±3 DE para los indicadores de peso (peso/edad, peso/longitud, peso/talla, IMC/edad).
 * Tablas: js/data/who-lms.json (scripts/generate-who-lms.mjs). Verificado contra dos paquetes independientes
 * en scripts/check-who-zscore.mjs.
 *
 * Fórmulas de adultos:
 *   IMC = kg / m² (clasificación OMS) · ICC = cintura/cadera (riesgo OMS: H > 0,90; M > 0,85)
 *   ICT = cintura/talla (Ashwell: < 0,40 bajo · 0,40–0,49 saludable · 0,50–0,59 riesgo · ≥ 0,60 riesgo alto)
 *   GEB Mifflin-St Jeor (1990) · GEB Harris-Benedict revisada (Roza y Shizgal, 1984) · GET = GEB × factor de actividad
 */

const WHO_URL = new URL('../data/who-lms.json', import.meta.url);
let whoCache = null;
/** Carga (una vez) las tablas de la OMS. @returns {Promise<Record<string, number[][]>>} */
export async function loadWho() {
  if (!whoCache) whoCache = fetch(WHO_URL).then((r) => { if (!r.ok) throw new Error('No se pudieron cargar las tablas de la OMS.'); return r.json(); });
  return whoCache;
}

export const num = (v) => {
  if (v == null || v === '') return null;
  const n = Number(String(v).replace(',', '.'));
  return Number.isFinite(n) ? n : null;
};
const fmt = (n, d = 1) => (n == null || !Number.isFinite(n) ? '' : n.toFixed(d));

/** Días cumplidos entre la fecha de nacimiento y la fecha de la consulta (ISO). */
export function ageDays(birthIso, onIso) {
  if (!birthIso) return null;
  const b = Date.parse(`${String(birthIso).slice(0, 10)}T00:00:00Z`);
  const o = Date.parse(`${String(onIso || new Date().toISOString()).slice(0, 10)}T00:00:00Z`);
  if (!Number.isFinite(b) || !Number.isFinite(o) || o < b) return null;
  return Math.round((o - b) / 86400000);
}
export const ageYears = (days) => (days == null ? null : days / 365.25);
/** «3 años 2 meses» o «7 meses» o «12 días» */
export function ageText(days) {
  if (days == null) return '';
  if (days < 31) return `${days} día${days === 1 ? '' : 's'}`;
  const m = Math.floor(days / 30.4375);
  if (m < 24) return `${m} mes${m === 1 ? '' : 'es'}`;
  const y = Math.floor(m / 12); const r = m % 12;
  return `${y} años${r ? ` ${r} mes${r === 1 ? '' : 'es'}` : ''}`;
}

/* ───────── Puntaje Z (OMS) ───────── */

/** LMS en x: tablas por día (paso 1, sin interpolar) o por mes / por cm (interpola linealmente). */
export function lmsAt(rows, x) {
  if (!rows || !rows.length) return null;
  const x0 = rows[0][0]; const x1 = rows[rows.length - 1][0];
  if (x < x0 || x > x1) return null;
  const step = rows.length > 1 ? rows[1][0] - rows[0][0] : 1;
  const i = (x - x0) / step;
  const lo = Math.floor(i + 1e-9); const hi = Math.min(lo + 1, rows.length - 1);
  const t = i - lo;
  if (t < 1e-9 || lo === hi) return { L: rows[lo][1], M: rows[lo][2], S: rows[lo][3] };
  const a = rows[lo]; const b = rows[hi];
  return { L: a[1] + (b[1] - a[1]) * t, M: a[2] + (b[2] - a[2]) * t, S: a[3] + (b[3] - a[3]) * t };
}

/** z = ((X/M)^L − 1)/(L·S); con «restricted» aplica la corrección OMS fuera de ±3 DE (indicadores de peso). */
export function zLms(X, { L, M, S }, restricted = false) {
  const z = Math.abs(L) < 1e-9 ? Math.log(X / M) / S : (Math.pow(X / M, L) - 1) / (L * S);
  if (!restricted || Math.abs(z) <= 3) return z;
  const sd = (k) => M * Math.pow(1 + L * S * k, 1 / L);
  if (z > 3) { const sd3 = sd(3); return 3 + (X - sd3) / (sd3 - sd(2)); }
  const sd3n = sd(-3); return -3 + (X - sd3n) / (sd(-2) - sd3n);
}

/**
 * Puntaje Z de un indicador OMS.
 * @param {object} who tablas (loadWho)
 * @param {'peso_edad'|'talla_edad'|'imc_edad'|'peso_talla'|'pc_edad'} ind
 * @param {'M'|'F'} sex
 * @param {number} days edad en días
 * @param {number} value medida (kg, cm o kg/m²)
 * @param {{lengthCm?: number}} [opt] para peso/talla: la longitud o talla (cm)
 * @returns {{z:number, ref:string}|{error:string}}
 */
export function whoZ(who, ind, sex, days, value, opt = {}) {
  if (sex !== 'M' && sex !== 'F') return { error: 'Registre el sexo del paciente (M o F) para calcular el puntaje Z.' };
  if (days == null) return { error: 'Registre la fecha de nacimiento del paciente para calcular el puntaje Z.' };
  if (value == null || value <= 0) return { error: '' };
  const months = days / 30.4375;
  let rows = null; let x = days; let restricted = true; let ref = 'OMS 2006';
  switch (ind) {
    case 'peso_edad':
      if (days <= 1856) rows = who[`wfa_${sex}_0_5`];
      else if (months <= 120) { rows = who[`wfa_${sex}_5_10`]; x = months; ref = 'OMS 2007'; }
      else return { error: 'Peso para la edad solo existe hasta los 10 años: use IMC para la edad.' };
      break;
    case 'talla_edad':
      restricted = false;
      if (days <= 1856) rows = who[`lhfa_${sex}_0_5`];
      else if (months <= 228) { rows = who[`hfa_${sex}_5_19`]; x = months; ref = 'OMS 2007'; }
      else return { error: 'La referencia de la OMS llega hasta los 19 años.' };
      break;
    case 'imc_edad':
      if (days <= 1856) rows = who[`bfa_${sex}_0_5`];
      else if (months <= 228) { rows = who[`bfa_${sex}_5_19`]; x = months; ref = 'OMS 2007'; }
      else return { error: 'La referencia de la OMS llega hasta los 19 años: use el IMC de adulto.' };
      break;
    case 'pc_edad':
      restricted = false;
      if (days <= 1856) rows = who[`hcfa_${sex}_0_5`];
      else return { error: 'El perímetro cefálico de la OMS llega hasta los 5 años.' };
      break;
    case 'peso_talla': {
      if (days > 1856) return { error: 'Peso para la talla de la OMS es para menores de 5 años: use IMC para la edad.' };
      const cm = opt.lengthCm;
      if (cm == null) return { error: '' };
      if (days < 731) { rows = who[`wfl_${sex}`]; x = Math.round(cm * 10) / 10; }
      else { rows = who[`wfh_${sex}`]; x = Math.round(cm * 10) / 10; }
      if (!lmsAt(rows, x)) return { error: days < 731 ? 'La longitud está fuera de la tabla OMS (45–110 cm).' : 'La talla está fuera de la tabla OMS (65–120 cm).' };
      break;
    }
    default: return { error: 'Indicador desconocido.' };
  }
  const lms = lmsAt(rows, x);
  if (!lms) return { error: 'La edad está fuera de la tabla de la OMS.' };
  return { z: zLms(value, lms, restricted), ref };
}

/**
 * Ajuste OMS de la medida de longitud/talla: menores de 2 años se miden acostados (longitud);
 * de 2 años en adelante, de pie (talla). Si se midió de la otra forma se corrige 0,7 cm.
 */
export function lengthForWho(cm, days, mode) {
  if (cm == null || days == null) return cm;
  if (days < 731 && mode === 'De pie') return cm + 0.7;
  if (days >= 731 && mode === 'Acostado') return cm - 0.7;
  return cm;
}

/** Clasificación OMS por indicador y puntaje Z. */
export function classifyZ(ind, z, days) {
  if (z == null || !Number.isFinite(z)) return '';
  const u5 = days != null && days <= 1856;
  switch (ind) {
    case 'talla_edad': return z < -3 ? 'Talla baja severa' : z < -2 ? 'Talla baja' : z > 3 ? 'Muy alto para la edad' : 'Talla adecuada';
    case 'peso_edad': return z < -3 ? 'Bajo peso severo' : z < -2 ? 'Bajo peso' : z > 1 ? 'Revisar con peso para la talla o IMC' : 'Peso adecuado';
    case 'pc_edad': return z < -2 ? 'Perímetro cefálico bajo (microcefalia)' : z > 2 ? 'Perímetro cefálico alto (macrocefalia)' : 'Normal';
    case 'peso_talla':
    case 'imc_edad':
      if (u5) return z < -3 ? 'Emaciación severa' : z < -2 ? 'Emaciación' : z > 3 ? 'Obesidad' : z > 2 ? 'Sobrepeso' : z > 1 ? 'Riesgo de sobrepeso' : 'Normal';
      return z < -3 ? 'Delgadez severa' : z < -2 ? 'Delgadez' : z > 2 ? 'Obesidad' : z > 1 ? 'Sobrepeso' : 'Normal';
    default: return '';
  }
}

/** Percentil a partir del puntaje Z (distribución normal estándar). */
export function percentile(z) {
  if (z == null || !Number.isFinite(z)) return null;
  // Aproximación de Abramowitz-Stegun 26.2.17 (error < 7.5e-8)
  const t = 1 / (1 + 0.2316419 * Math.abs(z));
  const d = 0.3989423 * Math.exp((-z * z) / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return (z > 0 ? 1 - p : p) * 100;
}

/* ───────── Adultos ───────── */
export const imc = (kg, cm) => (kg && cm ? kg / Math.pow(cm / 100, 2) : null);
export function imcClasif(v) {
  if (v == null) return '';
  return v < 18.5 ? 'Bajo peso' : v < 25 ? 'Normal' : v < 30 ? 'Sobrepeso' : v < 35 ? 'Obesidad grado I' : v < 40 ? 'Obesidad grado II' : 'Obesidad grado III';
}
export function iccClasif(v, sex) {
  if (v == null || !sex) return '';
  const lim = sex === 'M' ? 0.9 : sex === 'F' ? 0.85 : null;
  return lim == null ? '' : v > lim ? 'Riesgo cardiometabólico aumentado' : 'Sin riesgo aumentado';
}
export function ictClasif(v) {
  if (v == null) return '';
  return v < 0.4 ? 'Bajo' : v < 0.5 ? 'Saludable' : v < 0.6 ? 'Riesgo aumentado' : 'Riesgo alto';
}
export const ACTIVIDAD = { Sedentario: 1.2, Ligera: 1.375, Moderada: 1.55, Intensa: 1.725, 'Muy intensa': 1.9 };
export function gebMifflin(kg, cm, years, sex) {
  if (!kg || !cm || years == null || (sex !== 'M' && sex !== 'F')) return null;
  return 10 * kg + 6.25 * cm - 5 * years + (sex === 'M' ? 5 : -161);
}
export function gebHarris(kg, cm, years, sex) {
  if (!kg || !cm || years == null || (sex !== 'M' && sex !== 'F')) return null;
  return sex === 'M' ? 88.362 + 13.397 * kg + 4.799 * cm - 5.677 * years : 447.593 + 9.247 * kg + 3.098 * cm - 4.33 * years;
}

/**
 * Calcula todos los campos «calc» de una plantilla.
 * @param {{key:string, type:string, formula?:string}[]} fields
 * @param {Record<string,string>} v valores escritos
 * @param {{sex?:string, birth_date?:string}} patient
 * @param {string} encounterIso fecha de la consulta
 * @param {object|null} who tablas OMS (null si la plantilla no las necesita)
 * @returns {Record<string,string>} clave → texto a mostrar y guardar
 */
export function computeAll(fields, v, patient, encounterIso, who) {
  const sex = patient?.sex || null;
  const days = ageDays(patient?.birth_date, encounterIso);
  const years = ageYears(days);
  const kg = num(v.peso); const cmRaw = num(v.talla);
  const cm = lengthForWho(cmRaw, days, v.medicion);
  const cint = num(v.cintura); const cad = num(v.cadera);
  const bmi = imc(kg, cmRaw);
  const grasa = num(v.bia_grasa_pct);
  const out = {};
  const zTxt = (ind, value, opt) => {
    if (!who) return '';
    const r = whoZ(who, ind, sex, days, value, opt);
    if (r.error !== undefined) return r.error;
    const p = percentile(r.z);
    return `${r.z >= 0 ? '+' : ''}${r.z.toFixed(2)} DE · p${p < 1 ? '<1' : p > 99 ? '>99' : Math.round(p)} · ${classifyZ(ind, r.z, days)}`;
  };
  for (const f of fields) {
    if (f.type !== 'calc') continue;
    let val = '';
    switch (f.formula) {
      case 'edad': val = days == null ? 'Registre la fecha de nacimiento del paciente.' : ageText(days); break;
      case 'imc': val = bmi ? fmt(bmi, 1) : ''; break;
      case 'imc_clasif': val = bmi && years != null && years >= 19 ? imcClasif(bmi) : bmi && years != null && years < 19 ? 'Menor de 19 años: use IMC para la edad (puntaje Z)' : bmi ? imcClasif(bmi) : ''; break;
      case 'icc': { const r = cint && cad ? cint / cad : null; val = r ? `${fmt(r, 2)} · ${iccClasif(r, sex)}` : ''; break; }
      case 'ict': { const r = cint && cmRaw ? cint / cmRaw : null; val = r ? `${fmt(r, 2)} · ${ictClasif(r)}${years != null && years < 6 ? ' (en menores de 6 años, interpretar con cautela)' : ''}` : ''; break; }
      case 'masa_grasa_kg': val = kg && grasa != null ? fmt(kg * grasa / 100, 1) : ''; break;
      case 'masa_libre_grasa_kg': val = kg && grasa != null ? fmt(kg - kg * grasa / 100, 1) : ''; break;
      case 'geb_mifflin': { const g = gebMifflin(kg, cmRaw, years, sex); val = g ? `${Math.round(g)} kcal/día` : ''; break; }
      case 'geb_harris': { const g = gebHarris(kg, cmRaw, years, sex); val = g ? `${Math.round(g)} kcal/día` : ''; break; }
      case 'get': { const g = gebMifflin(kg, cmRaw, years, sex); const fa = ACTIVIDAD[v.actividad_fisica]; val = g && fa ? `${Math.round(g * fa)} kcal/día (Mifflin × ${fa})` : g ? 'Elija el nivel de actividad física' : ''; break; }
      case 'z_peso_edad': val = kg ? zTxt('peso_edad', kg) : ''; break;
      case 'z_talla_edad': val = cm ? zTxt('talla_edad', cm) : ''; break;
      case 'z_imc_edad': { const b = imc(kg, cm); val = b ? zTxt('imc_edad', b) : ''; break; }
      case 'z_peso_talla': val = kg && cm ? zTxt('peso_talla', kg, { lengthCm: cm }) : ''; break;
      case 'z_pc_edad': { const pc = num(v.perimetro_cefalico); val = pc ? zTxt('pc_edad', pc) : ''; break; }
      default: val = '';
    }
    out[f.key] = val;
  }
  return out;
}

/** ¿La plantilla necesita las tablas de la OMS? */
export const needsWho = (fields) => fields.some((f) => f.type === 'calc' && String(f.formula || '').startsWith('z_'));
