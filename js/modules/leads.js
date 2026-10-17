/** SOFA · Prospectos: todos los contactos comerciales y su última oportunidad */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, emptyView, opt } from '../utils/ui.js';
import { listLeads } from '../services/crm.js';
import { SOURCES, stageLabel, serviceName } from '../utils/constants.js';
import { date } from '../utils/formatters.js';
import { waLink, phoneFmt } from '../utils/whatsapp.js';
import { can, canOpen } from '../utils/permissions.js';
import { newProspectDialog } from './crm-dialogs.js';
import { rpc } from '../services/iter18.js';   // 5.15.0 · I72: marcar los que llegaron por el enlace público

/** 5.15.0 · I72 · Los estados de una solicitud, en el idioma de la pantalla. */
const SOL = { nueva: 'Nueva', por_revisar: 'Por revisar', en_contacto: 'En contacto',
  documentos_pendientes: 'Faltan documentos', lista: 'Lista para convertir',
  convertida: 'Convertida', descartada: 'Descartada' };

export async function render(main, ctx) {
  const st = { q: '', source: '' };
  paint(main, html`
    <div class="page-head"><div class="t"><h2>Prospectos</h2><p>Médicos y centros que aún no son clientes, con su canal de origen y su oportunidad más reciente.</p></div>
      ${can('crm.edit', ctx.role) ? html`<button class="btn primary" id="new">+ Nuevo prospecto</button>` : ''}</div>
    <div class="toolbar"><label class="sr-only" for="q">Buscar</label><input class="input grow" id="q" type="search" placeholder="Buscar por nombre o contacto">
      <label class="sr-only" for="src">Canal</label><select class="input" id="src" style="width:auto"><option value="">Todos los canales</option>${SOURCES.map((s) => opt(s))}</select></div>
    <div id="l"></div>`);
  const box = $('#l', main);
  // 5.15.0 · I72: se piden todas las solicitudes de una vez (no una por prospecto).
  // Si falla, la lista se pinta igual: la solicitud es un extra, no el dato principal.
  const conSolicitudes = async () => {
    const rows = await listLeads(st);
    if (!rows.length) return rows;
    const mapa = await rpc('lead_service_requests', { p_leads: rows.map((r) => r.id) }).catch(() => ({}));
    rows.forEach((r) => { r.solicitud = mapa[r.id] || null; });
    return rows;
  };
  // El Auditor ve la lista pero no abre la bandeja: se le muestra el folio sin enlace.
  const abreBandeja = canOpen('#/solicitudes', ctx.role);
  const load = () => loadInto(box, conSolicitudes, (rows) => {
    const bySrc = rows.reduce((m, r) => { m[r.source] = m[r.source] || [0, 0]; m[r.source][0]++; if (r.converted_org_id) m[r.source][1]++; return m; }, {});
    return html`<div class="grid kpis" style="margin-bottom:14px">${Object.entries(bySrc).sort((a, b) => b[1][0] - a[1][0]).slice(0, 4).map(([k, [n, w]]) => html`<div class="kpi"><div class="l">${k}</div><div class="v">${n}</div><div class="h">${w} convertidos en cliente</div></div>`)}</div>
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Prospecto</th><th>Contacto</th><th>Canal</th><th>Solicitud</th><th>Oportunidad</th><th>Registrado</th></tr></thead>
    <tbody>${rows.map((l) => {
      const last = (l.opportunities || []).slice().sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))[0];
      const wa = waLink(l.whatsapp);
      return html`<tr>
        <td data-l="Prospecto">${last ? html`<a href="#/oportunidades/${last.id}"><b>${l.company}</b></a>` : html`<b>${l.company}</b>`}<div class="small muted">${l.specialty || ''}</div></td>
        <td data-l="Contacto">${l.contact_name || '—'}<div class="small">${wa ? html`<a href="${wa}" target="_blank" rel="noopener">${phoneFmt(l.whatsapp)}</a>` : (l.email || '')}</div></td>
        <td data-l="Canal">${l.source}${l.referral_partners?.full_name ? html`<div class="small muted">Refirió: ${l.referral_partners.full_name}</div>` : ''}</td>
        <td data-l="Solicitud">${l.solicitud
          ? html`${abreBandeja ? html`<a href="#/solicitudes"><b>${l.solicitud.folio}</b></a>` : html`<b>${l.solicitud.folio}</b>`}<div class="small muted">${SOL[l.solicitud.estado] || l.solicitud.estado}${l.solicitud.documentos ? ` · ${l.solicitud.documentos} doc.` : ' · sin documentos'}</div>`
          : html`<span class="small muted">—</span>`}</td>
        <td data-l="Oportunidad">${l.converted_org_id ? html`<a class="pill ok" href="#/clientes/${l.converted_org_id}">Cliente</a>` : last ? html`<span class="pill ${last.stage === 'perdido' ? 'bad' : 'info'}">${stageLabel(last.stage)}</span> <span class="small muted">${serviceName(last.service_code)}</span>` : '—'}</td>
        <td data-l="Registrado">${date(l.created_at)}</td></tr>`;
    })}</tbody></table></div>`;
  }, { empty: () => emptyView(st.q || st.source ? 'Sin resultados' : 'Aún no hay prospectos', st.q || st.source ? 'Prueba con otros filtros.' : 'Registra el primero con "Nuevo prospecto".') });
  $('#new', main)?.addEventListener('click', async () => { const id = await newProspectDialog(); if (id) location.hash = `#/oportunidades/${id}`; });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value; load(); }, 350); });
  $('#src', main).addEventListener('change', (e) => { st.source = e.target.value; load(); });
  load();
}
