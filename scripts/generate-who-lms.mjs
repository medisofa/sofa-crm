#!/usr/bin/env node
/**
 * SOFA · Genera js/data/who-lms.json con las tablas LMS de la OMS para el puntaje Z en niños.
 *
 * Procedencia (verificada el 20/11/2026 antes de usarla):
 *   · 0 a 5 años — Patrones de Crecimiento Infantil de la OMS (2006), tablas por día:
 *       paquete npm who-growth-standards@1.0.1 (datos generados desde who.int, sin edición manual).
 *   · 5 a 19 años — Referencia de Crecimiento OMS 2007, tablas por mes:
 *       paquete npm @pedi-growth/core@1.1.2 (cada cifra verificada contra la fuente según su NOTICE).
 *   · Validación: ancla OMS peso/edad al nacer (niño L 0.3487 M 3.3464 S 0.14602; niña L 0.3809 M 3.2322 S 0.14171),
 *     primera fila IMC/edad 5-19 (niño 61 m: L -0.7387 M 15.2641 S 0.0839), y concordancia entre ambos paquetes.
 *     Ver scripts/check-who-zscore.mjs.
 * Los datos de referencia son obra de la OMS (https://www.who.int/tools/child-growth-standards); este archivo solo
 * los reproduce para el cálculo. SOFA no está afiliada ni certificada por la OMS.
 *
 * Uso (en una carpeta aparte, nunca dentro del repositorio):
 *   mkdir /tmp/who && cd /tmp/who && npm init -y && npm i --ignore-scripts who-growth-standards@1.0.1 @pedi-growth/core@1.1.2
 *   node <repo>/scripts/generate-who-lms.mjs /tmp/who/node_modules <repo>/js/data/who-lms.json
 */
import fs from 'node:fs';
import path from 'node:path';

const [, , nm, outFile] = process.argv;
if (!nm || !outFile) { console.error('Uso: generate-who-lms.mjs <node_modules> <salida.json>'); process.exit(1); }
const A = await import(path.join(nm, 'who-growth-standards/dist/index.js'));
const pg = (f) => JSON.parse(fs.readFileSync(path.join(nm, '@pedi-growth/core/dist/data', f), 'utf8'));

const r = (v, d) => Number(v.toFixed(d));
const rowsA = (ind, sex) => {
  // Formato del paquete A: { xAxis, start, step, lms: [[L, M, S], ...] } → [x, L, M, S]
  const t = A.getTable(ind, sex);
  if (!t || !Array.isArray(t.lms)) throw new Error(`Formato de tabla desconocido para ${ind}`);
  return t.lms.map(([l, m, s], i) => [t.start + i * t.step, l, m, s]);
};
const rowsB = (f) => pg(f).map((o) => [o.age, o.L, o.M, o.S]);
const fix = (rows) => rows.map(([x, l, m, s]) => [r(x, 1), r(l, 4), r(m, 4), r(s, 5)]);

const out = {
  _fuente: 'OMS · Patrones de Crecimiento Infantil 2006 (0-5 años, por día) y Referencia 2007 (5-19 años, por mes). Generado por scripts/generate-who-lms.mjs.',
  _generado: new Date().toISOString().slice(0, 10),
  // clave: <indicador>_<sexo>_<tramo>; x = días (0-5) o meses (5-19) o cm (peso para longitud/talla)
};
for (const [sex, s] of [['male', 'M'], ['female', 'F']]) {
  out[`wfa_${s}_0_5`] = fix(rowsA('wfa', sex));          // peso para la edad, días 0-1856
  out[`lhfa_${s}_0_5`] = fix(rowsA('lhfa', sex));        // longitud/talla para la edad, días
  out[`bfa_${s}_0_5`] = fix(rowsA('bfa', sex));          // IMC para la edad, días
  out[`hcfa_${s}_0_5`] = fix(rowsA('hcfa', sex));        // perímetro cefálico para la edad, días
  out[`wfl_${s}`] = fix(rowsA('wfl', sex));              // peso para la longitud, cm 45-110
  out[`wfh_${s}`] = fix(rowsA('wfh', sex));              // peso para la talla, cm 65-120
  const g = s === 'M' ? 'boys' : 'girls';
  out[`bfa_${s}_5_19`] = fix(rowsB(`bfa-${g}-5-19.json`));   // meses 61-228
  out[`hfa_${s}_5_19`] = fix(rowsB(`hfa-${g}-5-19.json`));   // meses 61-228
  out[`wfa_${s}_5_10`] = fix(rowsB(`wfa-${g}-5-10.json`));   // meses 61-120
}
fs.writeFileSync(outFile, JSON.stringify(out));
console.log('Escrito', outFile, (fs.statSync(outFile).size / 1024).toFixed(0), 'KB');
for (const [k, v] of Object.entries(out)) if (Array.isArray(v)) console.log(k.padEnd(14), v.length, 'filas', JSON.stringify(v[0]), '…', JSON.stringify(v[v.length - 1]));
