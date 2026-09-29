/** SOFA · Diálogos de tarifarios y codificación */
import { html, render as paint, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { money, todayISO } from '../utils/formatters.js';
import { listArs } from '../services/catalog.js';
import { activeProviders } from '../services/submissions.js';
import { createTariff, importTariffs, createProcedure, addCode, serviceTypes, plansFor, procedureList } from '../services/tariffs.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
export const FAMILIES = ['Medicina y hospitalización', 'Nutrición clínica', 'Laboratorio e imágenes', 'Procedimientos', 'Otros'];

export async function conceptDialog() {
  const types = await serviceTypes();
  return formDialog({
    title: 'Nuevo concepto', submitLabel: 'Crear concepto',
    body: html`${f('description', 'Descripción *', text('description', '', 'required maxlength="200" placeholder="CONSULTA DE CONTROL"'))}
      <div class="form-grid">${f('service_type_code', 'Tipo de servicio *', html`<select id="f_service_type_code" name="service_type_code" required>${types.map((t) => opt(t.code, t.name, 'consulta'))}</select>`, 'Define el checklist de documentos.')}
      ${f('family', 'Línea', html`<select id="f_family" name="family">${FAMILIES.map((x) => opt(x, x))}</select>`)}</div>
      <p class="small muted">El código interno (SOFA-P…) se asigna solo. Luego agrega sus códigos CUPS, SIMON o de cada ARS.</p>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['description', 'service_type_code'])) return false;
      if (d.description.trim().length < 3) { fieldError(form.elements.description, 'Muy corta.'); return false; }
      return (await createProcedure({ description: d.description.trim().toUpperCase(), service_type_code: d.service_type_code, family: d.family })).id;
    }
  });
}

export async function codeDialog(proc) {
  const ars = await listArs();
  return formDialog({
    title: `Agregar código · ${proc.internal_code}`, submitLabel: 'Agregar código',
    body: html`<div class="form-grid">
      ${f('system', 'Sistema *', html`<select id="f_system" name="system">${[['CUPS', 'CUPS'], ['SIMON', 'SIMON'], ['ARS', 'Código propio de una ARS']].map(([v, l]) => opt(v, l))}</select>`)}
      ${f('ars', 'ARS', html`<select id="f_ars" name="ars" disabled>${ars.map((a) => opt(a.id, a.name))}</select>`, 'Solo para código propio de una ARS.')}
      ${f('code', 'Código *', text('code', '', 'required maxlength="30" autocomplete="off"'))}</div>`,
    onOpen: (form) => form.elements.system.addEventListener('change', () => { form.elements.ars.disabled = form.elements.system.value !== 'ARS'; }),
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['code'])) return false;
      try { return await addCode(proc.id, d.system, d.code, d.system === 'ARS' ? form.elements.ars.value : null); }
      catch (err) { if (err?.code === '23505') throw new Error(`El código ${d.code.trim()} ya está asignado a otro concepto en ese sistema.`); throw err; }
    }
  });
}

/** Nueva tarifa con vigencia. preset: { procedure, ars, orgId (para limitar prestadores) } */
export async function tariffDialog(preset = {}) {
  const [ars, procs, providers] = await Promise.all([listArs(), preset.procedure ? Promise.resolve(null) : procedureList(), activeProviders(preset.orgId || '')]);
  return formDialog({
    title: preset.orgId ? 'Tarifa negociada del prestador' : 'Nueva tarifa', submitLabel: 'Guardar tarifa', wide: true,
    body: html`<div class="form-grid">
      ${procs ? html`<div class="field" style="grid-column:1/-1"><label for="f_procedure">Concepto *</label><select id="f_procedure" name="procedure" required>${procs.map((p) => opt(p.id, `${p.description} · ${p.internal_code}`))}</select></div>` : ''}
      ${f('ars', 'ARS *', html`<select id="f_ars" name="ars" required>${ars.filter((a) => a.is_active).map((a) => opt(a.id, a.name, preset.ars))}</select>`)}
      ${f('plan', 'Plan (opcional)', html`<select id="f_plan" name="plan"><option value="">Todos los planes</option></select>`)}
      ${f('provider', preset.orgId ? 'Prestador *' : 'Prestador (solo si es tarifa negociada)', html`<select id="f_provider" name="provider" ${preset.orgId ? raw('required') : ''}>${preset.orgId ? '' : html`<option value="">Tarifa general de la ARS</option>`}${providers.map((p) => opt(p.id, `${p.full_name} · ${p.organizations?.legal_name || ''}`))}</select>`)}
      ${f('amount', 'Monto (RD$) *', text('amount', '', 'type="number" min="0.01" step="0.01" required'))}
      ${f('valid_from', 'Vigente desde *', text('valid_from', todayISO(), 'type="date" required'), 'La tarifa anterior se cierra un día antes. Los servicios ya registrados conservan la suya.')}
      ${f('source', 'Fuente', text('source', '', 'maxlength="120" placeholder="Contrato 2026, circular, adenda…"'))}</div>`,
    onOpen: (form) => {
      const loadPlans = async () => { try { const pl = await plansFor(form.elements.ars.value); paint(form.elements.plan, html`<option value="">Todos los planes</option>${pl.map((p) => opt(p.id, p.name))}`); } catch { /* opcional */ } };
      form.elements.ars.addEventListener('change', loadPlans); loadPlans();
    },
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['ars', 'amount', 'valid_from'])) return false;
      if (!(Number(d.amount) > 0)) { fieldError(form.elements.amount, 'Debe ser mayor que cero.'); return false; }
      return createTariff({ procedure: preset.procedure || d.procedure, ars: d.ars, amount: Number(d.amount), validFrom: d.valid_from, provider: d.provider || null, plan: d.plan || null, source: d.source || null });
    }
  });
}

// ---- Importación de tarifario
export function parseTariffRows(textIn) {
  const lines = String(textIn || '').replace(/\r/g, '').split('\n').map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return [];
  const sep = lines[0].includes('\t') ? '\t' : ';';
  const split = (l) => { const out = []; let cur = '', q = false; for (let i = 0; i < l.length; i += 1) { const ch = l[i]; if (ch === '"') { if (q && l[i + 1] === '"') { cur += '"'; i += 1; } else q = !q; } else if (ch === sep && !q) { out.push(cur.trim()); cur = ''; } else cur += ch; } out.push(cur.trim()); return out; };
  let rows = lines.map(split);
  const isAmount = (v) => /^\s*(RD\$)?\s*[\d.,]+\s*$/.test(v || '');
  if (rows.length && !isAmount(rows[0][rows[0].length - 1])) rows = rows.slice(1); // encabezado
  return rows.map((c) => (c.length >= 3 ? { codigo: c[0], descripcion: c[1], monto: c[2] } : { codigo: c[0], monto: c[1] }));
}
export async function importTariffDialog() {
  const [ars, providers] = await Promise.all([listArs(), activeProviders('')]);
  let parsed = [];
  return formDialog({
    title: 'Importar tarifario', submitLabel: 'Importar', wide: true,
    body: html`<div class="form-grid">
      ${f('ars', 'ARS *', html`<select id="f_ars" name="ars" required>${ars.filter((a) => a.is_active).map((a) => opt(a.id, a.name))}</select>`)}
      ${f('valid_from', 'Vigente desde *', text('valid_from', todayISO(), 'type="date" required'))}
      ${f('provider', 'Prestador (solo si es tarifario negociado)', html`<select id="f_provider" name="provider"><option value="">Tarifa general de la ARS</option>${providers.map((p) => opt(p.id, `${p.full_name} · ${p.organizations?.legal_name || ''}`))}</select>`)}
      ${f('source', 'Fuente', text('source', '', 'maxlength="120" placeholder="Tarifario ARS 2026"'))}</div>
      <p class="small">Pega desde Excel (o sube CSV con <b>;</b>). Columnas: <span class="mono">Código · Descripción · Monto</span> o solo <span class="mono">Código · Monto</span>. El código puede ser CUPS, SIMON, el de la ARS o el interno; si no hay código, se busca por descripción exacta.</p>
      <div class="field"><label for="f_file">Archivo CSV (opcional)</label><input id="f_file" type="file" accept=".csv,text/csv,text/plain"></div>
      <div class="field"><label for="f_paste">Filas</label><textarea id="f_paste" rows="8" class="input" placeholder="S11306	CONSULTA EN HOSPITALIZACION	1650"></textarea></div>
      <p class="small" id="cnt">0 filas</p><div id="prev"></div>`,
    onOpen: (form) => {
      const ta = form.querySelector('#f_paste');
      const up = () => { parsed = parseTariffRows(ta.value); form.querySelector('#cnt').textContent = `${parsed.length} filas`;
        paint(form.querySelector('#prev'), parsed.length ? html`<div class="table-wrap" style="max-height:200px;overflow:auto"><table class="t"><thead><tr><th>#</th><th>Código</th><th>Descripción</th><th class="n">Monto</th></tr></thead><tbody>${parsed.slice(0, 25).map((r, i) => html`<tr><td>${i + 1}</td><td class="mono">${r.codigo}</td><td class="small">${r.descripcion || ''}</td><td class="n">${r.monto}</td></tr>`)}</tbody></table></div>` : html``); };
      ta.addEventListener('input', up);
      form.querySelector('#f_file').addEventListener('change', async (e) => { const file = e.target.files[0]; if (file) { ta.value = await file.text(); up(); } });
    },
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['ars', 'valid_from'])) return false;
      if (!parsed.length) { fieldError(form.querySelector('#f_paste'), 'Pega al menos una fila.'); return false; }
      return importTariffs({ ars: d.ars, validFrom: d.valid_from, rows: parsed, provider: d.provider || null, source: d.source || null });
    }
  });
}
export { money };
