/** SOFA · Buenas prácticas: guías con checklist para todo el personal */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, errorView, loadingView, toast, friendlyError } from '../utils/ui.js';
import { listGuides, getGuide } from '../services/intel.js';
import { dateTime } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';

export async function render(main, ctx) {
  if (ctx.arg) return renderGuide(main, ctx, ctx.arg);
  const admin = can('intel.admin', ctx.role);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Buenas prácticas</h2><p>Guías de trabajo de SOFA con su checklist, basadas en el plan de negocios y en prácticas internacionales del ciclo de ingresos. Úsalas para capacitar y para revisar el trabajo del día.</p></div>
      ${admin ? html`<button class="btn primary" id="new">+ Nueva guía</button>` : ''}</div><div id="l"></div>`);
  const l = $('#l', main);
  const load = () => loadInto(l, listGuides, (rows) => {
    const cats = [...new Set(rows.map((g) => g.category))];
    return html`${cats.map((c) => html`<h3 style="font-size:15px;margin:18px 0 8px">${c}</h3><div class="grid two">${rows.filter((g) => g.category === c).map((g) => html`
      <a class="card" href="#/guias/${g.id}" style="text-decoration:none;color:inherit;display:block"><h2>${g.title}${g.is_published ? '' : html` <span class="pill">Borrador</span>`}</h2><p class="sub">${g.summary || ''}</p>
        <div class="small muted">${(g.checklist || []).length} puntos de verificación · actualizada ${dateTime(g.updated_at)}</div></a>`)}</div>`)}`;
  }, { empty: () => emptyView('Sin guías', admin ? 'Crea la primera guía.' : 'Aún no hay guías publicadas.') });
  $('#new', main)?.addEventListener('click', async () => {
    const { guideDialog } = await import('./market-dialogs.js');
    try { const id = await guideDialog(ctx.operatorId); if (id) { toast('Guía creada', 'ok'); location.hash = `#/guias/${id}`; } } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}

async function renderGuide(main, ctx, id) {
  paint(main, html`<div id="g">${loadingView(6)}</div>`);
  const box = $('#g', main);
  const refresh = async () => {
    try {
      const g = await getGuide(id);
      if (!g) { paint(box, emptyView('Guía no encontrada', '', html`<a class="btn" href="#/guias">Volver</a>`)); return; }
      ctx.setTitle(g.title);
      const paras = String(g.body || '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
      paint(box, html`
        <div class="page-head"><div class="t"><p class="no-print"><a href="#/guias">← Buenas prácticas</a></p><h2>${g.title}</h2><p>${g.category} · <span class="mono">${g.code}</span>${g.is_published ? '' : ' · Borrador'}</p></div>
          <div class="toolbar no-print" style="margin:0"><button class="btn" id="print">Imprimir</button>${can('intel.admin', ctx.role) ? html`<button class="btn" id="edit">Editar</button>` : ''}</div></div>
        ${g.summary ? html`<div class="note">${g.summary}</div>` : ''}
        <div class="grid two">
          <div class="card"><h2>Cómo hacerlo</h2>${paras.map((p) => html`<p style="margin:0 0 12px;white-space:pre-wrap">${p}</p>`)}${g.reference ? html`<p class="small muted">Referencia: ${g.reference}</p>` : ''}</div>
          <div class="card"><h2>Checklist · ${(g.checklist || []).length}</h2><p class="sub no-print">Márcalo mientras trabajas (no se guarda: sirve de guía en pantalla o impreso).</p>
            <div class="list">${(g.checklist || []).map((c, i) => html`<label class="li check"><input type="checkbox" id="ck${i}"> <span class="b">${c}</span></label>`)}</div>
            <p class="small" id="ckc" style="margin-top:8px"></p></div>
        </div>`);
      const count = () => { const all = box.querySelectorAll('.list input[type=checkbox]'); const done = [...all].filter((x) => x.checked).length; $('#ckc', box).textContent = `${done} de ${all.length} completados`; };
      box.querySelectorAll('.list input[type=checkbox]').forEach((x) => x.addEventListener('change', count)); count();
      $('#print', box).addEventListener('click', () => window.print());
      $('#edit', box)?.addEventListener('click', async () => {
        const { guideDialog } = await import('./market-dialogs.js');
        try { if (await guideDialog(ctx.operatorId, g)) { toast('Guía actualizada', 'ok'); refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); }
      });
    } catch (err) { paint(box, errorView(err)); }
  };
  await refresh();
}
