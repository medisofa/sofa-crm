#!/usr/bin/env node
/**
 * SOFA · Static import/export resolver.
 *
 * Objetivo: atrapar en CI (y localmente antes del push) regresiones del tipo
 * del PR #146 — un servicio reescrito que borra exports que medio frontend
 * sigue importando, causando «does not provide an export named X» en producción.
 *
 * Algoritmo (análisis estático, sin ejecutar código):
 *   1. Recorre todos los `.js` bajo `js/`.
 *   2. Para cada archivo, parsea sus `import … from './rel-path'` con nombres.
 *   3. Para cada import nombrado, abre el archivo destino y busca si ese
 *      identificador aparece como `export` (`export function X`,
 *      `export const X`, `export { X, Y }`, `export { Y as X }`, etc.).
 *   4. Si no aparece, reporta y falla con exit code 1.
 *
 * No evalúa JS: evita todos los falsos positivos de esbuild/Node con
 * template literals anidados, y evita necesitar DOM. Solo analiza la
 * clase de error que quiere prevenir.
 *
 * Dependencias: ninguna. Es Node 20+ puro.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const JS_ROOT = path.join(ROOT, 'js');

/** Lista recursiva de archivos `.js` bajo `dir`. */
function listJs(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listJs(full));
    else if (entry.isFile() && entry.name.endsWith('.js')) out.push(full);
  }
  return out;
}

/** Quita comentarios /* * / y // para que no entren falsas firmas en el análisis. */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');   // conserva http://… en strings, no es perfecto pero suficiente
}

/**
 * Lee las declaraciones `export` del archivo y devuelve un Set con los nombres
 * exportados. Cubre las formas del repo:
 *   export function X(…)
 *   export async function X(…)
 *   export const X = …
 *   export let X = …
 *   export var X = …
 *   export class X …
 *   export { X, Y, Z as W }
 *   export default …  (marcado como 'default')
 *   export * from '…'  (re-exports delegados — se recursa al origen)
 * No intenta ejecutar el archivo.
 */
function exportsOf(filePath, visited = new Set()) {
  if (visited.has(filePath)) return new Set();
  visited.add(filePath);
  if (!fs.existsSync(filePath)) return new Set();
  const src = stripComments(fs.readFileSync(filePath, 'utf8'));
  const out = new Set();

  // Declaraciones directas: export (async)? function/const/let/var/class X
  const decl = /export\s+(?:async\s+)?(?:function\*?|const|let|var|class)\s+([A-Za-z_$][\w$]*)/g;
  for (const m of src.matchAll(decl)) out.add(m[1]);

  // Bloques: export { X, Y as Z, W };
  const block = /export\s*\{\s*([^}]+?)\s*\}(?:\s*;)?(?!\s*from)/g;
  for (const m of src.matchAll(block)) {
    for (const piece of m[1].split(',')) {
      const parts = piece.trim().split(/\s+as\s+/);
      const name = (parts[1] || parts[0]).trim();
      if (name) out.add(name);
    }
  }

  // Re-exports: export { X, Y as Z } from './otro.js'
  const reNamed = /export\s*\{\s*([^}]+?)\s*\}\s*from\s*['"]([^'"]+)['"]/g;
  for (const m of src.matchAll(reNamed)) {
    const origin = resolveRel(filePath, m[2]);
    const originExports = origin ? exportsOf(origin, visited) : new Set();
    for (const piece of m[1].split(',')) {
      const parts = piece.trim().split(/\s+as\s+/);
      const nameIn = parts[0].trim();
      const nameOut = (parts[1] || parts[0]).trim();
      if (nameOut && (originExports.has(nameIn) || nameIn === '*')) out.add(nameOut);
    }
  }

  // export * from './otro.js'  — todo lo del origen se re-exporta.
  const reStar = /export\s*\*\s*from\s*['"]([^'"]+)['"]/g;
  for (const m of src.matchAll(reStar)) {
    const origin = resolveRel(filePath, m[1]);
    if (origin) for (const n of exportsOf(origin, visited)) out.add(n);
  }

  // export default …
  if (/export\s+default\b/.test(src)) out.add('default');

  return out;
}

/** Devuelve la ruta absoluta a la que apunta un specifier relativo, o null si no es relativo. */
function resolveRel(fromFile, spec) {
  // Strip query string (`?v=xxx`) — SOFA usa versionado estilo `?v=5.30.0`
  const clean = spec.replace(/\?[^'"]*$/, '');
  if (!clean.startsWith('./') && !clean.startsWith('../') && !clean.startsWith('/')) return null;
  let abs = path.resolve(path.dirname(fromFile), clean);
  if (fs.existsSync(abs) && fs.statSync(abs).isFile()) return abs;
  if (fs.existsSync(abs + '.js')) return abs + '.js';
  const indexCandidate = path.join(abs, 'index.js');
  if (fs.existsSync(indexCandidate)) return indexCandidate;
  return null;
}

/**
 * Parsea los `import` de un archivo. Devuelve una lista de
 *   { origin, names: ['X', ...], defaultName: 'X' | null, namespace: 'X' | null }
 * Solo imports de rutas relativas. Dynamic import() con template literal se ignora
 * (no se puede resolver estáticamente, y lo cubre el import estático de cada módulo).
 */
function importsOf(filePath) {
  const src = stripComments(fs.readFileSync(filePath, 'utf8'));
  const out = [];
  // import X from './y.js';  |  import { a, b as c } from './y.js';  |  import * as X from './y.js';
  // Puede combinar: import X, { a } from './y.js';   import X, * as Y from './y.js';
  const re = /import\s+(?:([A-Za-z_$][\w$]*)\s*,\s*)?(?:(\*\s+as\s+[A-Za-z_$][\w$]*)|(\{[^}]*\}))?\s*(?:,\s*(\*\s+as\s+[A-Za-z_$][\w$]*)|,\s*(\{[^}]*\}))?\s*from\s*['"]([^'"]+)['"]/g;
  // Más simple: separo los dos casos.
  const reDefault = /import\s+([A-Za-z_$][\w$]*)\s+from\s*['"]([^'"]+)['"]/g;
  const reNs = /import\s+\*\s+as\s+([A-Za-z_$][\w$]*)\s+from\s*['"]([^'"]+)['"]/g;
  const reNamed = /import\s+(?:([A-Za-z_$][\w$]*)\s*,\s*)?\{\s*([^}]+?)\s*\}\s+from\s*['"]([^'"]+)['"]/g;
  const reSide = /import\s*['"]([^'"]+)['"]/g;

  for (const m of src.matchAll(reDefault)) {
    const origin = resolveRel(filePath, m[2]);
    if (!origin) continue;
    out.push({ origin, names: [], defaultName: m[1], namespace: null, raw: m[0] });
  }
  for (const m of src.matchAll(reNs)) {
    const origin = resolveRel(filePath, m[2]);
    if (!origin) continue;
    out.push({ origin, names: [], defaultName: null, namespace: m[1], raw: m[0] });
  }
  for (const m of src.matchAll(reNamed)) {
    const origin = resolveRel(filePath, m[3]);
    if (!origin) continue;
    const names = m[2].split(',').map((p) => {
      const parts = p.trim().split(/\s+as\s+/);
      return parts[0].trim();
    }).filter(Boolean);
    out.push({ origin, names, defaultName: m[1] || null, namespace: null, raw: m[0] });
  }
  for (const m of src.matchAll(reSide)) {
    const origin = resolveRel(filePath, m[1]);
    if (!origin) continue;
    out.push({ origin, names: [], defaultName: null, namespace: null, raw: m[0] });
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────────────
// Ejecución
// ──────────────────────────────────────────────────────────────────────────────

const files = listJs(JS_ROOT);
const exportsCache = new Map();
const problems = [];

for (const file of files) {
  for (const imp of importsOf(file)) {
    let exps = exportsCache.get(imp.origin);
    if (!exps) { exps = exportsOf(imp.origin); exportsCache.set(imp.origin, exps); }
    if (imp.defaultName && !exps.has('default')) {
      problems.push({ file, origin: imp.origin, name: 'default', detail: `default import ${imp.defaultName}` });
    }
    for (const name of imp.names) {
      if (!exps.has(name)) problems.push({ file, origin: imp.origin, name });
    }
  }
}

const rel = (p) => path.relative(ROOT, p);

if (problems.length) {
  console.error(`\n❌ ${problems.length} import(s) rotos detectados:\n`);
  for (const p of problems) {
    console.error(`  ${rel(p.file)}`);
    console.error(`    import { ${p.name} } from '${rel(p.origin)}'`);
    console.error(`    → ese archivo no exporta «${p.name}»${p.detail ? ` (${p.detail})` : ''}\n`);
  }
  console.error(`Total: ${files.length} archivos analizados, ${problems.length} problemas.`);
  process.exit(1);
}

console.log(`✅ Imports/exports OK · ${files.length} archivos analizados.`);
