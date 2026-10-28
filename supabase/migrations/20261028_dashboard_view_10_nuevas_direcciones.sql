-- 28/10/2026: diez vistas nuevas del dashboard, elegidas con el cliente a partir de un
-- catálogo de propuestas. Se agregan al whitelist existente (operativo/ejecutivo/visual),
-- que no cambia de significado ni se toca. Aplicado en producción (Supabase,
-- proyecto bpwjhgpzhzhiocoxrvzq) y registrado aquí para el historial.

alter table public.profiles drop constraint profiles_dashboard_view_chk;
alter table public.profiles add constraint profiles_dashboard_view_chk
  check (dashboard_view is null or dashboard_view = any (array[
    'operativo','ejecutivo','visual',
    'clinico','informe','operaciones','cercano','recibo','editorial','minimal','carpeta','vidrio','bloques'
  ]));

create or replace function public.set_my_dashboard_view(p_view text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if p_view not in ('operativo','ejecutivo','visual',
                     'clinico','informe','operaciones','cercano','recibo','editorial','minimal','carpeta','vidrio','bloques') then
    raise exception 'Vista de dashboard no válida' using errcode='22023';
  end if;

  update public.profiles
     set dashboard_view=p_view,
         updated_at=now()
   where id=auth.uid();

  if not found then
    raise exception 'Perfil no encontrado' using errcode='P0002';
  end if;

  return p_view;
end
$function$;
