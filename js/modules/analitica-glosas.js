/** SOFA · 26 · Analítica de glosas: cuánto se glosa, por qué, qué ARS y cuánto se recupera (solo lectura).
 *  Personal de SOFA puede ver todos los clientes; el médico ve solo los suyos. */
import { rpc, clientOptions, h, money, num, pct, note, guarded, kpi, table, todayIso, monthsAgoIso, clientName } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const out = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Analítica de glosas'), top, out);
  const clients = await guarded(top, clientOptions);
  if (!clients) return;
  const org = h('select', { id: 'ag-org' }, h('option', { value: '' }, 'Todos los clientes (solo SOFA)'), clients.map((c) => h('option', { value: c.id }, clientName(c))));
  if (clients.length === 1) org.value = clients[0].id;
  const from = h('input', { id: 'ag-from', type: 'date', value: monthsAgoIso(5) });
  const to = h('input', { id: 'ag-to', type: 'date', value: todayIso() });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Ver');
  top.replaceChildren(h('div', { class: 'i18-form' }, h('label', { for: 'ag-org' }, 'Cliente'), org,
    h('label', { for: 'ag-from' }, 'Glosas notificadas desde'), from, h('label', { for: 'ag-to' }, 'Hasta'), to, go));

  async function load() {
    const d = await guarded(out, () => rpc('glosa_analytics', { p_org: org.value || null, p_from: from.value, p_to: to.value }));
    if (!d) return;
    const t = d.totals, r = d.rates;
    const glosaRisk = r.glosa_pct == null ? null : r.glosa_pct > 0.25 ? ['alto', '#861D18', '#F6E7E6'] : r.glosa_pct > 0.15 ? ['medio', '#8A5A00', '#FBEFD5'] : ['normal', '#23703B', '#E2F2E6'];
    const recupRisk = r.recuperacion_pct == null ? null : r.recuperacion_pct < 0.5 ? ['baja', '#861D18', '#F6E7E6'] : r.recuperacion_pct < 0.7 ? ['media', '#8A5A00', '#FBEFD5'] : ['alta', '#23703B', '#E2F2E6'];
    // Benchmarks de la industria de salud RD (referencia estática del sector)
    const BENCH_GLOSA = { bueno: 0.05, industria_min: 0.08, industria_max: 0.12 };
    const BENCH_RECUP = { bueno: 0.80, industria_min: 0.60, industria_max: 0.70 };
    const benchBar = (val, low, high, reverse = false) => {
      if (val == null) return null;
      const ok = reverse ? val >= high : val <= low;
      const warn = reverse ? val >= low : val <= high;
      const color = ok ? 'var(--ok)' : warn ? 'var(--warn)' : 'var(--bad)';
      const w = Math.min(100, Math.round(reverse ? val * 100 : (1 - val) * 100));
      return h('div', { style: 'margin-top:4px' }, h('div', { style: `height:6px;background:var(--surface-2);border-radius:3px` },
        h('div', { style: `height:100%;width:${Math.max(4, Math.round(val * 100))}%;background:${color};border-radius:3px` })));
    };
    const benchRef = r.glosa_pct != null || r.recuperacion_pct != null ? h('div', { style: 'margin-bottom:16px;padding:12px 16px;background:var(--surface-2);border-radius:8px' },
      h('div', { style: 'font-size:13px;font-weight:600;margin-bottom:8px;color:var(--ink-2)' }, 'Referencia sector salud RD'),
      h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:12px' },
        h('div', {},
          h('div', { style: 'font-size:12px;color:var(--ink-2)' }, 'Tu tasa de glosa'),
          h('div', { style: 'font-size:16px;font-weight:700' }, r.glosa_pct != null ? pct(r.glosa_pct) : '—'),
          benchBar(r.glosa_pct, BENCH_GLOSA.bueno, BENCH_GLOSA.industria_max),
          h('div', { style: 'font-size:11px;color:var(--ink-3);margin-top:4px' }, `Industria: ${(BENCH_GLOSA.industria_min * 100).toFixed(0)}–${(BENCH_GLOSA.industria_max * 100).toFixed(0)}% · Top <${(BENCH_GLOSA.bueno * 100).toFixed(0)}%`)),
        h('div', {},
          h('div', { style: 'font-size:12px;color:var(--ink-2)' }, 'Tu tasa de recuperación'),
          h('div', { style: 'font-size:16px;font-weight:700' }, r.recuperacion_pct != null ? pct(r.recuperacion_pct) : '—'),
          benchBar(r.recuperacion_pct, BENCH_RECUP.industria_min, BENCH_RECUP.bueno, true),
          h('div', { style: 'font-size:11px;color:var(--ink-3);margin-top:4px' }, `Industria: ${(BENCH_RECUP.industria_min * 100).toFixed(0)}–${(BENCH_RECUP.industria_max * 100).toFixed(0)}% · Top >${(BENCH_RECUP.bueno * 100).toFixed(0)}%`)))) : null;
    out.replaceChildren(
      h('div', { class: 'i18-kpis' },
        kpi('Glosado', money(t.glosado), `${num(t.glosas)} glosa(s)`),
        kpi('% glosado de lo radicado', r.glosa_pct == null ? '—' : pct(r.glosa_pct), `Radicado: ${money(t.radicado)}`),
        kpi('Recuperado', money(t.recuperado), r.recuperacion_pct == null ? null : `Recuperación ${pct(r.recuperacion_pct)}`),
        kpi('Aceptado (perdido)', money(t.aceptado)), kpi('En disputa', money(t.en_disputa))),
      benchRef,
      (glosaRisk || recupRisk) ? h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px' },
        glosaRisk ? h('span', { style: `padding:4px 12px;border-radius:999px;font-size:12px;font-weight:600;background:${glosaRisk[2]};color:${glosaRisk[1]}` }, `Riesgo de glosa: ${glosaRisk[0]}`) : null,
        recupRisk ? h('span', { style: `padding:4px 12px;border-radius:999px;font-size:12px;font-weight:600;background:${recupRisk[2]};color:${recupRisk[1]}` }, `Recuperación: ${recupRisk[0]}`) : null) : null,
      h('h3', {}, 'Por motivo y cómo prevenirlo'),
      table([{ label: 'Motivo', get: (x) => x.reason }, { label: 'Servicios', right: true, get: (x) => num(x.items) },
        { label: 'Glosado', right: true, get: (x) => money(x.glosado) }, { label: 'Recuperado', right: true, get: (x) => money(x.recuperado) },
        { label: 'Cómo prevenirlo', get: (x) => x.tip }], d.by_reason),
      h('h3', {}, 'Por ARS'),
      table([{ label: 'ARS', get: (x) => x.ars }, { label: 'Glosado', right: true, get: (x) => money(x.glosado) },
        { label: 'Recuperado', right: true, get: (x) => money(x.recuperado) }, { label: 'Recuperación', right: true, get: (x) => (x.recuperacion_pct == null ? '—' : pct(x.recuperacion_pct)) }], d.by_ars),
      h('h3', {}, 'Auditores de ARS con más glosas'),
      table([{ label: 'Auditor', get: (x) => x.auditor }, { label: 'Glosas', right: true, get: (x) => num(x.glosas) },
        { label: 'Glosado', right: true, get: (x) => money(x.glosado) }], d.by_auditor));
  }
  go.addEventListener('click', load);
  if (org.value) await load(); else out.replaceChildren(note('Elija un cliente y toque «Ver». «Todos los clientes» solo funciona para el personal de SOFA.'));
}
