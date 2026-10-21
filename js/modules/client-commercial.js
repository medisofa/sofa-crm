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
import { uploadDocument, listDocuments, openDocument, sizeLabel } from '../services/documents.js';

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

/** Documentos A–E: modelo editable + carga del documento completado por el médico. */
const escDoc = (v) => String(v ?? '').replace(/[&<>"]/g, (ch) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[ch]));
const modelName = (code) => `SOFA_Modelo_${code}_${COMMERCIAL_DOCS[code].replace(/[^A-Za-z0-9]+/g,'_')}.doc`;

function modelHtml(code, org) {
  const name = escDoc(org.legal_name || org.trade_name || '________________');
  const tax = escDoc(org.tax_id || '________________');
  const address = escDoc([org.address, org.city].filter(Boolean).join(', ') || '________________');
  const email = escDoc(org.email || '________________');
  const phone = escDoc(org.phone || org.whatsapp || '________________');
  const legal = ['A','B'].includes(code)
    ? '<p style="border:2px solid #8B0000;padding:10px"><b>MODELO DE TRABAJO — REQUIERE REVISIÓN LEGAL ANTES DE FIRMA O USO.</b></p>'
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
      <p>Señores<br><b>ARS ________________________________</b></p>
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
    <style>body{font-family:Arial,sans-serif;font-size:11pt;line-height:1.45;margin:40px;color:#222}h1{color:#1A365D}h2{font-size:13pt;color:#1A365D}table{border-collapse:collapse}td{vertical-align:top}</style>
    </head><body>${legal}${blocks[code] || ''}<hr><p style="font-size:9pt;color:#666">SOFA · Soluciones de Facturación Médica · Modelo ${code}. Complete y revise antes de usar.</p></body></html>`;
}

function downloadModel(code, org) {
  const blob = new Blob([modelHtml(code, org)], { type: 'application/msword;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = modelName(code); document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function renderCommercialDocs(box, org, ctx, providers = []) {
  const canUpload = can('docs.upload', ctx.role);
  let docs = [];

  const load = () => loadInto(box, async () => {
    docs = await listDocuments({ entityType: 'organization', entityId: org.id, limit: 200 });
    return docs;
  }, (list) => html`
    <div class="note info" style="margin-bottom:10px">
      <b>Cómo usar esta sección</b><br>
      1. Descarga el modelo. 2. Complétalo y fírmalo cuando corresponda. 3. Súbelo aquí. SOFA conservará el archivo en el expediente privado del cliente.
    </div>
    <div class="list">
      ${Object.entries(COMMERCIAL_DOCS).map(([code, title]) => {
        const type = COMMERCIAL_DOC_TYPE[code];
        const files = list.filter((d) => d.document_type_code === type);
        const latest = files[0] || null;
        const legal = ['A','B'].includes(code);
        return html`<div class="li" style="align-items:flex-start">
          <div style="width:32px;height:32px;border-radius:8px;background:var(--surface-2);display:grid;place-items:center;font-weight:800">${code}</div>
          <div class="b">
            <div class="t1">${title}</div>
            <div class="t2">${legal ? 'Modelo de trabajo · requiere revisión legal antes de firma/uso.' : 'Modelo operativo editable.'}</div>
            ${latest ? html`<div class="small" style="margin-top:5px"><span class="pill ok">Cargado</span> ${latest.file_name} · ${sizeLabel(latest.size_bytes)} · ${dateTime(latest.uploaded_at)}</div>`
              : html`<div class="small muted" style="margin-top:5px">Aún no se ha cargado este documento.</div>`}
          </div>
          <div class="toolbar" style="margin:0">
            <button class="btn sm" data-model="${code}" type="button">Descargar modelo</button>
            ${latest ? html`<button class="btn sm" data-open-doc="${latest.id}" type="button">Ver cargado</button>` : ''}
            ${canUpload ? html`<label class="btn sm" style="cursor:pointer">${latest ? 'Reemplazar' : 'Subir documento'}<input type="file" data-upload-doc="${code}" accept="application/pdf,image/jpeg,image/png" hidden></label>` : ''}
          </div>
        </div>`;
      })}
    </div>
    <p class="small muted">Formatos aceptados al subir: PDF, JPG o PNG, máximo 10 MB. Los modelos son ayudas de gestión; A y B deben ser revisados y aprobados legalmente antes de su uso definitivo.</p>
  `, { isEmpty: () => false });

  box.addEventListener('click', async (e) => {
    const model = e.target.closest('[data-model]');
    const open = e.target.closest('[data-open-doc]');
    try {
      if (model) downloadModel(model.dataset.model, org);
      if (open) {
        const doc = docs.find((d) => d.id === open.dataset.openDoc);
        if (doc) {
          const fallback = await openDocument(doc);
          if (fallback) window.open(fallback, '_blank', 'noopener');
        }
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
      await uploadDocument({
        orgId: org.id,
        file,
        entityType: 'organization',
        entityId: org.id,
        docType: COMMERCIAL_DOC_TYPE[code],
        bucket: 'contracts'
      });
      toast(`${code} · ${COMMERCIAL_DOCS[code]} guardado en el expediente`, 'ok');
      load();
    } catch (err) {
      toast(friendlyError(err), 'bad');
      input.disabled = false;
    }
  });

  load();
  return { reload: load };
}
