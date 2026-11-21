#!/usr/bin/env node
/**
 * SOFA · Verificación del puntaje Z de js/utils/antropometria.js contra dos paquetes independientes de la OMS.
 * Uso:  node scripts/check-who-zscore.mjs /tmp/who/node_modules   (ver scripts/generate-who-lms.mjs)
 * Sale con código 1 si alguna diferencia supera la tolerancia.
 *
 * Hallazgo (20/11/2026): who-growth-standards@1.0.1 NO aplica la corrección de la OMS fuera de ±3 DE en los
 * indicadores de peso (devuelve el LMS sin corregir). Por eso, cuando |z| > 3 en un indicador de peso, la
 * referencia es @pedi-growth/core, que sí la aplica. Las tablas LMS de ambos paquetes coinciden.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const nm = process.argv[2];
if (!nm) { console.error('Uso: check-who-zscore.mjs <node_modules>'); process.exit(1); }
const here = path.dirname(fileURLToPath(import.meta.url));
const who = JSON.parse(fs.readFileSync(path.join(here, '../js/data/who-lms.json'), 'utf8'));
const { whoZ } = await import(path.join(here, '../js/utils/antropometria.js'));
const A = await import(path.join(nm, 'who-growth-standards/dist/index.js'));
const B = await import(path.join(nm, '@pedi-growth/core/dist/index.js'));

let seed = 20261120; const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const pick = (a, b) => a + (b - a) * rnd();
const res = { casos: 0, extremos: 0, maxDifA: 0, maxDifB: 0, fallos: [] };
const TOL_A = 0.001;   // A no redondea
const TOL_B = 0.006;   // B redondea a 2 decimales
const sexes = [['M', 'male'], ['F', 'female']];

// 0-5 años contra A (por día) — incluye valores extremos para probar la corrección > ±3 DE
for (let i = 0; i < 4000; i++) {
  const [s, sx] = sexes[i % 2]; const d = Math.floor(pick(0, 1856));
  const casos = [
    ['peso_edad', A.weightForAge(1, { sex: sx, ageDays: d }) && pick(1.5, 30), (v) => A.weightForAge(v, { sex: sx, ageDays: d }).zScore],
    ['talla_edad', pick(42, 125), (v) => A.heightForAge(v, { sex: sx, ageDays: d }).zScore],
    ['imc_edad', pick(9, 26), (v) => A.bmiForAge(v, { sex: sx, ageDays: d }).zScore],
    ['pc_edad', pick(30, 55), (v) => A.headCircumferenceForAge(v, { sex: sx, ageDays: d }).zScore],
  ];
  for (const [ind, v, fa] of casos) {
    const mine = whoZ(who, ind, s, d, v); if (mine.error) continue;
    const peso = ind === 'peso_edad' || ind === 'imc_edad';
    if (peso && Math.abs(mine.z) > 3) {   // extremo: referencia = B (aplica la corrección OMS)
      const indB = ind === 'peso_edad' ? 'weight-for-age' : 'bmi-for-age';
      let rb; try { rb = (await B.calculateZScore({ indicator: indB, sex: sx, ageInDays: d, measurement: v })).zScore; } catch { continue; }
      const dif = Math.abs(mine.z - rb); res.casos++; res.extremos++; res.maxDifB = Math.max(res.maxDifB, dif);
      if (dif > TOL_B) res.fallos.push({ ind, s, d, v: +v.toFixed(3), mine: +mine.z.toFixed(4), B: rb });
      continue;
    }
    let ref; try { ref = fa(v); } catch { continue; }
    const dif = Math.abs(mine.z - ref); res.casos++; res.maxDifA = Math.max(res.maxDifA, dif);
    if (dif > TOL_A) res.fallos.push({ ind, s, d, v: +v.toFixed(3), mine: +mine.z.toFixed(4), A: +ref.toFixed(4) });
  }
  // peso para longitud (< 2 a) / talla (≥ 2 a)
  const cm = d < 731 ? Math.round(pick(46, 109) * 10) / 10 : Math.round(pick(66, 119) * 10) / 10;
  const kg = pick(2, 25);
  const mine = whoZ(who, 'peso_talla', s, d, kg, { lengthCm: cm });
  if (!mine.error) {
    let ref;
    if (Math.abs(mine.z) > 3) {   // extremo: B
      try { ref = (await B.calculateZScore({ indicator: d < 731 ? 'weight-for-length' : 'weight-for-height', sex: sx, ageInDays: d, measurement: kg, lengthHeight: cm })).zScore; } catch { ref = null; }
      if (ref != null) { const dif = Math.abs(mine.z - ref); res.casos++; res.extremos++; res.maxDifB = Math.max(res.maxDifB, dif);
        if (dif > TOL_B) res.fallos.push({ ind: 'peso_talla(B)', s, d, cm, kg: +kg.toFixed(3), mine: +mine.z.toFixed(4), B: ref }); }
      ref = undefined;
    } else { try { ref = (d < 731 ? A.weightForLength(kg, cm, sx) : A.weightForHeight(kg, cm, sx)).zScore; } catch { ref = null; } }
    if (ref != null) { const dif = Math.abs(mine.z - ref); res.casos++; res.maxDifA = Math.max(res.maxDifA, dif);
      if (dif > TOL_A) res.fallos.push({ ind: 'peso_talla', s, d, cm, kg: +kg.toFixed(3), mine: +mine.z.toFixed(4), A: +ref.toFixed(4) }); }
  }
}
// 5-19 años contra B (por mes; B interpola por días)
for (let i = 0; i < 3000; i++) {
  const [s, sx] = sexes[i % 2]; const d = Math.floor(pick(1857, 6939));
  for (const [ind, indB, v] of [['imc_edad', 'bmi-for-age', pick(11, 38)], ['talla_edad', 'length-height-for-age', pick(95, 195)], ['peso_edad', 'weight-for-age', pick(12, 60)]]) {
    const mine = whoZ(who, ind, s, d, v); if (mine.error) continue;
    let ref; try { ref = (await B.calculateZScore({ indicator: indB, sex: sx, ageInDays: d, measurement: v })).zScore; } catch { continue; }
    if (ref == null) continue;
    const dif = Math.abs(mine.z - ref); res.casos++; res.maxDifB = Math.max(res.maxDifB, dif);
    if (dif > TOL_B) res.fallos.push({ ind, s, d, v: +v.toFixed(3), mine: +mine.z.toFixed(4), B: ref });
  }
}
console.log(`Casos comparados: ${res.casos} (de ellos ${res.extremos} extremos > ±3 DE contra @pedi-growth/core)`);
console.log(`Diferencia máxima vs who-growth-standards (0-5 años): ${res.maxDifA.toExponential(2)}  (tolerancia ${TOL_A})`);
console.log(`Diferencia máxima vs @pedi-growth/core (5-19 años):   ${res.maxDifB.toFixed(4)}  (tolerancia ${TOL_B})`);
console.log(`Fuera de tolerancia: ${res.fallos.length}`);
if (res.fallos.length) { console.log(JSON.stringify(res.fallos.slice(0, 12), null, 1)); process.exit(1); }
console.log('OK · el puntaje Z de SOFA coincide con ambos paquetes de la OMS.');
