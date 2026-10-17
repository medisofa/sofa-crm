-- 083 · Suite de la 082 (radicar solo SOFA oficina). Solo lee el catálogo; no modifica datos.
-- Ejecutar desde el SQL Editor:  select * from app.qa_run_tests_radicacion_oficina();
create or replace function app.qa_run_tests_radicacion_oficina()
returns table(n integer, resultado text, prueba text, detalle text)
language plpgsql
set search_path = ''
as $function$
declare v_roles text[]; v_res jsonb := '[]'::jsonb;
begin
  select allowed_roles into v_roles from public.submission_transitions where from_code = 'lista_para_radicar' and to_code = 'radicada';
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-01 · Facturación no puede pasar un lote a radicada','ok',v_roles is not null and not ('billing' = any (v_roles)),'d',v_roles::text));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-02 · Super Admin y Administrador sí pueden','ok',v_roles @> array['super_admin','admin'],'d',v_roles::text));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-03 · Médico y Secretaria no radican','ok',v_roles is not null and not (v_roles && array['client','capturer']),'d',null));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-04 · Facturación conserva sus otras transiciones (depuración)','ok',
     exists (select 1 from public.submission_transitions where from_code = 'en_depuracion' and to_code = 'lista_para_radicar' and 'billing' = any (allowed_roles)),'d',null));
  v_res := v_res || jsonb_build_array(jsonb_build_object('p','CT-05 · Ninguna transición hacia radicada admite client ni capturer','ok',
     not exists (select 1 from public.submission_transitions where to_code = 'radicada' and allowed_roles && array['client','capturer']),'d',null));
  return query
    select 0, case when bool_and(coalesce((e->>'ok')::boolean, false)) then 'TODO OK' else 'REVISAR' end,   -- 5.10.0: una prueba sin resultado (NULL) cuenta como fallo; antes bool_and la ignoraba
           format('%s de %s pruebas aprobadas', count(*) filter (where coalesce((e->>'ok')::boolean, false)), count(*)), null::text
      from jsonb_array_elements(v_res) e
    union all
    select x.i::int, case when (x.e->>'ok')::boolean then 'APROBADA' else 'FALLÓ' end, x.e->>'p', x.e->>'d'
      from jsonb_array_elements(v_res) with ordinality as x(e, i)
    order by 1;
end
$function$;
