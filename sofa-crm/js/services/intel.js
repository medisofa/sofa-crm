/** SOFA · Inteligencia de mercado: noticias, competencia, ideas, fuentes y guías */
import { sb } from '../supabase.js';
const must = ({ data, error }) => { if (error) throw error; return data; };
const withCount = ({ data, error, count }) => { if (error) throw error; return { data, count: count ?? data.length }; };
const clean = (q) => String(q || '').replace(/[%*,()\\]/g, ' ').trim();
const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString();

// ---- Noticias
export async function listItems({ topic = '', status = 'activas', minRel = 0, q = '', entityId = '', page = 0, size = 25 } = {}) {
  let query = sb().from('v_intel_items').select('*', { count: 'exact' });
  if (status === 'activas') query = query.in('status', ['nuevo', 'leido', 'destacado']);
  else if (status) query = query.eq('status', status);
  if (topic) query = query.eq('topic', topic);
  if (minRel) query = query.gte('relevance', minRel);
  if (entityId) query = query.eq('entity_id', entityId);
  const t = clean(q); if (t) query = query.or(`title.ilike.%${t}%,publisher.ilike.%${t}%,implication.ilike.%${t}%`);
  return withCount(await query.order('published_at', { ascending: false, nullsFirst: false }).order('relevance', { ascending: false }).range(page * size, page * size + size - 1));
}
export async function topItems({ days = 14, limit = 8, entitiesOnly = false } = {}) {
  let q = sb().from('v_intel_items').select('*').neq('status', 'descartado').gte('fetched_at', daysAgo(days));
  if (entitiesOnly) q = q.not('entity_id', 'is', null);
  return must(await q.order('relevance', { ascending: false }).order('published_at', { ascending: false, nullsFirst: false }).limit(limit));
}
export async function itemCounts() {
  const rows = must(await sb().from('intel_items').select('status, fetched_at').gte('fetched_at', daysAgo(30)).limit(5000));
  const week = daysAgo(7);
  return { new7: rows.filter((r) => r.fetched_at >= week && r.status === 'nuevo').length, starred: rows.filter((r) => r.status === 'destacado').length };
}
export async function setItemStatus(id, status) { return must(await sb().from('intel_items').update({ status }).eq('id', id).select('id, status').single()); }

// ---- Competencia y referentes
export async function listEntities({ kind = '', q = '' } = {}) {
  let query = sb().from('v_intel_entities').select('*');
  if (kind === 'competencia') query = query.in('kind', ['competidor_directo', 'competidor_indirecto', 'referente_local']);
  else if (kind === 'sector') query = query.in('kind', ['regulador', 'gremio', 'aliado_potencial']);
  else if (kind) query = query.eq('kind', kind);
  const t = clean(q); if (t) query = query.or(`name.ilike.%${t}%,services.ilike.%${t}%,description.ilike.%${t}%`);
  return must(await query.order('kind').order('name').limit(500));
}
export async function getEntity(id) { return must(await sb().from('v_intel_entities').select('*').eq('id', id).maybeSingle()); }
export async function entityNotes(id) { return must(await sb().from('intel_entity_notes').select('*').eq('entity_id', id).order('observed_on', { ascending: false }).limit(200)); }
export async function saveEntity(operatorId, v, id = null) {
  if (id) return must(await sb().from('intel_entities').update(v).eq('id', id).select('id').single());
  return must(await sb().from('intel_entities').insert({ ...v, operator_id: operatorId }).select('id').single());
}
export async function deleteEntity(id) { const { error, count } = await sb().from('intel_entities').delete({ count: 'exact' }).eq('id', id); if (error) throw error; if (!count) throw new Error('Solo Admin o Super Admin eliminan fichas.'); }
export async function addNote(operatorId, entityId, { note, sourceUrl = null, observedOn = null }) {
  return must(await sb().from('intel_entity_notes').insert({ operator_id: operatorId, entity_id: entityId, note, source_url: sourceUrl || null, observed_on: observedOn || undefined }).select('id').single());
}

// ---- Ideas de servicios
export async function listIdeas({ status = '' } = {}) {
  let q = sb().from('intel_ideas').select('*');
  if (status) q = q.eq('status', status);
  return must(await q.order('score', { ascending: false }).order('updated_at', { ascending: false }).limit(500));
}
export async function saveIdea(operatorId, v, id = null) {
  if (id) return must(await sb().from('intel_ideas').update(v).eq('id', id).select('id').single());
  return must(await sb().from('intel_ideas').insert({ ...v, operator_id: operatorId }).select('id').single());
}

// ---- Fuentes y corridas (Admin)
export async function listSources() { return must(await sb().from('intel_sources').select('*').order('is_active', { ascending: false }).order('name')); }
export async function saveSource(operatorId, v, id = null) {
  if (id) return must(await sb().from('intel_sources').update(v).eq('id', id).select('id').single());
  return must(await sb().from('intel_sources').insert({ ...v, operator_id: operatorId }).select('id').single());
}
export async function deleteSource(id) { const { error } = await sb().from('intel_sources').delete().eq('id', id); if (error) throw error; }
export async function lastRuns(limit = 10) { return must(await sb().from('intel_runs').select('*').order('started_at', { ascending: false }).limit(limit)); }

/** Pide a la Edge Function "market-intel" que busque noticias ahora (Admin y Super Admin) */
export async function refreshNow() {
  const { data, error } = await sb().functions.invoke('market-intel', { body: { action: 'refresh' } });
  if (error) {
    let msg = error.message || 'Error';
    try { const body = await error.context?.json?.(); if (body?.message) msg = body.message; } catch { /* sin cuerpo */ }
    if (error.context?.status === 404 || /Failed to send a request|not found/i.test(msg)) msg = 'La función market-intel no está publicada en Supabase (Iteración 11, paso 2 de la guía).';
    throw Object.assign(new Error(msg), { code: 'SOFA' });
  }
  if (data && data.ok === false) throw Object.assign(new Error(data.message || 'No se pudo actualizar'), { code: 'SOFA' });
  return data;
}

// ---- Guías de buenas prácticas
export async function listGuides() { return must(await sb().from('intel_guides').select('id, code, category, title, summary, is_published, sort_order, updated_at, checklist').order('sort_order').order('title')); }
export async function getGuide(id) { return must(await sb().from('intel_guides').select('*').eq('id', id).maybeSingle()); }
export async function saveGuide(operatorId, v, id = null) {
  if (id) return must(await sb().from('intel_guides').update(v).eq('id', id).select('id').single());
  return must(await sb().from('intel_guides').insert({ ...v, operator_id: operatorId }).select('id').single());
}
