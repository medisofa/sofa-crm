/** SOFA · Gráficos SVG livianos (sin librerías externas; respetan el tema claro/oscuro) */
import { html, raw, esc } from './dom.js';

const trim = (x) => x.replace(/\.0$/, '');
const short = (n) => { const v = Math.abs(Number(n) || 0); return v >= 1e6 ? `${trim((n / 1e6).toFixed(1))}M` : v >= 1e3 ? `${trim((n / 1e3).toFixed(v < 1e4 ? 1 : 0))}K` : `${Math.round(n)}`; };

/**
 * Barras verticales agrupadas.
 * labels: ['ene 2026', …]; series: [{ name, color, values: [..] }]
 */
export function barChart({ labels, series, height = 220, money = true }) {
  const W = 900, H = height, padL = 46, padB = 34, padT = 12, padR = 8;
  const max = Math.max(1, ...series.flatMap((s) => s.values.map((v) => Number(v) || 0)));
  const nice = Math.pow(10, Math.floor(Math.log10(max))); const top = Math.ceil(max / nice) * nice;
  const cw = (W - padL - padR) / Math.max(1, labels.length); const bw = Math.min(28, (cw * 0.75) / series.length);
  const y = (v) => padT + (H - padT - padB) * (1 - (Number(v) || 0) / top);
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => top * f);
  let svg = `<svg viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="${esc(series.map((s) => s.name).join(' vs '))} por mes" style="display:block;max-height:${H}px">`;
  ticks.forEach((t) => { svg += `<line x1="${padL}" x2="${W - padR}" y1="${y(t)}" y2="${y(t)}" stroke="var(--line)"/><text x="${padL - 6}" y="${y(t) + 4}" text-anchor="end" font-size="10" fill="var(--ink-3)">${money ? 'RD$' : ''}${short(t)}</text>`; });
  labels.forEach((l, i) => {
    const x0 = padL + i * cw + (cw - bw * series.length) / 2;
    series.forEach((s, k) => {
      const v = Number(s.values[i]) || 0; const yy = y(v);
      svg += `<rect x="${x0 + k * bw}" y="${yy}" width="${bw - 2}" height="${Math.max(0, H - padB - yy)}" rx="2" fill="${s.color}"><title>${esc(s.name)} · ${esc(l)}: ${money ? 'RD$' : ''}${esc(Number(v).toLocaleString('es-DO'))}</title></rect>`;
    });
    svg += `<text x="${padL + i * cw + cw / 2}" y="${H - padB + 16}" text-anchor="middle" font-size="10.5" fill="var(--ink-2)">${esc(l)}</text>`;
  });
  svg += '</svg>';
  const legend = series.map((s) => `<span style="display:inline-flex;align-items:center;gap:6px;margin-right:14px"><i style="width:10px;height:10px;border-radius:2px;background:${s.color};display:inline-block"></i>${esc(s.name)}</span>`).join('');
  return html`<div class="small" style="margin-bottom:6px">${raw(legend)}</div>${raw(svg)}`;
}

/** Barras horizontales con etiqueta y valor (listas cortas: aging, ARS, motivos) */
export function hBars(rows, { money: isMoney = true, color = 'var(--navy-2)', fmt } = {}) {
  const max = Math.max(1, ...rows.map((r) => Number(r.value) || 0));
  return html`${rows.map((r) => html`<div style="margin:8px 0"><div class="small" style="display:flex;justify-content:space-between;gap:10px"><span>${r.label}</span><b>${fmt ? fmt(r.value) : isMoney ? `RD$${Number(r.value || 0).toLocaleString('es-DO', { maximumFractionDigits: 0 })}` : r.value}</b></div>
    <div style="height:8px;background:var(--surface-2);border-radius:4px;overflow:hidden;margin-top:4px"><div style="height:100%;width:${Math.max(r.value > 0 ? 2 : 0, Math.round((100 * (Number(r.value) || 0)) / max))}%;background:${r.color || color}"></div></div></div>`)}`;
}

/** Barra de progreso contra una meta */
export function progress(value, target, color = 'var(--ok)') {
  const pct = target > 0 ? Math.min(100, Math.round((100 * value) / target)) : 0;
  return html`<div style="height:12px;background:var(--surface-2);border-radius:6px;overflow:hidden"><div style="height:100%;width:${pct}%;background:${color}"></div></div><div class="small muted" style="margin-top:4px">${pct}% de la meta</div>`;
}
