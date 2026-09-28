/** SOFA · Ficha de una radicación: factura, validación, servicios, expediente digital e historial */
import { html, render as paint, raw, $ } from '../utils/dom.js';
import { loadingView, emptyView, errorView, toast, friendlyError, confirmDialog, busy, fieldError, opt } from '../utils/ui.js';
import {
  getSubmission, listLines, lineChecklist, requirements, documentTypes, lineChecks, transitionsFrom, statusHistory,
  validateSubmission, changeStatus, updateSubmission, deleteSubmission, deleteLine, profileNames, organizationContact
} from '../services/submissions.js';
import { listDocuments, uploadDocument, openDocument, deleteDocument, fileProblem, sizeLabel } from '../services/documents.js';
import { money, num, date, dateTime, period, todayISO } from '../utils/formatters.js';
import { subStatus, TRANSITION_LABELS, CODE_STATUS } from '../utils/constants.js';
import { can, isStaff } from '../utils/permissions.js';
import { isNCF } from '../utils/validation.js';
import { waLink } from '../utils/whatsapp.js';
import { lineDialog, importDialog, checklistDialog, radicarDialog, overrideDialog, commentDialog } from './submission-dialogs.js';

const EDITABLE = ['borrador', 'recibida', 'pendiente_documentos', 'en_depuracion'];
const daysTo = (iso) => (iso ? Math.round((new Date(`${iso}T00:00:00`) - new Date(`${todayISO()}T00:00:00`)) / 86400000) : null);
const kv = (pairs) => html`<dl class="kv">${pairs.map(([k, v]) => html`<dt>${k}</dt><dd>${v || '—'}</dd>`)}</dl>`;

export async function render(main, ctx) {
  const id = ctx.arg;
  paint(main, html`<div id="sub">${loadingView(6)}</div>`);
  const box = $('#sub', main);
  let S = {};

  async function load() {
    const sub = await getSubmission(id);
    if (!sub) return null;
    const [lines, lineCk, reqs, docs, trans, hist, val, types, org] = await Promise.all([
      listLines(id), lineChecklist(id), requirements(), listDocuments({ submissionId: id }), transitionsFrom(sub.status),
      statusHistory(id), validateSubmission(id, false), documentTypes(),
      isStaff(ctx.role) ? organizationContact(sub.organization_id).catch(() => null) : Promise.resolve(null)
    ]);
    const checks = await lineChecks(lines.map((l) => l.id));
    const names = await profileNames([...hist.map((h) => h.changed_by), ...docs.map((d) => d.uploaded_by)]).catch(() => ({}));
    return { sub, lines, lineCk, reqs, docs, trans, hist, val, types, org, checks, names };
  }

  async function refresh() {
    try {
      const data = await load();
      if (!data) { paint(box, emptyView('Radicación no encontrada', 'No existe o tu rol no tiene acceso.', html`<a class="btn" href="#/radicaciones">Volver</a>`)); return; }
      S = data; draw();
    } catch (err) { console.error(err); paint(box, errorView(err, 'rs')); box.querySelector('[data-retry]')?.addEventListener('click', refresh); }
  }

  function draw() {
    const { sub, lines, lineCk, docs, trans, hist, val, types, org, names } = S;
    ctx.setTitle(sub.folio);
    const role = ctx.role;
    const editable = EDITABLE.includes(sub.status) && can('subs.edit', role) && (role !== 'client' || sub.status === 'borrador');
    const moves = trans.filter((t) => t.allowed_roles.includes(role));
    const [lbl, cls] = subStatus(sub.display_status);
    const ckMap = Object.fromEntries(lineCk.map((c) => [c.service_line_id, c]));
    const lineName = Object.fromEntries(lines.map((l) => [l.id, l.patient_name]));
    const total = lines.reduce((t, l) => t + Number(l.amount), 0);
    const failing = val.items.filter((i) => !i.ok);
    const codeLbl = CODE_STATUS[sub.provider_code_status || 'sin_codigo'][0];
    const dl = daysTo(sub.payment_deadline);
    const moveLabel = (to) => (role === 'client' && to === 'recibida' ? 'Enviar a SOFA' : TRANSITION_LABELS[to] || to);

    paint(box, html`
    <div class="page-head"><div class="t"><p><a href="#/radicaciones">← Radicaciones</a></p>
      <h2><span class="mono">${sub.folio}</span> <span class="pill ${cls}">${lbl}</span></h2>
      <p>${isStaff(role) ? `${sub.client_name} · ` : ''}${sub.provider_name} · ${sub.ars_name} · ${period(sub.period)}${sub.sequence > 1 ? ` · complementaria #${sub.sequence}` : ''}</p></div>
      <div class="toolbar" style="margin:0">
        ${moves.map((t) => html`<button class="btn ${['lista_para_radicar', 'radicada', 'recibida'].includes(t.to_code) ? 'primary' : ''}" data-to="${t.to_code}">${moveLabel(t.to_code)}</button>`)}
        ${org ? (waLink(org.whatsapp) ? html`<a class="btn" id="wa" target="_blank" rel="noopener" href="${waLink(org.whatsapp, waMessage())}">Pedir faltantes por WhatsApp</a>` : html`<button class="btn" disabled title="El cliente no tiene WhatsApp registrado">WhatsApp</button>`) : ''}
        <button class="btn" id="csv">Exportar CSV</button>
        ${sub.status === 'borrador' && can('subs.delete', role) ? html`<button class="btn danger" id="del">Eliminar</button>` : ''}
      </div></div>
    ${sub.provider_code_status !== 'codificado' ? html`<div class="note warn">Código del prestador en ${sub.ars_name}: <b>${codeLbl}</b>. Sin código asignado, la ARS no paga. Regístralo en la ficha del cliente.</div>` : ''}
    ${role === 'client' && sub.status === 'borrador' ? html`<div class="note">Agrega los servicios del mes y sus documentos. Cuando termines, pulsa <b>Enviar a SOFA</b>: el equipo la revisará y la radicará ante la ARS.</div>` : ''}

    <div class="grid two">
      <div class="card"><h2>Factura y radicación</h2>
        ${editable ? html`<form id="ff" novalidate class="form-grid">
            <div class="field"><label for="ncf">NCF de la factura</label><input id="ncf" name="ncf" value="${sub.ncf || ''}" placeholder="B0100000125" maxlength="13" autocomplete="off"><span class="hint">B + 10 dígitos o E + 12 dígitos</span></div>
            <div class="field"><label for="invd">Fecha de la factura</label><input id="invd" name="invoice_date" type="date" value="${sub.invoice_date || ''}" max="${todayISO()}"></div>
            <div class="field" style="grid-column:1/-1"><label for="nts">Notas</label><input id="nts" name="notes" value="${sub.notes || ''}" maxlength="300"></div>
            <div><button class="btn" type="submit">Guardar factura</button></div></form>`
          : kv([['NCF', sub.ncf ? html`<span class="mono">${sub.ncf}</span>` : ''], ['Fecha de la factura', date(sub.invoice_date)], ['Notas', sub.notes]])}
        ${kv([['Radicada', sub.submitted_on ? date(sub.submitted_on) : ''], ['Recepción ARS', sub.ars_receipt_number ? html`<span class="mono">${sub.ars_receipt_number}</span>` : ''],
              ['Límite de pago', sub.payment_deadline ? html`${date(sub.payment_deadline)} <span class="small ${dl < 0 ? '' : 'muted'}" style="${dl < 0 ? 'color:var(--bad);font-weight:600' : ''}">(${dl < 0 ? `vencido hace ${-dl} días` : `faltan ${dl} días`})</span>` : '']])}
      </div>
      <div class="card"><h2>Validación prefacturación · ${val.passed} de ${val.total}</h2>
        <div class="list">${val.items.map((i) => html`<div class="li"><span aria-hidden="true" style="font-weight:700;color:${i.ok ? 'var(--ok)' : i.critical ? 'var(--bad)' : 'var(--warn)'}">${i.ok ? '✓' : i.critical ? '✕' : '!'}</span>
          <div class="b"><div class="t1" style="font-weight:500">${i.label}</div>${!i.ok && i.n > 1 ? html`<div class="t2">${i.ok_count} de ${i.n} servicios cumplen</div>` : ''}</div><span class="sr-only">${i.ok ? 'Aprobada' : 'Pendiente'}</span></div>`)}</div>
        <div class="small" style="margin-top:10px">Expediente <b>${sub.docs_pct}% completo</b> · ${num(sub.complete_lines)} de ${num(sub.lines)} servicios con todos sus documentos</div>
        <div style="height:10px;background:var(--surface-2);border-radius:6px;overflow:hidden;margin-top:6px"><div style="height:100%;width:${Math.min(100, sub.docs_pct)}%;background:var(--ok)"></div></div>
        ${!val.critical_ok && EDITABLE.includes(sub.status) ? html`<div class="note warn" style="margin-top:10px">No puede pasar a "Lista para radicar" hasta resolver las validaciones marcadas con ✕, salvo excepción autorizada por un administrador.</div>` : ''}
      </div>
    </div>

    ${sub.submitted_on ? html`<div class="grid kpis" style="margin-top:14px">
      <div class="kpi"><div class="l">Radicado</div><div class="v">${money(sub.claimed)}</div></div>
      <div class="kpi"><div class="l">Pagado</div><div class="v">${money(sub.paid)}</div></div>
      <div class="kpi"><div class="l">Glosado</div><div class="v">${money(sub.glosado)}</div><div class="h">${money(sub.glosa_in_dispute)} en disputa</div></div>
      <div class="kpi"><div class="l">Saldo</div><div class="v">${money(sub.balance)}</div><div class="h">${sub.age_days} días desde la radicación</div></div></div>` : ''}

    <div class="card" style="margin-top:14px"><h2>Servicios del período · ${num(lines.length)} · ${money(total)}</h2>
      ${editable ? html`<div class="toolbar"><button class="btn primary" id="addLine">+ Agregar servicio</button><button class="btn" id="import">Carga masiva</button></div>` : ''}
      ${lines.length ? html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fecha</th><th>Afiliado</th><th>NSS</th><th>Autorización</th><th>Concepto</th><th class="n">Cant.</th><th class="n">Unitario</th><th class="n">Total</th><th>Documentos</th>${editable ? html`<th></th>` : ''}</tr></thead>
        <tbody>${lines.map((l) => {
          const ck = ckMap[l.id] || { pct: 0, required: 0 };
          const over = l.tariff_amount != null && Number(l.unit_amount) > Number(l.tariff_amount);
          return html`<tr>
            <td data-l="Fecha">${date(l.service_date)}</td>
            <td data-l="Afiliado">${l.patient_name}${l.patient_doc ? html`<div class="small muted mono">${l.patient_doc}</div>` : ''}</td>
            <td data-l="NSS" class="mono">${l.member_number || html`<span class="pill bad">Falta</span>`}</td>
            <td data-l="Autorización" class="mono">${l.authorization_number || html`<span class="pill bad">Falta</span>`}</td>
            <td data-l="Concepto">${l.procedures?.description}<div class="small muted">${l.procedures?.internal_code}</div></td>
            <td data-l="Cant." class="n">${num(l.quantity)}</td>
            <td data-l="Unitario" class="n">${money(l.unit_amount)}${l.tariff_amount == null ? html`<div><span class="pill warn">Sin tarifa</span></div>` : over ? html`<div><span class="pill bad">Supera ${money(l.tariff_amount)}</span></div>` : ''}</td>
            <td data-l="Total" class="n"><b>${money(l.amount)}</b></td>
            <td data-l="Documentos"><button class="btn sm" data-ck="${l.id}"><span class="pill ${ck.pct >= 100 ? 'ok' : ck.pct > 0 ? 'warn' : 'bad'}">${ck.required ? `${ck.pct}%` : 'N/A'}</span></button></td>
            ${editable ? html`<td data-l=""><button class="btn sm" data-edit="${l.id}">Editar</button> <button class="btn sm danger" data-rm="${l.id}" aria-label="Eliminar servicio de ${l.patient_name}">✕</button></td>` : ''}</tr>`;
        })}</tbody></table></div>` : emptyView('Sin servicios', editable ? 'Agrega el primer servicio o usa la carga masiva para pegar las filas desde Excel.' : 'Esta radicación no tiene servicios.')}
    </div>

    <div class="grid two" style="margin-top:14px">
      <div class="card"><h2>Expediente digital · ${num(docs.length)}</h2><p class="sub">Documentos privados: se abren con un enlace temporal de 5 minutos.</p>
        ${can('docs.upload', role) ? html`<form id="fu" novalidate class="form-grid">
          <div class="field"><label for="dtype">Tipo de documento</label><select id="dtype" name="type">${types.map((t) => opt(t.code, t.name, 'factura_ncf'))}</select></div>
          <div class="field"><label for="dline">Servicio</label><select id="dline" name="line"><option value="">Toda la radicación</option>${lines.map((l) => opt(l.id, `${date(l.service_date)} · ${l.patient_name}`))}</select></div>
          <div class="field" style="grid-column:1/-1"><label for="dfile">Archivo (PDF, JPG, PNG o WEBP, hasta 10 MB)</label><input id="dfile" name="file" type="file" accept="application/pdf,image/jpeg,image/png,image/webp"></div>
          <div><button class="btn primary" type="submit">Subir documento</button></div></form>` : ''}
        <div id="docLink"></div>
        ${docs.length ? html`<div class="list">${docs.map((d) => html`<div class="li"><div class="b"><div class="t1">${d.file_name}</div>
            <div class="t2">${d.document_types?.name || 'Sin tipo'}${d.service_line_id ? ` · ${lineName[d.service_line_id] || 'servicio'}` : ' · toda la radicación'} · ${sizeLabel(d.size_bytes)} · ${dateTime(d.uploaded_at)}${names[d.uploaded_by] ? ` · ${names[d.uploaded_by]}` : ''}</div></div>
            <button class="btn sm" data-open="${d.id}">Abrir</button>${can('docs.delete', role) ? html` <button class="btn sm danger" data-drm="${d.id}" aria-label="Eliminar ${d.file_name}">✕</button>` : ''}</div>`)}</div>`
          : html`<p class="small muted">Aún no hay documentos.</p>`}
      </div>
      <div class="card"><h2>Historial</h2>
        <div class="list">${hist.map((h) => html`<div class="li"><div class="b"><div class="t1" style="font-weight:500">${h.from_status ? `${subStatus(h.from_status)[0]} → ` : ''}${subStatus(h.to_status)[0]}${h.is_override ? html` <span class="pill warn">Excepción</span>` : ''}</div>
          <div class="t2">${dateTime(h.changed_at)}${names[h.changed_by] ? ` · ${names[h.changed_by]}` : ''}${h.comment ? ` · ${h.comment}` : ''}</div></div></div>`)}</div>
      </div>
    </div>`);
    bind(editable);
  }

  function waMessage() {
    const { sub, lines, lineCk } = S;
    const missing = S.val.items.filter((i) => !i.ok).map((i) => `• ${i.label}${i.n > 1 ? ` (${i.n - i.ok_count} servicios)` : ''}`);
    const noDocs = lines.filter((l) => (lineCk.find((c) => c.service_line_id === l.id)?.pct ?? 100) < 100).length;
    return `Saludos. Para radicar la cuenta ${sub.folio} de ${sub.ars_name} (${period(sub.period)}) necesitamos completar:\n${missing.join('\n') || '• Revisión final'}${noDocs ? `\nHay ${noDocs} servicio(s) con documentos pendientes.` : ''}\nPuede enviarlos por aquí mismo. Gracias. — SOFA`;
  }

  function exportCsv() {
    const { sub, lines } = S;
    const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const head = ['Folio', 'Prestador', 'ARS', 'Período', 'Fecha', 'Afiliado', 'Cédula', 'NSS', 'Autorización', 'Código', 'Concepto', 'Cantidad', 'Unitario', 'Total', 'Tarifa'];
    const rows = lines.map((l) => [sub.folio, sub.provider_name, sub.ars_name, sub.period.slice(0, 7), l.service_date, l.patient_name, l.patient_doc, l.member_number, l.authorization_number,
      l.procedures?.internal_code, l.procedures?.description, l.quantity, l.unit_amount, l.amount, l.tariff_amount]);
    const csv = '\uFEFF' + [head, ...rows].map((r) => r.map(q).join(';')).join('\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = `${sub.folio}-desglose.csv`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function doMove(to) {
    const { sub, trans } = S;
    const opts = {};
    try {
      if (to === 'radicada') { const r = await radicarDialog(sub); if (!r) return; Object.assign(opts, r); }
      if (to === 'rechazada' || to === 'cerrada') {
        const r = await commentDialog(to === 'rechazada' ? 'Rechazada por la ARS' : 'Cerrar radicación', to === 'rechazada'); if (!r) return; opts.comment = r.comment;
      }
      if (trans.find((t) => t.to_code === to)?.requires_validation) {
        const v = await validateSubmission(id, false);
        if (!v.critical_ok) {
          if (!['super_admin', 'admin'].includes(ctx.role)) { toast(`Hay validaciones críticas pendientes (${v.passed} de ${v.total}). Corrígelas o pide a un administrador que autorice la excepción.`, 'bad'); return; }
          const reason = await overrideDialog(v.items.filter((i) => !i.ok && i.critical)); if (!reason) return; opts.override = reason;
        }
      }
      await changeStatus(id, to, opts);
      toast(`Estado actualizado: ${subStatus(to)[0]}`, 'ok');
      await refresh();
    } catch (err) { toast(friendlyError(err), 'bad'); }
  }

  function bind(editable) {
    box.querySelectorAll('[data-to]').forEach((b) => b.addEventListener('click', () => busy(b, () => doMove(b.dataset.to))));
    $('#csv', box)?.addEventListener('click', exportCsv);
    $('#del', box)?.addEventListener('click', async () => {
      if (!(await confirmDialog('Eliminar radicación', `Se eliminará ${S.sub.folio} con sus ${S.lines.length} servicios. Esta acción no se puede deshacer.`, 'Eliminar', true))) return;
      try { await deleteSubmission(id); toast('Radicación eliminada', 'ok'); location.hash = '#/radicaciones'; } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    $('#ff', box)?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = e.target; const ncf = f.ncf.value.trim().toUpperCase();
      if (ncf && !isNCF(ncf)) { fieldError(f.ncf, 'Formato: B + 10 dígitos o E + 12 dígitos.'); return; }
      fieldError(f.ncf, null);
      await busy(e.submitter, async () => {
        try { await updateSubmission(id, { ncf: ncf || null, invoice_date: f.invoice_date.value || null, notes: f.notes.value.trim() || null }); toast('Factura guardada', 'ok'); await refresh(); }
        catch (err) { toast(friendlyError(err), 'bad'); }
      });
    });
    $('#addLine', box)?.addEventListener('click', async () => { try { if (await lineDialog(S.sub)) { toast('Servicio agregado', 'ok'); await refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); } });
    $('#import', box)?.addEventListener('click', async () => {
      try {
        const r = await importDialog(S.sub); if (!r) return;
        await refresh();
        const errs = r.rows.filter((x) => !x.ok);
        toast(`${r.inserted} servicios agregados${r.duplicates ? ` · ${r.duplicates} duplicados omitidos` : ''}${r.errors ? ` · ${r.errors} con error` : ''}`, r.errors ? '' : 'ok');
        if (errs.length) {
          await confirmDialog('Filas no importadas', html`${errs.slice(0, 40).map((x) => html`<div class="small"><b>Fila ${x.row}:</b> ${x.error}</div>`)}${errs.length > 40 ? html`<div class="small muted">…y ${errs.length - 40} más</div>` : ''}`, 'Entendido');
        }
      } catch (err) { toast(friendlyError(err), 'bad'); }
    });
    box.querySelectorAll('[data-edit]').forEach((b) => b.addEventListener('click', async () => {
      const line = S.lines.find((l) => l.id === b.dataset.edit);
      try { if (await lineDialog(S.sub, line)) { toast('Servicio actualizado', 'ok'); await refresh(); } } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-rm]').forEach((b) => b.addEventListener('click', async () => {
      const line = S.lines.find((l) => l.id === b.dataset.rm);
      if (!(await confirmDialog('Eliminar servicio', `${line.patient_name} · ${date(line.service_date)} · ${money(line.amount)}`, 'Eliminar', true))) return;
      try { await deleteLine(line.id); toast('Servicio eliminado', 'ok'); await refresh(); } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-ck]').forEach((b) => b.addEventListener('click', async () => {
      const line = S.lines.find((l) => l.id === b.dataset.ck);
      await checklistDialog(line, S.reqs, S.checks, editable);
      await refresh();
    }));
    $('#fu', box)?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = e.target; const file = f.file.files[0];
      const prob = file ? (file.type.startsWith('image/') ? null : fileProblem(file)) : 'Selecciona un archivo.';
      if (prob) { fieldError(f.file, prob); return; }
      fieldError(f.file, null);
      await busy(e.submitter, async () => {
        try {
          await uploadDocument({ orgId: S.sub.organization_id, submissionId: id, lineId: f.line.value || null, docType: f.type.value || null, file });
          toast('Documento guardado en el expediente', 'ok'); await refresh();
        } catch (err) { toast(friendlyError(err), 'bad'); }
      });
    });
    box.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', async () => {
      const doc = S.docs.find((d) => d.id === b.dataset.open);
      try {
        const url = await openDocument(doc);
        if (url) paint($('#docLink', box), html`<div class="note">Tu navegador bloqueó la ventana. <a href="${url}" target="_blank" rel="noopener">Abrir ${doc.file_name}</a> (enlace válido por 5 minutos).</div>`);
      } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
    box.querySelectorAll('[data-drm]').forEach((b) => b.addEventListener('click', async () => {
      const doc = S.docs.find((d) => d.id === b.dataset.drm);
      if (!(await confirmDialog('Eliminar documento', `Se eliminará ${doc.file_name} del expediente.`, 'Eliminar', true))) return;
      try { await deleteDocument(doc); toast('Documento eliminado', 'ok'); await refresh(); } catch (err) { toast(friendlyError(err), 'bad'); }
    }));
  }

  await refresh();
}
