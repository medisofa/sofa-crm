/** SOFA · Ficha de un caso de habilitación: etapas, datos del trámite, semáforo por requisito, evidencias e historial */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError, busy, opt, fieldError } from '../utils/ui.js';
import { getCase, caseItems, updateItem, updateCase, moveCase, caseActivity, leadContact, STAGES, STAGE_LABEL, ITEM_STATUS, CASE_KIND } from '../services/habilitation.js';
import { organizationContact, profileNames } from '../services/submissions.js';
import { listDocuments, uploadDocument, openDocument, fileProblem, sizeLabel } from '../services/documents.js';
import { money, date, dateTime, todayISO } from '../utils/formatters.js';
import { can, isStaff } from '../utils/permissions.js';
import { waLink } from '../utils/whatsapp.js';

const NEXT = { diagnostico: 'correccion', correccion: 'ensamblaje', ensamblaje: 'depositado', depositado: 'inspeccion', inspeccion: 'habilitado' };
const NEXT_LABEL = { correccion: 'Diagnóstico listo: pasar a corrección', ensamblaje: 'Brechas resueltas: armar expediente', depositado: 'Registrar depósito en DGHA', inspeccion: 'Pasar a inspección', habilitado: 'Marcar habilitado' };

export async function render(main, ctx) {
  const id = ctx.arg; const edit = can('hab.edit', ctx.role); const staff = isStaff(ctx.role);
  paint(main, html`<div id="h">${loadingView(8)}</div>`);
  const box = $('#h', main);
  let S = {};
  let areaFilter = '';

  async function refresh() {
    try {
      const c = await getCase(id);
      if (!c) { paint(box, emptyView('Caso no encontrado', 'No existe o tu rol no tiene acceso.', html`<a class="btn" href="#/habilitacion">Volver</a>`)); return; }
      const [items, docs, acts, contact] = await Promise.all([caseItems(id), listDocuments({ entityType: 'habilitation', entityId: id }), staff ? caseActivity(id).catch(() => []) : Promise.resolve([]),
        staff ? (c.organization_id ? organizationContact(c.organization_id) : c.lead_id ? leadContact(c.lead_id) : Promise.resolve(null)).catch(() => null) : Promise.resolve(null)]);
      const names = await profileNames(acts.map((a) => a.created_by)).catch(() => ({}));
      S = { c, items, docs, acts, contact, names }; draw();
    } catch (err) { console.error(err); paint(box, errorView(err)); }
  }

  function waMessage() {
    const { c, items } = S;
    const red = items.filter((i) => i.status === 'rojo'), yel = items.filter((i) => i.status === 'amarillo'), pend = items.filter((i) => i.status === 'pendiente');
    const lines = (arr) => arr.slice(0, 12).map((i) => `• ${i.requirement}${i.notes ? ` (${i.notes})` : ''}`).join('\n');
    return `Saludos. Resumen de la habilitación de ${c.establishment_name} (${c.ready_pct}% listo):\n`
      + (red.length ? `\nRequieren obra o inversión:\n${lines(red)}\n` : '')
      + (yel.length ? `\nCorregibles en menos de 15 días:\n${lines(yel)}\n` : '')
      + (pend.length ? `\nPendientes de revisar: ${pend.length}\n` : '')
      + (c.target_date ? `\nFecha objetivo: ${date(c.target_date)}.` : '') + '\n— SOFA';
  }

  function draw() {
    const { c, items, docs, acts, contact, names } = S;
    ctx.setTitle(c.folio || 'Habilitación');
    const idx = STAGES.indexOf(c.stage);
    const areas = [...new Set(items.map((i) => i.area))];
    const shown = areaFilter === 'abiertos' ? items.filter((i) => ['pendiente', 'amarillo', 'rojo'].includes(i.status)) : areaFilter ? items.filter((i) => i.area === areaFilter) : items;
    const docName = Object.fromEntries(docs.map((d) => [d.id, d]));
    const orgForDocs = c.organization_id || c.operator_id;
    const closed = ['habilitado', 'cancelado'].includes(c.stage);
    const wa = contact?.whatsapp ? waLink(contact.whatsapp, waMessage()) : null;

    paint(box, html`
      <div class="page-head"><div class="t"><p class="no-print"><a href="#/habilitacion">← Habilitación</a></p>
        <h2>${c.establishment_name} <span class="pill ${c.stage === 'habilitado' ? 'ok' : c.stage === 'cancelado' ? '' : 'info'}">${STAGE_LABEL[c.stage]}</span></h2>
        <p><span class="mono">${c.folio}</span> · ${c.establishment_type} · ${CASE_KIND[c.case_kind]}${staff && (c.client_name || c.lead_company) ? ` · ${c.client_name || c.lead_company}` : ''}${c.owner_name ? ` · Responsable: ${c.owner_name}` : ''}</p></div>
        <div class="toolbar no-print" style="margin:0">
          ${edit && NEXT[c.stage] ? html`<button class="btn primary" data-move="${NEXT[c.stage]}">${NEXT_LABEL[NEXT[c.stage]]}</button>` : ''}
          ${edit && ['ensamblaje', 'depositado', 'inspeccion'].includes(c.stage) ? html`<button class="btn" data-move="correccion">Volver a corrección</button>` : ''}
          ${edit && closed ? html`<button class="btn" data-move="diagnostico">Reabrir</button>` : ''}
          ${edit && c.stage === 'habilitado' ? html`<button class="btn" id="renew">Abrir renovación</button>` : ''}
          ${wa ? html`<a class="btn" target="_blank" rel="noopener" href="${wa}">Enviar brechas por WhatsApp</a>` : ''}
          <button class="btn" id="print">Imprimir informe</button>
          ${edit && !closed ? html`<button class="btn danger" data-move="cancelado">Cancelar</button>` : ''}
        </div></div>
      <ol class="stepper" aria-label="Etapas">${STAGES.map((s, i) => html`<li class="${c.stage === 'cancelado' ? '' : i < idx ? 'done' : i === idx ? 'now' : ''}" ${i === idx ? raw('aria-current="step"') : ''}>${i + 1}. ${STAGE_LABEL[s]}</li>`)}</ol>

      <div class="grid kpis">
        <div class="kpi"><div class="l">Listo</div><div class="v">${c.ready_pct}%</div><div class="h">${c.verde} de ${c.items_applicable} requisitos en verde</div></div>
        <div class="kpi"><div class="l">Semáforo</div><div class="v" style="font-size:18px"><span class="pill ok">${c.verde} verde</span> <span class="pill warn">${c.amarillo} amarillo</span> <span class="pill bad">${c.rojo} rojo</span></div><div class="h">${c.pendiente} sin evaluar · ${c.no_aplica} no aplican</div></div>
        <div class="kpi"><div class="l">Críticos abiertos</div><div class="v" style="${c.critical_open ? 'color:var(--bad)' : 'color:var(--ok)'}">${c.critical_open}</div><div class="h">Bloquean el ensamblaje</div></div>
        <div class="kpi"><div class="l">${c.stage === 'habilitado' ? 'Licencia vigente hasta' : 'Fecha objetivo'}</div><div class="v" style="font-size:20px">${c.stage === 'habilitado' ? date(c.license_valid_until) : date(c.target_date)}</div>
          <div class="h">${c.stage === 'habilitado' ? (c.license_days_left != null ? `${c.license_days_left} días` : '') : c.days_to_target != null ? (c.days_to_target < 0 ? `vencida hace ${-c.days_to_target} días` : `faltan ${c.days_to_target} días`) : ''}</div></div>
      </div>

      <div class="card" style="margin-top:14px"><h2>Datos del trámite</h2>
        ${edit ? html`<form id="fc" novalidate><div class="form-grid">
          <div class="field"><label for="c_target">Fecha objetivo</label><input id="c_target" name="target_date" type="date" value="${c.target_date || ''}"></div>
          <div class="field"><label for="c_file">No. de expediente DGHA</label><input id="c_file" name="dgha_file_number" value="${c.dgha_file_number || ''}" maxlength="60"></div>
          <div class="field"><label for="c_sub">Fecha de depósito</label><input id="c_sub" name="submitted_on" type="date" value="${c.submitted_on || ''}" max="${todayISO()}"></div>
          <div class="field"><label for="c_ins">Fecha de inspección</label><input id="c_ins" name="inspection_on" type="date" value="${c.inspection_on || ''}"></div>
          <div class="field"><label for="c_lic">No. de licencia</label><input id="c_lic" name="license_number" value="${c.license_number || ''}" maxlength="60"></div>
          <div class="field"><label for="c_val">Licencia vigente hasta</label><input id="c_val" name="license_valid_until" type="date" value="${c.license_valid_until || ''}"></div>
          <div class="field"><label for="c_pss">Código PSS (SISALRIL)</label><input id="c_pss" name="pss_code" value="${c.pss_code || ''}" maxlength="30"></div>
          <div class="field"><label for="c_fee">Honorario del servicio (RD$)</label><input id="c_fee" name="fee_amount" type="number" min="0" step="0.01" value="${c.fee_amount}"></div>
          <div class="field" style="grid-column:1/-1"><label for="c_notes">Notas</label><input id="c_notes" name="notes" value="${c.notes || ''}" maxlength="500"></div>
          </div><button class="btn" type="submit">Guardar datos</button></form>`
        : html`<dl class="kv"><dt>Expediente DGHA</dt><dd>${c.dgha_file_number || '—'}</dd><dt>Depositado</dt><dd>${date(c.submitted_on)}</dd><dt>Inspección</dt><dd>${date(c.inspection_on)}</dd>
            <dt>Licencia</dt><dd>${c.license_number || '—'}${c.license_valid_until ? ` · hasta ${date(c.license_valid_until)}` : ''}</dd><dt>Código PSS</dt><dd>${c.pss_code || '—'}</dd>${staff ? html`<dt>Honorario</dt><dd>${money(c.fee_amount)}</dd>` : ''}</dl>`}
      </div>

      <div class="card" style="margin-top:14px"><h2>Checklist de requisitos · ${items.length}</h2>
        <p class="sub">Verde: listo · Amarillo: corregible en menos de 15 días · Rojo: requiere obra o inversión. Los marcados <b>crítico</b> deben estar en verde para armar el expediente.</p>
        <div class="tabs no-print" id="areas" role="group" aria-label="Filtrar requisitos"><button data-a="" aria-pressed="${areaFilter === ''}">Todos</button><button data-a="abiertos" aria-pressed="${areaFilter === 'abiertos'}">Solo abiertos</button>${areas.map((a) => html`<button data-a="${a}" aria-pressed="${areaFilter === a}">${a.replace(/^\d+\.\s*/, '')}</button>`)}</div>
        ${shown.length ? areas.filter((a) => shown.some((i) => i.area === a)).map((a) => html`<h3 style="font-size:14px;margin:16px 0 2px">${a}</h3>
          ${shown.filter((i) => i.area === a).map((i) => html`<div class="hab-item" data-item="${i.id}">
            <span class="sem ${i.status}" aria-hidden="true"></span>
            <div><div style="font-weight:500">${i.requirement}${i.is_critical ? html` <span class="pill bad" style="font-size:10.5px">Crítico</span>` : ''}</div>
              <div class="small muted">${i.habilitation_requirements?.code || ''}${i.habilitation_requirements?.evidence_hint ? ` · Evidencia: ${i.habilitation_requirements.evidence_hint}` : ''}</div>
              ${edit ? html`<input class="input small" data-notes="${i.id}" value="${i.notes || ''}" placeholder="Observación o acción correctiva" maxlength="300" style="margin-top:6px;min-height:34px" aria-label="Observación">` : i.notes ? html`<div class="small" style="margin-top:4px">${i.notes}</div>` : ''}
              ${i.document_id && docName[i.document_id] ? html`<div class="small" style="margin-top:4px"><button class="btn link" data-open="${i.document_id}">Evidencia: ${docName[i.document_id].file_name}</button></div>` : ''}</div>
            <div class="ctl">
              ${edit ? html`<label class="sr-only" for="st-${i.id}">Estado</label><select id="st-${i.id}" class="input" data-status="${i.id}">${Object.entries(ITEM_STATUS).map(([k, [l]]) => opt(k, l, i.status))}</select>
                ${['amarillo', 'rojo'].includes(i.status) ? html`<label class="sr-only" for="due-${i.id}">Corregir antes de</label><input id="due-${i.id}" class="input" type="date" data-due="${i.id}" value="${i.due_on || ''}" title="Corregir antes de">` : ''}
                <label class="btn sm" style="cursor:pointer">Evidencia<input type="file" data-up="${i.id}" accept="application/pdf,image/jpeg,image/png,image/webp" hidden></label>`
              : html`<span class="pill ${ITEM_STATUS[i.status][1]}">${ITEM_STATUS[i.status][0]}</span>${i.due_on ? html`<span class="small muted">antes del ${date(i.due_on)}</span>` : ''}`}
            </div></div>`)}`)
          : html`<p class="small muted">Ningún requisito con este filtro.</p>`}
      </div>

      <div class="grid two" style="margin-top:14px">
        <div class="card"><h2>Expediente · ${docs.length} documentos</h2><div id="docLink"></div>
          ${docs.length ? html`<div class="list">${docs.map((d) => html`<div class="li"><div class="b"><div class="t1">${d.file_name}</div><div class="t2">${sizeLabel(d.size_bytes)} · ${dateTime(d.uploaded_at)}</div></div><button class="btn sm" data-open="${d.id}">Abrir</button></div>`)}</div>` : html`<p class="small muted">Sube la evidencia desde cada requisito.</p>`}</div>
        ${staff ? html`<div class="card"><h2>Historial</h2>${acts.length ? html`<div class="list">${acts.map((a) => html`<div class="li"><div class="b"><div class="t1" style="font-weight:500">${a.body}</div><div class="t2">${dateTime(a.occurred_at)}${names[a.created_by] ? ` · ${names[a.created_by]}` : ''}</div></div></div>`)}</div>` : html`<p class="small muted">Sin movimientos.</p>`}</div>` : ''}
      </div>`);
    bind(orgForDocs);
  }

  async function doMove(stage) {
    const d = await import('./habilitation-dialogs.js');
    let comment = null;
    if (stage === 'cancelado') { const r = await d.commentDialog('Cancelar el caso', true); if (!r) return; comment = r.comment; }
    try { await moveCase(id, stage, comment); toast(`Etapa: ${STAGE_LABEL[stage]}`, 'ok'); await refresh(); }
    catch (err) {
      const msg = String(err?.message || '');
      if (msg.includes('un Admin puede continuar')) {
        const reason = await d.overrideDialog(msg.replace(/ \(un Admin puede continuar.*\)$/, '')); if (!reason) return;
        try { await moveCase(id, stage, comment, reason); toast(`Etapa: ${STAGE_LABEL[stage]} (con excepción registrada)`, 'ok'); await refresh(); } catch (e2) { toast(friendlyError(e2), 'bad'); }
      } else toast(friendlyError(err), 'bad');
    }
  }

  function bind(orgForDocs) {
    box.querySelectorAll('[data-move]').forEach((b) => b.addEventListener('click', () => busy(b, () => doMove(b.dataset.move))));
    $('#print', box)?.addEventListener('click', () => window.print());
    $('#areas', box)?.addEventListener('click', (e) => { const b = e.target.closest('[data-a]'); if (b) { areaFilter = b.dataset.a; draw(); } });
    $('#renew', box)?.addEventListener('click', async () => {
      const { caseDialog } = await import('./habilitation-dialogs.js');
      const c = S.c;
      try { const nid = await caseDialog({ name: c.establishment_name, type: c.establishment_type, orgId: c.organization_id, kind: 'renovacion', target: c.license_valid_until }); if (nid) { toast('Renovación abierta', 'ok'); location.hash = `#/habilitacion/${nid}`; } }
      catch (err) { toast(friendlyError(err), 'bad'); }
    });
    $('#fc', box)?.addEventListener('submit', async (e) => {
      e.preventDefault(); const f = e.target;
      const v = Object.fromEntries(['target_date', 'dgha_file_number', 'submitted_on', 'inspection_on', 'license_number', 'license_valid_until', 'pss_code', 'notes'].map((k) => [k, f[k].value.trim() || null]));
      v.fee_amount = Number(f.fee_amount.value || 0);
      if (v.license_valid_until && v.license_valid_until < todayISO() && S.c.stage !== 'habilitado') { fieldError(f.license_valid_until, 'La vigencia ya pasó.'); return; }
      await busy(e.submitter, async () => { try { await updateCase(id, v); toast('Datos guardados', 'ok'); await refresh(); } catch (err) { toast(friendlyError(err), 'bad'); } });
    });
    box.querySelectorAll('[data-status]').forEach((s) => s.addEventListener('change', async () => {
      s.disabled = true;
      try { await updateItem(s.dataset.status, { status: s.value }); const it = S.items.find((i) => i.id === s.dataset.status); it.status = s.value; S.c = await getCase(id); draw(); }
      catch (err) { toast(friendlyError(err), 'bad'); s.disabled = false; }
    }));
    box.querySelectorAll('[data-notes]').forEach((n) => n.addEventListener('change', async () => {
      try { await updateItem(n.dataset.notes, { notes: n.value.trim() || null }); S.items.find((i) => i.id === n.dataset.notes).notes = n.value.trim() || null; toast('Observación guardada', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-due]').forEach((n) => n.addEventListener('change', async () => {
      try { await updateItem(n.dataset.due, { due_on: n.value || null }); S.items.find((i) => i.id === n.dataset.due).due_on = n.value || null; toast('Fecha guardada', 'ok'); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-up]').forEach((inp) => inp.addEventListener('change', async () => {
      const file = inp.files[0]; if (!file) return;
      const prob = file.type.startsWith('image/') ? null : fileProblem(file);
      if (prob) { toast(prob, 'bad'); return; }
      try {
        const doc = await uploadDocument({ orgId: orgForDocs, entityType: 'habilitation', entityId: id, file });
        await updateItem(inp.dataset.up, { document_id: doc.id });
        toast('Evidencia guardada', 'ok'); await refresh();
      } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', async () => {
      const doc = S.docs.find((d) => d.id === b.dataset.open); if (!doc) return;
      try { const url = await openDocument(doc); if (url) paint($('#docLink', box), html`<div class="note">Tu navegador bloqueó la ventana. <a href="${url}" target="_blank" rel="noopener">Abrir ${doc.file_name}</a> (válido 5 minutos).</div>`); }
      catch (err) { toast(friendlyError(err), 'bad'); }
    }));
  }
  await refresh();
}
