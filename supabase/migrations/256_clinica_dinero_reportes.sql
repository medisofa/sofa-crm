-- 256_clinica_dinero_reportes.sql
-- Ya aplicado en producción (2026-11-20, mcp__Supabase__apply_migration «clinica_dinero_reportes_256»).
--
-- Opción 1, etapa 1c (cierra la opción 1): en una clínica, el usuario «Médico» limitado (248) tampoco ve
-- la relación comercial de la clínica con SOFA, ni los reportes de toda la organización, ni los mensajes
-- o registros de sus colegas. Regla por lo que recibe cada función:
--   · p_provider              → solo su médico; si no se indica médico, se bloquea.
--   · p_org (toda la clínica) → «lo ve el director» (fail-closed: los reportes por médico quedan como mejora).
--   · un registro puntual     → se valida el médico dueño del registro.
--   · Tablas de honorarios y facturas SOFA → solo el director (son la cuenta de la clínica con SOFA).
--   · Mensajes a pacientes    → solo los de su médico.
--   · Inicio del médico (my_dashboard) → sus KPI se calculan solo con lo suyo; la deuda con SOFA no se muestra.
-- Las llamadas internas (tareas programadas, funciones del personal SOFA) no se afectan: client_limited es
-- falso sin usuario o para roles que no son «client».
-- Suite: 257_clinica_dinero_reportes_test.sql.

do $$ begin
  if to_regprocedure('app.i_am_limited_client()') is null then raise exception 'Falta la 252'; end if;
end $$;

-- 1. Tablas: políticas restrictivas
do $$
declare r record;
begin
  for r in select * from (values
      ('sofa_fees',             'not app.client_limited(organization_id)'),
      ('sofa_invoices',         'not app.client_limited(organization_id)'),
      ('sofa_invoice_payments', 'not app.client_limited(organization_id)'),
      ('fee_rules',             'not app.client_limited(organization_id)'),
      ('message_queue',         'app.client_provider_ok(provider_id) and (provider_id is not null or not app.client_limited(organization_id))'),
      ('hospital_reports',      'app.client_provider_ok(provider_id)')
    ) as t(tbl, expr)
  loop
    if to_regclass('public.' || r.tbl) is null then raise exception 'No existe la tabla %', r.tbl; end if;
    execute format('drop policy if exists %I on public.%I', r.tbl || '_clinica_propio', r.tbl);
    execute format('create policy %I on public.%I as restrictive for all to authenticated using ((select app.i_am_limited_client()) is not true or %s) with check ((select app.i_am_limited_client()) is not true or %s)',
                   r.tbl || '_clinica_propio', r.tbl, r.expr, r.expr);
  end loop;
end $$;

-- 2. Guardas al inicio de las RPC
do $$
declare r record; d text; v_fn text;
  msg_org  constant text := 'En una clínica este reporte lo ve el director, porque reúne a todos los médicos. Pídale el dato a la dirección de la clínica.';
  msg_prov constant text := 'En una clínica cada médico maneja solo lo suyo. Pida al director de la clínica que haga este cambio.';
begin
  for r in select * from (values
      -- toda la organización → director
      ('account_statement', 'not app.client_limited(p_org)', 'org'), ('accountant_report', 'not app.client_limited(p_org)', 'org'),
      ('collection_board', 'not app.client_limited(p_org)', 'org'), ('collection_calendar', 'not app.client_limited(p_org)', 'org'),
      ('glosa_analytics', 'not app.client_limited(p_org)', 'org'), ('profitability', 'not app.client_limited(p_org)', 'org'),
      ('quarterly_report', 'not app.client_limited(p_org)', 'org'), ('quarterly_reports_list', 'not app.client_limited(p_org)', 'org'),
      ('client_health', 'not app.client_limited(p_org)', 'org'), ('client_account', 'not app.client_limited(p_org)', 'org'),
      ('client_account_detail', 'not app.client_limited(p_org)', 'org'), ('my_plan_usage', 'not app.client_limited(p_org)', 'org'),
      ('my_subscription', 'not app.client_limited(p_org)', 'org'), ('plan_history', 'not app.client_limited(p_org)', 'org'),
      ('sub_cancel_request', 'not app.client_limited(p_org)', 'org'), ('sub_cancel_undo', 'not app.client_limited(p_org)', 'org'),
      ('patient_payments_board', 'not app.client_limited(p_org)', 'org'), ('generate_balance_reminders', 'not app.client_limited(p_org)', 'org'),
      ('patient_notice_settings_save', 'not app.client_limited(p_org)', 'org'), ('patient_notice_settings_get', 'not app.client_limited(p_org)', 'org'),
      ('portal_requests_list', 'not app.client_limited(p_org)', 'org'), ('portal_enrich_messages', 'not app.client_limited(p_org)', 'org'),
      ('dossier_indicator', 'not app.client_limited(p_org)', 'org'), ('legal_audit_report', 'not app.client_limited(p_org)', 'org'),
      ('storage_usage_org', 'not app.client_limited(p_org)', 'org'), ('tariff_stale_claims', 'not app.client_limited(p_org)', 'org'),
      ('ledger_cleanup_preview', 'not app.client_limited(p_org)', 'org'), ('request_user', 'not app.client_limited(p_org)', 'org'),
      ('authorize_user_creation', 'not app.client_limited(p_org)', 'org'), ('client_referral_add', 'not app.client_limited(p_org)', 'org'),
      ('my_referrals', 'not app.client_limited(p_org)', 'org'), ('clinical_import', 'not app.client_limited(p_org)', 'org'),
      ('clinical_import_authors', 'not app.client_limited(p_org)', 'org'), ('clinical_set_mode', 'not app.client_limited(p_org)', 'org'),
      ('clinical_access_report', 'not app.client_limited(p_org)', 'org'), ('clinical_access_active', 'not app.client_limited(p_org)', 'org'),
      ('clinical_access_pending', 'not app.client_limited(p_org)', 'org'), ('archive_period', 'not app.client_limited(p_org)', 'org'),
      ('restore_period', 'not app.client_limited(p_org)', 'org'), ('client_document_portal_context', 'not app.client_limited(p_org)', 'org'),
      ('client_habilitation', 'not app.client_limited(p_org)', 'org'), ('ecf_client_status', 'not app.client_limited(p_org)', 'org'),
      ('tariffs_expiring', 'not app.client_limited(p_org)', 'org'), ('physician_reminders_v1', 'not app.client_limited(p_org)', 'org'),
      ('save_health_center', 'not app.client_limited(p_org)', 'org'), ('save_patient_global', 'not app.client_limited(p_org)', 'org'),
      ('attach_global_patient', 'not app.client_limited(p_org)', 'org'),
      -- un médico → el propio
      ('weekly_summary', 'app.client_provider_ok(p_provider)', 'prov'), ('set_followup_settings', 'app.client_provider_ok(p_provider)', 'prov'),
      ('set_patient_notice_settings', 'app.client_provider_ok(p_provider)', 'prov'), ('set_provider_centers', 'app.client_provider_ok(p_provider)', 'prov'),
      ('list_consult_assistants', 'app.client_provider_ok(p_provider)', 'prov'), ('set_consult_assistant_permissions', 'app.client_provider_ok(p_provider)', 'prov'),
      ('link_provider_user', 'app.client_provider_ok(p_provider)', 'prov'),
      ('tariff_gaps', 'app.client_provider_ok(p_provider) and (p_provider is not null or not app.client_limited(p_org))', 'prov'),
      ('sub_export_gate', 'app.client_provider_ok(p_provider) and (p_provider is not null or not app.client_limited(p_org))', 'prov'),
      ('golive_load', 'app.client_provider_ok(p_provider) and (p_provider is not null or not app.client_limited(p_org))', 'prov'),
      ('service_case_request', 'app.client_provider_ok(p_provider) and (p_provider is not null or not app.client_limited(p_org))', 'prov'),
      -- un registro puntual → su médico
      ('sofa_invoice_document', 'not exists (select 1 from public.sofa_invoices x where x.id = p_invoice and app.client_limited(x.organization_id))', 'org'),
      ('sub_invoice_detail', 'not exists (select 1 from public.sofa_invoices x where x.id = p_invoice and app.client_limited(x.organization_id))', 'org'),
      ('mark_message', 'not exists (select 1 from public.message_queue x where x.id = p_id and not (app.client_provider_ok(x.provider_id) and (x.provider_id is not null or not app.client_limited(x.organization_id))))', 'prov'),
      ('patient_payment_void', 'not exists (select 1 from public.patient_payments x where x.id = p_id and not (app.client_provider_ok(x.provider_id) and (x.provider_id is not null or not app.client_limited(x.organization_id))))', 'prov'),
      ('void_private_charge', 'not exists (select 1 from public.private_charges x where x.id = p_id and not app.client_provider_ok(x.provider_id))', 'prov'),
      ('hospital_log_add', 'not exists (select 1 from public.hospital_reports x where x.id = p_report and not app.client_provider_ok(x.provider_id))', 'prov'),
      ('hospital_log_list', 'not exists (select 1 from public.hospital_reports x where x.id = p_report and not app.client_provider_ok(x.provider_id))', 'prov'),
      ('hospital_report_submit', 'not exists (select 1 from public.hospital_reports x where x.id = p_report and not app.client_provider_ok(x.provider_id))', 'prov')
    ) as t(fn, cond, kind)
  loop
    for v_fn in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = r.fn loop
      d := pg_get_functiondef(v_fn::regprocedure);
      if position('clinica_propio' in d) > 0 then continue; end if;
      if position(E'\nbegin\n' in d) = 0 then raise exception 'No se encontró el inicio de %', v_fn; end if;
      d := overlay(d placing E'\nbegin\n  -- clinica_propio (256)\n  if not (' || r.cond || E') then\n    raise exception ''' ||
                   replace(case r.kind when 'org' then msg_org else msg_prov end, '''', '''''') || E''' using errcode = ''42501'';\n  end if;\n'
                   from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
      execute d;
    end loop;
  end loop;
end $$;

-- 3. sofa_debt_alert: el médico limitado no ve la deuda de la clínica con SOFA (devuelve vacío, no error:
--    la llama my_dashboard y no debe romper el inicio).
do $$ declare d text; begin
  d := pg_get_functiondef('public.sofa_debt_alert(uuid)'::regprocedure);
  if position('clinica_propio' in d) = 0 then
    d := overlay(d placing E'\nbegin\n  -- clinica_propio (256)\n  if app.client_limited(p_org) then return null; end if;\n'
                 from position(E'\nbegin\n' in d) for length(E'\nbegin\n'));
    execute d;
  end if;
end $$;

-- 4. fee_scheme (SQL): la rama «client» exige no ser médico limitado (devuelve vacío como para quien no tiene permiso)
do $$ declare d text; begin
  d := pg_get_functiondef('public.fee_scheme(uuid)'::regprocedure);
  if position('client_limited' in d) = 0 then
    d := replace(d, 'or app.can(p_org, array[''client'']) then', 'or (app.can(p_org, array[''client'']) and not app.client_limited(p_org)) then');
    if position('client_limited' in d) = 0 then raise exception 'No se pudo ajustar fee_scheme'; end if;
    execute d;
  end if;
end $$;

-- 5. my_dashboard: los KPI del médico se calculan solo con lo suyo
do $$ declare d text; begin
  d := pg_get_functiondef('public.my_dashboard()'::regprocedure);
  if position('clinica_propio' in d) = 0 then
    d := replace(d, 'into v_n, v_a from public.appointments a where a.organization_id = v_org;',
                    'into v_n, v_a from public.appointments a where a.organization_id = v_org and app.client_provider_ok(a.provider_id); -- clinica_propio (256)');
    d := replace(d, 'from public.service_lines l where l.organization_id = v_org and l.service_date >= v_m1;',
                    'from public.service_lines l where l.organization_id = v_org and l.service_date >= v_m1 and app.client_line_ok(l.id);');
    d := replace(d, 'from public.v_submission_balance b where b.organization_id = v_org and b.status in (''radicada'',''en_auditoria_ars'');',
                    'from public.v_submission_balance b where b.organization_id = v_org and b.status in (''radicada'',''en_auditoria_ars'') and app.client_provider_ok(b.provider_id);');
    if position('clinica_propio' in d) = 0 or position('client_line_ok(l.id)' in d) = 0 or position('client_provider_ok(b.provider_id)' in d) = 0 then
      raise exception 'No se pudo ajustar my_dashboard';
    end if;
    execute d;
  end if;
end $$;
