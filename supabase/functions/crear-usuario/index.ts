// SOFA · Edge Function crear-usuario
// Crea un usuario de acceso con una clave temporal ALEATORIA y le asigna su rol.
// La clave temporal se devuelve una sola vez a quien hace el alta; el usuario queda obligado a cambiarla en su primer acceso.
// 2.1: también crea usuarios de PROSPECTOS (lead_id + rol prospect): solo ven su incorporación y pasan a Médico al convertirse en cliente.
// 2.6.1: aprueba SOLICITUDES del consultorio (request_id): solo el Super Admin; el correo, el rol y los médicos salen de la solicitud.
// 1.9.2: CORS acepta la cabecera x-sofa-client que envía la aplicación (antes el navegador bloqueaba la llamada:
//        «Failed to send a request to the Edge Function») y las claves se leen con el formato nuevo o el heredado.
// No requiere secretos propios: SUPABASE_URL y las claves las inyecta Supabase.
// La clave de servicio vive solo aquí (servidor). NUNCA la copies al frontend ni al repositorio.
//
// 5.34.1 · Sincronizado al repo desde producción (orphan hasta ahora). Versión desplegada: v11.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const BASE_HEADERS = "authorization, x-client-info, apikey, content-type, x-sofa-client";
const cors = (req: Request) => ({
  "Access-Control-Allow-Origin": "*",
  // Se aceptan las cabeceras base y cualquiera que el navegador anuncie en la verificación previa
  "Access-Control-Allow-Headers": [BASE_HEADERS, req.headers.get("Access-Control-Request-Headers") ?? ""].filter(Boolean).join(", "),
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "600",
});

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Claves: primero las nuevas (sb_publishable / sb_secret); si no existen, las heredadas (anon / service_role) */
const keyFrom = (jsonVar: string, legacyVar: string): string => {
  try { const k = JSON.parse(Deno.env.get(jsonVar) || "{}").default; if (k) return k; } catch { /* sin claves nuevas */ }
  return Deno.env.get(legacyVar) || "";
};

Deno.serve(async (req) => {
  const CORS = cors(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" } });

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use el formulario de usuarios para crear un usuario." }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Su sesión venció. Inicie sesión de nuevo e intente otra vez." }, 401);

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "La solicitud llegó incompleta. Recargue la página e intente de nuevo." }, 400); }

  let email = String(b.email ?? "").trim().toLowerCase();
  const lead = String(b.lead_id ?? "");
  const request = String(b.request_id ?? "");
  let org = String(b.organization_id ?? "");
  let role = String(b.role_code ?? "");
  let providers = Array.isArray(b.provider_ids) ? (b.provider_ids as unknown[]).map(String) : [];
  let canBook = b.can_book === undefined ? true : Boolean(b.can_book);
  let canWa = Boolean(b.can_whatsapp);
  if (request && !UUID.test(request)) return json({ error: "La solicitud no es válida. Recargue la página." }, 422);

  if (!request && !EMAIL.test(email)) return json({ error: "Escriba un correo válido, por ejemplo nombre@dominio.com." }, 422);
  if (request) {
    // los datos se toman de la solicitud (paso 1)
  } else if (lead) {
    if (!UUID.test(lead)) return json({ error: "Elija el prospecto de la lista." }, 422);
  } else {
    if (!UUID.test(org)) return json({ error: "Elija la organización del usuario." }, 422);
    if (!role) return json({ error: "Elija el rol del usuario." }, 422);
  }
  if (providers.some((p) => !UUID.test(p))) return json({ error: "La lista de médicos no es válida. Recargue la página." }, 422);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = keyFrom("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const serviceKey = keyFrom("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!anonKey || !serviceKey) return json({ error: "La función no encuentra las claves del proyecto. Avise al Administrador para revisar la configuración de crear-usuario en Supabase." }, 500);

  // 1) Autorización con el token de quien pide el alta (reglas en la base)
  const quien = createClient(url, anonKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: u } = await quien.auth.getUser(auth.replace(/^Bearer\s+/i, ""));
  if (!u?.user) return json({ error: "Su sesión venció. Inicie sesión de nuevo e intente otra vez." }, 401);
  const ok = request ? await quien.rpc("authorize_user_request", { p_id: request })
           : lead ? await quien.rpc("authorize_prospect_user", { p_lead: lead })
                  : await quien.rpc("authorize_user_creation", { p_org: org, p_role: role, p_providers: providers });
  if (ok.error) return json({ error: ok.error.message }, 403);
  if (request) {
    const q = ok.data as Record<string, unknown>;
    email = String(q.email ?? ""); org = String(q.organization_id ?? ""); role = String(q.role_code ?? "");
    providers = Array.isArray(q.provider_ids) ? (q.provider_ids as unknown[]).map(String) : [];
    canBook = Boolean(q.can_book); canWa = Boolean(q.can_whatsapp);
    if (!EMAIL.test(email) || !UUID.test(org) || !role) return json({ error: "La solicitud está incompleta. Rechácela y pida al consultorio que la envíe de nuevo." }, 422);
  }

  // 2) Invitación por correo: el usuario establece su contraseña, sin clave temporal ni confirmación artificial.
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const creado = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: "https://app.sofamedica.com/login.html",
  });
  if (creado.error || !creado.data?.user) {
    const m = (creado.error?.message ?? "").toLowerCase();
    if (m.includes("already") || m.includes("registered") || m.includes("exists")) {
      return json({ error: "Ese correo ya tiene usuario. Si necesita otro rol, asígnelo en «Usuarios y roles» con «Cambiar rol» en lugar de crearlo de nuevo." }, 409);
    }
    return json({ error: "No se pudo crear el acceso. Revise el correo e intente de nuevo; si sigue igual, avise al Administrador." }, 500);
  }

  // 3) Rol, médicos y bandera de cambio de clave
  const reg = lead
    ? await admin.rpc("register_prospect_user", { p_user: creado.data.user.id, p_lead: lead, p_created_by: u.user.id })
    : await admin.rpc("register_new_user", {
        p_user: creado.data.user.id, p_org: org, p_role: role, p_providers: providers,
        p_can_book: canBook, p_can_whatsapp: canWa, p_created_by: u.user.id,
      });
  if (reg.error) {
    await admin.auth.admin.deleteUser(creado.data.user.id); // no deja un acceso sin rol
    return json({ error: `No se pudo asignar el rol: ${reg.error.message}` }, 500);
  }
  if (request) {
    const fin = await admin.rpc("complete_user_request", { p_id: request, p_user: creado.data.user.id, p_by: u.user.id });
    if (fin.error) return json({ error: `La cuenta se creó pero la solicitud no se marcó como aprobada: ${fin.error.message}. Avise al soporte de SOFA.` }, 500);
  }

  return json({ user_id: creado.data.user.id, email, role: lead ? "prospect" : role, invitation_sent: true,
    aviso: "Invitación enviada. El usuario debe abrir su correo, verificar el enlace y establecer su contraseña." });
});
