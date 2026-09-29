/** SOFA · Diálogos de radicaciones */
import { html, render as paint, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError, toast, friendlyError } from '../utils/ui.js';
import { money, todayISO, period as periodLabel, rangeContains, addMonths } from '../utils/formatters.js';
import { isTaxId } from '../utils/validation.js';
import { CODE_STATUS } from '../utils/constants.js';
import { listArs } from '../services/catalog.js';
import {
  newSubmission, activeProviders, providerCodes, procedureOptions, lookupTariff, checkDuplicate,
  addLine, updateLine, importLines, setLineCheck
} from '../services/submissions.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
const monthISO = () => todayISO().slice(0, 7);
const lastDay = (periodDate) => { const [y, m] = periodDate.split('-').map(Number); return `${y}-${String(m).padStart(2, '0')}-${String(new Date(y, m, 0).getDate()).padStart(2, '0')}`; };

/** Nueva radicación: cliente → prestador → ARS → período. Devuelve el id creado. */
export async function newSubmissionDialog(presetOrg = '') {
  const [providers, ars] = await Promise.all([activeProviders(presetOrg), listArs()]);
  if (!providers.length) {
    toast(presetOrg ? 'Este cliente no tiene prestadores activos. Agrégalo en su ficha.' : 'No hay prestadores activos. Crea primero el cliente y su prestador.', 'bad');
    return null;
  }
  const byOrg = {};
  providers.forEach((p) => { const k = p.organizations?.legal_name || 'Cliente'; (byOrg[k] = byOrg[k] || []).push(p); });
  return formDialog({
    title: 'Nueva radicación', submitLabel: 'Crear radicación', wide: true,
    body: html`<p class="small muted" style="margin-top:0">Una radicación es el desglose de los servicios que un prestador dio en un mes a los afiliados de una ARS.</p>
      <div class="form-grid">
      ${f('provider', 'Prestador *', html`<select id="f_provider" name="provider" required>${Object.entries(byOrg).map(([org, ps]) => html`<optgroup label="${org}">${ps.map((p) => opt(p.id, p.full_name))}</optgroup>`)}</select>`)}
      ${f('ars', 'ARS *', html`<select id="f_ars" name="ars" required>${ars.filter((a) => a.is_active).map((a) => opt(a.id, a.name))}</select>`)}
      ${f('period', 'Período (mes de los servicios) *', text('period', addMonths(monthISO(), -1), `type="month" required max="${monthISO()}"`))}
      ${f('notes', 'Notas', text('notes', '', 'maxlength="300"'))}
      </div><div id="codeWarn"></div>`,
    onOpen: (form) => {
      const warn = form.querySelector('#codeWarn');
      const check = async () => {
        paint(warn, html``);
        try {
          const codes = await providerCodes(form.elements.provider.value);
          const c = codes.find((x) => x.ars_id === form.elements.ars.value);
          const [lbl] = CODE_STATUS[c?.status || 'sin_codigo'];
          if (!c || c.status !== 'codificado') paint(warn, html`<div class="note warn">Código de prestador en esta ARS: <b>${lbl}</b>. Sin código asignado, la ARS no paga: regístralo en la ficha del cliente antes de radicar.</div>`);
        } catch { /* aviso opcional */ }
      };
      form.elements.provider.addEventListener('change', check); form.elements.ars.addEventListener('change', check); check();
    },
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['provider', 'ars', 'period'])) return false;
      if (d.period > monthISO()) { fieldError(form.elements.period, 'No puede ser un mes futuro.'); return false; }
      return newSubmission({ provider: d.provider, ars: d.ars, period: `${d.period}-01`, notes: d.notes || null });
    }
  });
}

/** Lista de conceptos con la tarifa general de la ARS (los que tienen tarifa, primero) */
async function conceptOptions(sub) {
  const { procs, tariffs } = await procedureOptions(sub.ars_id);
  const today = todayISO();
  const price = {};
  tariffs.forEach((t) => { if (rangeContains(t.valid_during, today)) price[t.procedure_id] = t.amount; });
  const codeOf = (p) => (p.procedure_codes || []).map((c) => c.code).slice(0, 2).join(' · ');
  const withT = procs.filter((p) => price[p.id] != null), without = procs.filter((p) => price[p.id] == null);
  return { procs, price, codeOf, withT, without };
}

/** Agregar o editar un servicio. Devuelve true si guardó. */
export async function lineDialog(sub, line = null) {
  const opts = await conceptOptions(sub);
  const min = sub.period, maxD = [lastDay(sub.period), todayISO()].sort()[0];
  let dupConfirmed = false;
  const optsHtml = (sel) => html`
    ${opts.withT.length ? html`<optgroup label="Con tarifa en ${sub.ars_name}">${opts.withT.map((p) => opt(p.id, `${p.description} · ${money(opts.price[p.id])}${opts.codeOf(p) ? ` · ${opts.codeOf(p)}` : ''}`, sel))}</optgroup>` : ''}
    <optgroup label="Sin tarifa registrada en esta ARS">${opts.without.map((p) => opt(p.id, `${p.description}${opts.codeOf(p) ? ` · ${opts.codeOf(p)}` : ' · sin código'}`, sel))}</optgroup>`;
  return formDialog({
    title: line ? 'Editar servicio' : 'Agregar servicio', submitLabel: line ? 'Guardar cambios' : 'Agregar servicio', wide: true,
    body: html`<div id="dupWarn"></div><div class="form-grid">
      ${f('service_date', 'Fecha del servicio *', text('service_date', line?.service_date || maxD, `type="date" required min="${min}" max="${maxD}"`))}
      ${f('patient_name', 'Afiliado (nombre completo) *', text('patient_name', line?.patient_name, 'required maxlength="150" autocomplete="off"'))}
      ${f('patient_doc', 'Cédula del afiliado', text('patient_doc', line?.patient_doc, 'inputmode="numeric" placeholder="031-0000000-0"'))}
      ${f('member_number', 'NSS / No. de afiliado *', text('member_number', line?.member_number, 'required inputmode="numeric"'))}
      ${f('authorization_number', 'No. de autorización', text('authorization_number', line?.authorization_number, 'autocomplete="off"'), 'Obligatoria para radicar.')}
      <div class="field" style="grid-column:1/-1"><label for="f_procedure_id">Concepto *</label><select id="f_procedure_id" name="procedure_id" required>${optsHtml(line?.procedure_id)}</select></div>
      ${f('quantity', 'Cantidad *', text('quantity', line?.quantity ?? 1, 'type="number" min="0.01" step="0.01" required'))}
      ${f('unit_amount', 'Monto unitario (RD$) *', text('unit_amount', line?.unit_amount ?? '', 'type="number" min="0" step="0.01" required'), html`<span id="tarHint"></span>`)}
      ${f('notes', 'Notas', text('notes', line?.notes, 'maxlength="300"'))}
      </div>`,
    onOpen: (form) => {
      const hint = form.querySelector('#tarHint');
      const refresh = async (fill) => {
        const pid = form.elements.procedure_id.value, dt = form.elements.service_date.value;
        if (!pid || !dt) return;
        try {
          const t = await lookupTariff(pid, sub.ars_id, dt, sub.provider_id, sub.plan_id);
          hint.textContent = t ? `Tarifa vigente (${t.scope}): ${money(t.amount)}` : 'Sin tarifa registrada: escribe el monto facturado.';
          if (t && fill) form.elements.unit_amount.value = t.amount;
        } catch { hint.textContent = ''; }
      };
      form.elements.procedure_id.addEventListener('change', () => refresh(true));
      form.elements.service_date.addEventListener('change', () => refresh(!line));
      ['member_number', 'service_date', 'procedure_id', 'authorization_number'].forEach((n) => form.elements[n].addEventListener('change', () => { dupConfirmed = false; }));
      refresh(!line);
    },
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['service_date', 'patient_name', 'member_number', 'procedure_id', 'quantity', 'unit_amount'])) return false;
      if (d.patient_doc && !/^\d{11}$/.test(d.patient_doc.replace(/\D/g, ''))) { fieldError(form.elements.patient_doc, 'La cédula lleva 11 dígitos.'); return false; }
      if (d.service_date < min || d.service_date > maxD) { fieldError(form.elements.service_date, `Debe estar entre ${min} y ${maxD}.`); return false; }
      if (Number(d.unit_amount) < 0 || Number(d.quantity) <= 0) { fieldError(form.elements.unit_amount, 'Revisa cantidad y monto.'); return false; }
      if (!dupConfirmed) {
        const dups = (await checkDuplicate(sub.organization_id, sub.ars_id, d.member_number, d.service_date, d.procedure_id, d.authorization_number))
          .filter((x) => x.service_line_id !== line?.id);
        if (dups.length) {
          dupConfirmed = true;
          paint(form.querySelector('#dupWarn'), html`<div class="note warn" role="alert"><b>Posible duplicado.</b> ${dups.map((x) => html`<div class="small">${x.folio} · ${x.patient_name} · ${x.service_date} · coincide por ${x.match_type}</div>`)}<div class="small" style="margin-top:4px">Si es correcto (por ejemplo, dos consultas el mismo día), pulsa de nuevo para guardarlo.</div></div>`);
          form.querySelector('[type=submit]').textContent = 'Guardar de todos modos';
          return false;
        }
      }
      if (line) await updateLine(line.id, d); else await addLine(sub, d);
      return true;
    }
  });
}

// ---- Carga masiva
const COLS = ['fecha', 'afiliado', 'cedula', 'nss', 'autorizacion', 'codigo', 'cantidad', 'monto'];
export function parseRows(textIn) {
  const lines = String(textIn || '').replace(/\r/g, '').split('\n').map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return [];
  const sep = lines[0].includes('\t') ? '\t' : (lines[0].split(';').length >= lines[0].split(',').length ? ';' : ',');
  const split = (l) => { // admite comillas dobles en CSV
    const out = []; let cur = '', q = false;
    for (let i = 0; i < l.length; i += 1) {
      const ch = l[i];
      if (ch === '"') { if (q && l[i + 1] === '"') { cur += '"'; i += 1; } else q = !q; }
      else if (ch === sep && !q) { out.push(cur.trim()); cur = ''; } else cur += ch;
    }
    out.push(cur.trim()); return out;
  };
  let rows = lines.map(split);
  if (rows.length && !/\d/.test(rows[0][0] || '')) rows = rows.slice(1); // encabezado
  return rows.map((c) => Object.fromEntries(COLS.map((k, i) => [k, c[i] ?? ''])));
}
export function templateCsv() {
  return 'Fecha;Afiliado;Cédula;NSS;Autorización;Código;Cantidad;Monto\n05/09/2026;María Rodríguez Peña;03100000001;00458213;AUT-778124;S11306;1;\n';
}
/** Devuelve el resultado de la importación o null si se canceló */
export async function importDialog(sub) {
  let parsed = [];
  return formDialog({
    title: `Carga masiva · ${sub.folio}`, submitLabel: 'Importar servicios', wide: true,
    body: html`<p class="small" style="margin-top:0">Copia las filas desde Excel y pégalas aquí, o elige un archivo CSV. Columnas en este orden:</p>
      <p class="mono small" style="background:var(--surface-2);padding:8px;border-radius:6px">Fecha · Afiliado · Cédula · NSS · Autorización · Código · Cantidad · Monto</p>
      <p class="small muted">El código puede ser CUPS, SIMON, el de la ARS o el interno (SOFA-P02). Si dejas el monto vacío se usa la tarifa vigente. Los duplicados se omiten y se informan.</p>
      <div class="field"><label for="f_file">Archivo CSV (opcional)</label><input id="f_file" type="file" accept=".csv,text/csv,text/plain"></div>
      <div class="field"><label for="f_paste">Filas</label><textarea id="f_paste" name="paste" rows="7" class="input" placeholder="05/09/2026	María Rodríguez	03100000001	00458213	AUT-778124	S11306	1	"></textarea></div>
      <p class="small"><a href="#" id="tpl">Descargar plantilla CSV</a> · <span id="cnt">0 filas detectadas</span></p><div id="prev"></div>`,
    onOpen: (form) => {
      const ta = form.querySelector('#f_paste'), cnt = form.querySelector('#cnt'), prev = form.querySelector('#prev');
      const update = () => {
        parsed = parseRows(ta.value);
        cnt.textContent = `${parsed.length} filas detectadas`;
        paint(prev, parsed.length ? html`<div class="table-wrap" style="max-height:220px;overflow:auto"><table class="t"><thead><tr><th>#</th>${COLS.map((c) => html`<th>${c}</th>`)}</tr></thead><tbody>${parsed.slice(0, 30).map((r, i) => html`<tr><td>${i + 1}</td>${COLS.map((c) => html`<td class="small">${r[c]}</td>`)}</tr>`)}</tbody></table></div>${parsed.length > 30 ? html`<p class="small muted">…y ${parsed.length - 30} más</p>` : ''}` : html``);
      };
      ta.addEventListener('input', update);
      form.querySelector('#f_file').addEventListener('change', async (e) => { const file = e.target.files[0]; if (file) { ta.value = await file.text(); update(); } });
      form.querySelector('#tpl').addEventListener('click', (e) => {
        e.preventDefault();
        const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['\uFEFF' + templateCsv()], { type: 'text/csv' })); a.download = 'plantilla-servicios-sofa.csv'; a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      });
    },
    onSubmit: async (d, form) => {
      if (!parsed.length) { fieldError(form.querySelector('#f_paste'), 'Pega al menos una fila.'); return false; }
      if (parsed.length > 500) { fieldError(form.querySelector('#f_paste'), 'Máximo 500 filas por carga.'); return false; }
      return importLines(sub.id, parsed, true);
    }
  });
}

/** Checklist documental de un servicio (casillas que se guardan al marcar) */
export async function checklistDialog(line, reqs, checks, editable) {
  const needed = reqs.filter((r) => r.service_type_code === line.procedures?.service_type_code)
    .sort((a, b) => (a.document_types?.sort_order || 0) - (b.document_types?.sort_order || 0));
  const has = new Set(checks.filter((c) => c.service_line_id === line.id && c.present).map((c) => c.document_type_code));
  return formDialog({
    title: `Documentos · ${line.patient_name}`, submitLabel: 'Listo',
    body: html`<p class="small muted" style="margin-top:0">${line.procedures?.description}. Marca lo que ya está en el expediente. Al subir un archivo ligado a este servicio se marca solo.</p>
      ${needed.length ? html`<div class="list">${needed.map((r) => html`<label class="li check"><input type="checkbox" data-doc="${r.document_type_code}" ${has.has(r.document_type_code) ? raw('checked') : ''} ${editable ? '' : raw('disabled')}><span class="b">${r.document_types?.name || r.document_type_code}</span></label>`)}</div>`
        : html`<p>Este tipo de servicio no tiene documentos obligatorios configurados.</p>`}
      ${editable ? '' : html`<div class="note">La radicación ya no admite cambios en el checklist.</div>`}`,
    onOpen: (form) => {
      form.addEventListener('change', async (e) => {
        const cb = e.target.closest('[data-doc]'); if (!cb) return;
        cb.disabled = true;
        try { await setLineCheck(line, cb.dataset.doc, cb.checked); }
        catch (err) { cb.checked = !cb.checked; toast(friendlyError(err), 'bad'); }
        finally { cb.disabled = false; }
      });
    },
    onSubmit: async () => true
  });
}

/** Datos de la radicación ante la ARS */
export function radicarDialog(sub) {
  return formDialog({
    title: `Radicar ${sub.folio} ante ${sub.ars_name}`, submitLabel: 'Radicar',
    body: html`<div class="form-grid">
      ${f('submitted_on', 'Fecha de radicación *', text('submitted_on', todayISO(), `type="date" required max="${todayISO()}"`))}
      ${f('receipt', 'No. de recepción de la ARS *', text('receipt', '', 'required maxlength="60" placeholder="R-458921"'))}</div>
      <p class="small muted">Desde esta fecha corre el plazo de pago (90 días por defecto) y los servicios quedan bloqueados.</p>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['submitted_on', 'receipt'])) return false;
      return { submittedOn: d.submitted_on, receipt: d.receipt.trim() };
    }
  });
}

/** Excepción autorizada (solo Admin / Super Admin) */
export function overrideDialog(failing) {
  return formDialog({
    title: 'Autorizar excepción', submitLabel: 'Autorizar y continuar',
    body: html`<div class="note warn">Hay validaciones críticas pendientes:<ul style="margin:6px 0 0;padding-left:18px">${failing.map((i) => html`<li>${i.label}</li>`)}</ul></div>
      ${f('reason', 'Motivo de la excepción (queda en la auditoría) *', html`<textarea id="f_reason" name="reason" rows="3" class="input" required placeholder="La ARS acepta radicar sin código mientras se tramita"></textarea>`)}`,
    onSubmit: async (d, form) => {
      if (!d.reason || d.reason.trim().length < 10) { fieldError(form.elements.reason, 'Mínimo 10 caracteres.'); return false; }
      return d.reason.trim();
    }
  });
}

/** Comentario opcional para Rechazada / Cerrar */
export function commentDialog(title, required = false) {
  return formDialog({
    title, submitLabel: 'Confirmar',
    body: html`${f('comment', required ? 'Motivo *' : 'Comentario (opcional)', html`<textarea id="f_comment" name="comment" rows="3" class="input" maxlength="500"></textarea>`)}`,
    onSubmit: async (d, form) => {
      if (required && (!d.comment || d.comment.trim().length < 5)) { fieldError(form.elements.comment, 'Escribe el motivo.'); return false; }
      return { comment: (d.comment || '').trim() || null };
    }
  });
}

export { periodLabel, isTaxId };
