\set ON_ERROR_STOP on
-- SOLO BASE DE PRUEBA VACÍA. Datos sintéticos, nunca usar en producción.
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE SCHEMA auth; CREATE SCHEMA app;
CREATE TABLE public.sofa_user_repair_fixture_marker(value text PRIMARY KEY);
INSERT INTO public.sofa_user_repair_fixture_marker VALUES('synthetic-user-repair-only');
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text NOT NULL);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id),is_active boolean NOT NULL DEFAULT true,must_change_password boolean NOT NULL DEFAULT false);
CREATE TABLE public.organizations(id uuid PRIMARY KEY,kind text,operator_id uuid,clinical_state text DEFAULT 'desactivada');
CREATE TABLE public.organization_users(organization_id uuid REFERENCES public.organizations(id),user_id uuid REFERENCES public.profiles(id),role_code text NOT NULL,is_active boolean NOT NULL DEFAULT true,PRIMARY KEY(organization_id,user_id));
CREATE TABLE public.providers(id uuid PRIMARY KEY,user_id uuid REFERENCES public.profiles(id));
CREATE FUNCTION app.clinical_mode(p_org uuid) RETURNS text LANGUAGE sql AS $$ SELECT clinical_state FROM public.organizations WHERE id=p_org $$;
CREATE FUNCTION app.qa_segregation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF new.is_active AND new.role_code='admin' AND EXISTS(SELECT 1 FROM public.organization_users WHERE user_id=new.user_id AND role_code IN('client','capturer') AND is_active) THEN
  RAISE EXCEPTION 'No se mezcla personal y cliente' USING ERRCODE='42501';
 END IF; RETURN new; END $$;
CREATE TRIGGER qa_segregation BEFORE INSERT OR UPDATE ON public.organization_users FOR EACH ROW EXECUTE FUNCTION app.qa_segregation();
INSERT INTO public.organizations(id,kind,operator_id) VALUES
 ('00000000-0000-4000-8000-000000000100','operator',null),
 ('00000000-0000-4000-8000-000000000101','client','00000000-0000-4000-8000-000000000100'),
 ('00000000-0000-4000-8000-000000000102','client','00000000-0000-4000-8000-000000000100'),
 ('00000000-0000-4000-8000-000000000200','operator',null),
 ('00000000-0000-4000-8000-000000000201','client','00000000-0000-4000-8000-000000000200');
INSERT INTO auth.users SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'qa-'||n||'@example.test' FROM generate_series(1,9)n;
INSERT INTO public.profiles(id) SELECT id FROM auth.users;
INSERT INTO public.organization_users VALUES
 ('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000001','super_admin',true),
 ('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000002','admin',true),
 ('00000000-0000-4000-8000-000000000200','00000000-0000-4000-8000-000000000009','super_admin',true);
INSERT INTO public.organization_users SELECT '00000000-0000-4000-8000-000000000101'::uuid,id,'client',true FROM auth.users WHERE id::text BETWEEN '00000000-0000-4000-8000-000000000003' AND '00000000-0000-4000-8000-000000000008';
GRANT USAGE ON SCHEMA public,auth TO authenticated,anon;
GRANT EXECUTE ON FUNCTION auth.uid(),auth.jwt() TO authenticated,anon;
