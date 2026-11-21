-- 252_clinica_reclamaciones_propias.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «clinica_reclamaciones_propias_252»).
--
-- Opción 1, etapa 1b: en una clínica (organización con 2 o más médicos activos) el usuario «Médico» limitado
-- (ver 248: app.client_limited / sees_all_providers) ve y maneja solo las reclamaciones, radicaciones, glosas,
-- pagos de ARS y documentos de SUS radicaciones.
--
-- Diseño: en vez de reescribir las ~40 políticas existentes (casi todas «organization_id in visible_org_ids()»),
-- cada tabla recibe UNA política RESTRICTIVA que se suma (AND) a las permisivas:
--     (select app.i_am_limited_client()) is not true  or  <la fila es de mis radicaciones>
-- Para cualquier usuario que no sea médico limitado, la primera parte es verdadera y se evalúa UNA vez por
-- consulta (subselect = initplan): no hay costo por fila ni cambio de comportamiento.
--
-- RPC SECURITY DEFINER (saltan RLS):
--   · Reciben médico/radicación/línea → guarda al inicio (capture_claim_dx, preaudit_submission,
--     register_captured_document, remove_service_line, confirm_document_ocr).
--   · history_search → se fuerza p_provider al médico propio.
--   · Tableros de toda la organización → el médico limitado recibe «este tablero lo ve el director».
--     Fail-closed a propósito; la versión filtrada por médico queda para la 1c.
-- Pendiente 1c: honorarios y facturas SOFA, mensajes, BI y reporte del contador.
-- 252b (aplicada aparte el mismo día): client_document_ok cubre documentos de glosa y de pago.
-- Suite: 253_clinica_reclamaciones_propias_test.sql.

do $$ begin
  if to_regprocedure('app.client_limited(uuid)') is null then raise exception 'Falta la 248'; end if;
end $$;

-- 1. Funciones de alcance
create or replace function app.i_am_limited_client()
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.organization_users ou
                  where ou.user_id = auth.uid() and ou.is_active and ou.role_code = 'client'
                    and app.client_limited(ou.organization_id));
$$;

create or replace function app.client_submission_ok(p_submission uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select p_submission is null or exists (select 1 from public.submissions s where s.id = p_submission and app.client_provider_ok(s.provider_id))
      or not exists (select 1 from public.submissions s where s.id = p_submission);
$$;

create or replace function app.client_line_ok(p_line uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select p_line is null or not exists (select 1 from public.service_lines sl where sl.id = p_line)
      or exists (select 1 from public.service_lines sl where sl.id = p_line and app.client_submission_ok(sl.submission_id));
$$;

create or replace function app.client_glosa_ok(p_glosa uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select p_glosa is null or not exists (select 1 from public.glosas g where g.id = p_glosa)
      or exists (select 1 from public.glosas g where g.id = p_glosa and app.client_submission_ok(g.submission_id));
$$;

-- Un pago de ARS (transferencia) puede cubrir radicaciones de varios médicos: el médico limitado lo ve
-- solo si alguna de sus radicaciones está en él. (Ve el total de la transferencia; su parte está en las asignaciones.)
create or replace function app.client_payment_ok(p_payment uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.payment_allocations pa where pa.payment_id = p_payment and app.client_submission_ok(pa.submission_id)
                   and exists (select 1 from public.submissions s where s.id = pa.submission_id));
$$;

create or replace function app.client_document_ok(p_line uuid, p_entity_type text, p_entity_id uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select app.client_line_ok(p_line)
     and case p_entity_type when 'submission'   then app.client_submission_ok(p_entity_id)
                            when 'service_line' then app.client_line_ok(p_entity_id)
                            when 'glosa'        then app.client_glosa_ok(p_entity_id)
                            when 'payment'      then app.client_payment_ok(p_entity_id)
                            else true end;   -- organization, contract, habilitation, sofa_invoice, service_request: de la organización (1c revisa sofa_invoice)
$$;

-- 2. Políticas restrictivas
do $$
declare r record;
begin
  for r in select * from (values
      ('submissions',               'app.client_provider_ok(provider_id)'),
      ('submission_status_history', 'app.client_submission_ok(submission_id)'),
      ('validation_runs',           'app.client_submission_ok(submission_id)'),
      ('service_lines',             'app.client_submission_ok(submission_id)'),
      ('glosas',                    'app.client_submission_ok(submission_id)'),
      ('payment_allocations',       'app.client_submission_ok(submission_id)'),
      ('payment_line_allocations',  'app.client_submission_ok(submission_id)'),
      ('claim_audits',              'app.client_line_ok(service_line_id)'),
      ('claim_diagnoses',           'app.client_line_ok(service_line_id)'),
      ('claim_dossier_exceptions',  'app.client_line_ok(service_line_id)'),
      ('claim_resubmissions',       'app.client_line_ok(service_line_id)'),
      ('claim_status_history',      'app.client_line_ok(service_line_id)'),
      ('glosa_items',               'app.client_line_ok(service_line_id)'),
      ('line_document_checks',      'app.client_line_ok(service_line_id)'),
      ('glosa_appeals',             'app.client_glosa_ok(glosa_id)'),
      ('glosa_conciliation_acts',   'app.client_glosa_ok(glosa_id)'),
      ('glosa_status_history',      'app.client_glosa_ok(glosa_id)'),
      ('payments',                  'app.client_payment_ok(id)'),
      ('documents',                 'app.client_document_ok(service_line_id, entity_type, entity_id)'),
      ('commercial_documents',      'app.client_provider_ok(provider_id)'),
      ('senasa_payment_certificates','app.client_provider_ok(provider_id)'),
      ('claim_duplicate_reviews',   'not app.client_limited(organization_id)')
    ) as t(tbl, expr)
  loop
    if to_regclass('public.' || r.tbl) is null then raise exception 'No existe la tabla %', r.tbl; end if;
    execute format('drop policy if exists %I on public.%I', r.tbl || '_clinica_propio', r.tbl);
    execute format('create policy %I on public.%I as restrictive for all to authenticated using ((select app.i_am_limited_client()) is not true or %s) with check ((select app.i_am_limited_client()) is not true or %s)',
                   r.tbl || '_clinica_propio', r.tbl, r.expr, r.expr);
  end loop;
end $$;

-- 3. Guardas en RPC que reciben médico / radicación / línea / documento
do $$
declare r record; d text;
begin
  for r in select * from (values
      ('public.capture_claim_dx(uuid,uuid,uuid,date,text,text,text,text,numeric,numeric,text,text,text,text,text,text,boolean,uuid,text)', 'app.client_provider_ok(p_provider)'),
      ('public.preaudit_submission(uuid)',  'app.client_submission_ok(p_submission)'),
      ('public.register_captured_document(uuid,uuid,uuid,text,text,text,text,bigint,text,text,jsonb)', 'app.client_submission_ok(p_submission) and app.client_line_ok(p_line)'),
      ('public.remove_service_line(uuid,text)', 'app.client_line_ok(p_line)'),
      ('public.confirm_document_ocr(uuid,jsonb)', 'exists (select 1 from public.documents x where x.id = p_document and app.client_document_ok(x.service_line_id, x.entity_type, x.entity_id)) or not exists (select 1 from public.documents x where x.id = p_document)')
    ) as t(sig, cond)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    if position('clinica_propio' in d) = 0 then
      if position(E'\nbegin\n' in d) = 0 then raise exception 'No se encontró el inicio de %', r.sig; end if;
      d := overlay(d placing E'\nbegin\n  -- clinica_propio (252)\n  if not (' || r.cond || E') then\n    raise exception ''En una clínica cada médico maneja solo sus reclamaciones. Pida al director de la clínica que lo haga.'' using errcode = ''42501'';\n  end if;\n'
                   from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
      execute d;
    end if;
  end loop;
end $$;

-- 4. history_search: el médico limitado solo busca en lo suyo
do $$ declare d text; sig constant text := 'public.history_search(uuid,text,uuid,uuid,date,date,text,numeric,numeric,boolean,integer,jsonb)'; begin
  d := pg_get_functiondef(sig::regprocedure);
  if position('clinica_propio' in d) = 0 then
    d := overlay(d placing E'\nbegin\n  -- clinica_propio (252)\n  if app.client_limited(p_org) then\n    p_provider := (select p.id from public.providers p where p.organization_id = p_org and p.user_id = auth.uid() and p.is_active limit 1);\n    if p_provider is null then raise exception ''Su usuario no está enlazado a su ficha de médico. Pida al director de la clínica que lo enlace.'' using errcode = ''42501''; end if;\n  end if;\n'
                 from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
    execute d;
  end if;
end $$;

-- 5. Tableros de toda la organización: el médico limitado no los abre (los ve el director)
do $$
declare f text; d text;
begin
  foreach f in array array[
    'public.glosa_response_board(uuid)', 'public.preaudit_open_lots(uuid)', 'public.recon_list(uuid,text,integer)',
    'public.legal_audit_queue(uuid,text)', 'public.first_pass_glosa(uuid,integer)', 'public.my_glosa_causes(uuid)',
    'public.archive_candidates(uuid)', 'public.archives_list(uuid)', 'public.archive_periods_until(uuid,date,text)',
    'public.golive_checklist(uuid)', 'public.onboarding_plan(uuid)']
  loop
    d := pg_get_functiondef(f::regprocedure);
    if position('clinica_propio' in d) = 0 then
      if position(E'\nbegin\n' in d) = 0 then raise exception 'No se encontró el inicio de %', f; end if;
      d := overlay(d placing E'\nbegin\n  -- clinica_propio (252)\n  if app.client_limited(p_org) then\n    raise exception ''En una clínica este tablero lo ve el director, porque reúne a todos los médicos. Pídale el dato a la dirección de la clínica.'' using errcode = ''42501'';\n  end if;\n'
                   from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
      execute d;
    end if;
  end loop;
end $$;
