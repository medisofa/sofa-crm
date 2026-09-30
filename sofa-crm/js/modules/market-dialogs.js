/** SOFA · Diálogos de inteligencia de mercado */
import { html, raw } from '../utils/dom.js';
import { formDialog, opt, requireFields, fieldError } from '../utils/ui.js';
import { todayISO } from '../utils/formatters.js';
import { ENTITY_KINDS, THREAT, IDEA_STATUS, INTEL_TOPICS } from '../utils/constants.js';
import { saveEntity, addNote, saveIdea, saveSource, saveGuide } from '../services/intel.js';

const f = (name, label, input, hint = '') => html`<div class="field"><label for="f_${name}">${label}</label>${input}${hint ? html`<span class="hint">${hint}</span>` : ''}</div>`;
const text = (name, value = '', attrs = '') => html`<input id="f_${name}" name="${name}" value="${value ?? ''}" ${raw(attrs)}>`;
const area = (name, value = '', rows = 3, attrs = '') => html`<textarea id="f_${name}" name="${name}" rows="${rows}" class="input" ${raw(attrs)}>${value ?? ''}</textarea>`;
const scale = (name, label, value, hint) => f(name, label, html`<select id="f_${name}" name="${name}">${[1, 2, 3, 4, 5].map((n) => opt(String(n), `${n}${n === 1 ? ' · bajo' : n === 5 ? ' · alto' : ''}`, String(value ?? 3)))}</select>`, hint);
const urlOk = (u) => !u || /^https?:\/\/\S+$/i.test(u.trim());

export function entityDialog(operatorId, e = null) {
  return formDialog({
    title: e ? `Editar · ${e.name}` : 'Nueva ficha de competencia o referente', submitLabel: 'Guardar', wide: true,
    body: html`<div class="form-grid">
      ${f('name', 'Nombre *', text('name', e?.name, 'required maxlength="120"'))}
      ${f('kind', 'Tipo *', html`<select id="f_kind" name="kind">${Object.entries(ENTITY_KINDS).map(([k, l]) => opt(k, l, e?.kind || 'competidor_directo'))}</select>`)}
      ${f('threat_level', 'Nivel de amenaza', html`<select id="f_threat_level" name="threat_level">${Object.entries(THREAT).map(([k, [l]]) => opt(k, k === 'n/a' ? 'No aplica' : l, e?.threat_level || 'n/a'))}</select>`)}
      ${f('country', 'País', text('country', e?.country || 'República Dominicana', 'maxlength="60"'))}
      ${f('website', 'Sitio web', text('website', e?.website, 'type="url" placeholder="https://"'))}
      ${f('last_reviewed_on', 'Última revisión', text('last_reviewed_on', e?.last_reviewed_on || todayISO(), 'type="date"'))}</div>
      ${f('description', 'Descripción', area('description', e?.description, 2, 'maxlength="600"'))}
      ${f('services', 'Servicios que ofrece', area('services', e?.services, 2, 'maxlength="600"'))}
      <div class="form-grid">${f('strengths', 'Fortalezas', area('strengths', e?.strengths, 3, 'maxlength="600"'))}${f('weaknesses', 'Debilidades', area('weaknesses', e?.weaknesses, 3, 'maxlength="600"'))}</div>
      ${f('pricing_notes', 'Precios o modelo de cobro conocido', text('pricing_notes', e?.pricing_notes, 'maxlength="300"'))}
      <label class="check small"><input type="checkbox" name="monitor" ${e?.monitor ? raw('checked') : ''}> Monitorear sus noticias todos los días</label>
      ${f('monitor_query', 'Búsqueda de monitoreo', text('monitor_query', e?.monitor_query, 'maxlength="150" placeholder=\'"Nombre de la empresa" República Dominicana\''), 'Usa comillas para el nombre exacto. Si la dejas vacía se usa el nombre.')}`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['name', 'kind'])) return false;
      if (!urlOk(d.website)) { fieldError(form.elements.website, 'Debe empezar con https://'); return false; }
      const monitor = form.elements.monitor.checked;
      const v = { name: d.name.trim(), kind: d.kind, threat_level: d.threat_level, country: d.country || null, website: d.website?.trim() || null, last_reviewed_on: d.last_reviewed_on || null,
        description: d.description || null, services: d.services || null, strengths: d.strengths || null, weaknesses: d.weaknesses || null, pricing_notes: d.pricing_notes || null,
        monitor, monitor_query: monitor ? (d.monitor_query?.trim() || `"${d.name.trim()}"`) : (d.monitor_query?.trim() || null) };
      return (await saveEntity(operatorId, v, e?.id)).id;
    }
  });
}

export function noteDialog(operatorId, entity) {
  return formDialog({
    title: `Observación · ${entity.name}`, submitLabel: 'Guardar observación',
    body: html`${f('observed_on', 'Fecha', text('observed_on', todayISO(), `type="date" max="${todayISO()}"`))}
      ${f('note', 'Qué observaste *', area('note', '', 4, 'required maxlength="1000" placeholder="Lanzó un plan mensual para consultorios a RD$…"'))}
      ${f('source_url', 'Enlace de la fuente', text('source_url', '', 'type="url" placeholder="https://"'))}`,
    onSubmit: async (d, form) => {
      if (!d.note || d.note.trim().length < 5) { fieldError(form.elements.note, 'Describe la observación.'); return false; }
      if (!urlOk(d.source_url)) { fieldError(form.elements.source_url, 'Debe empezar con https://'); return false; }
      return addNote(operatorId, entity.id, { note: d.note.trim(), sourceUrl: d.source_url?.trim(), observedOn: d.observed_on });
    }
  });
}

/** Idea nueva o edición; item = noticia que la origina (evidencia) */
export function ideaDialog(operatorId, idea = null, item = null) {
  return formDialog({
    title: idea ? 'Editar idea' : 'Nueva idea de servicio', submitLabel: 'Guardar idea', wide: true,
    body: html`${item ? html`<div class="note">Evidencia: <b>${item.title}</b>${item.publisher ? ` · ${item.publisher}` : ''}</div>` : ''}
      ${f('title', 'Nombre de la idea *', text('title', idea?.title, 'required maxlength="150"'))}
      ${f('description', 'En qué consiste', area('description', idea?.description ?? (item?.implication || ''), 3, 'maxlength="800"'))}
      <div class="form-grid">${f('value_prop', 'Valor para el cliente', text('value_prop', idea?.value_prop, 'maxlength="300"'))}${f('segment', 'Segmento', text('segment', idea?.segment, 'maxlength="150"'))}
      ${f('revenue_model', 'Cómo se cobra', text('revenue_model', idea?.revenue_model, 'maxlength="150"'))}
      ${f('status', 'Estado', html`<select id="f_status" name="status">${Object.entries(IDEA_STATUS).map(([k, [l]]) => opt(k, l, idea?.status || 'idea'))}</select>`)}
      ${scale('impact', 'Impacto en ingresos o valor *', idea?.impact, '5 = mueve la aguja')}${scale('fit', 'Encaje con SOFA *', idea?.fit, '5 = usa lo que ya sabemos hacer')}${scale('effort', 'Esfuerzo *', idea?.effort, '5 = requiere mucha inversión')}</div>
      <p class="small muted">Puntaje = impacto × encaje ÷ esfuerzo. Ordena el banco de ideas.</p>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['title'])) return false;
      if (d.title.trim().length < 5) { fieldError(form.elements.title, 'Muy corto.'); return false; }
      const v = { title: d.title.trim(), description: d.description || null, value_prop: d.value_prop || null, segment: d.segment || null, revenue_model: d.revenue_model || null,
        status: d.status, impact: Number(d.impact), fit: Number(d.fit), effort: Number(d.effort) };
      if (!idea && item) v.evidence_item_id = item.id;
      return (await saveIdea(operatorId, v, idea?.id)).id;
    }
  });
}

export function sourceDialog(operatorId, s = null) {
  return formDialog({
    title: s ? `Editar fuente · ${s.name}` : 'Nueva fuente de noticias', submitLabel: 'Guardar fuente', wide: true,
    body: html`<div class="form-grid">
      ${f('name', 'Nombre *', text('name', s?.name, 'required maxlength="80"'))}
      ${f('kind', 'Tipo', html`<select id="f_kind" name="kind">${opt('google_news', 'Búsqueda en Google News', s?.kind || 'google_news')}${opt('rss', 'Canal RSS (URL)', s?.kind)}</select>`)}
      ${f('lang', 'Idioma y país', html`<select id="f_lang" name="lang">${opt('es', 'Español · República Dominicana', s?.lang || 'es')}${opt('en', 'Inglés · Estados Unidos', s?.lang)}</select>`)}
      ${f('topic', 'Tema por defecto', html`<select id="f_topic" name="topic">${Object.entries(INTEL_TOPICS).map(([k, [l]]) => opt(k, l, s?.topic || 'mercado'))}</select>`)}
      ${f('weight', 'Peso', html`<select id="f_weight" name="weight">${opt('1', '1 · complementaria', String(s?.weight ?? 2))}${opt('2', '2 · normal', String(s?.weight ?? 2))}${opt('3', '3 · núcleo del negocio', String(s?.weight ?? 2))}</select>`)}</div>
      ${f('query', 'Búsqueda o URL del RSS *', text('query', s?.query, 'required maxlength="300"'), 'Búsqueda: usa comillas para frases exactas, p. ej. "facturación médica" Santiago. RSS: la dirección completa que empieza con https://')}
      <label class="check small"><input type="checkbox" name="is_active" ${!s || s.is_active ? raw('checked') : ''}> Activa</label>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, ['name', 'query'])) return false;
      if (d.kind === 'rss' && !/^https:\/\/\S+$/i.test(d.query.trim())) { fieldError(form.elements.query, 'El RSS debe ser una URL que empiece con https://'); return false; }
      return (await saveSource(operatorId, { name: d.name.trim(), kind: d.kind, lang: d.lang, topic: d.topic, weight: Number(d.weight), query: d.query.trim(), is_active: form.elements.is_active.checked }, s?.id)).id;
    }
  });
}

export function guideDialog(operatorId, g = null) {
  return formDialog({
    title: g ? `Editar guía · ${g.title}` : 'Nueva guía de buenas prácticas', submitLabel: 'Guardar guía', wide: true,
    body: html`<div class="form-grid">
      ${f('title', 'Título *', text('title', g?.title, 'required maxlength="150"'))}
      ${f('category', 'Categoría *', text('category', g?.category || 'Facturación', 'required maxlength="60" list="gcats"'))}
      <datalist id="gcats">${['Facturación', 'Glosas', 'Ciclo de ingresos', 'Documentación clínica', 'Habilitación', 'Cumplimiento', 'Comercial', 'Tecnología'].map((c) => html`<option value="${c}">`)}</datalist>
      ${g ? '' : f('code', 'Código *', text('code', '', 'required maxlength="30" placeholder="GUIA-COM-01"'))}</div>
      ${f('summary', 'Resumen (una o dos frases)', area('summary', g?.summary, 2, 'maxlength="400"'))}
      ${f('body', 'Contenido', area('body', g?.body, 9, 'maxlength="8000"'), 'Separa los párrafos con una línea en blanco.')}
      ${f('checklist', 'Checklist (un punto por línea)', area('checklist', (g?.checklist || []).join('\n'), 6, 'maxlength="4000"'))}
      ${f('reference', 'Referencia o fuente', text('reference', g?.reference, 'maxlength="300"'))}
      <label class="check small"><input type="checkbox" name="is_published" ${!g || g.is_published ? raw('checked') : ''}> Publicada (visible para todo el personal)</label>`,
    onSubmit: async (d, form) => {
      if (!requireFields(form, g ? ['title', 'category'] : ['title', 'category', 'code'])) return false;
      const v = { title: d.title.trim(), category: d.category.trim(), summary: d.summary || null, body: d.body || '', reference: d.reference || null,
        checklist: String(d.checklist || '').split('\n').map((x) => x.trim()).filter(Boolean).slice(0, 40), is_published: form.elements.is_published.checked };
      if (!g) v.code = d.code.trim().toUpperCase();
      return (await saveGuide(operatorId, v, g?.id)).id;
    }
  });
}
