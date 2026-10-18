// SOFA · Edge Function enviar-correos (5.3.0 · Iteración 63 · avisos por correo y resúmenes programados)
// Consume la cola public.email_queue: toma un lote (email_claim_batch), lo entrega a un PROVEEDOR y marca cada correo como enviado o fallido.
// HOY EL PROVEEDOR ES SIMULADO: no sale ningún correo real. Para conectar Resend, SMTP u otro:
//   1) escriba una clase que implemente la interfaz ProveedorCorreo (más abajo) y regístrela en PROVEEDORES;
//   2) ponga CORREO_PROVEEDOR=resend (o el nombre que le dé) y sus secretos con «supabase secrets set» o en Vault/variables de la función;
//   3) NUNCA ponga claves en este archivo, en el repositorio ni en la base de datos.
// Variables de la función (todas son secretos o configuración, ninguna va al repositorio):
//   SUPABASE_URL y la clave de servicio: las inyecta Supabase.
//   CORREOS_SECRETO       (obligatoria) texto largo y aleatorio; quien programa la función (pg_cron/pg_net o el programador de Supabase) lo manda en el encabezado x-sofa-secreto.
//   CORREO_PROVEEDOR      (opcional) «simulado» por defecto.\n//   RESEND_API_KEY       (requerida solo para resend; secreto del servidor).\n//   CORREO_ENVIO_REAL_HABILITADO (requerida para proveedor real; valor literal true).
//   CORREO_REMITENTE      (opcional) «SOFA <avisos@dominio-por-definir>»: el dominio remitente todavía no está decidido.
//   PIXEL_URL             (opcional) URL pública de esta función; solo se usa si el operador encendió el seguimiento de aperturas.
//   ORIGEN_PERMITIDO      (opcional) origen exacto de la app para CORS; sin él, no se responde a navegadores.
// DESPLIEGUE ACTUAL: verify_jwt=true. Conservarlo hasta probar la autenticación del programador.\n// El encabezado x-sofa-secreto es una segunda capa para POST; no sustituye al JWT del gateway.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

// ── Interfaz del proveedor ───────────────────────────────────────────────────────────────────────────────────────
export interface Correo { id: string; to: string; name: string | null; subject: string; html: string; text: string; attempt: number; token: string | null; critical: boolean }
export interface Resultado { ok: boolean; messageId?: string; permanente?: boolean; error?: string }
export interface ProveedorCorreo { nombre: string; enviar(c: Correo, remitente: string): Promise<Resultado> }

/** Proveedor simulado: valida lo básico y devuelve un id inventado. No abre ninguna conexión. */
class ProveedorSimulado implements ProveedorCorreo {
  nombre = "simulado";
  async enviar(c: Correo): Promise<Resultado> {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(c.to)) return { ok: false, permanente: true, error: "Dirección de destino no válida." };
    return { ok: true, messageId: `sim-${crypto.randomUUID()}` };
  }
}
/** Proveedor real: preparado pero inactivo hasta verificar dominio, secreto y pruebas. */
class ProveedorResend implements ProveedorCorreo {
  nombre = "resend";
  async enviar(c: Correo, remitente: string): Promise<Resultado> {
    const apiKey = Deno.env.get("RESEND_API_KEY") || "";
    if (!apiKey || !remitente || /dominio-por-definir|\.invalid/i.test(remitente)) {
      return { ok: false, permanente: true, error: "Dominio remitente o credenciales de correo sin configurar." };
    }
    const from = remitente.trim();
    if (!/^.+<[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+>$/.test(from)) {
      return { ok: false, permanente: true, error: "Formato de remitente inválido." };
    }
    let response: Response;
    try {
      response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": c.id,
        },
        body: JSON.stringify({ from, to: [c.to], subject: c.subject, html: c.html, text: c.text }),
        signal: AbortSignal.timeout(15000),
      });
    } catch {
      return { ok: false, error: "No se pudo conectar con el proveedor de correo." };
    }
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      return {
        ok: false,
        permanente: response.status >= 400 && response.status < 500 && ![408, 409, 429].includes(response.status),
        error: `Proveedor rechazó el envío (HTTP ${response.status}).`,
      };
    }
    if (typeof result?.id !== "string" || !result.id) {
      return { ok: false, error: "Proveedor no confirmó el identificador del mensaje." };
    }
    return { ok: true, messageId: result.id };
  }
}
const PROVEEDORES: Record<string, () => ProveedorCorreo> = {
  simulado: () => new ProveedorSimulado(),
  resend: () => new ProveedorResend(),
};

// ── Utilidades ───────────────────────────────────────────────────────────────────────────────────────────────────
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GIF = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (c) => c.charCodeAt(0));
const keyFrom = (jsonVar: string, legacyVar: string): string => {
  try { const k = JSON.parse(Deno.env.get(jsonVar) || "{}").default; if (k) return k; } catch { /* sin claves nuevas */ }
  return Deno.env.get(legacyVar) || "";
};
function igualesSeguro(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}
const cors = (): Record<string, string> => {
  const o = Deno.env.get("ORIGEN_PERMITIDO") || "";
  return o ? { "Access-Control-Allow-Origin": o, "Vary": "Origin", "Access-Control-Allow-Headers": "content-type, x-sofa-secreto", "Access-Control-Allow-Methods": "POST, GET, OPTIONS", "Access-Control-Max-Age": "600" } : {};
};

Deno.serve(async (req) => {
  const CORS = cors();
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = keyFrom("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  const secreto = Deno.env.get("CORREOS_SECRETO") || "";
  if (!url || !serviceKey || secreto.length < 24) return json({ error: "El servicio de correos no está configurado. Avise al Administrador para revisar «enviar-correos»." }, 500);
  const db = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

  // Pixel de apertura (GET ?o=<token>): responde siempre el mismo GIF, haya o no correo, para no revelar qué tokens existen.
  if (req.method === "GET") {
    const o = new URL(req.url).searchParams.get("o") || "";
    if (UUID.test(o)) { try { await db.rpc("email_register_open", { p_token: o }); } catch { /* el pixel nunca falla */ } }
    return new Response(GIF, { status: 200, headers: { "Content-Type": "image/gif", "Cache-Control": "no-store, max-age=0" } });
  }
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  // Quien procesa la cola presenta el secreto (comparación en tiempo constante)
  if (!igualesSeguro(req.headers.get("x-sofa-secreto") || "", secreto)) return json({ error: "No autorizado." }, 401);

  let limite = 20;
  try { const b = await req.json(); if (b && Number.isInteger(b.limite)) limite = Math.min(Math.max(b.limite, 1), 100); } catch { /* sin cuerpo: lote normal */ }

  const nombre = Deno.env.get("CORREO_PROVEEDOR") || "simulado";
  // Bloqueo explícito: un proveedor real exige autorización de activación separada.
  if (nombre !== "simulado" && Deno.env.get("CORREO_ENVIO_REAL_HABILITADO") !== "true") {
    return json({ error: "El envío real aún no está habilitado." }, 503);
  }
  const fabrica = PROVEEDORES[nombre];
  if (!fabrica) return json({ error: "El proveedor de correo configurado no está disponible. Avise al Administrador para revisar «enviar-correos»." }, 500);
  const proveedor = fabrica();
  const remitente = Deno.env.get("CORREO_REMITENTE") || "SOFA <avisos@dominio-por-definir.invalid>";
  const pixelUrl = Deno.env.get("PIXEL_URL") || "";

  const lote = await db.rpc("email_claim_batch", { p_limit: limite });
  if (lote.error) return json({ error: "No se pudo tomar el lote de correos. Intente de nuevo en unos minutos." }, 500);
  const correos = (lote.data ?? []) as Correo[];

  let enviados = 0, fallidos = 0, reintentos = 0;
  for (const c of correos) {
    let html = c.html;
    // El pixel solo va si la base entregó token (seguimiento encendido) y existe PIXEL_URL; nunca en avisos críticos.
    if (c.token && !c.critical && pixelUrl && UUID.test(c.token)) {
      html = html.replace(`<!--sofa-pixel:${c.token}-->`, `<img src="${pixelUrl}?o=${c.token}" width="1" height="1" alt="" style="display:none">`);
    }
    let r: Resultado;
    try { r = await proveedor.enviar({ ...c, html }, remitente); }
    catch { r = { ok: false, error: "El proveedor no respondió." }; }   // el detalle técnico no se guarda ni se devuelve
    try {
      if (r.ok) { await db.rpc("email_mark_sent", { p_id: c.id, p_provider: proveedor.nombre, p_message_id: r.messageId ?? "" }); enviados++; }
      else {
        const m = await db.rpc("email_mark_failed", { p_id: c.id, p_error: r.error ?? "El proveedor no pudo enviar el correo.", p_permanent: !!r.permanente });
        if (m.data === "fallido") fallidos++; else reintentos++;
      }
    } catch { /* si el marcado falla, el correo vuelve a la cola a los 10 minutos (email_claim_batch) */ }
  }
  return json({ tomados: correos.length, enviados, fallidos, reintentos, proveedor: proveedor.nombre });
});
