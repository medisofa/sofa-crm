/**
 * SOFA · Ficha del cliente, Iteración 15: implementación (onboarding de 9 pasos con activación)
 * y documentos A–E (generar, PDF con membrete, estado, copia firmada).
 */
import { html } from '../utils/dom.js';
import { loadInto, toast, friendlyError, opt, formDialog, fieldError } from '../utils/ui.js';
import { dateTime } from '../utils/formatters.js';
import { COMMERCIAL_DOCS, COMMERCIAL_DOC_STATUS, COMMERCIAL_DOC_TYPE } from '../utils/constants.js';
import { can } from '../utils/permissions.js';
import { onboardingStatus, setOnboardingStep, activateClient } from '../services/crm.js';
import { uploadDocument, listDocuments, openDocument, sizeLabel, listClientDocumentReviews, reviewClientDocument, clientDocumentArsOptions, listClientDocumentArs, linkClientDocumentArs } from '../services/documents.js';

const SRC = { automatico: ['Automático', 'ok'], manual: ['Marcado a mano', 'info'], pendiente: ['Pendiente', 'warn'] };

/** Implementación: barra de avance, 9 pasos y "Activar cliente" */
export function renderOnboarding(box, org, ctx, onChange = () => {}) {
  const manage = can('onboarding.manage', ctx.role); const admin = can('onboarding.override', ctx.role);
  const load = () => loadInto(box, () => onboardingStatus(org.id), (steps) => {
    const done = steps.filter((s) => s.done).length; const pct = Math.round((100 * done) / (steps.length || 9));
    return html`<div style="display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap">
        <div><b style="font-size:20px">${pct}%</b> <span class="small muted">${done} de ${steps.length} pasos</span></div>
        ${org.status === 'activo' ? html`<span class="pill ok">Cliente activo</span>` : manage ? html`<button class="btn primary" id="activate">Activar cliente</button>` : ''}</div>
      <div style="height:10px;background:var(--surface-2);border-radius:6px;overflow:hidden;margin:8px 0 12px" role="progressbar" aria-valuenow="${pct}" aria-valuemin="0" aria-valuemax="100" aria-label="Avance del onboarding">
        <div style="height:100%;width:${pct}%;background:${pct === 100 ? 'var(--ok)' : 'var(--navy)'}"></div></div>
      ${org.activation_override ? html`<div class="note warn small">${org.activation_override}</div>` : ''}
      <div class="list">${steps.map((s) => { const [l, c] = SRC[s.source] || [s.source, '']; return html`<div class="li">
        <span aria-hidden="true" style="font-weight:700;width:18px;color:${s.done ? 'var(--ok)' : 'var(--ink-3)'}">${s.done ? '✓' : s.step}</span>
        <div class="b"><div class="t1">${s.label}</div><div class="t2">${s.detail}${s.done_at ? ` · ${dateTime(s.done_at)}` : ''}</div></div>
        <span class="pill ${c}">${l}</span>
        ${manage && s.source === 'pendiente' ? html`<button class="btn sm" data-mark="${s.code}" data-label="${s.label}">Marcar</button>` : ''}
        ${manage && s.source === 'manual' ? html`<button class="btn sm" data-unmark="${s.code}">Desmarcar</button>` : ''}</div>`; })}</div>
      <p class="small muted">Los pasos con documento o con datos del sistema se cumplen solos. Márcalo a mano solo si se cumplió fuera del sistema, indicando cómo.</p>`;
  });
  box.addEventListener('click', async (e) => {
    const m = e.target.closest('[data-mark]'); const u = e.target.closest('[data-unmark]');
    try {
      if (m) {
        const ok = await formDialog({ title: `Marcar: ${m.dataset.label}`, submitLabel: 'Marcar como cumplido',
          body: html`<div class="field"><label for="ob_n">¿Cómo se cumplió? *</label><textarea id="ob_n" name="notes" rows="2" class="input" maxlength="300"></textarea></div>`,
          onSubmit: async (d, f) => { if ((d.notes || '').trim().length < 5) { fieldError(f.elements.notes, 'Mínimo 5 caracteres'); return false; } await setOnboardingStep(org.id, m.dataset.mark, true, d.notes.trim()); return true; } });
        if (ok) { toast('Paso marcado', 'ok'); load(); onChange(); }
      } else if (u) { await setOnboardingStep(org.id, u.dataset.unmark, false); toast('Paso desmarcado'); load(); onChange(); }
      else if (e.target.closest('#activate')) {
        const steps = await onboardingStatus(org.id); const pct = Math.round((100 * steps.filter((s) => s.done).length) / steps.length);
        if (pct < 100 && !admin) { toast(`El onboarding va en ${pct} %. Complétalo o pide a un administrador que active por excepción.`, 'bad'); return; }
        const r = await formDialog({ title: pct < 100 ? `Activar por excepción (onboarding en ${pct} %)` : 'Activar cliente', submitLabel: 'Activar',
          body: pct < 100 ? html`<div class="note warn">Faltan pasos del onboarding. La activación quedará registrada como EXCEPCIÓN con tu usuario y el motivo.</div>
            <div class="field"><label for="ac_r">Motivo (mínimo 10 caracteres) *</label><textarea id="ac_r" name="reason" rows="2" class="input"></textarea></div>`
            : html`<p>El onboarding está completo. El cliente pasa a <b>Activo</b> y la oportunidad se cierra como ganada.</p>`,
          onSubmit: async (d, f) => { if (pct < 100 && (d.reason || '').trim().length < 10) { fieldError(f.elements.reason, 'Mínimo 10 caracteres'); return false; } await activateClient(org.id, pct < 100 ? d.reason.trim() : null); return true; } });
        if (r) { toast('Cliente activado', 'ok'); onChange(true); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });
  load();
  return { reload: load };
}

/** Documentos A–E: modelos editables, carga del médico y revisión SOFA. */
const escDoc = (v) => String(v ?? '').replace(/[&<>"]/g, (ch) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[ch]));
const modelName = (code, arsName = '') => `SOFA_Modelo_${code}_${COMMERCIAL_DOCS[code].replace(/[^A-Za-z0-9]+/g,'_')}${arsName ? '_' + arsName.replace(/[^A-Za-z0-9]+/g,'_') : ''}.doc`;

function modelHtml(code, org, arsName = '') {
  const name = escDoc(org.legal_name || org.trade_name || '________________');
  const tax = escDoc(org.tax_id || '________________');
  const address = escDoc([org.address, org.city].filter(Boolean).join(', ') || '________________');
  const email = escDoc(org.email || '________________');
  const phone = escDoc(org.phone || org.whatsapp || '________________');
  const ars = escDoc(arsName || '________________');
  const legal = ['A','B'].includes(code)
    ? '<p style="border:2px solid #861D18;padding:10px"><b>MODELO DE TRABAJO — REQUIERE REVISIÓN LEGAL ANTES DE FIRMA O USO.</b></p>'
    : '<p style="border:1px solid #999;padding:10px"><b>MODELO OPERATIVO.</b> Revise y complete los campos pendientes antes de utilizarlo.</p>';

  const blocks = {
    A: `
      <h1>Contrato de servicios SOFA</h1>
      <p><b>Entre:</b> ${name}, RNC/Cédula ${tax}, con domicilio en ${address}, en adelante “EL CLIENTE”; y SOFA · Soluciones de Facturación Médica, en adelante “SOFA”.</p>
      <h2>1. Objeto</h2><p>Definir los servicios administrativos y de gestión contratados: ________________________________.</p>
      <h2>2. Alcance</h2><p>ARS / centros / especialidades incluidas: ________________________________.</p>
      <h2>3. Honorarios y forma de pago</h2><p>Modalidad y monto: ________________________________.</p>
      <h2>4. Obligaciones del cliente</h2><p>Entrega oportuna de información, autorizaciones y documentos necesarios para la gestión.</p>
      <h2>5. Obligaciones de SOFA</h2><p>Gestión diligente, trazabilidad, confidencialidad y reporte del estado de los procesos contratados.</p>
      <h2>6. Confidencialidad y protección de información</h2><p>Condiciones aplicables: ________________________________.</p>
      <h2>7. Vigencia, terminación y jurisdicción</h2><p>_______________________________.</p>
      <p>Firma EL CLIENTE: ____________________ &nbsp;&nbsp; Firma SOFA: ____________________</p>`,
    B: `
      <h1>Autorización de representación</h1>
      <p>Yo, __________________________________, actuando en nombre de ${name}, RNC/Cédula ${tax}, autorizo a SOFA · Soluciones de Facturación Médica a realizar, dentro del alcance contratado, gestiones administrativas relacionadas con facturación, codificación, reclamaciones, radicación, seguimiento y comunicación ante los centros de salud y/o ARS indicados por el cliente.</p>
      <p><b>Alcance específico autorizado:</b> ________________________________________________.</p>
      <p><b>ARS / centros aplicables:</b> ________________________________________________.</p>
      <p><b>Vigencia:</b> desde ____/____/______ hasta ____/____/______ o hasta revocación escrita conforme a lo contratado.</p>
      <p>Firma: ____________________ &nbsp; Cédula: ____________________ &nbsp; Fecha: ____/____/______</p>`,
    C: `
      <h1>Carta de presentación a la clínica / centro de salud</h1>
      <p>Fecha: ____/____/______</p>
      <p>Señores<br><b>________________________________</b><br>Ciudad</p>
      <p>Por medio de la presente, ${name} informa que SOFA · Soluciones de Facturación Médica apoyará la gestión administrativa de sus reclamaciones y procesos de facturación conforme a la autorización otorgada por el cliente.</p>
      <p>Solicitamos facilitar la coordinación operativa necesaria con el personal autorizado de SOFA para los procesos correspondientes.</p>
      <p>Contacto del cliente: ${phone} · ${email}</p>
      <p>Atentamente,</p><p>________________________________<br>Nombre / firma / sello</p>`,
    D: `
      <h1>Carta de representación ante ARS</h1>
      <p>Fecha: ____/____/______</p>
      <p>Señores<br><b>${ars}</b></p>
      <p>Por medio de la presente, ${name}, RNC/Cédula ${tax}, comunica que SOFA · Soluciones de Facturación Médica ha sido autorizada para apoyar las gestiones administrativas vinculadas a facturación, codificación, radicación y seguimiento de reclamaciones, dentro del alcance expresamente autorizado por el cliente.</p>
      <p><b>Código de prestador:</b> ____________________ &nbsp; <b>Especialidad:</b> ____________________</p>
      <p><b>Contacto autorizado:</b> ________________________________.</p>
      <p>Atentamente,</p><p>________________________________<br>Nombre / firma / sello</p>`,
    E: `
      <h1>Formulario de implementación SOFA</h1>
      <table border="1" cellspacing="0" cellpadding="6" width="100%">
        <tr><td><b>Cliente</b></td><td>${name}</td></tr>
        <tr><td><b>RNC/Cédula</b></td><td>${tax}</td></tr>
        <tr><td><b>Dirección</b></td><td>${address}</td></tr>
        <tr><td><b>Teléfono</b></td><td>${phone}</td></tr>
        <tr><td><b>Correo</b></td><td>${email}</td></tr>
        <tr><td><b>Prestador principal</b></td><td>____________________________</td></tr>
        <tr><td><b>Especialidad</b></td><td>____________________________</td></tr>
        <tr><td><b>ARS contratadas</b></td><td>____________________________</td></tr>
        <tr><td><b>Códigos de prestador</b></td><td>____________________________</td></tr>
        <tr><td><b>Centros / clínicas</b></td><td>____________________________</td></tr>
        <tr><td><b>Contacto operativo</b></td><td>____________________________</td></tr>
        <tr><td><b>Frecuencia de retiro / entrega</b></td><td>____________________________</td></tr>
        <tr><td><b>Observaciones</b></td><td><br><br><br></td></tr>
      </table>`
  };

  return `<!doctype html><html><head><meta charset="utf-8"><title>${escDoc(COMMERCIAL_DOCS[code])}</title>
    <style>body{font-family:Arial,sans-serif;font-size:11pt;line-height:1.45;margin:40px;color:#222}h1{color:#223A5D}h2{font-size:13pt;color:#223A5D}table{border-collapse:collapse}td{vertical-align:top}</style>
    </head><body>${legal}${blocks[code] || ''}<hr><p style="font-size:9pt;color:#666">SOFA · Soluciones de Facturación Médica · Modelo ${code}. Complete y revise antes de usar.</p></body></html>`;
}

function downloadModel(code, org, arsName = '') {
  const blob = new Blob([modelHtml(code, org, arsName)], { type: 'application/msword;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = modelName(code, arsName); document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function renderCommercialDocs(box, org, ctx, providers = []) {
  const canUpload = can('docs.upload', ctx.role) || can('clientdocs.upload', ctx.role);
  const canReview = ['super_admin','admin','assistant','operations'].includes(ctx.role);
  let docs = []; let reviews = []; let arsOptions = []; let arsLinks = [];

  const reviewState = (latest) => {
    const review = latest ? reviews.find((r) => r.document_id === latest.id) : null;
    const status = !latest ? ['Pendiente','warn']
      : !review ? ['Cargado por cliente','info']
      : review.status === 'aprobado' ? ['Aprobado','ok']
      : review.status === 'requiere_correccion' ? ['Requiere corrección','bad']
      : ['En revisión SOFA','warn'];
    return { review, status };
  };

  const standardCard = (code, title, list) => {
    const type = COMMERCIAL_DOC_TYPE[code];
    const files = list.filter((d) => d.document_type_code === type);
    const latest = files[0] || null;
    const { review, status } = reviewState(latest);
    const legal = ['A','B'].includes(code);
    return html`<div class="li commercial-doc-row">
      <div class="commercial-doc-code">${code}</div>
      <div class="b">
        <div class="t1">${title}</div>
        <div class="t2">${legal ? 'Modelo de trabajo · requiere revisión legal antes de firma/uso.' : 'Modelo operativo editable.'}</div>
        <div class="small" style="margin-top:5px"><span class="pill ${status[1]}">${status[0]}</span>${latest ? ` · ${latest.file_name} · ${sizeLabel(latest.size_bytes)} · ${dateTime(latest.uploaded_at)}` : ''}</div>
        ${review?.notes ? html`<div class="note ${review.status === 'requiere_correccion' ? 'bad' : 'info'} small" style="margin-top:6px"><b>Observación SOFA:</b> ${review.notes}</div>` : ''}
      </div>
      <div class="toolbar commercial-doc-actions">
        <button class="btn sm" data-model="${code}" type="button">Descargar modelo</button>
        ${latest ? html`<button class="btn sm" data-open-doc="${latest.id}" type="button">Ver cargado</button>` : ''}
        ${canUpload ? html`<label class="btn sm" style="cursor:pointer">${latest ? 'Subir nueva versión' : 'Subir documento'}<input type="file" data-upload-doc="${code}" accept="application/pdf,image/jpeg,image/png" hidden></label>` : ''}
        ${canReview && latest ? html`<button class="btn sm" data-review-doc="${latest.id}" data-review-code="${code}" type="button">Revisar</button>` : ''}
      </div>
    </div>`;
  };

  const documentD = (list) => html`<div class="li commercial-doc-row">
    <div class="commercial-doc-code">D</div>
    <div class="b">
      <div class="t1">Carta de representación ante ARS</div>
      <div class="t2">Se gestiona una carta independiente por cada ARS vinculada al cliente.</div>
      ${arsOptions.length ? html`<div class="list" style="margin-top:8px">
        ${arsOptions.map((a) => {
          const ids = new Set(arsLinks.filter((x) => x.ars_id === a.ars_id).map((x) => x.document_id));
          const latest = list.find((d) => d.document_type_code === 'carta_ars' && ids.has(d.id)) || null;
          const { review, status } = reviewState(latest);
          return html`<div class="li commercial-doc-ars-row">
            <div class="b">
              <div class="t1">${a.ars_name}</div>
              <div class="small"><span class="pill ${status[1]}">${status[0]}</span>${latest ? ` · ${latest.file_name} · ${dateTime(latest.uploaded_at)}` : ''}</div>
              ${review?.notes ? html`<div class="note ${review.status === 'requiere_correccion' ? 'bad' : 'info'} small" style="margin-top:5px"><b>Observación SOFA:</b> ${review.notes}</div>` : ''}
            </div>
            <div class="toolbar commercial-doc-actions">
              <button class="btn sm" data-model="D" data-model-ars="${a.ars_name}" type="button">Descargar modelo</button>
              ${latest ? html`<button class="btn sm" data-open-doc="${latest.id}" type="button">Ver cargado</button>` : ''}
              ${canUpload ? html`<label class="btn sm" style="cursor:pointer">${latest ? 'Nueva versión' : 'Subir carta'}<input type="file" data-upload-doc="D" data-upload-ars="${a.ars_id}" accept="application/pdf,image/jpeg,image/png" hidden></label>` : ''}
              ${canReview && latest ? html`<button class="btn sm" data-review-doc="${latest.id}" data-review-code="D" data-review-ars="${a.ars_name}" type="button">Revisar</button>` : ''}
            </div>
          </div>`;
        })}
      </div>` : html`<div class="note warn small" style="margin-top:8px">Este cliente todavía no tiene ARS vinculadas en tarifarios o radicaciones. Cuando se configure una ARS, aparecerá aquí automáticamente.</div>`}
    </div>
  </div>`;

  const load = () => loadInto(box, async () => {
    [docs, reviews, arsOptions, arsLinks] = await Promise.all([
      listDocuments({ entityType: 'organization', entityId: org.id, limit: 200 }),
      listClientDocumentReviews(org.id).catch(() => []),
      clientDocumentArsOptions(org.id).catch(() => []),
      listClientDocumentArs(org.id).catch(() => [])
    ]);
    return docs;
  }, (list) => html`
    <div class="note info" style="margin-bottom:10px">
      <b>Cómo usar esta sección</b><br>
      1. Descarga el modelo. 2. Complétalo y fírmalo cuando corresponda. 3. Súbelo aquí. 4. SOFA lo revisa y te indica si fue aprobado o requiere corrección.
    </div>
    <div class="list">
      ${standardCard('A', COMMERCIAL_DOCS.A, list)}
      ${standardCard('B', COMMERCIAL_DOCS.B, list)}
      ${standardCard('C', COMMERCIAL_DOCS.C, list)}
      ${documentD(list)}
      ${standardCard('E', COMMERCIAL_DOCS.E, list)}
    </div>
    <p class="small muted">Formatos aceptados al subir: PDF, JPG o PNG, máximo 10 MB. Los modelos son ayudas de gestión; A y B deben ser revisados y aprobados legalmente antes de su uso definitivo.</p>
  `, { isEmpty: () => false });

  box.addEventListener('click', async (e) => {
    const model = e.target.closest('[data-model]');
    const open = e.target.closest('[data-open-doc]');
    const reviewBtn = e.target.closest('[data-review-doc]');
    try {
      if (model) downloadModel(model.dataset.model, org, model.dataset.modelArs || '');
      if (open) {
        const doc = docs.find((d) => d.id === open.dataset.openDoc);
        if (doc) {
          const fallback = await openDocument(doc);
          if (fallback) window.open(fallback, '_blank', 'noopener');
        }
      }
      if (reviewBtn) {
        const current = reviews.find((r) => r.document_id === reviewBtn.dataset.reviewDoc);
        const label = reviewBtn.dataset.reviewArs ? `D · ${reviewBtn.dataset.reviewArs}` : `${reviewBtn.dataset.reviewCode} · ${COMMERCIAL_DOCS[reviewBtn.dataset.reviewCode]}`;
        const ok = await formDialog({
          title: `Revisar ${label}`,
          submitLabel: 'Guardar revisión',
          body: html`<div class="field"><label for="cdr_status">Resultado *</label>
            <select id="cdr_status" name="status">
              <option value="en_revision" ${current?.status === 'en_revision' ? 'selected' : ''}>En revisión SOFA</option>
              <option value="aprobado" ${current?.status === 'aprobado' ? 'selected' : ''}>Aprobado</option>
              <option value="requiere_correccion" ${current?.status === 'requiere_correccion' ? 'selected' : ''}>Requiere corrección</option>
            </select></div>
            <div class="field"><label for="cdr_notes">Observaciones</label><textarea id="cdr_notes" name="notes" rows="3" maxlength="600" placeholder="Indique qué debe corregirse o deje una nota de aprobación.">${current?.notes || ''}</textarea></div>`,
          onSubmit: async (d, form) => {
            if (d.status === 'requiere_correccion' && String(d.notes || '').trim().length < 5) {
              fieldError(form.elements.notes, 'Indique qué debe corregir el cliente.');
              return false;
            }
            await reviewClientDocument(reviewBtn.dataset.reviewDoc, d.status, String(d.notes || '').trim());
            return true;
          }
        });
        if (ok) { toast('Revisión documental guardada', 'ok'); load(); }
      }
    } catch (err) { toast(friendlyError(err), 'bad'); }
  });

  box.addEventListener('change', async (e) => {
    const input = e.target.closest('[data-upload-doc]');
    if (!input || !input.files?.[0]) return;
    const code = input.dataset.uploadDoc;
    const file = input.files[0];
    try {
      input.disabled = true;
      toast('Subiendo documento…');
      const up = await uploadDocument({
        orgId: org.id,
        file,
        entityType: 'organization',
        entityId: org.id,
        docType: COMMERCIAL_DOC_TYPE[code],
        bucket: 'contracts'
      });
      if (code === 'D') {
        if (!input.dataset.uploadArs) throw new Error('Seleccione la ARS correspondiente a la carta.');
        await linkClientDocumentArs(up.id, input.dataset.uploadArs);
      }
      toast(`${code} · ${code === 'D' ? 'Carta ante ARS' : COMMERCIAL_DOCS[code]} guardado. Queda pendiente de revisión SOFA.`, 'ok');
      load();
    } catch (err) {
      toast(friendlyError(err), 'bad');
      input.disabled = false;
    }
  });

  load();
  return { reload: load };
}

