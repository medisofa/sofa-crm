/** SOFA · Iteración 18 · Adaptador común (servicios + utilidades de pantalla).
 *  Es el ÚNICO archivo de la Iteración 18 que toca el cliente de Supabase.
 *  Usa el cliente único de js/supabase.js (función sb()). */
import { sb } from '../supabase.js';

/** Cliente de Supabase del proyecto. js/supabase.js exporta sb() (no «supabase»): este objeto lo envuelve
 *  para que las pantallas sigan usando supabase.rpc / .from / .functions / .auth sin cambios. */
const supabase = new Proxy({}, {
  get(_, key) {
    const c = sb();
    if (!c) throw new Error('SOFA no tiene configurada la conexión con Supabase (js/config.js). Pide al administrador que la revise.');
    const v = c[key];
    return typeof v === 'function' ? v.bind(c) : v;
  }
});

/** Llama una función de la base (RPC). Los errores de la base ya vienen en español y dicen qué hacer. */
export async function rpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message || 'No se pudo completar la operación. Intente de nuevo.');
  return data;
}

/** Lectura (select) con RLS. El frontend nunca inserta, actualiza ni borra directo. */
async function read(query) {
  const { data, error } = await query;
  if (error) throw new Error(error.message || 'No se pudo leer la información. Intente de nuevo.');
  return data || [];
}
export const clientOptions = () => read(supabase.from('organizations').select('id, legal_name, trade_name').eq('kind', 'client').order('legal_name'));
export const providerOptions = () => read(supabase.from('providers').select('id, full_name, organization_id').eq('is_active', true).order('full_name'));
export const pendingMessages = () => read(supabase.from('message_queue').select('id, kind, provider_id, organization_id, to_phone, subject, body, scheduled_for, status, patient_id').eq('status', 'pendiente').order('scheduled_for').limit(300));
export const recentSummaries = () => read(supabase.from('message_queue').select('id, provider_id, organization_id, subject, body, scheduled_for, status').eq('kind', 'resumen_semanal').order('scheduled_for', { ascending: false }).limit(40));

/** Constructor de nodos sin innerHTML (evita inyección de texto). h('div', {class:'x'}, 'texto', otroNodo) */
export function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  return el;
}

export const money = (n) => (n == null || n === '' ? '—' : 'RD$ ' + Number(n).toLocaleString('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
export const pct = (n) => (n == null ? '—' : Number(n).toLocaleString('es-DO', { maximumFractionDigits: 1 }) + ' %');
export const num = (n) => (n == null ? '—' : Number(n).toLocaleString('es-DO'));
export const fmtDate = (iso) => { if (!iso) return '—'; const [y, m, d] = String(iso).slice(0, 10).split('-'); return `${d}/${m}/${y}`; };
export const todayIso = () => new Date().toISOString().slice(0, 10);
export const monthNow = () => todayIso().slice(0, 7);
export const monthToDate = (ym) => `${ym}-01`;
export const monthsAgoIso = (n) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - n); return d.toISOString().slice(0, 10); };
export const clientName = (c) => c.trade_name || c.legal_name;

export function kpi(label, value, hint) {
  return h('div', { class: 'i18-kpi' }, h('div', { class: 'i18-kpi-v' }, value), h('div', { class: 'i18-kpi-l' }, label), hint ? h('div', { class: 'i18-kpi-h' }, hint) : null);
}
export function table(cols, rows, foot) {
  return h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
    h('thead', {}, h('tr', {}, cols.map((c) => h('th', { class: c.right ? 'i18-r' : '' }, c.label)))),
    h('tbody', {}, rows.length ? rows.map((r) => h('tr', {}, cols.map((c) => h('td', { class: c.right ? 'i18-r' : '' }, c.get(r))))) : h('tr', {}, h('td', { colspan: cols.length, class: 'i18-empty' }, 'Sin datos para mostrar.'))),
    foot ? h('tfoot', {}, h('tr', {}, cols.map((c) => h('td', { class: c.right ? 'i18-r' : '' }, foot[c.key] ?? '')))) : null));
}
export const note = (text, kind = 'info') => h('p', { class: `i18-note i18-${kind}`, role: kind === 'error' ? 'alert' : 'status' }, text);

/** CSV para Excel en español: BOM, comillas y protección contra fórmulas (=, +, -, @). */
export function downloadCsv(filename, rows) {
  const cell = (v) => { let s = v == null ? '' : String(v); if (/^[=+\-@]/.test(s) && isNaN(Number(s))) s = "'" + s; return /[",;\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  const blob = new Blob(['﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const a = h('a', { href: URL.createObjectURL(blob), download: filename });
  document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

/** Ejecuta una carga mostrando "Cargando…" y el error en español si falla. */
export async function guarded(box, fn) {
  box.replaceChildren(note('Cargando…'));
  try { const out = await fn(); box.replaceChildren(); return out; }
  catch (e) { box.replaceChildren(note(e.message, 'error')); return null; }
}

/** Llamada a una Edge Function con la sesión actual (usada por el alta de usuarios). */
export async function invoke(name, body) {
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (error) {
    let msg = error.message;
    try { const j = await error.context.json(); if (j && (j.error || j.message)) msg = j.error || j.message; } catch (_) { /* se usa el mensaje base */ }
    // 1.9.2 · Mensajes en español que dicen qué hacer
    if (/Failed to send a request/i.test(msg)) msg = `No se pudo comunicar con la función «${name}» de Supabase. Revise su conexión a internet; si sigue igual, el Administrador debe verificar que la función «${name}» esté publicada (Supabase › Edge Functions).`;
    else if (/Relay Error|non-2xx/i.test(msg)) msg = `La función «${name}» respondió con un error. Intente de nuevo; si se repite, avise al Administrador.`;
    throw new Error(msg);
  }
  if (data && data.error) throw new Error(data.error);
  return data;
}
export { supabase };

/** Modalidades de atención que aplican al médico (según su especialidad). Para el selector de Reclamaciones. */
export const careModesFor = (providerId) => rpc('care_modes_for', { p_provider: providerId });
