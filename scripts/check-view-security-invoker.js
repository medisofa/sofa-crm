#!/usr/bin/env node
/**
 * SOFA · Guardia de CI: toda vista pública nueva o recreada en una migración debe llevar
 * security_invoker, o un escape explícito.
 *
 * Por qué existe: dos veces en el mismo día (v_habilitation_cases y v_submissions) un
 * `CREATE OR REPLACE VIEW` que solo quería agregar columnas o un JOIN terminó revirtiendo
 * silenciosamente la vista a SECURITY DEFINER (privilegios de owner), reabriendo una fuga de
 * datos entre organizaciones ya corregida antes. Esto revisa cada migración SQL que cambia en el
 * push o PR y falla si define/recrea una vista en el esquema public sin la opción, para atraparlo
 * antes de que llegue a producción en vez de depender de auditar después.
 *
 * Escape explícito para una vista que de verdad no necesita invoker (p. ej. nunca se expone a
 * authenticated/anon): agregar en el mismo archivo un comentario
 *   -- security_invoker: no aplica, <motivo>
 */
const { execSync } = require('child_process');
const fs = require('fs');

const BASE_SHA = process.env.BASE_SHA;
const HEAD_SHA = process.env.HEAD_SHA || 'HEAD';

function changedMigrationFiles() {
  if (!BASE_SHA) {
    // Sin base conocida (primer commit, o ejecución local): revisa todo el directorio.
    return execSync('git ls-files supabase/migrations').toString().trim().split('\n').filter(Boolean);
  }
  try {
    const out = execSync(`git diff --name-only --diff-filter=ACM ${BASE_SHA} ${HEAD_SHA} -- supabase/migrations`).toString();
    return out.trim().split('\n').filter(Boolean);
  } catch (e) {
    console.error('No se pudo calcular el diff contra la base; revisando todo el directorio por seguridad.');
    return execSync('git ls-files supabase/migrations').toString().trim().split('\n').filter(Boolean);
  }
}

const VIEW_RE = /create\s+(or\s+replace\s+)?view\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z0-9_]+)/gi;
const files = changedMigrationFiles();
let failures = [];

for (const file of files) {
  if (!file.endsWith('.sql') || !fs.existsSync(file)) continue;
  const sql = fs.readFileSync(file, 'utf8');
  const hasEscape = /--\s*security_invoker:\s*no aplica/i.test(sql);
  if (hasEscape) continue;
  const hasInvokerOption = /security_invoker/i.test(sql);
  if (hasInvokerOption) continue;
  let m;
  const views = new Set();
  while ((m = VIEW_RE.exec(sql))) views.add(m[2]);
  if (views.size) failures.push({ file, views: [...views] });
}

if (failures.length) {
  console.error('\n✗ Vista(s) sin security_invoker en migraciones nuevas o modificadas:\n');
  for (const f of failures) {
    console.error(`  ${f.file}`);
    for (const v of f.views) console.error(`    - ${v}`);
  }
  console.error('\nAgrega `alter view public.<vista> set (security_invoker = true);` en el mismo archivo');
  console.error('(o justo después de crearla), o si de verdad no aplica agrega un comentario:');
  console.error('  -- security_invoker: no aplica, <motivo>\n');
  console.error('Contexto: dos veces el mismo día un CREATE OR REPLACE VIEW sin esto reabrió una');
  console.error('fuga real de datos entre organizaciones (v_habilitation_cases, v_submissions).\n');
  process.exit(1);
}

console.log(`✓ ${files.filter((f) => f.endsWith('.sql')).length} migración(es) revisada(s); ninguna vista pública sin security_invoker.`);
