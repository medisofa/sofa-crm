/** SOFA · Barra de filtros común (período, cliente, ARS) para dashboard, aging y reportes */
import { html, render as paint, $ } from './dom.js';
import { opt } from './ui.js';
import { listArs } from '../services/catalog.js';
import { clientOptions, defaultRange } from '../services/bi.js';
import { isStaff } from './permissions.js';

/**
 * Pinta la barra en `el` y llama onChange(state) al cambiar.
 * opts: { period: true|false, months: 6 }
 */
export async function filterBar(el, ctx, onChange, { period = true, months = 6 } = {}) {
  const st = { ...defaultRange(months), orgId: '', arsId: '' };
  const staff = isStaff(ctx.role);
  const [ars, clients] = await Promise.all([listArs().catch(() => []), staff ? clientOptions().catch(() => []) : Promise.resolve([])]);
  const max = defaultRange(1).to;
  paint(el, html`<div class="toolbar no-print" role="group" aria-label="Filtros">
    ${period ? html`<label class="small" for="fFrom">Desde</label><input class="input" type="month" id="fFrom" value="${st.from}" max="${max}" style="width:auto">
      <label class="small" for="fTo">Hasta</label><input class="input" type="month" id="fTo" value="${st.to}" max="${max}" style="width:auto">` : ''}
    ${staff ? html`<label class="sr-only" for="fOrg">Cliente</label><select class="input" id="fOrg" style="width:auto;max-width:260px"><option value="">Todos los clientes</option>${clients.map((c) => opt(c.id, c.legal_name))}</select>` : ''}
    <label class="sr-only" for="fArs">ARS</label><select class="input" id="fArs" style="width:auto"><option value="">Todas las ARS</option>${ars.map((a) => opt(a.id, a.name))}</select>
  </div>`);
  const fire = () => {
    if (period) {
      st.from = $('#fFrom', el).value || st.from; st.to = $('#fTo', el).value || st.to;
      if (st.from > st.to) { const t = st.from; st.from = st.to; st.to = t; $('#fFrom', el).value = st.from; $('#fTo', el).value = st.to; }
    }
    st.orgId = $('#fOrg', el)?.value || ''; st.arsId = $('#fArs', el).value;
    onChange({ ...st });
  };
  el.querySelectorAll('input,select').forEach((x) => x.addEventListener('change', fire));
  return { ...st };
}

/** Descarga filas como CSV (separador ; y BOM para Excel en español) */
export function downloadCsv(name, head, rows) {
  const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = '\uFEFF' + [head, ...rows].map((r) => r.map(q).join(';')).join('\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
