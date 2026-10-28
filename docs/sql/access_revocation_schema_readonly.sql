-- Solo estructura de seguridad: no consulta pacientes ni usuarios.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout='20s';
SELECT current_setting('transaction_read_only') AS read_only;
SELECT table_schema,table_name,column_name,data_type,is_nullable
FROM information_schema.columns
WHERE table_schema='public' AND table_name IN
 ('organization_users','profiles','organizations','providers','staff_client_access','capturer_provider_access')
ORDER BY table_name,ordinal_position;
SELECT conrelid::regclass AS relation,conname,pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid IN
 (to_regclass('public.organization_users'),to_regclass('public.providers'))
 OR confrelid=to_regclass('public.organization_users');
SELECT tgrelid::regclass AS relation,tgname,pg_get_triggerdef(oid) AS definition,
 pg_get_functiondef(tgfoid) AS trigger_function
FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN
 (to_regclass('public.organization_users'),to_regclass('public.profiles'));
SELECT n.nspname,p.proname,pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='app' AND p.proname IN
 ('role_for_org','visible_org_ids','can_operator','can','can_orgs','capturer_providers','capturer_can','is_active_user'))
 OR (n.nspname='public' AND p.proname IN ('admin_assign_role','my_context','my_security_state','users_overview'));
SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check
FROM pg_policies WHERE (schemaname='public' AND tablename IN
 ('organization_users','providers','staff_client_access','capturer_provider_access'))
 OR (schemaname='storage' AND tablename='objects');
ROLLBACK;
