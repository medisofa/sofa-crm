/** SOFA · 5.35.3 · «Mercadeo»: panel para registrar actividades (post, llamada, demo, referido) y
 *  gestionar el backlog de materiales (idea → en proceso → listo → publicado). No reemplaza al CRM:
 *  las actividades pueden enlazar a un lead (prospecto) o a una organización (cliente ya convertido)
 *  para medir cuáles canales convierten. Pantalla ejecutiva: super_admin, admin, operations. */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, formDialog, loadingView, emptyView, fieldError } from '../utils/ui.js';
import { date as fmtDate, todayISO } from '../utils/formatters.js';
import { can } from '../utils/permissions.js';
import { overview, saveActivity, saveMaterial } from '../services/mercadeo.js';

const CHANNELS = { whatsapp: 'WhatsApp', linkedin: 'LinkedIn', instagram: 'Instagram', llamada: 'Llamada', email: 'Correo', evento: 'Evento', referido: 'Referido', otro: 'Otro' };
const KINDS = { post: 'Post', mensaje: 'Mensaje directo', llamada: 'Llamada', demo: 'Demo', reunion: 'Reunión', visita: 'Visita', material: 'Entrega de material', otro: 'Otro' };
const OUTCOMES = { pendiente: ['Pendiente', ''], sin_respuesta: ['Sin respuesta', ''], interesado: ['Interesado', 'info'], demo_agendada: ['Demo agendada', 'warn'], no_interesado: ['No interesado', 'bad'], convertido: ['Convertido', 'ok'] };
const MAT_CHANNELS = { linkedin: 'LinkedIn', instagram: 'Instagram', whatsapp: 'WhatsApp', video: 'Video', pdf: 'PDF', email: 'Correo', otro: 'Otro' };
const MAT_STATUS = { idea: ['Idea', ''], en_proceso: ['En proceso', 'warn'], listo: ['Listo', 'info'], publicado: ['Publicado', 'ok'], pausado: ['Pausado', ''] };

/** rango por defecto: últimos 30 días */
function defaultRange() {
  const to = todayISO();
  const d = new Date(); d.setDate(d.getDate() - 30);
  const from = d.toISOString().slice(0, 10);
  return { from, to };
}

export async function render(main, ctx) {
  if (!can('mercadeo.view', ctx.role) && !['super_admin', 'admin', 'operations'].includes(ctx.role)) {
    paint(main, emptyView('Sin acceso', 'Este módulo es para el equipo de dirección y operaciones de SOFA.'));
    return;
  }
  const canEdit = ['super_admin', 'admin', 'operations'].includes(ctx.role);
  const range = defaultRange();

  paint(main, html`
    <div class="page-head">
      <div class="t"><h2>Mercadeo</h2><p>Actividades de captación, materiales en producción y conversión por canal.</p></div>
      ${canEdit ? html`<div class="toolbar" style="margin:0">
        <button class="btn primary" id="mk_new_act">+ Registrar actividad</button>
        <button class="btn" id="mk_new_mat">+ Nuevo material</button>
      </div>` : ''}
    </div>
    <div class="toolbar" style="margin:0 0 10px">
      <label>Desde <input class="input" id="mk_from" type="date" value="${range.from}"></label>
      <label>Hasta <input class="input" id="mk_to" type="date" value="${range.to}"></label>
    </div>
    <div id="mk_kpis"></div>
    <div class="grid two" style="align-items:start;margin-top:14px">
      <div class="card"><h2>Actividades</h2><div id="mk_acts"></div></div>
      <div class="card"><h2>Backlog de materiales</h2><div id="mk_mats"></div></div>
    </div>`);

  const alive = () => document.body.contains(main);
  async function load() {
    const from = $('#mk_from', main).value || null;
    const to = $('#mk_to', main).value || null;
    paint($('#mk_kpis', main), loadingView(2));
    paint($('#mk_acts', main), loadingView(3));
    paint($('#mk_mats', main), loadingView(3));
    try {
      const data = await overview(from, to);
      if (!alive()) return;
      drawKpis(data);
      drawActs(data);
      drawMats(data);
    } catch (err) {
      if (!alive()) return;
      const msg = html`<div class="note bad">${friendlyError(err)}</div>`;
      paint($('#mk_kpis', main), msg);
      paint($('#mk_acts', main), html``);
      paint($('#mk_mats', main), html``);
    }
  }

  function drawKpis(d) {
    const k = d.kpis || {};
    const totalInt = (k.interesados || 0) + (k.demos || 0) + (k.convertidos || 0);
    const conv = k.leads_tocados ? Math.round(((k.convertidos || 0) / k.leads_tocados) * 100) : 0;
    const byCh = Object.entries(d.by_channel || {}).sort((a, b) => b[1] - a[1]);
    paint($('#mk_kpis', main), html`
      <div class="grid kpis">
        <div class="kpi"><div class="l">Actividades</div><div class="v">${k.total || 0}</div><div class="h">${k.posts || 0} post · ${k.demos || 0} demo</div></div>
        <div class="kpi"><div class="l">Interés generado</div><div class="v">${totalInt}</div><div class="h">${k.interesados || 0} interesados · ${k.convertidos || 0} convertidos</div></div>
        <div class="kpi"><div class="l">Leads tocados</div><div class="v">${k.leads_tocados || 0}</div><div class="h">Conversión ${conv}%</div></div>
        <div class="kpi"><div class="l">Canal principal</div><div class="v">${byCh[0] ? (CHANNELS[byCh[0][0]] || byCh[0][0]) : '—'}</div><div class="h">${byCh.slice(0, 3).map(([k, n]) => `${CHANNELS[k] || k}: ${n}`).join(' · ')}</div></div>
      </div>`);
  }

  function drawActs(d) {
    const rows = d.activities || [];
    if (!rows.length) { paint($('#mk_acts', main), emptyView('Sin actividades en el rango', canEdit ? 'Usa «+ Registrar actividad» para empezar.' : '')); return; }
    paint($('#mk_acts', main), html`<div class="list">${rows.map((a) => {
      const [outL, outC] = OUTCOMES[a.outcome] || [a.outcome, ''];
      return html`<div class="li" style="align-items:flex-start">
        <b class="mono" style="width:76px">${fmtDate(a.activity_date)}</b>
        <div class="b">
          <div class="t1">${a.subject} <span class="pill info">${CHANNELS[a.channel] || a.channel}</span> <span class="pill">${KINDS[a.kind] || a.kind}</span> <span class="pill ${outC}">${outL}</span></div>
          <div class="t2">${[
            a.lead_company ? `Prospecto: ${a.lead_company}` : '',
            a.organization_name ? `Cliente: ${a.organization_name}` : '',
            a.actor_name ? `Registró: ${a.actor_name}` : ''
          ].filter(Boolean).join(' · ')}</div>
          ${a.notes ? html`<div class="small" style="margin-top:4px;white-space:pre-wrap">${a.notes}</div>` : ''}
        </div>
        ${canEdit ? html`<button class="btn sm" data-edit-act="${a.id}">Editar</button>` : ''}
      </div>`;
    })}</div>`);
  }

  function drawMats(d) {
    const rows = d.materials || [];
    if (!rows.length) { paint($('#mk_mats', main), emptyView('Sin materiales en el backlog', canEdit ? 'Usa «+ Nuevo material» para agregar el primero.' : '')); return; }
    paint($('#mk_mats', main), html`<div class="list">${rows.map((m) => {
      const [stL, stC] = MAT_STATUS[m.status] || [m.status, ''];
      return html`<div class="li" style="align-items:flex-start">
        <div class="b">
          <div class="t1"><b>${m.title}</b> <span class="pill info">${MAT_CHANNELS[m.channel] || m.channel}</span> <span class="pill ${stC}">${stL}</span></div>
          <div class="t2">${[
            m.due_date ? `Entrega ${fmtDate(m.due_date)}` : '',
            m.published_on ? `Publicado ${fmtDate(m.published_on)}` : '',
            m.owner_name ? `Dueño: ${m.owner_name}` : ''
          ].filter(Boolean).join(' · ')}</div>
          ${m.notes ? html`<div class="small" style="margin-top:4px;white-space:pre-wrap">${m.notes}</div>` : ''}
        </div>
        ${canEdit ? html`<button class="btn sm" data-edit-mat="${m.id}">Editar</button>` : ''}
      </div>`;
    })}</div>`);
  }

  // delegación de clicks (editar)
  main.addEventListener('click', async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    try {
      if (b.dataset.editAct) {
        const data = await overview($('#mk_from', main).value || null, $('#mk_to', main).value || null);
        const a = (data.activities || []).find((x) => String(x.id) === b.dataset.editAct);
        if (a && await activityDialog(a)) { toast('Actividad actualizada', 'ok'); load(); }
      } else if (b.dataset.editMat) {
        const data = await overview($('#mk_from', main).value || null, $('#mk_to', main).value || null);
        const m = (data.materials || []).find((x) => String(x.id) === b.dataset.editMat);
        if (m && await materialDialog(m)) { toast('Material actualizado', 'ok'); load(); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });

  $('#mk_from', main).addEventListener('change', load);
  $('#mk_to', main).addEventListener('change', load);
  if (canEdit) {
    $('#mk_new_act', main)?.addEventListener('click', async () => {
      try { if (await activityDialog()) { toast('Actividad registrada', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    $('#mk_new_mat', main)?.addEventListener('click', async () => {
      try { if (await materialDialog()) { toast('Material registrado', 'ok'); load(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    });
  }

  load();
}

/** Diálogo registrar/editar actividad. El vínculo a lead/organización es opcional y se escribe a mano
 *  por UUID: evitamos cargar todo el catálogo de prospectos aquí (lo hace el CRM). Si el usuario pega
 *  un UUID inválido, el backend responde con una violación de FK que friendlyError traduce. */
async function activityDialog(a = {}) {
  return formDialog({
    title: a.id ? 'Editar actividad' : 'Registrar actividad', submitLabel: 'Guardar', wide: true,
    body: html`<div class="form-grid">
      <div class="field"><label for="act_d">Fecha *</label><input id="act_d" name="activity_date" type="date" max="${todayISO()}" value="${a.activity_date || todayISO()}"></div>
      <div class="field"><label for="act_ch">Canal *</label><select id="act_ch" name="channel">${Object.entries(CHANNELS).map(([k, l]) => opt(k, l, a.channel || 'whatsapp'))}</select></div>
      <div class="field"><label for="act_k">Tipo *</label><select id="act_k" name="kind">${Object.entries(KINDS).map(([k, l]) => opt(k, l, a.kind || 'mensaje'))}</select></div>
      <div class="field"><label for="act_o">Resultado *</label><select id="act_o" name="outcome">${Object.entries(OUTCOMES).map(([k, [l]]) => opt(k, l, a.outcome || 'pendiente'))}</select></div>
      <div class="field" style="grid-column:1/-1"><label for="act_s">Asunto *</label><input id="act_s" name="subject" maxlength="200" value="${a.subject || ''}" placeholder="Qué se hizo o se publicó"></div>
      <div class="field"><label for="act_l">ID de prospecto (opcional)</label><input id="act_l" name="lead_id" value="${a.lead_id || ''}" placeholder="UUID"></div>
      <div class="field"><label for="act_g">ID de organización (opcional)</label><input id="act_g" name="organization_id" value="${a.organization_id || ''}" placeholder="UUID"></div>
      <div class="field" style="grid-column:1/-1"><label for="act_n">Notas</label><textarea id="act_n" name="notes" rows="3" maxlength="2000">${a.notes || ''}</textarea></div>
    </div>`,
    onSubmit: async (d, f) => {
      if (!d.subject?.trim()) { fieldError(f.elements.subject, 'Escribe el asunto'); return false; }
      return saveActivity({ id: a.id, ...d });
    }
  });
}

/** Diálogo registrar/editar material. */
async function materialDialog(m = {}) {
  return formDialog({
    title: m.id ? 'Editar material' : 'Nuevo material', submitLabel: 'Guardar', wide: true,
    body: html`<div class="form-grid">
      <div class="field" style="grid-column:1/-1"><label for="mat_t">Título *</label><input id="mat_t" name="title" maxlength="160" value="${m.title || ''}" placeholder="Carrusel: 3 errores al facturar SENASA"></div>
      <div class="field"><label for="mat_ch">Canal *</label><select id="mat_ch" name="channel">${Object.entries(MAT_CHANNELS).map(([k, l]) => opt(k, l, m.channel || 'linkedin'))}</select></div>
      <div class="field"><label for="mat_s">Estado *</label><select id="mat_s" name="status">${Object.entries(MAT_STATUS).map(([k, [l]]) => opt(k, l, m.status || 'idea'))}</select></div>
      <div class="field"><label for="mat_d">Entrega</label><input id="mat_d" name="due_date" type="date" value="${m.due_date || ''}"></div>
      <div class="field"><label for="mat_p">Publicado</label><input id="mat_p" name="published_on" type="date" value="${m.published_on || ''}"></div>
      <div class="field" style="grid-column:1/-1"><label for="mat_n">Notas</label><textarea id="mat_n" name="notes" rows="3" maxlength="2000">${m.notes || ''}</textarea></div>
    </div>`,
    onSubmit: async (d, f) => {
      if (!d.title?.trim()) { fieldError(f.elements.title, 'Escribe el título'); return false; }
      return saveMaterial({ id: m.id, ...d });
    }
  });
}
