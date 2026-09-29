/** SOFA · Ficha de un concepto: datos, códigos, tarifas vigentes e histórico por ARS */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError, confirmDialog, busy, opt, fieldError } from '../utils/ui.js';
import { getProcedure, updateProcedure, deleteCode, tariffHistory, serviceTypes } from '../services/tariffs.js';
import { listArs } from '../services/catalog.js';
import { money, date, dateTime, todayISO, rangeContains } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { FAMILIES } from './tariff-dialogs.js';

const rangeParts = (r) => { const m = /^[\[(]([^,]*),([^\])]*)[\])]$/.exec(String(r || '')); return m ? [m[1] || null, m[2] || null] : [null, null]; };
const dayBefore = (iso) => { const d = new Date(`${iso}T00:00:00`); d.setDate(d.getDate() - 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

export async function render(main, ctx) {
  const id = ctx.arg; const edit = can('tariffs.edit', ctx.role);
  paint(main, html`<div id="c">${loadingView(6)}</div>`);
  const box = $('#c', main);
  const refresh = async () => {
    try {
      const [p, hist, ars, types] = await Promise.all([getProcedure(id), tariffHistory(id), listArs(), serviceTypes()]);
      if (!p) { paint(box, emptyView('Concepto no encontrado', '', html`<a class="btn" href="#/codificacion">Volver</a>`)); return; }
      draw(p, hist, Object.fromEntries(ars.map((a) => [a.id, a.name])), types);
    } catch (err) { paint(box, errorView(err)); }
  };
  const draw = (p, hist, arsMap, types) => {
    ctx.setTitle(p.internal_code);
    const today = todayISO();
    const current = hist.filter((t) => rangeContains(t.valid_during, today));
    const groups = {};
    hist.forEach((t) => { const k = `${t.ars?.name || arsMap[t.ars_id]}${t.providers ? ` · ${t.providers.full_name}` : ''}${t.ars_plans ? ` · Plan ${t.ars_plans.name}` : ''}`; (groups[k] = groups[k] || []).push(t); });
    paint(box, html`
      <div class="page-head"><div class="t"><p><a href="#/codificacion">← Codificación y tarifarios</a></p><h2>${p.description}</h2>
        <p><span class="mono">${p.internal_code}</span> · ${p.service_types?.name || p.service_type_code} · ${p.family}${p.is_active ? '' : ' · INACTIVO'}</p></div>
        ${edit ? html`<button class="btn primary" id="newT">+ Nueva tarifa</button>` : ''}</div>
      <div class="grid two">
        <div class="card"><h2>Datos del concepto</h2>
          ${edit ? html`<form id="fp" novalidate>
            <div class="field"><label for="pd">Descripción</label><input id="pd" name="description" value="${p.description}" maxlength="200"></div>
            <div class="form-grid"><div class="field"><label for="pt">Tipo de servicio</label><select id="pt" name="service_type_code">${types.map((t) => opt(t.code, t.name, p.service_type_code))}</select><span class="hint">Define los documentos obligatorios.</span></div>
            <div class="field"><label for="pf">Línea</label><select id="pf" name="family">${[...new Set([...FAMILIES, p.family])].map((x) => opt(x, x, p.family))}</select></div></div>
            <label class="check small" style="margin-bottom:10px"><input type="checkbox" name="is_active" ${p.is_active ? 'checked' : ''}> Activo (disponible para nuevos servicios)</label>
            <button class="btn" type="submit">Guardar</button></form>` : html`<p class="small">${p.source_note || ''}</p>`}
        </div>
        <div class="card"><h2>Códigos</h2><p class="sub">Un código no puede apuntar a dos conceptos del mismo sistema.</p>
          ${(p.procedure_codes || []).length ? html`<div class="list">${p.procedure_codes.map((c) => html`<div class="li"><div class="b"><div class="t1 mono">${c.code}</div><div class="t2">${c.code_system === 'ARS' ? `Propio de ${arsMap[c.ars_id] || 'ARS'}` : c.code_system}</div></div>${edit ? html`<button class="btn sm danger" data-rmc="${c.id}" aria-label="Quitar código ${c.code}">✕</button>` : ''}</div>`)}</div>` : html`<div class="note bad">Sin código: los servicios con este concepto fallan la validación "Código reconocido".</div>`}
          ${edit ? html`<button class="btn sm" id="addCode" style="margin-top:8px">+ Agregar código</button>` : ''}
        </div>
      </div>
      <div class="card" style="margin-top:14px"><h2>Tarifas vigentes hoy · ${current.length}</h2>
        ${current.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>ARS</th><th>Alcance</th><th class="n">Monto</th><th>Desde</th>${edit ? html`<th></th>` : ''}</tr></thead><tbody>
          ${current.sort((a, b) => (a.ars?.name || '').localeCompare(b.ars?.name || '')).map((t) => html`<tr><td data-l="ARS">${t.ars?.name}</td><td data-l="Alcance">${t.providers ? html`<span class="pill info">Negociada · ${t.providers.full_name}</span>` : t.ars_plans ? `Plan ${t.ars_plans.name}` : 'General'}</td>
            <td data-l="Monto" class="n"><b>${money(t.amount)}</b></td><td data-l="Desde">${date(rangeParts(t.valid_during)[0])}</td>
            ${edit ? html`<td data-l=""><button class="btn sm" data-newt="${t.ars_id}">Nueva tarifa</button></td>` : ''}</tr>`)}</tbody></table></div>`
          : html`<p class="small muted">Ninguna ARS tiene tarifa vigente para este concepto.</p>`}</div>
      <div class="card" style="margin-top:14px"><h2>Histórico de tarifas</h2><p class="sub">Nunca se borra: cada cambio cierra la tarifa anterior el día previo a la nueva vigencia.</p>
        ${Object.keys(groups).length ? html`${Object.entries(groups).sort((a, b) => a[0].localeCompare(b[0])).map(([k, rows]) => html`<h3 style="font-size:14px;margin:14px 0 4px">${k}</h3><div class="list">${rows.map((t) => { const [from, to] = rangeParts(t.valid_during); return html`<div class="li"><div class="b"><div class="t1">${money(t.amount)}</div><div class="t2">${date(from)} → ${to ? date(dayBefore(to)) : 'vigente'}${t.source ? ` · ${t.source}` : ''} · registrada ${dateTime(t.created_at)}</div></div>${!to ? html`<span class="pill ok">Vigente</span>` : ''}</div>`; })}</div>`)}` : html`<p class="small muted">Sin tarifas.</p>`}</div>`);

    $('#fp', box)?.addEventListener('submit', async (e) => {
      e.preventDefault(); const f = e.target;
      if (f.description.value.trim().length < 3) { fieldError(f.description, 'Muy corta.'); return; }
      await busy(e.submitter, async () => {
        try { await updateProcedure(id, { description: f.description.value.trim(), service_type_code: f.service_type_code.value, family: f.family.value, is_active: f.is_active.checked }); toast('Concepto actualizado', 'ok'); await refresh(); }
        catch (err) { toast(friendlyError(err), 'bad'); }
      });
    });
    box.querySelectorAll('[data-rmc]').forEach((b) => b.addEventListener('click', async () => {
      if (!(await confirmDialog('Quitar código', 'Los servicios ya registrados no cambian, pero las nuevas validaciones y cargas masivas dejarán de reconocerlo.', 'Quitar', true))) return;
      try { await deleteCode(b.dataset.rmc); toast('Código quitado', 'ok'); await refresh(); } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    const d = () => import('./tariff-dialogs.js');
    $('#addCode', box)?.addEventListener('click', async () => { try { if (await (await d()).codeDialog(p)) { toast('Código agregado', 'ok'); await refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
    const newT = async (ars) => { try { if (await (await d()).tariffDialog({ procedure: id, ars })) { toast('Tarifa registrada con su vigencia', 'ok'); await refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); } };
    $('#newT', box)?.addEventListener('click', () => newT());
    box.querySelectorAll('[data-newt]').forEach((b) => b.addEventListener('click', () => newT(b.dataset.newt)));
  };
  await refresh();
}
