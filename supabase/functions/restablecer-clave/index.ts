// SOFA · Edge Function restablecer-clave (2.1 · Iteración 30 · 2.6.1: el error dice la causa y qué hacer)
// El Super Admin restablece la contraseña de otro usuario: se genera una clave temporal ALEATORIA que se muestra una sola vez
// y el usuario debe cambiarla en su primer acceso. La clave nunca se guarda en la base ni en el navegador.
// Autoriza con la sesión de quien la pide (public.authorize_password_reset) y registra con la clave de servicio (public.mark_password_reset).
// No requiere secretos propios: SUPABASE_URL y las claves las inyecta Supabase. Verify JWT: activado.
//
// 5.34.1 · Sincronizado al repo desde producción (orphan hasta ahora). Versión desplegada: v4.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const BASE_HEADERS = "authorization, x-client-info, apikey, content-type, x-sofa-client";
const cors = (req: Request) => ({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": [BASE_HEADERS, req.headers.get("Access-Control-Request-Headers") ?? ""].filter(Boolean).join(", "),
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "600",
});
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const keyFrom = (jsonVar: string, legacyVar: string): string => {
  try { const k = JSON.parse(Deno.env.get(jsonVar) || "{}").default; if (k) return k; } catch { /* sin claves nuevas */ }
  return Deno.env.get(legacyVar) || "";
};
function claveTemporal(): string {
  const may = "ABCDEFGHJKLMNPQRSTUVWXYZ", min = "abcdefghijkmnopqrstuvwxyz", num = "23456789", sim = "@#$%&*+?";
  const todo = may + min + num + sim;
  const pick = (set: string) => set[crypto.getRandomValues(new Uint32Array(1))[0] % set.length];
  const chars = [pick(may), pick(min), pick(num), pick(sim)];
  while (chars.length < 14) chars.push(pick(todo));
  for (let i = chars.length - 1; i > 0; i--) { const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1); [chars[i], chars[j]] = [chars[j], chars[i]]; }
  return chars.join("");
}

Deno.serve(async (req) => {
  const CORS = cors(req);
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use el botón «Restablecer contraseña» en Usuarios y roles." }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Su sesión venció. Inicie sesión de nuevo e intente otra vez." }, 401);
  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "La solicitud llegó incompleta. Recargue la página e intente de nuevo." }, 400); }
  const userId = String(b.user_id ?? "");
  if (!UUID.test(userId)) return json({ error: "Elija el usuario de la lista y vuelva a intentar." }, 422);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = keyFrom("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const serviceKey = keyFrom("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!anonKey || !serviceKey) return json({ error: "La función no encuentra las claves del proyecto. Avise al Administrador para revisar «restablecer-clave» en Supabase." }, 500);

  const quien = createClient(url, anonKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: u } = await quien.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!u?.user) return json({ error: "Su sesión venció. Inicie sesión de nuevo e intente otra vez." }, 401);
  const ok = await quien.rpc("authorize_password_reset", { p_user: userId });
  if (ok.error) return json({ error: ok.error.message }, 403);

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const clave = claveTemporal();
  const upd = await admin.auth.admin.updateUserById(userId, { password: clave });
  if (upd.error) {
    const m = String(upd.error.message ?? "");
    const pista = /scan error|converting null|database error finding user/i.test(m)
      ? "La cuenta fue creada por SQL y le faltan datos de acceso: aplique la migración 126 (SOFA 2.6.1) y vuelva a intentar."
      : /password/i.test(m) ? "Supabase rechazó la clave por su política de contraseñas: revise Authentication › Policies."
      : "Revise el usuario en Supabase › Authentication y vuelva a intentar.";
    return json({ error: `No se pudo cambiar la contraseña. ${pista} (Detalle: ${m.slice(0, 160)})` }, 500);
  }
  const reg = await admin.rpc("mark_password_reset", { p_user: userId, p_by: u.user.id });
  if (reg.error) return json({ error: `La clave se cambió pero no se pudo marcar el cambio obligatorio: ${reg.error.message}. Vuelva a restablecerla.` }, 500);
  return json({ user_id: userId, email: ok.data?.email, temporary_password: clave,
    aviso: "Entregue esta clave por un medio privado. Se muestra una sola vez y el usuario deberá cambiarla al entrar." });
});
