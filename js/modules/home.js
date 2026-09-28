/** SOFA · Inicio: contexto del usuario, cifras visibles y plan de 90 días */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError } from '../utils/ui.js';
import { visibleNav, isStaff, can } from '../utils/permissions.js';
import { headCount } from '../services/stats.js';
import { listMilestones, setMilestoneDone } from '../services/admin.js';
import { num, date } from '../utils/formatters.js';

export async function render(main, ctx) {
  const first = String(ctx.profile.full_name || '').split(' ')[0] || 'bienvenido';
  const staff = isStaff(ctx.role);
  const nav = visibleNav(ctx.role).flatMap((g) => g.items);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Hola, ${first}</h2><p>${ctx.membership.role_name} · ${ctx.membership.organization}</p></div></div>
    <div class="grid kpis" id="kpis"></div>
    <div class="grid two" style="margin-top:14px">
      ${staff ? html`<div class="card"><h2>Plan de 90 días</h2><p class="sub">Hitos comerciales y técnicos. ${can('milestones.edit', ctx.role) ? 'Márcalos al cumplirlos.' : 'Solo lectura para tu rol.'}</p><div id="plan"></div></div>` : ''}
      <div class="card"><h2>Tus módulos</h2><p class="sub">Lo que tu rol puede usar hoy y lo que llega en las próximas iteraciones.</p>
        <div class="list">${nav.map((i) => html`<div class="li"><div class="b"><div class="t1"><a href="#/${i.route}">${i.label}</a></div></div>${i.ready ? html`<span class="pill ok">Disponible</span>` : html`<span class="pill">Iteración ${i.iteration}</span>`}</div>`)}</div>
      </div>
    </div>`);

  const kp = $('#kpis', main);
  const defs = [
    ['Clientes PSS visibles', 'organizations', (q) => q.eq('kind', 'client')],
    ['Radicaciones visibles', 'submissions'],
    ['ARS en catálogo', 'ars'],
    ['Conceptos en catálogo', 'procedures']
  ];
  paint(kp, html`${defs.map(([l]) => html`<div class="kpi"><div class="l">${l}</div><div class="v">…</div></div>`)}`);
  const vals = await Promise.allSettled(defs.map(([, t, f]) => headCount(t, f)));
  paint(kp, html`${defs.map(([l], i) => html`<div class="kpi"><div class="l">${l}</div><div class="v">${vals[i].status === 'fulfilled' ? num(vals[i].value) : '—'}</div>${vals[i].status === 'rejected' ? html`<div class="h">${friendlyError(vals[i].reason)}</div>` : ''}</div>`)}`);

  if (staff) {
    const box = $('#plan', main);
    const editable = can('milestones.edit', ctx.role);
    const draw = (rows) => {
      const done = rows.filter((r) => r.done_on).length;
      const pct = rows.length ? Math.round((done / rows.length) * 100) : 0;
      return html`<div class="small muted">${done} de ${rows.length} hitos · ${pct}%</div>
        <div style="height:10px;background:var(--surface-2);border-radius:6px;overflow:hidden;margin:6px 0 10px"><div style="height:100%;width:${pct}%;background:var(--ok)"></div></div>
        <div class="list">${rows.map((r) => html`<label class="li check"><input type="checkbox" data-id="${r.id}" ${r.done_on ? raw('checked') : ''} ${editable ? '' : raw('disabled')}><span class="b"><span class="t1">${r.title}</span><br><span class="t2">Semana ${r.week_no}${r.due_on ? ` · meta ${date(r.due_on)}` : ''}${r.done_on ? ` · cumplido ${date(r.done_on)}` : ''}</span></span></label>`)}</div>`;
    };
    const rows = await loadInto(box, listMilestones, draw, { empty: () => emptyView('Sin hitos', 'Ejecuta 005_seed_catalogs.sql para cargar el plan.') });
    if (rows && editable) {
      box.addEventListener('change', async (e) => {
        const cb = e.target.closest('input[data-id]'); if (!cb) return;
        cb.disabled = true;
        try {
          const r = await setMilestoneDone(cb.dataset.id, cb.checked);
          const row = rows.find((x) => x.id === cb.dataset.id); row.done_on = r.done_on;
          paint(box, draw(rows)); toast(cb.checked ? 'Hito marcado como cumplido' : 'Hito reabierto', 'ok');
        } catch (err) { cb.checked = !cb.checked; cb.disabled = false; toast(friendlyError(err), 'bad'); }
      });
    }
  }
}
