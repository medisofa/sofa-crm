/**
 * SOFA · Médico 360 (Iteración 15). Lista de médicos y ficha por médico: datos, cliente, onboarding,
 * contratos por ARS, clínicas, secretarias, reclamaciones por estado, montos y últimos lotes.
 * Todo respeta RLS: cada rol ve solo lo suyo (el Capturador, sus médicos y sin lo pagado).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { loadInto, loadingView, emptyView, errorView } from '../utils/ui.js';
import { money, num, date, period } from '../utils/formatters.js';
import { claimStatus, subStatus } from '../utils/constants.js';
import { can, canOpen, isStaff } from '../utils/permissions.js';
import { sb } from '../supabase.js';
import { provider360 } from '../services/crm.js';

const must = ({ data, error }) => { if (error) throw error; return data; };
const listProviders = (q) => {
  let r = sb().from('providers').select('id, full_name, specialty, exequatur, is_active, organization_id, organizations(legal_name, status)').order('full_name').limit(200);
  if (q) r = r.ilike('full_name', `%${q.replace(/[%_]/g, '')}%`);
  return r.then(must);
};
const link = (href, role, content) => (canOpen(href, role) ? html`<a href="${href}">${content}</a>` : html`<span>${content}</span>`);

export async function render(main, ctx) {
  if (ctx.arg) return renderOne(main, ctx);
  paint(main, html`<div class="page-head"><div class="t"><h2>Médicos 360</h2><p>Todo lo de cada médico en una sola ficha: contratos, reclamaciones, cobros, documentos e implementación.</p></div></div>
    <div class="toolbar"><label class="sr-only" for="q">Buscar médico</label><input class="input grow" id="q" type="search" placeholder="Nombre del médico"></div><div id="l"></div>`);
  const box = $('#l', main);
  const load = (q = '') => loadInto(box, () => listProviders(q), (rows) => html`<div class="list">${rows.map((p) => html`<a class="li" href="#/medicos/${p.id}" style="text-decoration:none;color:inherit">
      <div class="b"><div class="t1">${p.full_name}${p.is_active ? '' : html` <span class="pill">Inactivo</span>`}</div><div class="t2">${[p.specialty, p.organizations?.legal_name].filter(Boolean).join(' · ')}</div></div>
      ${p.organizations?.status === 'incorporacion' ? html`<span class="pill warn">En implementación</span>` : ''}</a>`)}</div>`,
    { isEmpty: (r) => !r.length, empty: () => emptyView('Sin médicos', 'No hay médicos visibles para tu usuario con ese nombre.') });
  let t; $('#q', main).addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => load(e.target.value.trim()), 300); });
  load();
}

async function renderOne(main, ctx) {
  paint(main, html`<div id="m360">${loadingView(6)}</div>`);
  const box = $('#m360', main); const role = ctx.role;
  let d;
  try { d = await provider360(ctx.arg); }
  catch (err) {
    if (err?.code === 'P0002') { paint(box, emptyView('Médico no disponible', 'No existe o tu usuario no tiene acceso a él.', html`<a class="btn" href="#/medicos">Volver</a>`)); return; }
    paint(box, errorView(err, 'm360')); return;
  }
  const p = d.provider; const c = d.client; const cl = d.claims || {}; const ob = d.onboarding;
  const money_ = can('claims.money', role);
  ctx.setTitle(p.full_name);
  const byStatus = Object.entries(cl.by_status || {}).sort((a, b) => b[1] - a[1]);
  paint(box, html`
    <div class="page-head"><div class="t"><p><a href="#/medicos">← Médicos 360</a></p><h2>${p.full_name}</h2>
      <p>${[p.specialty, p.exequatur && `Exequátur ${p.exequatur}`, p.tax_id && `Cédula ${p.tax_id}`].filter(Boolean).join(' · ') || 'Sin datos profesionales registrados'}${p.is_active ? '' : ' · Inactivo'}</p></div>
      <div class="toolbar" style="margin:0">${link(`#/clientes/${c.id}`, role, html`<span class="btn">Cliente: ${c.legal_name}</span>`)}${can('claims.capture', role) ? html`<a class="btn primary" href="#/captura">+ Captura rápida</a>` : ''}</div></div>
    ${!p.tax_id || !p.exequatur || !p.specialty ? html`<div class="note warn">Faltan datos del médico (cédula, exequátur o especialidad): se necesitan para los documentos A–E y el paso 3 del onboarding.</div>` : ''}
    <div class="grid kpis">
      <div class="kpi"><div class="l">Reclamaciones abiertas</div><div class="v">${num(cl.open)}</div><div class="h">${num(cl.total)} en total · ${num(cl.captured_30d)} en 30 días</div></div>
      <div class="kpi"><div class="l">Reclamado</div><div class="v">${money(cl.claimed)}</div></div>
      ${money_ ? html`<div class="kpi"><div class="l">Pagado</div><div class="v" style="color:var(--ok)">${money(cl.paid)}</div></div>
        <div class="kpi"><div class="l">Saldo en la ARS</div><div class="v">${money(cl.balance)}</div><div class="h">Glosado ${money(cl.glosado)}</div></div>` : ''}
      ${ob ? html`<div class="kpi"><div class="l">Implementación del cliente</div><div class="v">${ob.pct}%</div><div class="h">${ob.done} de ${ob.total} pasos${c.status === 'activo' ? ' · activo' : ''}</div></div>` : ''}
    </div>
    <div class="grid two" style="margin-top:14px">
      <div class="card"><h2>Contratos por ARS · ${num(d.ars.length)}</h2>${d.ars.length ? html`<div class="list">${d.ars.map((a) => html`<div class="li"><div class="b"><div class="t1">${a.ars}</div>
        <div class="t2">${num(a.services)} servicios contratados vigentes · desde ${date(a.from)}</div></div></div>`)}</div>` : html`<p class="small muted">Sin tarifario contractual vigente. Sin él, sus reclamaciones quedan "Pendiente de configuración".</p>`}
        ${link('#/contratos', role, html`<span class="small">Ver tarifario contractual →</span>`)}</div>
      <div class="card"><h2>Reclamaciones por estado</h2>${byStatus.length ? html`<div class="list">${byStatus.map(([k, n]) => { const [l, cls] = claimStatus(k); return html`<div class="li"><span class="pill ${cls}">${l}</span><div class="b"></div><b>${num(n)}</b></div>`; })}</div>`
        : html`<p class="small muted">Aún no tiene reclamaciones registradas.</p>`}${link('#/reclamaciones', role, html`<span class="small">Ir a Reclamaciones →</span>`)}</div>
      <div class="card"><h2>Clínicas</h2>${d.clinics.length ? html`<p>${d.clinics.join(' · ')}</p>` : html`<p class="small muted">Se completan con la clínica registrada en cada reclamación.</p>`}</div>
      <div class="card"><h2>Secretarias</h2>${d.secretaries.length ? html`<div class="list">${d.secretaries.map((s) => html`<div class="li"><div class="b"><div class="t1">${s.name}</div>
        <div class="t2">${[s.phone, s.clinic, s.inducted_on ? `inducida el ${date(s.inducted_on)}` : 'sin inducción registrada'].filter(Boolean).join(' · ')}</div></div></div>`)}</div>` : html`<p class="small muted">Sin secretarias registradas como contacto del cliente.</p>`}
        <p class="small">${num(d.capturers)} usuario(s) Capturador asignado(s) a este médico.</p></div>
      <div class="card" style="grid-column:1/-1"><h2>Últimos lotes de radicación</h2>${d.submissions.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Lote</th><th>ARS</th><th>Período</th><th>Estado</th><th class="n">Reclamado</th></tr></thead>
        <tbody>${d.submissions.map((s) => { const [l, cls] = subStatus(s.status); return html`<tr><td data-l="Lote" class="mono">${link(`#/radicaciones/${s.id}`, role, s.folio)}</td><td data-l="ARS">${s.ars}</td><td data-l="Período">${period(s.period)}</td>
          <td data-l="Estado"><span class="pill ${cls}">${l}</span></td><td data-l="Reclamado" class="n">${money(s.claimed)}</td></tr>`; })}</tbody></table></div>` : html`<p class="small muted">Sin lotes todavía.</p>`}</div>
    </div>
    ${isStaff(role) ? html`<p class="small muted" style="margin-top:10px">Documentos comerciales generados para este médico: ${num(d.documents)} · ${link(`#/clientes/${c.id}`, role, 'ver en la ficha del cliente')}</p>` : ''}`);
}
