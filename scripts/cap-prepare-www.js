#!/usr/bin/env node
/**
 * SOFA · Prepara www/ para Capacitor: copia SOLO lo que debe ir dentro de la app nativa
 * (lo mismo que ya sirve GitHub Pages), dejando fuera node_modules, .git, supabase/, scripts/,
 * tests/, docs/ y cualquier otro archivo de desarrollo. GitHub Pages sigue sirviendo desde la
 * raíz del repo, sin cambios; www/ es solo para `npx cap sync`.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DEST = path.join(ROOT, 'www');

const ITEMS = [
  '404.html', 'index.html', 'login.html', 'portal.html', 'solicitud.html',
  'iter18.css', 'manifest.json', 'sw.js',
  'assets', 'css', 'js', 'vendor'
];

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src)) copyRecursive(path.join(src, entry), path.join(dest, entry));
  } else {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }
}

fs.rmSync(DEST, { recursive: true, force: true });
fs.mkdirSync(DEST, { recursive: true });

let copied = 0, faltantes = [];
for (const item of ITEMS) {
  const src = path.join(ROOT, item);
  if (!fs.existsSync(src)) { faltantes.push(item); continue; }
  copyRecursive(src, path.join(DEST, item));
  copied++;
}

if (faltantes.length) console.warn('cap-prepare-www: no se encontraron (se omiten):', faltantes.join(', '));
console.log(`cap-prepare-www: ${copied} elemento(s) copiados a www/`);
