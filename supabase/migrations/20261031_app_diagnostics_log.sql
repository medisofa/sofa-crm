-- Ya aplicado en producción (31/10/2026).
--
-- Contexto: el usuario (Súper Admin) reportó que, con el segundo factor ya verificado — incluso
-- en una ventana de incógnito nueva, sin nada en caché — solo ve 1 de 6 clientes reales en la
-- pantalla "Clientes". Se verificó directo en la base de datos que las reglas de RLS (visible_org_ids)
-- SÍ devuelven los 6 clientes cuando la sesión está en aal2, así que el dato y los permisos están
-- bien: lo que falta es poder ver, desde la cuenta del propio Súper Admin, qué trae realmente la
-- sesión real del navegador (su aal, su rol) en el momento del problema — sin poder automatizar un
-- inicio de sesión con MFA para probarlo en vivo.
--
-- Esta tabla guarda, desde cualquier pantalla y cualquier usuario, un registro permanente de
-- eventos (inicio de sesión con su aal, y errores de carga) para que el Súper Admin pueda revisarlo
-- sin pedirle capturas de pantalla a nadie.
create table if not exists public.app_diagnostics_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  role_code text,
  organization_id uuid,
  aal text,
  route text,
  event_type text not null,
  table_name text,
  message text not null,
  details jsonb
);
create index if not exists app_diagnostics_log_created_idx on public.app_diagnostics_log (created_at desc);

alter table public.app_diagnostics_log enable row level security;

-- Cualquier usuario autenticado puede dejar su propio evento (nunca el de otro usuario).
create policy app_diagnostics_log_insert on public.app_diagnostics_log
  for insert to authenticated
  with check (user_id = auth.uid());

-- Solo el Súper Admin puede leerlo (app.is_staff ya exige, aparte, el segundo factor verificado).
create policy app_diagnostics_log_select on public.app_diagnostics_log
  for select to authenticated
  using (app.is_staff(array['super_admin']));

grant select, insert on public.app_diagnostics_log to authenticated;
