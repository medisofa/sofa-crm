/** SOFA · Documentos: expediente digital de todas las radicaciones visibles para tu rol */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, opt } from '../utils/ui.js';
import { listDocuments, openDocument, sizeLabel } from '../services/documents.js';
import { documentTypes } from '../services/submissions.js';
import { sb } from '../supabase.js';
import { dateTime } from '../utils/formatters.js';

export async function render(main) {
  const st = { type: '' };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Documentos</h2><p>Los 200 documentos más recientes de los expedientes que tu rol puede ver. Para subir uno, abre la radicación.</p></div></div>
    <div class="toolbar"><label class="sr-only" for="dt">Tipo</label><select class="input" id="dt" style="width:auto"><option value="">Todos los tipos</option></select></div>
    <div id="docLink"></div><div id="l"></div>`);
  documentTypes().then((t) => paint($('#dt', main), html`<option value="">Todos los tipos</option>${t.map((x) => opt(x.code, x.name))}`)).catch(() => {});
  const list = $('#l', main);
  let docs = [];
  const load = () => loadInto(list, async () => {
    docs = await listDocuments({ type: st.type });
    const ids = [...new Set(docs.filter((d) => d.entity_type === 'submission').map((d) => d.entity_id))];
    let subs = {};
    if (ids.length) {
      const { data } = await sb().from('v_submissions').select('id, folio, provider_name, ars_name').in('id', ids);
      subs = Object.fromEntries((data || []).map((s) => [s.id, s]));
    }
    return docs.map((d) => ({ ...d, sub: subs[d.entity_id] }));
  }, (rows) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Documento</th><th>Tipo</th><th>Radicación</th><th>Tamaño</th><th>Subido</th><th></th></tr></thead>
    <tbody>${rows.map((d) => html`<tr>
      <td data-l="Documento">${d.file_name}</td><td data-l="Tipo">${d.document_types?.name || '—'}</td>
      <td data-l="Radicación">${d.sub ? html`<a href="#/radicaciones/${d.sub.id}" class="mono">${d.sub.folio}</a><div class="small muted">${d.sub.provider_name} · ${d.sub.ars_name}</div>` : '—'}</td>
      <td data-l="Tamaño">${sizeLabel(d.size_bytes)}</td><td data-l="Subido">${dateTime(d.uploaded_at)}</td>
      <td data-l=""><button class="btn sm" data-open="${d.id}">Abrir</button></td></tr>`)}</tbody></table></div>`,
  { empty: () => emptyView('Sin documentos', 'Los documentos se suben desde cada radicación.') });
  $('#dt', main).addEventListener('change', (e) => { st.type = e.target.value; load(); });
  list.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-open]'); if (!b) return;
    const doc = docs.find((d) => d.id === b.dataset.open);
    try { const url = await openDocument(doc); if (url) paint($('#docLink', main), html`<div class="note">Tu navegador bloqueó la ventana. <a href="${url}" target="_blank" rel="noopener">Abrir ${doc.file_name}</a> (válido 5 minutos).</div>`); }
    catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
}
