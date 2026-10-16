/** SOFA · 5.4.0 · I64 · «Rendimiento y archivo»: tiempos de carga (p95), tamaño de la base y proyección, archivo de periodos cerrados y búsqueda en el histórico.
 *  Todo se calcula en la base de datos y el servidor vuelve a verificar el rol en cada función. Super Admin y Administrador administran; Operaciones consulta. */
import { rpc, h, money, fmtDate, note, kpi, table, guarded, clientOptions, clientName, num } from '../services/iter18.js';
import { perfReport, perfDb, perfParams, perfParamsSet, archivesList, archiveCandidates, archivePeriod, archiveUntil, restorePeriod, historySearch } from '../services/perf.js';

const ESTADO = { ok: 'Sin acción por ahora', atencion: 'Planifique el cambio de plan', critico: 'Actúe pronto' };
const gb = (b) => (b == null ? '—' : b >= 1073741824 ? `${(b / 1073741824).toLocaleString('es-DO', { maximumFractionDigits: 2 })} GB` : `${(b / 1048576).toLocaleString('es-DO', { maximumFractionDigits: 0 })} MB`);
const mes = (iso) => { if (!iso) return '—'; const [y, m] = String(iso).slice(0, 7).split('-'); return `${m}/${y}`; };
const ms = (v) => (v == null ? '—' : v >= 1000 ? `${(v / 1000).toLocaleString('es-DO', { maximumFractionDigits: 2 })} s` : `${v} ms`);

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const admin = ['super_admin', 'admin'].includes(ctx.role);
  const esSuper = ctx.role === 'super_admin';
  const tabsBar = h('div', { class: 'i18-tabs rd-tabs', role: 'tablist', 'aria-label': 'Secciones de rendimiento' });
  const panel = h('div', { class: 'rd-panel', role: 'tabpanel', 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Rendimiento y archivo'),
    h('p', { class: 'i18-sub' }, 'Que las pantallas sigan en menos de 2 segundos cuando haya años de datos: tiempos reales de carga, espacio de la base, periodos cerrados en solo lectura y búsqueda en el histórico.'), tabsBar, panel));
  const SECTIONS = [['tiempos', 'Tiempos de carga'], ...(admin ? [['base', 'Base de datos']] : []), ['archivo', 'Periodos archivados'], ['historico', 'Histórico'], ['reglas', 'Reglas']];
  const VIEW = { tiempos, base, archivo, historico, reglas };
  let current = 'tiempos';
  function tabs() {
    tabsBar.replaceChildren(...SECTIONS.map(([k, label]) => {
      const b = h('button', { class: 'i18-tab', type: 'button', role: 'tab', id: `rd-tab-${k}`, 'aria-selected': k === current ? 'true' : 'false', 'aria-controls': 'rd-panel' }, label);
      b.addEventListener('click', () => { current = k; tabs(); show(); });
      return b;
    }));
  }
  function show() { panel.replaceChildren(); panel.id = 'rd-panel'; panel.setAttribute('aria-labelledby', `rd-tab-${current}`); return VIEW[current](); }

  // ── Tiempos de carga ─────────────────────────────────────────────────
  async function tiempos() {
    const days = h('select', { id: 'rd-days', 'aria-label': 'Periodo' }, [[1, 'Último día'], [7, 'Últimos 7 días'], [30, 'Últimos 30 días'], [90, 'Últimos 90 días']].map(([v, t]) => h('option', { value: v, selected: v === 7 }, t)));
    const box = h('div', { 'aria-live': 'polite' });
    panel.append(h('div', { class: 'i18-bar' }, h('label', { for: 'rd-days' }, 'Periodo', days)), box);
    async function load() {
      const d = await guarded(box, () => perfReport(Number(days.value)));
      if (!d) return;
      const o = d.overall || {};
      const out = [h('div', { class: 'i18-kpis' },
        kpi('Tiempo p95 (el 95 % carga en menos de…)', ms(o.p95), `Meta: menos de ${ms(d.target_ms)}`),
        kpi('Mediana (p50)', ms(o.p50)), kpi('Mediciones', num(o.n)),
        kpi('Estado', o.n ? (o.ok ? 'Dentro de la meta' : 'Fuera de la meta') : 'Sin datos', o.n ? null : 'Se llena solo cuando la gente usa SOFA'))];
      if (!o.n) out.push(note('Todavía no hay mediciones. Aparecen solas conforme el equipo y los clientes abren las pantallas.'));
      else if (!o.ok) out.push(note(`El p95 supera la meta de ${ms(d.target_ms)}. Revise abajo las pantallas en rojo: son las que hay que optimizar primero.`, 'warn'));
      out.push(table([
        { label: 'Pantalla', get: (r) => r.route }, { label: 'Mediciones', right: true, get: (r) => num(r.n) },
        { label: 'p50', right: true, get: (r) => ms(r.p50) }, { label: 'p95', right: true, get: (r) => h('span', { class: !r.enough ? 'rd-low' : r.ok ? 'rd-ok' : 'rd-bad' }, ms(r.p95)) },
        { label: 'Máximo', right: true, get: (r) => ms(r.max) }, { label: 'Lectura', get: (r) => (!r.enough ? 'Pocos datos (menos de 5)' : r.ok ? 'Dentro de la meta' : 'Fuera de la meta') }], d.routes || []));
      if ((d.daily || []).length) out.push(h('details', {}, h('summary', {}, 'Por día'), table([{ label: 'Día', get: (r) => fmtDate(r.day) }, { label: 'Mediciones', right: true, get: (r) => num(r.n) }, { label: 'p95', right: true, get: (r) => ms(r.p95) }], d.daily)));
      box.replaceChildren(...out);
    }
    days.addEventListener('change', load);
    await load();
  }

  // ── Base de datos ────────────────────────────────────────────────────
  async function base() {
    const box = h('div', { 'aria-live': 'polite' }); panel.append(box);
    const d = await guarded(box, () => perfDb());
    if (!d) return;
    const out = [h('div', { class: 'i18-kpis' },
      kpi('Tamaño de la base', gb(d.size_bytes), `${d.used_pct} % del límite (${gb(d.limit_bytes)})`),
      kpi('Crece por día', gb(d.growth_bytes_per_day), d.method),
      kpi('Se llena en', d.days_to_limit == null ? '—' : `${num(d.days_to_limit)} días`, d.limit_date ? `Aprox. ${fmtDate(d.limit_date)}` : 'A este ritmo no se llena'),
      kpi('Con 50 clientes', gb(d.projected_50_clients_bytes), `${d.projected_50_pct} % del límite · ${d.clients} clientes hoy`))];
    out.push(note(`${ESTADO[d.state] || ''}. ${d.advice}`, d.state === 'ok' ? 'ok' : d.state === 'critico' ? 'error' : 'warn'));
    out.push(h('h3', {}, 'Tablas más grandes'), table([{ label: 'Tabla', get: (r) => r.table }, { label: 'Tamaño', right: true, get: (r) => gb(r.bytes) }], d.biggest_tables || []));
    const p = await rpc('perf_params_get').catch(() => null);
    if (p && admin) {
      const lim = h('input', { type: 'number', id: 'rd-lim', min: '0.1', step: '0.1', value: String(Math.round(p.db_limit_bytes / 107374182.4) / 10), 'aria-describedby': 'rd-lim-h' });
      const tgt = h('input', { type: 'number', id: 'rd-tgt', min: '200', max: '60000', step: '100', value: String(p.p95_target_ms) });
      const go = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar parámetros'); const msg = h('div', { 'aria-live': 'polite' });
      go.addEventListener('click', async () => {
        try { await perfParamsSet({ dbLimitBytes: Math.round(Number(lim.value) * 1073741824), p95TargetMs: Number(tgt.value) }); msg.replaceChildren(note('Parámetros guardados.', 'ok')); }
        catch (e) { msg.replaceChildren(note(e.message, 'error')); }
      });
      out.push(h('fieldset', { class: 'i18-fs' }, h('legend', {}, 'Plan de Supabase y meta de tiempo'),
        h('p', { class: 'i18-sub', id: 'rd-lim-h' }, 'Decisión abierta: el límite de la base según el plan de Supabase que contrate (el Pro trae 8 GB). Con él se calcula cuándo se llena.'),
        h('div', { class: 'i18-bar' }, h('label', { for: 'rd-lim' }, 'Límite de la base (GB)', lim), h('label', { for: 'rd-tgt' }, 'Meta p95 (milisegundos)', tgt), go), msg));
    }
    box.replaceChildren(...out);
  }

  // ── Periodos archivados ──────────────────────────────────────────────
  async function archivo() {
    const clientes = await clientOptions().catch(() => []);
    const sel = h('select', { id: 'rd-org' }, h('option', { value: '' }, 'Todos los clientes'), clientes.map((c) => h('option', { value: c.id }, clientName(c))));
    const box = h('div', { 'aria-live': 'polite' }); const cand = h('div', { 'aria-live': 'polite' });
    panel.append(h('div', { class: 'i18-bar' }, h('label', { for: 'rd-org' }, 'Cliente', sel)), cand, box);
    async function lista() {
      const d = await guarded(box, () => archivesList(sel.value || null));
      if (!d) return;
      box.replaceChildren(h('h3', {}, 'Periodos archivados'), table([
        { label: 'Cliente', get: (r) => r.client }, { label: 'Periodo', get: (r) => mes(r.period) }, { label: 'Lotes', right: true, get: (r) => num(r.lots) },
        { label: 'Estado', get: (r) => (r.active ? 'Archivado (solo lectura)' : `Reabierto el ${fmtDate(r.restored_at)}`) },
        { label: 'Archivó', get: (r) => `${r.archived_by || '—'} · ${fmtDate(r.archived_at)}` }, { label: 'Motivo', get: (r) => r.restore_reason || r.reason || '—' },
        { label: '', get: (r) => (r.active && esSuper ? reabrir(r) : '') }], d));
    }
    function reabrir(r) {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Reabrir');
      b.addEventListener('click', async () => {
        const why = window.prompt(`Motivo para reabrir ${mes(r.period)} de ${r.client} (mínimo 10 caracteres; queda en la bitácora):`);
        if (!why) return;
        try { await restorePeriod(r.organization_id, r.period, why); await lista(); await candidatos(); } catch (e) { box.prepend(note(e.message, 'error')); }
      });
      return b;
    }
    async function candidatos() {
      if (!sel.value) { cand.replaceChildren(note('Elija un cliente para ver qué periodos se pueden archivar.')); return; }
      const d = await guarded(cand, () => archiveCandidates(sel.value));
      if (!d) return;
      const hasReady = d.some((x) => x.ready);
      const all = h('button', { class: 'i18-btn', type: 'button', disabled: !admin || !hasReady }, 'Archivar todo lo que ya se puede');
      all.addEventListener('click', async () => {
        try { const last = d.filter((x) => x.ready).map((x) => x.period).sort().pop(); const r = await archiveUntil(sel.value, last, null); cand.prepend(note(`Se archivaron ${r.archived_count} periodo(s).`, 'ok')); await lista(); await candidatos(); }
        catch (e) { cand.prepend(note(e.message, 'error')); }
      });
      cand.replaceChildren(h('h3', {}, 'Periodos de este cliente'), admin ? h('div', { class: 'i18-actions' }, all) : null, table([
        { label: 'Periodo', get: (r) => mes(r.period) },
        { label: 'Estado', get: (r) => (r.archived ? 'Archivado' : r.ready ? 'Listo para archivar' : 'Todavía no') },
        { label: 'Qué falta', get: (r) => (r.archived ? '—' : r.ready ? '—' : (r.blockers || []).join(' ')) },
        { label: '', get: (r) => (!r.archived && r.ready && admin ? uno(r) : '') }], d));
    }
    function uno(r) {
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Archivar');
      b.addEventListener('click', async () => { try { await archivePeriod(sel.value, r.period, null); await lista(); await candidatos(); } catch (e) { cand.prepend(note(e.message, 'error')); } });
      return b;
    }
    sel.addEventListener('change', () => { lista(); candidatos(); });
    await candidatos(); await lista();
  }

  // ── Histórico ────────────────────────────────────────────────────────
  async function historico() {
    const clientes = await clientOptions().catch(() => []);
    const f = {
      org: h('select', { id: 'rd-h-org' }, h('option', { value: '' }, 'Todos'), clientes.map((c) => h('option', { value: c.id }, clientName(c)))),
      q: h('input', { type: 'search', id: 'rd-h-q', maxlength: '80', placeholder: 'Nombre, folio, afiliado o autorización (mín. 3 letras)' }),
      from: h('input', { type: 'date', id: 'rd-h-from' }), to: h('input', { type: 'date', id: 'rd-h-to' }),
      min: h('input', { type: 'number', id: 'rd-h-min', min: '0', step: '0.01' }), max: h('input', { type: 'number', id: 'rd-h-max', min: '0', step: '0.01' }),
      arch: h('input', { type: 'checkbox', id: 'rd-h-arch' })
    };
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Buscar'); const more = h('button', { class: 'i18-btn i18-sec', type: 'button', hidden: true }, 'Cargar más');
    const out = h('div', { 'aria-live': 'polite' }); const rowsBox = h('div'); let rows = []; let next = null;
    panel.append(h('div', { class: 'i18-bar' },
      h('label', { for: 'rd-h-org' }, 'Cliente', f.org), h('label', { for: 'rd-h-q' }, 'Buscar', f.q), h('label', { for: 'rd-h-from' }, 'Desde', f.from), h('label', { for: 'rd-h-to' }, 'Hasta', f.to),
      h('label', { for: 'rd-h-min' }, 'Monto mínimo', f.min), h('label', { for: 'rd-h-max' }, 'Monto máximo', f.max),
      h('label', { for: 'rd-h-arch', class: 'rd-chk' }, f.arch, ' Solo periodos archivados'), go), out, rowsBox, h('div', { class: 'i18-actions' }, more));
    const filtros = () => ({ org: f.org.value, q: f.q.value.trim(), from: f.from.value, to: f.to.value, min: f.min.value, max: f.max.value, archivedOnly: f.arch.checked, limit: 50 });
    function draw() {
      rowsBox.replaceChildren(table([
        { label: 'Fecha', get: (r) => fmtDate(r.service_date) }, { label: 'Cliente', get: (r) => r.client }, { label: 'Paciente', get: (r) => r.patient }, { label: 'Folio', get: (r) => r.folio || '—' },
        { label: 'Lote', get: (r) => r.submission_folio || '—' }, { label: 'Estado', get: (r) => r.claim_status }, { label: 'Monto', right: true, get: (r) => money(r.amount) },
        { label: 'Archivo', get: (r) => (r.archived ? 'Solo lectura' : '') }], rows));
      more.hidden = !next;
    }
    async function buscar(primera) {
      try {
        out.replaceChildren(note('Buscando…'));
        const d = await historySearch(filtros(), primera ? null : next);
        rows = primera ? d.rows : rows.concat(d.rows); next = d.next;
        out.replaceChildren(note(`${num(rows.length)} resultado(s) mostrados${d.has_more ? ' (hay más)' : ''}.`)); draw();
      } catch (e) { out.replaceChildren(note(e.message, 'error')); }
    }
    go.addEventListener('click', () => buscar(true)); more.addEventListener('click', () => buscar(false));
    f.q.addEventListener('keydown', (e) => { if (e.key === 'Enter') buscar(true); });
  }

  // ── Reglas ───────────────────────────────────────────────────────────
  function reglas() {
    panel.append(h('ul', { class: 'rd-rules' },
      h('li', {}, 'Un periodo se archiva cuando todas sus radicaciones están Pagadas, Cerradas o Rechazadas, no quedan glosas abiertas y pasaron los días de espera (60 por defecto).'),
      h('li', {}, 'Archivado = solo lectura: nadie cambia ni borra radicaciones, reclamaciones, glosas ni pagos aplicados de ese mes. El Super Admin puede corregir si hace falta y queda registrado en la bitácora.'),
      h('li', {}, 'Reabrir un periodo lo hace solo el Super Admin, con un motivo de al menos 10 caracteres. El registro del archivo no se borra: queda la historia.'),
      h('li', {}, 'La búsqueda del histórico respeta lo que cada usuario puede ver, trae como máximo 100 filas por página y se pide por partes con «Cargar más».'),
      h('li', {}, 'Los tiempos de carga solo guardan la clave de la pantalla y los milisegundos: nada de nombres, identificadores ni direcciones con datos. Se conservan 90 días.')));
  }

  tabs(); await show();
}
export default render;
