/**
 * SOFA · Edge Function "admin-users" (Supabase).
 * Invita usuarios, reenvía accesos y cambia roles con la clave de servicio,
 * que vive SOLO en el servidor de Supabase (nunca en el navegador).
 *
 * 1.9.2: roles alineados al modelo operativo. Prospecto se excluye intencionalmente.
 *        Antes faltaban y «Cambiar rol» a Secretaria respondía «Rol inválido».
 *
 * Variables (Supabase las agrega solas): SUPABASE_URL y las claves (SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS,
 *   o las heredadas SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY)
 * Configuración: AUTH_REDIRECT_URL (recomendado, p. ej. https://staging.sofamedica.com/login)
 *                APP_URL (fallback, p. ej. https://app.sofamedica.com)
 *                ALLOWED_ORIGINS (p. ej. https://staging.sofamedica.com,https://app.sofamedica.com)
 */
import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

export type Deps = {
  getCaller: (jwt: string) => Promise<{ id: string; email?: string } | null>;
  assignRole: (actor: string, user: string | null, role: string, org: string | null, dryRun: boolean) => Promise<string>;
  userIdByEmail: (email: string) => Promise<string | null>;
  inviteUser: (email: string, fullName: string, redirectTo: string) => Promise<{ id: string }>;
  createActiveUser: (email: string, fullName: string, password: string) => Promise<{ id: string }>;
  getUser: (id: string) => Promise<{ id: string; email: string; last_sign_in_at?: string | null } | null>;
  sendRecovery: (email: string, redirectTo: string) => Promise<void>;
  appUrl: string;
  authRedirectUrl?: string;
  allowedOrigins: string[];
};

// Prospecto NO es asignable aquí: vive en lead_users / incorporación y no en organization_users.
const ASSIGNABLE_ROLES = ['super_admin', 'admin', 'operations', 'billing', 'glosas', 'assistant', 'auditor', 'client', 'capturer'];
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const TRUSTED_ORIGINS = ['https://medisofa.github.io', 'https://app.sofamedica.com', 'https://staging.sofamedica.com'];

export function corsHeaders(origin: string | null, allowed: string[]): Record<string, string> {
  const effective = Array.from(new Set([...allowed, ...TRUSTED_ORIGINS]));
  const ok = origin && (effective.includes('*') || effective.includes(origin));
  return {
    'Access-Control-Allow-Origin': ok ? origin! : effective[0] || 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-sofa-client',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin'
  };
}

function reply(status: number, body: Record<string, unknown>, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' } });
}

/** Traduce errores de la base de datos a mensajes para la pantalla */
function dbMessage(e: unknown): string {
  const m = String((e as { message?: string })?.message || e || '');
  return m.replace(/^.*?ERROR:\s*/, '') || 'Error inesperado';
}

export async function handle(req: Request, d: Deps): Promise<Response> {
  const cors = corsHeaders(req.headers.get('origin'), d.allowedOrigins);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply(405, { ok: false, message: 'Método no permitido' }, cors);
  const origin = req.headers.get('origin');
  const effectiveOrigins = Array.from(new Set([...d.allowedOrigins, ...TRUSTED_ORIGINS]));
  if (origin && !effectiveOrigins.includes('*') && !effectiveOrigins.includes(origin)) return reply(403, { ok: false, message: 'Origen no autorizado' }, cors);

  const jwt = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return reply(401, { ok: false, message: 'Sesión requerida' }, cors);
  const caller = await d.getCaller(jwt).catch(() => null);
  if (!caller) return reply(401, { ok: false, message: 'Sesión inválida o vencida' }, cors);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { ok: false, message: 'Solicitud inválida' }, cors); }
  const action = String(body.action || '');
  const email = String(body.email || '').trim().toLowerCase();
  const fullName = String(body.full_name || '').trim().slice(0, 120);
  const role = String(body.role || '');
  const password = String(body.password || '');
  const org = body.organization_id ? String(body.organization_id) : null;
  const configuredRedirect = (d.authRedirectUrl || '').trim();
  const appBase = (d.appUrl || '').replace(/\/+$/, '');
  const legacyStatic = /github\.io/i.test(appBase);
  const redirectTo = configuredRedirect || (appBase ? `${appBase}${legacyStatic ? '/login.html' : '/login'}` : 'https://medisofa.github.io/sofa-crm/login.html');

  if (!['invite', 'resend', 'grant', 'create_active'].includes(action)) return reply(400, { ok: false, message: 'Acción desconocida' }, cors);
  if (!EMAIL.test(email)) return reply(400, { ok: false, message: 'Correo inválido' }, cors);
  if (action !== 'resend' && !ASSIGNABLE_ROLES.includes(role)) return reply(400, { ok: false, message: 'Rol inválido. Elija uno de la lista de roles.' }, cors);
  if ((action === 'invite' || action === 'create_active') && fullName.length < 3) return reply(400, { ok: false, message: 'Escribe el nombre completo' }, cors);
  if (action === 'create_active' && password.length < 12) return reply(400, { ok: false, message: 'La contraseña temporal debe tener al menos 12 caracteres' }, cors);

  try {
    if (action === 'create_active') {
      // Solo Super Admin: alta inmediata, sin correo de invitación. La cuenta queda confirmada
      // pero obligada a cambiar la contraseña temporal en el primer acceso.
      await d.assignRole(caller.id, null, 'super_admin', null, true);
      const existing = await d.userIdByEmail(email);
      if (existing) return reply(409, { ok: false, message: 'Ese correo ya tiene una cuenta. Use Cambiar rol, Activar usuario o Restablecer contraseña.' }, cors);
      await d.assignRole(caller.id, null, role, org, true);
      const u = await d.createActiveUser(email, fullName, password);
      const msg = await d.assignRole(caller.id, u.id, role, org, false);
      return reply(200, { ok: true, user_id: u.id, email_sent: false, must_change_password: true, message: `Usuario creado y activado sin correo. ${msg}. Debe cambiar la contraseña temporal al iniciar sesión.` }, cors);
    }
    if (action === 'invite') {
      await d.assignRole(caller.id, null, role, org, true);
      const existing = await d.userIdByEmail(email);
      if (existing) {
        const msg = await d.assignRole(caller.id, existing, role, org, false);
        return reply(200, { ok: true, user_id: existing, existed: true, message: `El usuario ya existía: ${msg}. Puede entrar con su contraseña o recuperarla.` }, cors);
      }
      const u = await d.inviteUser(email, fullName, redirectTo);
      const msg = await d.assignRole(caller.id, u.id, role, org, false);
      return reply(200, { ok: true, user_id: u.id, message: `Invitación enviada a ${email}. ${msg}.` }, cors);
    }
    const id = await d.userIdByEmail(email);
    if (!id) return reply(404, { ok: false, message: 'No existe un usuario con ese correo' }, cors);
    if (action === 'grant') {
      const msg = await d.assignRole(caller.id, id, role, org, false);
      return reply(200, { ok: true, user_id: id, message: msg }, cors);
    }
    await d.assignRole(caller.id, null, 'billing', null, true);
    const u = await d.getUser(id);
    if (!u?.last_sign_in_at) {
      try { await d.inviteUser(email, fullName || email, redirectTo); return reply(200, { ok: true, message: `Invitación reenviada a ${email}` }, cors); }
      catch (err) {
        if (!/already been registered|email_exists|already registered/i.test(dbMessage(err))) throw err;
      }
    }
    await d.sendRecovery(email, redirectTo);
    return reply(200, { ok: true, message: `Se envió a ${email} un enlace para crear una contraseña nueva` }, cors);
  } catch (e) {
    const msg = dbMessage(e);
    const status = /permiso|Solo el|Solo |no puede/i.test(msg) ? 403 : /inválid|indique|desconocido/i.test(msg) ? 400 : 500;
    return reply(status, { ok: false, message: msg }, cors);
  }
}

const url = Deno.env.get('SUPABASE_URL')!;
const keyFrom = (jsonVar: string, legacyVar: string): string => {
  try { const k = JSON.parse(Deno.env.get(jsonVar) || '{}').default; if (k) return k; } catch { /* sin claves nuevas */ }
  return Deno.env.get(legacyVar) || '';
};
const anonKey = keyFrom('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
const serviceKey = keyFrom('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const publicClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });

const unwrap = <T>({ data, error }: { data: T; error: unknown }): T => { if (error) throw error; return data; };

Deno.serve((req) => handle(req, {
  appUrl: Deno.env.get('APP_URL') || '',
  authRedirectUrl: Deno.env.get('AUTH_REDIRECT_URL') || undefined,
  allowedOrigins: (Deno.env.get('ALLOWED_ORIGINS') || '').split(',').map((s) => s.trim()).filter(Boolean),
  getCaller: async (jwt) => { const { data, error } = await admin.auth.getUser(jwt); return error || !data?.user ? null : { id: data.user.id, email: data.user.email }; },
  assignRole: async (actor, user, role, org, dryRun) => unwrap(await admin.rpc('admin_assign_role', { p_actor: actor, p_user: user, p_role: role, p_org: org, p_dry_run: dryRun })) as string,
  userIdByEmail: async (email) => unwrap(await admin.rpc('admin_user_id_by_email', { p_email: email })) as string | null,
  inviteUser: async (email, fullName, redirectTo) => {
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName }, redirectTo });
    if (error) throw error; return { id: data.user!.id };
  },
  createActiveUser: async (email, fullName, password) => {
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName } });
    if (error) throw error;
    const id = data.user!.id;
    const { error: pe } = await admin.from('profiles').upsert({ id, full_name: fullName, is_active: true, must_change_password: true }, { onConflict: 'id' });
    if (pe) throw pe;
    return { id };
  },
  getUser: async (id) => { const { data, error } = await admin.auth.admin.getUserById(id); if (error) throw error; return data.user as { id: string; email: string; last_sign_in_at?: string | null }; },
  sendRecovery: async (email, redirectTo) => { const { error } = await publicClient.auth.resetPasswordForEmail(email, { redirectTo }); if (error) throw error; }
}));
