// SOFA · Edge Function calendario-medico (260 · recordatorio de citas al médico, opción 1)
// Entrega la agenda de UN médico en formato iCal para suscribirse desde iPhone, Google Calendar u Outlook.
//
// GET /functions/v1/calendario-medico?t=<token de 64 hex>
//
// Seguridad:
//   · Pública a propósito (verify_jwt=false): las apps de calendario no inician sesión en SOFA.
//   · El acceso lo da el token del enlace (32 bytes aleatorios). La base solo guarda su SHA-256 y el enlace es
//     revocable (calendar_feed_revoke). Token inválido o revocado → 404 sin detalles.
//   · Solo llama a public.calendar_feed_ics, que únicamente service_role puede ejecutar.
//   · El contenido lleva iniciales del paciente, nunca nombre completo, cédula ni teléfono (lo arma la base).
//   · La clave de servicio la inyecta Supabase; nunca va al repositorio.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const TOKEN = /^[0-9a-f]{64}$/;
const noEncontrado = () =>
  new Response("Calendario no encontrado. Pida a SOFA un enlace nuevo desde Agenda › Calendario en mi teléfono.\n", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Método no permitido\n", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const url = new URL(req.url);
  const token = (url.searchParams.get("t") || "").trim().toLowerCase();
  if (!TOKEN.test(token)) return noEncontrado();

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data, error } = await sb.rpc("calendar_feed_ics", { p_token: token });
  if (error) {
    console.error("calendar_feed_ics", error.message);
    return new Response("El calendario no está disponible en este momento. Intente más tarde.\n", {
      status: 503,
      headers: { "Content-Type": "text/plain; charset=utf-8", "Retry-After": "300" },
    });
  }
  if (!data) return noEncontrado();
  return new Response(req.method === "HEAD" ? null : (data as string), {
    status: 200,
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="agenda-sofa.ics"',
      "Cache-Control": "private, max-age=300",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
  });
});
