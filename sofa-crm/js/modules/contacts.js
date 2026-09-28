/** SOFA · Contactos de clientes y prospectos */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, toast, friendlyError, confirmDialog } from '../utils/ui.js';
import { listContacts, deleteContact } from '../services/crm.js';
import { waLink, phoneFmt } from '../utils/whatsapp.js';
import { can } from '../utils/permissions.js';
import { contactDialog } from './crm-dialogs.js';

export async function render(main, ctx) {
  const st = { q: '' };
  const edit = can('crm.edit', ctx.role), del = can('contacts.delete', ctx.role);
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Contactos</h2><p>Personas clave de cada cliente y prospecto. Para agregar uno, ábrelo desde la ficha del cliente o la oportunidad.</p></div></div>
    <div class="toolbar"><label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Buscar por nombre"></div>
    <div id="l"></div>`);
  const box = $('#l', main);
  let rows = [];
  const load = () => loadInto(box, async () => { rows = await listContacts(st); return rows; }, (list) => html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Nombre</th><th>De</th><th>Teléfono</th><th>Correo</th><th></th></tr></thead>
    <tbody>${list.map((c) => { const wa = waLink(c.whatsapp); return html`<tr>
      <td data-l="Nombre"><b>${c.full_name}</b>${c.is_primary ? html` <span class="pill info">Principal</span>` : ''}<div class="small muted">${c.role_title || ''}</div></td>
      <td data-l="De">${c.organization_id ? html`<a href="#/clientes/${c.organization_id}">${c.organizations?.legal_name || 'Cliente'}</a>` : html`${c.leads?.company || 'Prospecto'} <span class="small muted">(prospecto)</span>`}</td>
      <td data-l="Teléfono">${wa ? html`<a href="${wa}" target="_blank" rel="noopener">WhatsApp ${phoneFmt(c.whatsapp)}</a>` : phoneFmt(c.phone) || '—'}</td>
      <td data-l="Correo">${c.email ? html`<a href="mailto:${c.email}">${c.email}</a>` : '—'}</td>
      <td data-l="">${edit ? html`<button class="btn sm" data-edit="${c.id}">Editar</button>` : ''} ${del ? html`<button class="btn sm danger" data-del="${c.id}">Eliminar</button>` : ''}</td></tr>`; })}</tbody></table></div>`,
  { empty: () => emptyView(st.q ? 'Sin resultados' : 'Aún no hay contactos') });
  box.addEventListener('click', async (e) => {
    const ed = e.target.closest('[data-edit]'), dl = e.target.closest('[data-del]');
    if (ed) { const c = rows.find((x) => x.id === ed.dataset.edit); if (await contactDialog(ctx, null, c)) load(); }
    if (dl) {
      const c = rows.find((x) => x.id === dl.dataset.del);
      if (!(await confirmDialog('Eliminar contacto', `Se eliminará a ${c.full_name}. Esta acción queda en la auditoría.`, 'Eliminar', true))) return;
      try { await deleteContact(c.id); toast('Contacto eliminado', 'ok'); load(); } catch (err) { toast(friendlyError(err), 'bad'); }
    }
  });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; load(); }, 350); });
  load();
}
