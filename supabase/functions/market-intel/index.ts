// 5.34.1 · Sincronizado al repo desde produccion (orphan hasta ahora). Version desplegada: v5.
/**
 * SOFA · Edge Function "market-intel" (Supabase).
 * Actualiza las noticias del sector: lee las fuentes activas (búsquedas de Google News o RSS),
 * clasifica cada titular por tema y relevancia para SOFA y guarda SOLO titular, medio, fecha y enlace.
 * Opcional: con el secreto ANTHROPIC_API_KEY agrega una línea "¿Qué significa para SOFA?" a los
 * 20 titulares más relevantes de cada corrida (solo se envían titulares, nunca datos de pacientes).
 *
 * Secretos: ALLOWED_ORIGINS (p. ej. https://medisofa.github.io) · CRON_SECRET (texto largo al azar,
 *           para la tarea programada) · ANTHROPIC_API_KEY (opcional) · INTEL_AI_MODEL (opcional)
 * Supabase agrega solos SUPABASE_URL y las claves (SUPABASE_SECRET_KEYS o SUPABASE_SERVICE_ROLE_KEY).
 */
import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

// ---------------------------------------------------------------------
// Lógica comprobable sin conexión con Supabase
// ---------------------------------------------------------------------
export type Source = { id: string | null; name: string; kind: 'google_news' | 'rss'; query: string; lang: 'es' | 'en'; topic: string; weight: number; entity_id?: string | null };
export type Entity = { id: string; name: string; kind: string; monitor: boolean; monitor_query: string | null };
export type FeedItem = { title: string; link: string; publisher: string | null; published: Date | null };
export type Row = { operator_id: string; source_id: string | null; entity_id: string | null; url: string; url_hash: string; title: string; title_hash: string;
  publisher: string | null; published_at: string | null; lang: string; topic: string; relevance: number; implication: string | null; is_ai: boolean };
export type AiResult = { i: number; relevancia?: number; tema?: string; implicacion?: string };
export type Deps = {
  getCaller: (jwt: string) => Promise<{ id: string } | null>;
  isAllowed: (userId: string) => Promise<boolean>;
  cronSecret: string;
  operatorId: () => Promise<string>;
  sources: () => Promise<Source[]>;
  entities: () => Promise<Entity[]>;
  recentTitleHashes: () => Promise<Set<string>>;
  fetchText: (url: string) => Promise<string>;
  insertItems: (rows: Row[]) => Promise<number>;
  markSource: (id: string, error: string | null) => Promise<void>;
  startRun: (trigger: 'manual' | 'cron', userId: string | null) => Promise<string>;
  finishRun: (id: string, stats: Record<string, unknown>) => Promise<void>;
  prune: () => Promise<number>;
  ai: ((items: { i: number; title: string; publisher: string | null; lang: string }[]) => Promise<AiResult[]>) | null;
  googleBase: string;
  allowedOrigins: string[];
  now: () => Date;
};

export const TOPICS = ['regulacion', 'ars', 'facturacion', 'habilitacion', 'tecnologia', 'competencia', 'internacional', 'mercado'];
const CORE = new Set(['regulacion', 'ars', 'facturacion', 'habilitacion']);
const KEYWORDS: Record<string, string[]> = {
  regulacion: ['sisalril', 'cnss', 'seguridad social', '87-01', 'resolucion', 'normativa', 'pdss', 'superintendencia', 'reglamento', 'circular', 'regulation', 'cms rule'],
  ars: [' ars ', 'administradora de riesgos', 'aseguradora', 'senasa', 'seguro familiar de salud', 'afiliados', 'adars', 'health insurer', 'payer'],
  facturacion: ['glosa', 'facturacion', 'reclamacion', 'cobro', 'pago a prestadores', 'tarifa', 'tarifario', 'honorarios', 'deuda', 'claim', 'denial', 'billing', 'reimbursement', 'prior authorization', 'revenue cycle', 'coding'],
  habilitacion: ['habilitacion', 'acreditacion', 'licencia sanitaria', 'establecimientos de salud', 'clausur', 'inspeccion', 'dgha', 'cierre de clinica'],
  tecnologia: ['inteligencia artificial', ' ia ', 'digital', 'software', 'automatiza', ' ai ', 'telemedicina', 'expediente electronico', 'interoperab', 'automation'],
  competencia: ['facturacion medica', 'gestion de cobros', 'outsourcing', 'empresa de facturacion', 'acquisition', 'acquires', 'merger', 'adquiere'],
  mercado: ['clinica', 'hospital', 'medicos', 'prestadores', 'colegio medico', 'andeclip', 'salud privada', 'centro medico', 'physician', 'health system']
};
const DR = ['republica dominicana', 'dominicana', 'santo domingo', 'santiago de los caballeros', ' rd '];
/** Palabra con espacio final = palabra completa; sin espacio = prefijo (clausur → clausura, clausurado) */
const key = (w: string) => (/\s$/.test(w) ? norm(w) : norm(w).trimEnd());

export function norm(s: string): string {
  return ` ${String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9ñ\-\s]/g, ' ').replace(/\s+/g, ' ').trim()} `;
}
const decode = (s: string) => s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
  .replace(/&#39;|&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n))).replace(/&amp;/g, '&').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
const tag = (block: string, name: string) => { const m = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`, 'i').exec(block); return m ? decode(m[1]) : ''; };

/** RSS 2.0 y Atom básicos (Google News usa RSS 2.0 con <source>) */
export function parseFeed(xml: string): FeedItem[] {
  const out: FeedItem[] = [];
  const blocks = xml.match(/<item[\s>][\s\S]*?<\/item>/gi) || xml.match(/<entry[\s>][\s\S]*?<\/entry>/gi) || [];
  for (const b of blocks.slice(0, 100)) {
    let title = tag(b, 'title');
    let link = tag(b, 'link');
    if (!link) { const m = /<link[^>]*href="([^"]+)"/i.exec(b); link = m ? m[1] : ''; }
    const publisher = tag(b, 'source') || null;
    const dateTxt = tag(b, 'pubDate') || tag(b, 'published') || tag(b, 'updated');
    const d = dateTxt ? new Date(dateTxt) : null;
    if (publisher && title.endsWith(` - ${publisher}`)) title = title.slice(0, -(publisher.length + 3)).trim();
    if (!title || !/^https?:\/\//i.test(link)) continue;
    out.push({ title: title.slice(0, 300), link, publisher: publisher ? publisher.slice(0, 120) : null, published: d && !isNaN(d.getTime()) ? d : null });
  }
  return out;
}

/** Tema y relevancia 0–100 por reglas; la IA puede ajustarlos después */
export function classify(title: string, source: Source, entities: Entity[]): { topic: string; relevance: number; entity_id: string | null } {
  const t = norm(title);
  const points: Record<string, number> = {};
  let score = 10;
  for (const [topic, words] of Object.entries(KEYWORDS)) {
    let hits = 0;
    for (const w of words) if (t.includes(key(w))) hits += 1;
    if (hits) { const p = Math.min(hits, 3) * (CORE.has(topic) ? 15 : 8); points[topic] = p; score += p; }
  }
  const drHit = source.lang === 'es' && DR.some((w) => t.includes(key(w)));
  if (drHit) score += 10;
  let entity_id: string | null = null;
  for (const e of entities) {
    const n = norm(e.name).trim();
    if (n.length >= 4 && t.includes(` ${n}`)) { entity_id = e.id; score += 20; break; }
  }
  // Noticia de una búsqueda de monitoreo: se liga a la entidad solo si además es del sector
  if (!entity_id && source.entity_id && score >= 25) entity_id = source.entity_id;
  if (source.lang === 'en') points.internacional = (points.internacional || 0) + 12;
  score = Math.round(score * (0.8 + 0.15 * Math.max(1, Math.min(3, source.weight || 2))));
  const PRIORITY = ['facturacion', 'habilitacion', 'regulacion', 'ars', 'competencia', 'tecnologia', 'internacional', 'mercado'];
  const best = Object.entries(points).sort((a, b) => b[1] - a[1] || PRIORITY.indexOf(a[0]) - PRIORITY.indexOf(b[0]))[0];
  return { topic: best ? best[0] : source.topic, relevance: Math.max(0, Math.min(100, score)), entity_id };
}

export async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
export function feedUrl(s: Source, googleBase: string): string {
  if (s.kind === 'rss') return s.query;
  const loc = s.lang === 'en' ? 'hl=en-US&gl=US&ceid=US:en' : 'hl=es-419&gl=DO&ceid=DO:es-419';
  return `${googleBase.replace(/\/+$/, '')}/rss/search?q=${encodeURIComponent(s.query)}&${loc}`;
}
const ENTITY_TOPIC: Record<string, string> = { regulador: 'regulacion', gremio: 'mercado', competidor_directo: 'competencia', competidor_indirecto: 'competencia', referente_local: 'competencia', referente_internacional: 'internacional', aliado_potencial: 'mercado' };

export const DEFAULT_ORIGINS = ['https://app.sofamedica.com', 'https://medisofa.github.io'];
export function configuredOrigins(raw = ''): string[] {
  const extra = raw.split(',').map((s) => s.trim()).filter((s) => {
    try { const u = new URL(s); return u.protocol === 'https:' && u.origin === s; } catch { return false; }
  });
  return [...new Set([...DEFAULT_ORIGINS, ...extra])];
}
export function corsHeaders(origin: string | null, allowed: string[]): Record<string, string> {
  const ok = origin && allowed.includes(origin);
  return { 'Access-Control-Allow-Origin': ok ? origin! : allowed[0] || 'null', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-sofa-client, x-cron-secret', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin' };
}
const reply = (status: number, body: Record<string, unknown>, cors: Record<string, string>) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' } });

export async function handle(req: Request, d: Deps): Promise<Response> {
  const cors = corsHeaders(req.headers.get('origin'), d.allowedOrigins);
  const origin = req.headers.get('origin');
  if (origin && !d.allowedOrigins.includes(origin)) return reply(403, { ok: false, message: 'Origen no autorizado' }, cors);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply(405, { ok: false, message: 'Método no permitido' }, cors);

  // Quién llama: la tarea programada (secreto compartido) o un Admin / Super Admin con sesión
  let trigger: 'manual' | 'cron' = 'manual'; let userId: string | null = null;
  const cron = req.headers.get('x-cron-secret');
  if (cron) {
    if (!d.cronSecret || cron !== d.cronSecret) return reply(401, { ok: false, message: 'Secreto de tarea programada inválido' }, cors);
    trigger = 'cron';
  } else {
    const jwt = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (!jwt) return reply(401, { ok: false, message: 'Sesión requerida' }, cors);
    const caller = await d.getCaller(jwt).catch(() => null);
    if (!caller) return reply(401, { ok: false, message: 'Sesión inválida o vencida' }, cors);
    if (!(await d.isAllowed(caller.id).catch(() => false))) return reply(403, { ok: false, message: 'Solo el Super Admin o un Administrador SOFA actualizan las noticias' }, cors);
    userId = caller.id;
  }

  let runId: string | null = null;
  const errors: { source: string; error: string }[] = [];
  let fetched = 0, inserted = 0, aiEnriched = 0, successfulSources = 0;
  try {
    runId = await d.startRun(trigger, userId);
    const [op, sources, entities, seen] = await Promise.all([d.operatorId(), d.sources(), d.entities(), d.recentTitleHashes()]);
    const all: Source[] = [...[...sources].sort((a,b) => Number(b.kind === 'rss') - Number(a.kind === 'rss')), ...entities.filter((e) => e.monitor && e.monitor_query).map((e) => ({
      id: null, name: `Monitoreo · ${e.name}`, kind: 'google_news' as const, query: e.monitor_query!, lang: 'es' as const, topic: ENTITY_TOPIC[e.kind] || 'mercado', weight: 2, entity_id: e.id }))].slice(0, 30);
    const cutoff = d.now().getTime() - 45 * 86400000;
    const rows: Row[] = [];
    const runTitles = new Set<string>();
    const feedDeadline = Date.now() + 30000;
    for (const [sourceIndex, s] of all.entries()) {
      if (Date.now() >= feedDeadline) {
        errors.push({ source: 'general', error: `${all.length - sourceIndex} fuentes pendientes: se alcanzó el tiempo máximo de lectura. Intente más tarde.` });
        break;
      }
      try {
        const items = parseFeed(await d.fetchText(feedUrl(s, d.googleBase)));
        fetched += items.length; successfulSources += 1;
        for (const it of items) {
          if (it.published && it.published.getTime() < cutoff) continue;
          const th = await sha256(norm(it.title).trim());
          if (seen.has(th) || runTitles.has(th)) continue;
          const c = classify(it.title, s, entities);
          if (c.relevance < 15) continue;
          runTitles.add(th);
          rows.push({ operator_id: op, source_id: s.id, entity_id: c.entity_id, url: it.link, url_hash: await sha256(it.link.trim()), title: it.title, title_hash: th,
            publisher: it.publisher, published_at: it.published ? it.published.toISOString() : null, lang: s.lang, topic: c.topic, relevance: c.relevance, implication: null, is_ai: false });
        }
        if (s.id) await d.markSource(s.id, null);
      } catch (e) {
        const msg = String((e as Error)?.message || e).slice(0, 200);
        errors.push({ source: s.name, error: msg });
        if (s.id) await d.markSource(s.id, msg).catch(() => {});
      }
    }
    // Enriquecimiento opcional con IA: solo titulares, los 20 más relevantes
    if (d.ai && rows.length) {
      const top = rows.map((r, i) => ({ r, i })).filter((x) => x.r.relevance >= 30).sort((a, b) => b.r.relevance - a.r.relevance).slice(0, 20);
      if (top.length) {
        try {
          const res = await d.ai(top.map((x, k) => ({ i: k, title: x.r.title, publisher: x.r.publisher, lang: x.r.lang })));
          for (const a of res || []) {
            const x = top[a.i]; if (!x) continue;
            if (typeof a.relevancia === 'number') x.r.relevance = Math.max(0, Math.min(100, Math.round((x.r.relevance + a.relevancia) / 2)));
            if (a.tema && TOPICS.includes(a.tema)) x.r.topic = a.tema;
            if (a.implicacion) { x.r.implication = String(a.implicacion).slice(0, 240); x.r.is_ai = true; aiEnriched += 1; }
          }
        } catch (e) { errors.push({ source: 'IA', error: String((e as Error)?.message || e).slice(0, 200) }); }
      }
    }
    inserted = rows.length ? await d.insertItems(rows) : 0;
    if (successfulSources) await d.prune().catch(() => 0);
    const stats = { sources: all.length, fetched, inserted, ai_enriched: aiEnriched, errors };
    await d.finishRun(runId, stats);
    if (!all.length) return reply(409, { ok: false, ...stats, message: 'No hay fuentes activas ni entidades con monitoreo configurado.' }, cors);
    if (!successfulSources) return reply(502, { ok: false, ...stats, message: 'No se pudo leer ninguna fuente de noticias. El proveedor de las fuentes no respondió correctamente; las noticias guardadas se conservan. Intente más tarde.' }, cors);
    return reply(200, { ok: true, ...stats, message: `${inserted} ${inserted === 1 ? 'noticia nueva' : 'noticias nuevas'} de ${all.length} fuentes${errors.length ? ` · ${errors.length} ${errors.length === 1 ? 'fuente' : 'fuentes'} con error` : ''}` }, cors);
  } catch (e) {
    const msg = String((e as Error)?.message || e);
    if (runId) await d.finishRun(runId, { sources: 0, fetched, inserted, ai_enriched: aiEnriched, errors: [...errors, { source: 'general', error: msg }] }).catch(() => {});
    return reply(500, { ok: false, message: msg }, cors);
  }
}

/** Un solo reintento para fallos transitorios; cada fuente consume como máximo ~12 s. */
export async function fetchFeedText(url: string, fetcher: typeof fetch = fetch, pause: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms))): Promise<string> {
  let lastError: Error = new Error('La fuente no respondió');
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetcher(url, { signal: AbortSignal.timeout(6000), headers: { 'user-agent': 'Mozilla/5.0 (compatible; SOFA-market-intel/1.1)', accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml' } });
      if (!r.ok) {
        lastError = new Error(`HTTP ${r.status}`);
        if (attempt === 0 && [429, 502, 503, 504].includes(r.status)) { await r.body?.cancel().catch(() => {}); await pause(300); continue; }
        throw lastError;
      }
      const xml = await r.text();
      if (!/<(?:rss|feed)(?:\s|>)/i.test(xml)) throw new Error('La fuente no devolvió un canal RSS o Atom válido');
      return xml;
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
      if (attempt === 0 && ['AbortError', 'TimeoutError', 'TypeError'].includes(lastError.name)) { await pause(300); continue; }
      throw lastError;
    }
  }
  throw lastError;
}

// ---------------------------------------------------------------------
// Conexión con Supabase y con la IA (opcional)
// ---------------------------------------------------------------------
const keyFrom = (jsonVar: string, legacyVar: string): string => {
  try { const k = JSON.parse(Deno.env.get(jsonVar) || '{}').default; if (k) return k; } catch { /* sin claves nuevas */ }
  return Deno.env.get(legacyVar) || '';
};
const admin = createClient(Deno.env.get('SUPABASE_URL')!, keyFrom('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
const unwrap = <T>({ data, error }: { data: T; error: unknown }): T => { if (error) throw error; return data; };
let opCache = '';
const operatorId = async () => {
  if (!opCache) opCache = (unwrap(await admin.from('organizations').select('id').eq('kind', 'operator').limit(1).single()) as { id: string }).id;
  return opCache;
};

const aiKey = Deno.env.get('ANTHROPIC_API_KEY') || '';
const aiModel = Deno.env.get('INTEL_AI_MODEL') || 'claude-haiku-4-5-20251001';
const aiBase = (Deno.env.get('ANTHROPIC_BASE_URL') || 'https://api.anthropic.com').replace(/\/+$/, '');
async function aiEnrich(items: { i: number; title: string; publisher: string | null; lang: string }[]): Promise<AiResult[]> {
  const prompt = 'Eres analista de mercado de SOFA, empresa dominicana que gestiona la facturación médica ante las ARS '
    + '(radicación, codificación, glosas y cobros) y la habilitación de establecimientos ante el MISPAS. '
    + 'Para cada titular devuelve SOLO un arreglo JSON, sin texto adicional: '
    + '[{"i":n,"relevancia":0-100,"tema":"regulacion|ars|facturacion|habilitacion|tecnologia|competencia|internacional|mercado",'
    + '"implicacion":"una frase en español de máximo 160 caracteres sobre qué significa para SOFA o sus clientes"}]. '
    + 'Relevancia alta si afecta cobros, glosas, normas de SISALRIL o de las ARS, habilitación, o competidores de facturación médica en República Dominicana. '
    + 'Usa solo lo que dice el titular; no inventes datos.\n\nTitulares:\n'
    + items.map((x) => `${x.i}. [${x.lang}] ${x.title}${x.publisher ? ` (${x.publisher})` : ''}`).join('\n');
  const r = await fetch(`${aiBase}/v1/messages`, {
    method: 'POST', signal: AbortSignal.timeout(45000),
    headers: { 'content-type': 'application/json', 'x-api-key': aiKey, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({ model: aiModel, max_tokens: 2000, messages: [{ role: 'user', content: prompt }] })
  });
  if (!r.ok) throw new Error(`IA HTTP ${r.status}`);
  const j = await r.json() as { content?: { type: string; text?: string }[] };
  const text = (j.content || []).filter((c) => c.type === 'text').map((c) => c.text || '').join('');
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) throw new Error('La IA no devolvió JSON');
  return JSON.parse(m[0]) as AiResult[];
}

Deno.serve((req) => handle(req, {
  cronSecret: Deno.env.get('CRON_SECRET') || '',
  allowedOrigins: configuredOrigins(Deno.env.get('ALLOWED_ORIGINS') || ''),
  googleBase: Deno.env.get('GOOGLE_NEWS_BASE') || 'https://news.google.com',
  now: () => new Date(),
  getCaller: async (jwt) => { const { data, error } = await admin.auth.getUser(jwt); return error || !data?.user ? null : { id: data.user.id }; },
  isAllowed: async (uid) => {
    const rows = unwrap(await admin.from('organization_users').select('role_code, organizations!inner(kind), profiles!inner(is_active)')
      .eq('user_id', uid).eq('is_active', true).eq('organizations.kind', 'operator').eq('profiles.is_active', true)
      .in('role_code', ['super_admin', 'admin']).limit(1)) as unknown[];
    return rows.length > 0;
  },
  operatorId,
  sources: async () => unwrap(await admin.from('intel_sources').select('id, name, kind, query, lang, topic, weight').eq('is_active', true)) as Source[],
  entities: async () => unwrap(await admin.from('intel_entities').select('id, name, kind, monitor, monitor_query')) as Entity[],
  recentTitleHashes: async () => {
    const since = new Date(Date.now() - 30 * 86400000).toISOString();
    const rows = unwrap(await admin.from('intel_items').select('title_hash').gte('fetched_at', since).limit(10000)) as { title_hash: string }[];
    return new Set(rows.map((r) => r.title_hash));
  },
  fetchText: (url) => fetchFeedText(url),
  insertItems: async (rows) => (unwrap(await admin.from('intel_items').upsert(rows, { onConflict: 'operator_id,url_hash', ignoreDuplicates: true }).select('id')) as unknown[] || []).length,
  markSource: async (id, error) => { unwrap(await admin.from('intel_sources').update({ last_fetched_at: new Date().toISOString(), last_error: error }).eq('id', id)); },
  startRun: async (trigger, userId) => (unwrap(await admin.from('intel_runs').insert({ operator_id: await operatorId(), trigger, triggered_by: userId }).select('id').single()) as { id: string }).id,
  finishRun: async (id, st) => { unwrap(await admin.from('intel_runs').update({ finished_at: new Date().toISOString(), ...st }).eq('id', id)); },
  prune: async () => unwrap(await admin.rpc('intel_prune', { p_days: 180 })) as number,
  ai: aiKey ? aiEnrich : null
}));

