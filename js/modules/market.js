/** SOFA · Inteligencia de mercado: resumen, noticias del sector, competencia y referentes, ideas de servicios y fuentes */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, errorView, loadingView, toast, friendlyError, opt, busy, confirmDialog } from '../utils/ui.js';
import { listItems, topItems, itemCounts, setItemStatus, listEntities, getEntity, entityNotes, deleteEntity, listIdeas, saveIdea, listSources, saveSource, deleteSource, lastRuns, refreshNow } from '../services/intel.js';
import { profileNames } from '../services/submissions.js';
import { intelTopic, INTEL_TOPICS, ENTITY_KINDS, THREAT, IDEA_STATUS } from '../utils/constants.js';
import { date, dateTime, num } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { pager } from './clients.js';

const ext = (url, label) => (/^https?:\/\//i.test(url || '') ? html`<a href="${url}" target="_blank" rel="noopener noreferrer">${label}</a>` : label);
const relBar = (r) => html`<span title="Relevancia ${r}/100" style="display:inline-block;width:46px;height:6px;background:var(--surface-2);border-radius:3px;vertical-align:middle;overflow:hidden"><span style="display:block;height:100%;width:${r}%;background:${r >= 60 ? 'var(--red)' : r >= 35 ? 'var(--warn)' : 'var(--ink-3)'}"></span></span>`;
const dlg = () => import('./market-dialogs.js');

/** Tarjeta de noticia (resumen, listado y dashboard) */
export function itemCard(i, { actions = false } = {}) {
  const [tl, tc] = intelTopic(i.topic);
  return html`<div class="li" data-item="${i.id}">
    <div class="b"><div class="t1" style="font-weight:600">${ext(i.url, i.title)}${i.status === 'destacado' ? html` <span class="pill warn">★ Destacada</span>` : ''}</div>
      <div class="t2">${i.publisher || 'Fuente'} · ${i.published_at ? date(i.published_at) : dateTime(i.fetched_at)} · <span class="pill ${tc}">${tl}</span>${i.entity_name ? html` <span class="pill info">${i.entity_name}</span>` : ''} ${relBar(i.relevance)}</div>
      ${i.implication ? html`<div class="small" style="margin-top:4px"><b>¿Qué significa para SOFA?</b> ${i.implication}${i.is_ai ? html` <span class="pill" title="Generado con IA a partir del titular">IA</span>` : ''}</div>` : ''}
      ${actions ? html`<div class="toolbar" style="margin:6px 0 0">
        <button class="btn sm" data-st="${i.status === 'destacado' ? 'leido' : 'destacado'}">${i.status === 'destacado' ? 'Quitar destacado' : '★ Destacar'}</button>
        ${i.status === 'nuevo' ? html`<button class="btn sm" data-st="leido">Marcar leída</button>` : ''}
        ${i.status !== 'descartado' ? html`<button class="btn sm" data-st="descartado">Descartar</button>` : html`<button class="btn sm" data-st="leido">Recuperar</button>`}
        <button class="btn sm" data-idea="1">Crear idea</button></div>` : ''}</div></div>`;
}

/** Resumen de mercado (lo usa también el Dashboard) */
export async function renderMarketSummary(el, ctx, { compact = false } = {}) {
  paint(el, loadingView(5));
  try {
    const [top, ent, ideas, counts, runs] = await Promise.all([topItems({ days: 14, limit: compact ? 5 : 8 }), topItems({ days: 30, limit: 6, entitiesOnly: true }),
      listIdeas().then((r) => r.filter((x) => !['descartado', 'lanzado'].includes(x.status)).slice(0, 5)), itemCounts(), can('intel.admin', ctx.role) ? lastRuns(1).catch(() => []) : Promise.resolve([])]);
    const last = runs[0];
    paint(el, html`
      ${compact ? '' : html`<div class="grid kpis">
        <div class="kpi"><div class="l">Noticias nuevas (7 días)</div><div class="v">${num(counts.new7)}</div></div>
        <div class="kpi"><div class="l">Destacadas</div><div class="v">${num(counts.starred)}</div></div>
        <div class="kpi"><div class="l">Ideas en evaluación o piloto</div><div class="v">${num(ideas.filter((x) => ['evaluando', 'piloto'].includes(x.status)).length)}</div></div>
        <div class="kpi"><div class="l">Última actualización</div><div class="v" style="font-size:17px">${last ? dateTime(last.finished_at || last.started_at) : '—'}</div><div class="h">${last ? `${last.inserted} nuevas${(last.errors || []).length ? ` · ${last.errors.length} ${last.errors.length === 1 ? 'fuente' : 'fuentes'} con error` : ''}` : 'Pulsa "Actualizar ahora" o programa la tarea diaria'}</div></div></div>`}
      <div class="grid two" style="margin-top:${compact ? 0 : 14}px">
        <div class="card"><h2>Lo más relevante · 14 días</h2>${top.length ? html`<div class="list">${top.map((i) => itemCard(i))}</div>` : html`<p class="small muted">Aún no hay noticias. ${can('intel.admin', ctx.role) ? 'Publica la función market-intel y pulsa "Actualizar ahora".' : ''}</p>`}</div>
        <div class="card"><h2>Competidores, referentes y reguladores · 30 días</h2>${ent.length ? html`<div class="list">${ent.map((i) => itemCard(i))}</div>` : html`<p class="small muted">Sin menciones recientes de las entidades monitoreadas.</p>`}
          <h2 style="margin-top:16px">Ideas mejor puntuadas</h2>${ideas.length ? html`<div class="list">${ideas.map((d) => html`<div class="li"><div class="b"><div class="t1">${d.title}</div><div class="t2">${d.segment || ''}</div></div><span class="pill ${IDEA_STATUS[d.status][1]}">${IDEA_STATUS[d.status][0]}</span> <b>${d.score}</b></div>`)}</div>` : html`<p class="small muted">Sin ideas activas.</p>`}
          ${compact ? html`<p class="small" style="margin-top:10px"><a href="#/mercado">Abrir Inteligencia de mercado →</a></p>` : ''}</div>
      </div>`);
  } catch (err) { paint(el, errorView(err)); }
}

export async function render(main, ctx) {
  if (ctx.arg && ctx.arg.startsWith('entidad/')) return renderEntity(main, ctx, ctx.arg.slice(8));
  const edit = can('intel.edit', ctx.role); const admin = can('intel.admin', ctx.role);
  const st = { tab: 'resumen', status: 'activas', topic: '', minRel: 0, q: '', kind: 'competencia', page: 0 };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Inteligencia de mercado</h2><p>Noticias del sector, competencia y referentes, y el banco de ideas para robustecer la oferta de SOFA. Solo se guardan titulares y enlaces; la lectura completa está en cada medio.</p></div>
      ${admin ? html`<button class="btn primary" id="refresh">Actualizar ahora</button>` : ''}</div>
    <div class="tabs" id="tabs" role="group" aria-label="Vista"></div><div id="body"></div>`);
  const tabs = [['resumen', 'Resumen'], ['noticias', 'Noticias'], ['competencia', 'Competencia y referentes'], ['ideas', 'Ideas de servicios'], ...(admin ? [['fuentes', 'Fuentes']] : [])];
  const drawTabs = () => paint($('#tabs', main), html`${tabs.map(([k, l]) => html`<button data-t="${k}" aria-pressed="${st.tab === k}">${l}</button>`)}`);
  const body = $('#body', main);
  let items = [];

  const draw = () => {
    drawTabs();
    // Contenedor propio: si el usuario cambia de pestaña mientras el resumen carga, el resumen tardío no pisa la pestaña nueva
    if (st.tab === 'resumen') { paint(body, html``); const pane = document.createElement('div'); body.appendChild(pane); return renderMarketSummary(pane, ctx); }
    if (st.tab === 'noticias') return drawNews();
    if (st.tab === 'competencia') return drawEntities();
    if (st.tab === 'ideas') return drawIdeas();
    return drawSources();
  };

  function drawNews() {
    paint(body, html`<div class="toolbar">
      <label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" value="${st.q}" placeholder="Buscar en titulares y medios">
      <label class="sr-only" for="tp">Tema</label><select class="input" id="tp" style="width:auto"><option value="">Todos los temas</option>${Object.entries(INTEL_TOPICS).map(([k, [l]]) => opt(k, l, st.topic))}</select>
      <label class="sr-only" for="rl">Relevancia</label><select class="input" id="rl" style="width:auto">${[[0, 'Toda relevancia'], [40, 'Relevancia 40+'], [60, 'Relevancia 60+']].map(([v, l]) => opt(String(v), l, String(st.minRel)))}</select>
      <label class="sr-only" for="ss">Estado</label><select class="input" id="ss" style="width:auto">${[['activas', 'Activas'], ['nuevo', 'Nuevas'], ['destacado', 'Destacadas'], ['descartado', 'Descartadas']].map(([v, l]) => opt(v, l, st.status))}</select></div><div id="l"></div>`);
    const l = $('#l', body);
    const load = () => loadInto(l, async () => { const r = await listItems({ ...st }); items = r.data; return r; },
      ({ data, count }) => html`<div class="card"><div class="list">${data.map((i) => itemCard(i, { actions: edit }))}</div>${pager(count, st.page)}</div>`,
      { isEmpty: (r) => !r.data.length, empty: () => emptyView('Sin noticias con estos filtros', admin ? 'Pulsa "Actualizar ahora" o ajusta los filtros.' : 'Ajusta los filtros.') });
    let t; $('#q', body).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; st.page = 0; load(); }, 350); });
    [['#tp', 'topic'], ['#rl', 'minRel'], ['#ss', 'status']].forEach(([sel, k]) => $(sel, body).addEventListener('change', (e) => { st[k] = k === 'minRel' ? Number(e.target.value) : e.target.value; st.page = 0; load(); }));
    l.addEventListener('click', async (e) => {
      const p = e.target.closest('[data-page]'); if (p) { st.page = Number(p.dataset.page); load(); return; }
      const card = e.target.closest('[data-item]'); if (!card) return;
      const it = items.find((x) => x.id === card.dataset.item);
      const s = e.target.closest('[data-st]');
      if (s) { try { await setItemStatus(it.id, s.dataset.st); toast(s.dataset.st === 'destacado' ? 'Noticia destacada' : 'Listo', 'ok'); load(); } catch (err) { toast(friendlyError(err), 'bad'); } return; }
      if (e.target.closest('[data-idea]')) {
        try { if (await (await dlg()).ideaDialog(ctx.operatorId, null, it)) { toast('Idea creada con la noticia como evidencia', 'ok'); if (it.status === 'nuevo') await setItemStatus(it.id, 'leido'); load(); } }
        catch (err) { toast(friendlyError(err), 'bad'); }
      }
    });
    load();
  }

  function drawEntities() {
    paint(body, html`<div class="toolbar">
      <div class="tabs" id="kinds" role="group" aria-label="Tipo" style="margin:0">${[['competencia', 'Competencia'], ['referente_internacional', 'Referentes internacionales'], ['sector', 'Reguladores y gremios'], ['', 'Todas']].map(([k, l]) => html`<button data-k="${k}" aria-pressed="${st.kind === k}">${l}</button>`)}</div>
      <span class="grow"></span>${edit ? html`<button class="btn" id="newEnt">+ Agregar ficha</button>` : ''}</div><div id="l"></div>`);
    const l = $('#l', body);
    const load = () => loadInto(l, () => listEntities({ kind: st.kind }), (rows) => html`<div class="grid two">${rows.map((e) => html`<div class="card" data-ent="${e.id}" style="cursor:pointer">
        <h2 style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><a href="#/mercado/entidad/${e.id}">${e.name}</a><span class="pill">${ENTITY_KINDS[e.kind]}</span>${e.threat_level !== 'n/a' ? html`<span class="pill ${THREAT[e.threat_level][1]}">${THREAT[e.threat_level][0]}</span>` : ''}${e.monitor ? html`<span class="pill info">Monitoreado</span>` : ''}</h2>
        <p class="sub">${e.description || e.services || 'Sin descripción'}</p>
        <div class="small muted">${num(e.news_30d)} noticias en 30 días · ${num(e.notes)} observaciones${e.last_reviewed_on ? ` · revisada ${date(e.last_reviewed_on)}` : ''}</div></div>`)}</div>`,
    { empty: () => emptyView(st.kind === 'competencia' ? 'Aún no hay competidores registrados' : 'Sin fichas', st.kind === 'competencia' ? 'Agrega las empresas o profesionales que ofrecen facturación médica, gestión de glosas o trámites de habilitación en tu mercado. Activa el monitoreo para seguir sus noticias.' : '', edit ? html`<button class="btn primary" data-new>+ Agregar ficha</button>` : '') });
    $('#kinds', body).addEventListener('click', (e) => { const b = e.target.closest('[data-k]'); if (b) { st.kind = b.dataset.k; drawEntities(); } });
    const add = async () => { try { const id = await (await dlg()).entityDialog(ctx.operatorId); if (id) { toast('Ficha creada', 'ok'); location.hash = `#/mercado/entidad/${id}`; } } catch (err) { toast(friendlyError(err), 'bad'); } };
    $('#newEnt', body)?.addEventListener('click', add);
    l.addEventListener('click', (e) => { if (e.target.closest('[data-new]')) { add(); return; } const c = e.target.closest('[data-ent]'); if (c && !e.target.closest('a')) location.hash = `#/mercado/entidad/${c.dataset.ent}`; });
    load();
  }

  function drawIdeas() {
    paint(body, html`<div class="toolbar"><span class="small muted grow">Ordenadas por puntaje (impacto × encaje ÷ esfuerzo).</span>${edit ? html`<button class="btn" id="newIdea">+ Nueva idea</button>` : ''}</div><div id="l"></div>`);
    const l = $('#l', body); let rows = [];
    const load = () => loadInto(l, async () => { rows = await listIdeas(); return rows; }, (all) => html`${Object.entries(IDEA_STATUS).map(([k, [lbl, cls]]) => {
      const list = all.filter((x) => x.status === k); if (!list.length) return '';
      return html`<div class="card" style="margin-bottom:12px"><h2>${lbl} · ${list.length}</h2><div class="list">${list.map((d) => html`<div class="li" data-idea="${d.id}">
        <span class="pill ${cls}" style="min-width:48px;justify-content:center" title="Puntaje">${d.score}</span>
        <div class="b"><div class="t1">${d.title}</div><div class="t2">${d.description || ''}</div>
          <div class="small" style="margin-top:4px">${d.value_prop ? html`<b>Valor:</b> ${d.value_prop} · ` : ''}${d.segment ? html`<b>Segmento:</b> ${d.segment} · ` : ''}${d.revenue_model ? html`<b>Cobro:</b> ${d.revenue_model} · ` : ''}Impacto ${d.impact} · Encaje ${d.fit} · Esfuerzo ${d.effort}</div></div>
        ${edit ? html`<div class="toolbar" style="margin:0"><label class="sr-only" for="is-${d.id}">Estado</label><select class="input" id="is-${d.id}" data-ist="${d.id}" style="width:auto;min-height:34px">${Object.entries(IDEA_STATUS).map(([s, [sl]]) => opt(s, sl, d.status))}</select><button class="btn sm" data-edit="${d.id}">Editar</button></div>` : ''}</div>`)}</div></div>`;
    })}`, { empty: () => emptyView('Sin ideas', 'Crea la primera o conviértela desde una noticia.') });
    $('#newIdea', body)?.addEventListener('click', async () => { try { if (await (await dlg()).ideaDialog(ctx.operatorId)) { toast('Idea creada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
    l.addEventListener('change', async (e) => {
      const s = e.target.closest('[data-ist]'); if (!s) return;
      try { await saveIdea(ctx.operatorId, { status: s.value }, s.dataset.ist); toast(`Idea en "${IDEA_STATUS[s.value][0]}"`, 'ok'); load(); } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    l.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-edit]'); if (!b) return;
      try { if (await (await dlg()).ideaDialog(ctx.operatorId, rows.find((x) => x.id === b.dataset.edit))) { toast('Idea actualizada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    load();
  }

  function drawSources() {
    paint(body, html`<div class="toolbar"><span class="small muted grow">Búsquedas de Google News (español para República Dominicana o inglés para EE.UU.) o canales RSS. Las fichas con monitoreo activo agregan su propia búsqueda.</span><button class="btn" id="newSrc">+ Nueva fuente</button></div><div id="l"></div><div class="card" style="margin-top:14px"><h2>Últimas actualizaciones</h2><div id="runs"></div></div>`);
    const l = $('#l', body); let rows = [];
    const load = () => loadInto(l, async () => { rows = await listSources(); return rows; }, (all) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fuente</th><th>Búsqueda o URL</th><th>Tema</th><th>Peso</th><th>Última lectura</th><th></th></tr></thead><tbody>
      ${all.map((s) => html`<tr><td data-l="Fuente"><b>${s.name}</b><div class="small muted">${s.kind === 'rss' ? 'RSS' : `Google News · ${s.lang === 'en' ? 'inglés' : 'español'}`}${s.is_active ? '' : ' · inactiva'}</div></td>
        <td data-l="Búsqueda" class="mono small">${s.query}</td><td data-l="Tema">${intelTopic(s.topic)[0]}</td><td data-l="Peso">${s.weight}</td>
        <td data-l="Última lectura">${s.last_fetched_at ? dateTime(s.last_fetched_at) : '—'}${s.last_error ? html`<div class="small" style="color:var(--bad)">${s.last_error}</div>` : ''}</td>
        <td data-l=""><button class="btn sm" data-es="${s.id}">Editar</button> <button class="btn sm" data-tg="${s.id}">${s.is_active ? 'Pausar' : 'Activar'}</button> <button class="btn sm danger" data-rm="${s.id}" aria-label="Eliminar ${s.name}">✕</button></td></tr>`)}</tbody></table></div>`,
    { empty: () => emptyView('Sin fuentes', 'Agrega la primera búsqueda.') });
    loadInto($('#runs', body), () => lastRuns(10), (runs) => html`<div class="list">${runs.map((r) => html`<div class="li"><div class="b"><div class="t1">${dateTime(r.started_at)} · ${r.trigger === 'cron' ? 'Programada' : 'Manual'}</div>
      <div class="t2">${r.sources} fuentes · ${r.fetched} leídas · <b>${r.inserted} nuevas</b>${r.ai_enriched ? ` · ${r.ai_enriched} con IA` : ''}${(r.errors || []).length ? ` · ${(r.errors || []).map((x) => `${x.source}: ${x.error}`).join(' | ')}` : ''}</div></div></div>`)}</div>`,
    { empty: () => html`<p class="small muted">Todavía no se ha ejecutado ninguna actualización.</p>` });
    $('#newSrc', body).addEventListener('click', async () => { try { if (await (await dlg()).sourceDialog(ctx.operatorId)) { toast('Fuente agregada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
    l.addEventListener('click', async (e) => {
      const ed = e.target.closest('[data-es]'), tg = e.target.closest('[data-tg]'), rm = e.target.closest('[data-rm]');
      try {
        if (ed && await (await dlg()).sourceDialog(ctx.operatorId, rows.find((x) => x.id === ed.dataset.es))) { toast('Fuente actualizada', 'ok'); load(); }
        if (tg) { const s = rows.find((x) => x.id === tg.dataset.tg); await saveSource(ctx.operatorId, { is_active: !s.is_active }, s.id); load(); }
        if (rm && await confirmDialog('Eliminar fuente', 'Las noticias ya guardadas se conservan.', 'Eliminar', true)) { await deleteSource(rm.dataset.rm); toast('Fuente eliminada', 'ok'); load(); }
      } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    load();
  }

  $('#tabs', main).addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (b) { st.tab = b.dataset.t; st.page = 0; draw(); } });
  $('#refresh', main)?.addEventListener('click', (e) => busy(e.currentTarget, async () => {
    try { const r = await refreshNow(); toast(r.message || 'Noticias actualizadas', 'ok'); draw(); } catch (err) { toast(friendlyError(err), 'bad'); }
  }));
  draw();
}

async function renderEntity(main, ctx, id) {
  const edit = can('intel.edit', ctx.role);
  paint(main, html`<div id="e">${loadingView(6)}</div>`);
  const box = $('#e', main);
  const refresh = async () => {
    try {
      const e = await getEntity(id);
      if (!e) { paint(box, emptyView('Ficha no encontrada', '', html`<a class="btn" href="#/mercado">Volver</a>`)); return; }
      const [notes, news] = await Promise.all([entityNotes(id), listItems({ entityId: id, status: 'activas', size: 15 })]);
      const names = await profileNames(notes.map((n) => n.created_by)).catch(() => ({}));
      ctx.setTitle(e.name);
      const row = (k, v) => (v ? html`<dt>${k}</dt><dd style="white-space:pre-wrap">${v}</dd>` : '');
      paint(box, html`
        <div class="page-head"><div class="t"><p><a href="#/mercado">← Inteligencia de mercado</a></p><h2>${e.name} <span class="pill">${ENTITY_KINDS[e.kind]}</span>${e.threat_level !== 'n/a' ? html` <span class="pill ${THREAT[e.threat_level][1]}">${THREAT[e.threat_level][0]}</span>` : ''}</h2>
          <p>${e.country || ''}${e.website ? html` · ${ext(e.website, 'Sitio web')}` : ''}${e.last_reviewed_on ? ` · revisada ${date(e.last_reviewed_on)}` : ''}${e.monitor ? ` · Monitoreo: ${e.monitor_query}` : ''}</p></div>
          ${edit ? html`<div class="toolbar" style="margin:0"><button class="btn" id="note">+ Observación</button><button class="btn" id="edit">Editar</button>${can('intel.admin', ctx.role) ? html`<button class="btn danger" id="del">Eliminar</button>` : ''}</div>` : ''}</div>
        <div class="grid two">
          <div class="card"><h2>Ficha</h2><dl class="kv">${row('Descripción', e.description)}${row('Servicios', e.services)}${row('Fortalezas', e.strengths)}${row('Debilidades', e.weaknesses)}${row('Precios', e.pricing_notes)}</dl>
            ${!e.description && !e.services && !e.strengths ? html`<p class="small muted">Completa la ficha con lo que sabes: servicios, precios, fortalezas y debilidades frente a SOFA.</p>` : ''}</div>
          <div class="card"><h2>Observaciones · ${notes.length}</h2>${notes.length ? html`<div class="list">${notes.map((n) => html`<div class="li"><div class="b"><div class="t1" style="font-weight:500;white-space:pre-wrap">${n.note}</div><div class="t2">${date(n.observed_on)}${names[n.created_by] ? ` · ${names[n.created_by]}` : ''}${n.source_url ? html` · ${ext(n.source_url, 'Fuente')}` : ''}</div></div></div>`)}</div>` : html`<p class="small muted">Registra lo que observes: precios, clientes que ganó, servicios nuevos, quejas.</p>`}</div>
        </div>
        <div class="card" style="margin-top:14px"><h2>Noticias relacionadas</h2>${news.data.length ? html`<div class="list">${news.data.map((i) => itemCard(i))}</div>` : html`<p class="small muted">${e.monitor ? 'Aún no hay noticias: aparecerán en la próxima actualización.' : 'Activa el monitoreo para seguir sus noticias.'}</p>`}</div>`);
      const d = await dlg();
      $('#edit', box)?.addEventListener('click', async () => { try { if (await d.entityDialog(ctx.operatorId, e)) { toast('Ficha actualizada', 'ok'); refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
      $('#note', box)?.addEventListener('click', async () => { try { if (await d.noteDialog(ctx.operatorId, e)) { toast('Observación guardada', 'ok'); refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
      $('#del', box)?.addEventListener('click', async () => {
        if (!(await confirmDialog('Eliminar ficha', `Se eliminará ${e.name} con sus observaciones. Las noticias se conservan.`, 'Eliminar', true))) return;
        try { await deleteEntity(e.id); toast('Ficha eliminada', 'ok'); location.hash = '#/mercado'; } catch (err) { toast(friendlyError(err), 'bad'); }
      });
    } catch (err) { paint(box, errorView(err)); }
  };
  await refresh();
}
