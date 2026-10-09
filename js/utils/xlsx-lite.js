/** SOFA · 2.2 · Lector mínimo de Excel (.xlsx) y CSV, sin librerías externas.
 *  Un .xlsx es un ZIP con XML: se descomprime con DecompressionStream (navegador) y se lee la PRIMERA hoja.
 *  Devuelve una matriz de filas (arreglos de texto). Las fechas de Excel (números de serie) se convierten con excelDate(). */

const td = new TextDecoder('utf-8');

async function inflateRaw(bytes) {
  const ds = new DecompressionStream('deflate-raw');
  const out = new Response(new Blob([bytes]).stream().pipeThrough(ds));
  return new Uint8Array(await out.arrayBuffer());
}

/** Lee las entradas de un ZIP (directorio central) y devuelve { nombre: () => Promise<Uint8Array> } */
function zipEntries(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) { if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; } }
  if (eocd < 0) throw new Error('El archivo no es un Excel válido (.xlsx). Ábralo en Excel y guárdelo de nuevo como .xlsx o como CSV.');
  const count = dv.getUint16(eocd + 10, true); let p = dv.getUint32(eocd + 16, true);
  const files = {};
  for (let k = 0; k < count; k++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break;
    const method = dv.getUint16(p + 10, true), csize = dv.getUint32(p + 20, true);
    const nlen = dv.getUint16(p + 28, true), elen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true), off = dv.getUint32(p + 42, true);
    const name = td.decode(buf.subarray(p + 46, p + 46 + nlen));
    files[name] = async () => {
      const ln = dv.getUint16(off + 26, true), le = dv.getUint16(off + 28, true);
      const data = buf.subarray(off + 30 + ln + le, off + 30 + ln + le + csize);
      if (method === 0) return data;
      if (method === 8) return inflateRaw(data);
      throw new Error('El Excel usa una compresión no compatible. Guárdelo como CSV e intente de nuevo.');
    };
    p += 46 + nlen + elen + clen;
  }
  return files;
}

const colIndex = (ref) => { let n = 0; for (const ch of ref.replace(/\d+/g, '')) n = n * 26 + (ch.charCodeAt(0) - 64); return n - 1; };
const xmlText = (el) => el ? el.textContent : '';

export async function readXlsx(file) {
  if (typeof DecompressionStream === 'undefined') throw new Error('Su navegador no puede leer Excel. Use Chrome o Edge actualizados, o guarde el archivo como CSV.');
  const buf = new Uint8Array(await file.arrayBuffer());
  const files = zipEntries(buf);
  const parse = async (name) => (files[name] ? new DOMParser().parseFromString(td.decode(await files[name]()), 'application/xml') : null);
  const shared = [];
  const ss = await parse('xl/sharedStrings.xml');
  if (ss) for (const si of ss.getElementsByTagName('si')) shared.push([...si.getElementsByTagName('t')].map(xmlText).join(''));
  // Primera hoja según workbook.xml (por si no se llama sheet1)
  let sheetPath = 'xl/worksheets/sheet1.xml';
  const wb = await parse('xl/workbook.xml'); const rels = await parse('xl/_rels/workbook.xml.rels');
  const first = wb?.getElementsByTagName('sheet')[0];
  if (first && rels) {
    const rid = first.getAttribute('r:id') || first.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id');
    const rel = [...rels.getElementsByTagName('Relationship')].find((r) => r.getAttribute('Id') === rid);
    if (rel) sheetPath = 'xl/' + rel.getAttribute('Target').replace(/^\/?xl\//, '').replace(/^\//, '');
  }
  const sh = await parse(sheetPath);
  if (!sh) throw new Error('No se encontró la hoja del Excel. Verifique que el archivo tenga datos en la primera hoja.');
  const rows = [];
  for (const row of sh.getElementsByTagName('row')) {
    const r = [];
    for (const c of row.getElementsByTagName('c')) {
      const t = c.getAttribute('t'); const i = colIndex(c.getAttribute('r') || 'A');
      let v = xmlText(c.getElementsByTagName('v')[0]);
      if (t === 's') v = shared[Number(v)] ?? '';
      else if (t === 'inlineStr') v = [...c.getElementsByTagName('t')].map(xmlText).join('');
      else if (t === 'b') v = v === '1' ? 'VERDADERO' : 'FALSO';
      r[i] = String(v ?? '').trim();
    }
    rows.push(Array.from(r, (x) => x ?? ''));
  }
  return rows.filter((r) => r.some((x) => x !== ''));
}

/** CSV / TSV (separador ; , o tabulador) con comillas */
export function readDelimited(text) {
  const clean = text.replace(/^﻿/, '');
  const firstLine = clean.split(/\r?\n/)[0] || '';
  const sep = firstLine.includes('\t') ? '\t' : (firstLine.split(';').length >= firstLine.split(',').length ? ';' : ',');
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    if (q) { if (ch === '"') { if (clean[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += ch; continue; }
    if (ch === '"') q = true;
    else if (ch === sep) { row.push(cell.trim()); cell = ''; }
    else if (ch === '\n') { row.push(cell.trim()); rows.push(row); row = []; cell = ''; }
    else if (ch !== '\r') cell += ch;
  }
  if (cell !== '' || row.length) { row.push(cell.trim()); rows.push(row); }
  return rows.filter((r) => r.some((x) => x !== ''));
}

/** Lee .xlsx, .csv o .txt y devuelve las filas */
export async function readTable(file) {
  if (!file) throw new Error('Elija un archivo.');
  if (file.size > 15 * 1024 * 1024) throw new Error('El archivo pasa de 15 MB. Divídalo e intente de nuevo.');
  if (/\.xlsx$/i.test(file.name)) return readXlsx(file);
  if (/\.xls$/i.test(file.name)) throw new Error('El formato .xls (Excel 97-2003) no se puede leer. En Excel use «Guardar como» → Libro de Excel (.xlsx) o CSV.');
  return readDelimited(await file.text());
}

/** Número de serie de Excel (días desde 1899-12-30) → DD/MM/AAAA; cualquier otro texto se devuelve igual */
export function excelDate(v) {
  const s = String(v ?? '').trim();
  if (/^\d{4,5}(\.\d+)?$/.test(s)) {
    const n = Number(s); if (n > 20000 && n < 80000) {
      const d = new Date(Date.UTC(1899, 11, 30) + Math.floor(n) * 86400000);
      return `${String(d.getUTCDate()).padStart(2, '0')}/${String(d.getUTCMonth() + 1).padStart(2, '0')}/${d.getUTCFullYear()}`;
    }
  }
  return s;
}

/** Normaliza un encabezado para compararlo (sin tildes, minúsculas, sin signos) */
export const normHead = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/** Busca en la primera fila los encabezados conocidos. aliases: { campo: ['alias1', ...] } → { campo: índice } */
export function detectColumns(head, aliases) {
  const h = head.map(normHead); const map = {};
  for (const [k, al] of Object.entries(aliases)) {
    const i = h.findIndex((x) => al.some((a) => x === a || x.startsWith(a + ' ') || x.endsWith(' ' + a)));
    if (i >= 0) map[k] = i;
  }
  return map;
}
