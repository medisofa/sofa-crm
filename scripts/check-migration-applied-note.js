#!/usr/bin/env node
/**
 * SOFA · Guardia de CI: toda migración nueva en supabase/migrations/ debe declarar en su
 * cabecera que ya fue aplicada en producción (la regla de CLAUDE.md §2).
 *
 * Por qué existe: SOFA no tiene un pipeline que aplique automáticamente las migraciones
 * cuando se fusiona un PR. Si alguien fusiona primero el .sql y aplica después (o se
 * olvida), main queda con código que llama a RPCs/tablas que no existen en producción
 * y la pantalla afectada rompe silenciosamente.
 *
 * Qué busca: en cada archivo nuevo o modificado dentro de supabase/migrations/, al menos
 * una de estas frases dentro de las primeras 30 líneas (comentarios SQL):
 *
 *   «ya aplicado en producción»
 *   «ya aplicada en producción»
 *   «Ya aplicado en producción»          (mayúsculas indiferentes)
 *   «mcp__Supabase__apply_migration»     (traza directa del MCP)
 *
 * Cómo escapar un caso legítimo (p. ej. una migración puramente de re-formato o un seed
 * que no toca schema): agregar en la cabecera
 *
 *   -- aplicada-primero: no aplica, <motivo>
 *
 * El escape queda registrado en el PR y en el historial del archivo.
 */
const { execSync } = require('child_process');
const fs = require('fs');

const BASE_SHA = process.env.BASE_SHA;
const HEAD_SHA = process.env.HEAD_SHA || 'HEAD';

function changedMigrationFiles() {
  if (!BASE_SHA) {
    // Sin base: revisa solo los archivos del commit HEAD.
    return execSync(`git show --name-only --format= --diff-filter=ACM ${HEAD_SHA} -- supabase/migrations`)
      .toString().trim().split('\n').filter(Boolean);
  }
  try {
    const out = execSync(
      `git diff --name-only --diff-filter=A ${BASE_SHA} ${HEAD_SHA} -- supabase/migrations`
    ).toString();
    // Solo archivos AGREGADOS (A). Modificaciones a un archivo ya aplicado son ruido.
    return out.trim().split('\n').filter(Boolean);
  } catch (e) {
    console.error('No se pudo calcular el diff contra la base; revisando todo el directorio.');
    return execSync('git ls-files supabase/migrations').toString().trim().split('\n').filter(Boolean);
  }
}

const APPLIED_RE = /ya\s+aplicad[ao]\s+en\s+producci[oó]n|mcp__Supabase__apply_migration/i;
const ESCAPE_RE = /aplicada-primero:\s*no\s+aplica/i;

const files = changedMigrationFiles();
let failures = [];
let passed = [];

for (const f of files) {
  if (!f.endsWith('.sql')) continue;
  let content;
  try { content = fs.readFileSync(f, 'utf8'); }
  catch (_) { continue; }                     // archivo eliminado en HEAD: ignorar
  const header = content.split('\n').slice(0, 30).join('\n');
  if (ESCAPE_RE.test(header)) { passed.push(`  escape explícito · ${f}`); continue; }
  if (APPLIED_RE.test(header)) { passed.push(`  aplicada en producción · ${f}`); continue; }
  failures.push(f);
}

if (passed.length) {
  console.log('Migraciones nuevas válidas:');
  for (const line of passed) console.log(line);
}

if (failures.length) {
  console.error('');
  console.error('Estas migraciones nuevas no declaran que ya fueron aplicadas en producción:');
  for (const f of failures) console.error(`  · ${f}`);
  console.error('');
  console.error('Antes de fusionar este PR:');
  console.error('  1) Aplicar el SQL en producción (mcp__Supabase__apply_migration o dashboard).');
  console.error('  2) Agregar en la cabecera del archivo, dentro de las primeras 30 líneas:');
  console.error('       -- Ya aplicado en producción (mcp__Supabase__apply_migration YYYY-MM-DD).');
  console.error('  3) Para un caso legítimo que no aplica en vivo (seed de desarrollo, re-formato):');
  console.error('       -- aplicada-primero: no aplica, <motivo>');
  console.error('');
  console.error('La regla vive en CLAUDE.md §2. Este guard evita que main referencie RPCs/tablas');
  console.error('que no existen en Supabase.');
  process.exit(1);
}

console.log(`Revisadas ${files.length} archivo(s) en supabase/migrations/. Todo en regla.`);
