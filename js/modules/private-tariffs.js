/** SOFA · Tarifas privadas por médico y servicio (Iteración 16). El precio del paciente privado sale de aquí. */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, toast, friendlyError, opt, formDialog, fieldError, emptyView } from '../utils/ui.js';
import { money, date, todayISO } from '../utils/formatters.js';
import { captureProviders, searchCatalog } from '../services/claims.js';
import { listPrivateTariffs, createPrivateTariff, inRange } from '../services/consultorio.js';

const rangeText = (r) => { const m = /^[[(]([^,]*),([^\])]*)[\])]$/.exec(r || ''); return m ? `${date(m[1])} – ${m[2] ? date(new Date(new Date(m[2]).getTime() - 864e5).toISOString().slice(0, 10)) : 'abierta'}` : r; };

export async function render(main, ctx) {
  paint(main, html`<div class="page-head"><div class="t"><h2>Tarifas privadas</h2><p>Precio de cada servicio para pacientes que pagan directo (sin ARS). Un cambio crea una vigencia nueva; la anterior se conserva.</p></div>
    <button class="btn primary" id="new">+ Nueva tarifa</button></div>
    <div class="toolbar"><label class="sr-only" for="tp_p">Médico</label><select class="input" id="tp_p" style="width:auto"></select>
      <label class="check"><input type="checkbox" id="tp_cur" checked> Solo vigentes hoy</label></div><div id="l"></div>`);
  const provs = await captureProviders().catch(() => []);
  if (!$('#tp_p', main)) return;
  if (!provs.length) { paint($('#l', main), emptyView('Sin médicos', 'No hay médicos visibles para tu usuario.')); return; }
  paint($('#tp_p', main), html`${provs.map((p) => opt(p.id, p.full_name))}`);
  const list = $('#l', main);
  const load = () => loadInto(list, () => listPrivateTariffs($('#tp_p', main).value), (rows) => {
    const today = todayISO(); const shown = $('#tp_cur', main).checked ? rows.filter((r) => inRange(r.valid_during, today)) : rows;
    return shown.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Servicio</th><th class="n">Precio privado</th><th>Vigencia</th><th>Estado</th></tr></thead><tbody>
      ${shown.map((r) => html`<tr><td data-l="Servicio">${r.procedures?.description || '—'}<div class="small muted mono">${r.procedures?.internal_code || ''}</div></td><td data-l="Precio" class="n"><b>${money(r.amount)}</b></td>
        <td data-l="Vigencia">${rangeText(r.valid_during)}${inRange(r.valid_during, today) ? html` <span class="pill ok">Hoy</span>` : ''}</td><td data-l="Estado">${r.status === 'vigente' ? 'Vigente' : 'Suspendida'}</td></tr>`)}</tbody></table></div>`
      : emptyView('Sin tarifas privadas', 'Agrega el precio de cada servicio que el médico cobra a pacientes privados.');
  }, { isEmpty: () => false });
  $('#tp_p', main).addEventListener('change', load); $('#tp_cur', main).addEventListener('change', load);
  $('#new', main).addEventListener('click', async () => {
    let pick = null;
    try {
      const ok = await formDialog({ title: 'Nueva tarifa privada', submitLabel: 'Guardar', wide: true,
        body: html`<div class="field"><label for="np_q">Servicio del catálogo *</label><input id="np_q" type="search" placeholder="Nombre, código, SIMON o CUPS" autocomplete="off"><div id="np_r" class="list" style="max-height:200px;overflow:auto"></div></div>
          <div class="form-grid"><div class="field"><label for="np_m">Precio (RD$) *</label><input id="np_m" name="amount" type="number" min="0.01" step="0.01"></div>
          <div class="field"><label for="np_f">Vigente desde *</label><input id="np_f" name="from" type="date" value="${todayISO()}"></div>
          <div class="field" style="grid-column:1/-1"><label for="np_n">Notas</label><input id="np_n" name="notes" maxlength="200"></div></div>`,
        onOpen: (f) => { const q = f.querySelector('#np_q'); const box = f.querySelector('#np_r'); let t;
          const run = async () => { try { const rows = await searchCatalog(q.value, 15); paint(box, html`${rows.map((r) => html`<label class="li" style="cursor:pointer"><input type="radio" name="proc" value="${r.id}"><div class="b"><div class="t1">${r.name}</div><div class="t2">${[r.internal_code, r.cups && `CUPS ${r.cups}`].filter(Boolean).join(' · ')}</div></div></label>`)}`); } catch (err) { paint(box, html`<div class="note bad">${friendlyError(err)}</div>`); } };
          q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 300); }); box.addEventListener('change', (e) => { if (e.target.name === 'proc') pick = e.target.value; }); run(); },
        onSubmit: async (d, f) => {
          if (!pick) { toast('Seleccione el servicio', 'bad'); return false; }
          if (!(Number(d.amount) > 0)) { fieldError(f.elements.amount, 'Mayor que cero'); return false; }
          return createPrivateTariff({ provider: $('#tp_p', main).value, procedure: pick, amount: d.amount, from: d.from, notes: d.notes });
        } });
      if (ok) { toast('Tarifa privada guardada', 'ok'); load(); }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}
