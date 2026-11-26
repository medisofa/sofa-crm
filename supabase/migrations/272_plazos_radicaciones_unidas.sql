-- Ya aplicado en producción (26/11/2026). Se guarda aquí como documentación.
-- 272 · Plazos de las radicaciones unidas (268): se miden desde el mes más antiguo incluido,
-- y el lote que quedó vacío al unir ya no genera avisos ni tareas.
-- Las funciones se parchan sobre su definición vigente (si un ancla no aparece, aborta).

begin;

do $dep$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'submissions' and column_name = 'period_from') then
    raise exception 'Falta la migración 268: aplíquela antes de la 272.';
  end if;
end $dep$;

-- Lote vaciado por «Unir en una radicación». Si vuelve a recibir reclamaciones, deja de contar como vaciado.
create or replace function app.merged_away(p_submission uuid, p_notes text)
returns boolean language sql stable set search_path = '' as $$
  select coalesce(p_notes, '') like '%UNIDA a %'
     and not exists (select 1 from public.service_lines l where l.submission_id = p_submission);
$$;
revoke all on function app.merged_away(uuid, text) from public, anon;
grant execute on function app.merged_away(uuid, text) to authenticated, service_role;

-- Cada función se parcha en memoria con todos sus cambios y se recrea una sola vez:
-- un cambio a medias no compila (el alias de uno depende del «join» de otro).
do $mig$
declare
  v text;
  v_orig text;
  f record;
  r record;
begin
  create temp table _p272 (n int, fn text, viejo text, nuevo text) on commit drop;
  insert into _p272 values
      -- función, texto vigente, texto nuevo
      (1, 'app.inbox_tasks(date)', '((s.period + interval ''1 month'')::date - 1 + prm.win)', '((coalesce(s.period_from, s.period) + interval ''1 month'')::date - 1 + prm.win)'),
      (2, 'app.preaudit_lot(uuid)', '(s.period + interval ''1 month'')::date - 1 + v_window', '(coalesce(s.period_from, s.period) + interval ''1 month'')::date - 1 + v_window'),
      (3, 'public.refresh_alerts()', '(s.period + interval ''1 month'')::date - 1 + coalesce(st.submission_window_days,30)', '(coalesce(s.period_from, s.period) + interval ''1 month'')::date - 1 + coalesce(st.submission_window_days,30)'),
      (4, 'public.refresh_alerts()', 'where s.submitted_on is null and s.status not in (''rechazada'',''cerrada'')', 'where not app.merged_away(s.id, s.notes) and s.submitted_on is null and s.status not in (''rechazada'',''cerrada'')'),
      (5, 'public.work_queue()', '(s.period + interval ''1 month'')::date - 1 + st.win', '(coalesce(x.period_from, s.period) + interval ''1 month'')::date - 1 + st.win'),
      (6, 'public.work_queue()', E'from public.v_submissions s, st\n   where s.submitted_on is null', E'from public.v_submissions s join public.submissions x on x.id = s.id cross join st\n   where not app.merged_away(s.id, s.notes) and s.submitted_on is null'),
      (7, 'public.work_queue()', 'from public.v_submissions s where s.status in (''borrador'',''recibida'',''pendiente_documentos'',''en_depuracion'')', 'from public.v_submissions s where not app.merged_away(s.id, s.notes) and s.status in (''borrador'',''recibida'',''pendiente_documentos'',''en_depuracion'')');
  for f in select distinct fn from _p272 order by fn loop
    select pg_get_functiondef(f.fn::regprocedure) into v;
    v_orig := v;
    for r in select * from _p272 p where p.fn = f.fn order by p.n loop
      if position(r.nuevo in v) > 0 then continue; end if;   -- ya aplicado
      if position(r.viejo in v) = 0 then raise exception '272: no se encontró el ancla % en %', r.n, r.fn; end if;
      v := replace(v, r.viejo, r.nuevo);
    end loop;
    if v is distinct from v_orig then execute v; end if;
  end loop;
end $mig$;

delete from app.schema_migrations where version = '272';
insert into app.schema_migrations (version, report) values ('272', jsonb_build_object('tema', 'plazos de radicaciones unidas'));

commit;
