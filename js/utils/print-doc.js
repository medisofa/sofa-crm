/** SOFA · 3.4 · Documento para imprimir o guardar en PDF (cartas de cobro, carpeta de negociación).
 *  Se abre la ventana en el mismo clic (si no, el navegador la bloquea) y luego se llena con nodos, sin innerHTML. */

const CSS = `body{font:14px/1.55 Georgia,'Times New Roman',serif;color:#111;margin:0;background:#fff}
main{max-width:760px;margin:0 auto;padding:32px 28px}h1{font:700 20px/1.3 system-ui,sans-serif;margin:0 0 4px}
h2{font:700 15px/1.3 system-ui,sans-serif;margin:22px 0 6px;border-bottom:1px solid #ccc;padding-bottom:4px}
.sub{color:#555;font:13px system-ui,sans-serif;margin:0 0 14px}.warn{background:#fff8c5;border:1px solid #9a6700;border-radius:8px;padding:8px 12px;font:13px system-ui,sans-serif;margin:0 0 14px}
pre{white-space:pre-wrap;font:inherit;margin:0}table{border-collapse:collapse;width:100%;font:12.5px system-ui,sans-serif;margin:6px 0}
th,td{border:1px solid #bbb;padding:5px 7px;text-align:left;vertical-align:top}th{background:#f2f4f7}td.r,th.r{text-align:right}
.big{font:700 22px system-ui,sans-serif;margin:6px 0}.bar{position:sticky;top:0;background:#1A365D;padding:10px;text-align:center}
.bar button{font:600 14px system-ui,sans-serif;padding:8px 16px;border-radius:8px;border:0;margin:0 4px;cursor:pointer}
@media print{.bar,.warn{display:none}main{padding:0}}`;

/** Llamar dentro del clic. Devuelve la ventana (o null si el navegador la bloqueó). */
export function openPrint() {
  const w = window.open('', '_blank');
  if (w) { try { w.opener = null; } catch (_) { /* sin efecto */ } w.document.title = 'Preparando documento…'; }
  return w;
}

/** blocks: [{ h: 'título' } | { p: 'texto' } | { pre: 'texto largo' } | { big: 'cifra' } | { table: { head: [...], rows: [[...]], right: [índices] } } | { warn: 'texto' }] */
export function fillPrint(w, title, sub, blocks) {
  if (!w) return false;
  const d = w.document;
  d.open(); d.write('<!doctype html><html lang="es"><head><meta charset="utf-8"><title></title></head><body></body></html>'); d.close();
  d.title = title;
  const el = (tag, attrs = {}, ...kids) => {
    const e = d.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) if (v != null) { if (k === 'class') e.className = v; else e.setAttribute(k, v); }
    for (const k of kids.flat()) if (k != null && k !== '') e.append(k.nodeType ? k : d.createTextNode(String(k)));
    return e;
  };
  const style = d.createElement('style'); style.textContent = CSS; d.head.append(style);
  const pr = el('button', { type: 'button' }, 'Imprimir o guardar en PDF'); pr.addEventListener('click', () => w.print());
  const cl = el('button', { type: 'button' }, 'Cerrar'); cl.addEventListener('click', () => w.close());
  const main = el('main', {}, el('h1', {}, title), sub ? el('p', { class: 'sub' }, sub) : null);
  for (const b of blocks || []) {
    if (b.h) main.append(el('h2', {}, b.h));
    else if (b.p) main.append(el('p', {}, b.p));
    else if (b.pre) main.append(el('pre', {}, b.pre));
    else if (b.big) main.append(el('div', { class: 'big' }, b.big));
    else if (b.warn) main.append(el('div', { class: 'warn' }, b.warn));
    else if (b.table) {
      const right = new Set(b.table.right || []);
      main.append(el('table', {}, el('thead', {}, el('tr', {}, b.table.head.map((x, i) => el('th', { class: right.has(i) ? 'r' : null }, x)))),
        el('tbody', {}, b.table.rows.map((r) => el('tr', {}, r.map((x, i) => el('td', { class: right.has(i) ? 'r' : null }, x)))))));
    }
  }
  d.body.append(el('div', { class: 'bar' }, pr, cl), main);
  return true;
}
