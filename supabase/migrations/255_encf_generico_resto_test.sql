-- 255 · Suite de la 254 (radicar con cualquier e-NCF válido). Se deshace sola.
-- Ya aplicado en producción (2026-11-20): crea la función de prueba; ejecutarla no deja datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_encf_resto();
create or replace function app.qa_run_tests_encf_resto()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare
  v_res jsonb := '[]'::jsonb;
  o constant uuid := 'b9000000-0000-4000-8000-0000000000e9';
  p constant uuid := 'c9000000-0000-4000-8000-0000000000e9';
  s1 constant uuid := 'f9000000-0000-4000-8000-0000000000a9';
  s2 constant uuid := 'f9000000-0000-4000-8000-0000000000b9';
  v_ars uuid := (select id from public.ars where is_active order by name limit 1);
begin
  if auth.uid() is not null then raise exception 'Las pruebas solo se ejecutan desde el SQL Editor' using errcode = '42501'; end if;
  begin
    insert into public.organizations (id, kind, operator_id, legal_name, tax_id, org_type, status, started_on, whatsapp, ecf_required_from)
      values (o,'client','00000000-0000-4000-8000-000000000001','QA EN','00000000199','Consultorio','activo',current_date-90,'8095550071', current_date - 10);
    insert into public.providers (id, organization_id, full_name) values (p, o, 'Dr. EN');
    insert into public.submissions (id, organization_id, provider_id, ars_id, period, sequence, ncf, ecf_security_code, ecf_dgii_status) values
      (s1, o, p, v_ars, date_trunc('month', current_date)::date, 1, 'E450000000004', 'ABC123', 'aceptado'),
      (s2, o, p, v_ars, date_trunc('month', current_date)::date, 2, null, null, null);
    perform set_config('app.status_change', 'on', true);
    begin
      update public.submissions set status = 'radicada', submitted_on = current_date, ars_receipt_number = 'QA-EN-1' where id = s1;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EN-01 · Un lote con e-NCF E45 aceptado se radica','ok',true,'d',null));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EN-01 · Un lote con e-NCF E45 aceptado se radica','ok',false,'d',left(sqlerrm,160)));
    end;
    begin
      update public.submissions set status = 'radicada' where id = s2;
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EN-02 · Un lote sin e-NCF sigue bloqueado','ok',false,'d','Se permitió'));
    exception when others then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','EN-02 · Un lote sin e-NCF sigue bloqueado','ok',sqlerrm like '%e-NCF%' and sqlerrm not like '%E31%','d',left(sqlerrm,160)));
    end;
    perform set_config('app.status_change', '', true);
    v_res := v_res || jsonb_build_array(jsonb_build_object('p','EN-03 · Ninguna función de negocio exige solo E31','ok',
      not exists (select 1 from pg_proc x join pg_namespace n on n.oid = x.pronamespace where n.nspname in ('public','app') and x.proname not like 'qa\_%' and x.prosrc like '%E31\\d{10}%'),'d',null));
    raise exception using errcode = 'P0001', message = 'sofa_qa_rollback';
  exception when others then
    if sqlerrm <> 'sofa_qa_rollback' then
      v_res := v_res || jsonb_build_array(jsonb_build_object('p','Error inesperado (las pruebas se detuvieron aquí)','ok',false,'d',left(sqlerrm, 300)));
    end if;
  end;
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
revoke execute on function app.qa_run_tests_encf_resto() from public, anon, authenticated;
