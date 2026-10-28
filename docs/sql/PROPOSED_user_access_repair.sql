-- CANDIDATO PARA QA. No ejecutar en producción sin validar esquema y triggers reales.
-- Corrige una asociación errónea; NO borra cuentas ni historial.
BEGIN;
CREATE TABLE IF NOT EXISTS public.user_access_repair_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL,
  user_id uuid NOT NULL,
  client_org_id uuid NOT NULL,
  operator_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) >= 12),
  before_access jsonb NOT NULL,
  before_staff jsonb,
  after_access jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_access_repair_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_access_repair_audit FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app.user_access_repair_context(p_user uuid, p_org uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  actor uuid := auth.uid(); op uuid; target_email text; target_active boolean;
  membership public.organization_users; old_staff jsonb;
  blockers jsonb := '[]'::jsonb; fingerprint text;
BEGIN
  IF actor IS NULL OR coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' THEN
    RAISE EXCEPTION 'Se requiere sesión con verificación en dos pasos' USING ERRCODE='42501';
  END IF;
  SELECT o.operator_id INTO op FROM public.organizations o
   WHERE o.id=p_org AND o.kind='client';
  IF op IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_users m JOIN public.profiles p ON p.id=m.user_id
      JOIN public.organizations o ON o.id=m.organization_id AND o.kind='operator'
    WHERE m.user_id=actor AND m.organization_id=op AND m.role_code='super_admin'
      AND m.is_active AND p.is_active AND NOT p.must_change_password
  ) THEN RAISE EXCEPTION 'Solo el Super Admin del operador puede corregir esta asociación' USING ERRCODE='42501'; END IF;
  IF p_user=actor THEN RAISE EXCEPTION 'No puede corregir su propia cuenta' USING ERRCODE='42501'; END IF;
  SELECT * INTO membership FROM public.organization_users m
    WHERE m.user_id=p_user AND m.organization_id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cuenta o asociación no disponible' USING ERRCODE='P0002'; END IF;
  SELECT u.email,p.is_active INTO target_email,target_active
    FROM auth.users u JOIN public.profiles p ON p.id=u.id WHERE u.id=p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cuenta o asociación no disponible' USING ERRCODE='P0002'; END IF;
  SELECT to_jsonb(m) INTO old_staff FROM public.organization_users m WHERE m.user_id=p_user AND m.organization_id=op;
  IF p_user=actor THEN blockers:=blockers||jsonb_build_array('No puede corregir su propia cuenta.'); END IF;
  IF membership.role_code NOT IN ('client','capturer') OR membership.is_active IS DISTINCT FROM true THEN
    blockers:=blockers||jsonb_build_array('Debe seleccionar una asociación activa de Médico o Secretaria.');
  END IF;
  IF EXISTS(SELECT 1 FROM public.organization_users m WHERE m.user_id=p_user AND m.role_code='super_admin') THEN
    blockers:=blockers||jsonb_build_array('No se reclasifica una cuenta que tiene o tuvo rol Super Admin.');
  END IF;
  IF EXISTS(SELECT 1 FROM public.organization_users m WHERE m.user_id=p_user AND m.is_active AND m.organization_id<>p_org) THEN
    blockers:=blockers||jsonb_build_array('Hay otros accesos activos: se requiere revisión individual.');
  END IF;
  IF EXISTS(SELECT 1 FROM public.organization_users m JOIN public.organizations o ON o.id=m.organization_id
    WHERE m.user_id=p_user AND o.id<>op AND o.operator_id IS DISTINCT FROM op) THEN
    blockers:=blockers||jsonb_build_array('La cuenta tiene asociaciones con otro operador.');
  END IF;
  IF EXISTS(SELECT 1 FROM public.providers p WHERE p.user_id=p_user) THEN
    blockers:=blockers||jsonb_build_array('La cuenta está enlazada a un médico. No se modifica automáticamente.');
  END IF;
  IF app.clinical_mode(p_org) IS DISTINCT FROM 'desactivada' THEN
    blockers:=blockers||jsonb_build_array('El consultorio tiene historia clínica habilitada o sin estado verificable. Requiere revisión clínica.');
  END IF;
  fingerprint:=md5(jsonb_build_object('membership',to_jsonb(membership),'staff',old_staff,'active',target_active,'email',target_email)::text);
  RETURN jsonb_build_object('user_id',p_user,'email',target_email,'client_org_id',p_org,'operator_id',op,
    'current_role',membership.role_code,'target_role','admin','profile_active',target_active,
    'blockers',blockers,'can_repair',jsonb_array_length(blockers)=0,'expected',fingerprint,
    'before_access',to_jsonb(membership),'before_staff',old_staff);
END $$;
REVOKE ALL ON FUNCTION app.user_access_repair_context(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_user_repair_preview(p_user uuid,p_org uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=''
AS $$ SELECT app.user_access_repair_context(p_user,p_org) - 'before_access' - 'before_staff' $$;
REVOKE ALL ON FUNCTION public.admin_user_repair_preview(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_user_repair_preview(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_repair_user_access(
  p_user uuid,p_org uuid,p_reason text,p_confirm_email text,p_expected text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE context jsonb; actor uuid:=auth.uid(); audit_id uuid; old_member jsonb; new_member jsonb;
BEGIN
  -- Autorizar antes de tomar bloqueos o examinar la cuenta objetivo.
  context:=app.user_access_repair_context(p_user,p_org);
  PERFORM p.id FROM public.profiles p WHERE p.id IN(actor,p_user) ORDER BY p.id FOR UPDATE;
  PERFORM u.id FROM auth.users u WHERE u.id=p_user FOR UPDATE;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_org FOR UPDATE;
  PERFORM m.user_id FROM public.organization_users m
    WHERE m.user_id IN(actor,p_user) ORDER BY m.user_id,m.organization_id FOR UPDATE;
  -- Revalidar con los bloqueos adquiridos; no aceptar una vista previa obsoleta.
  context:=app.user_access_repair_context(p_user,p_org);
  IF NOT (context->>'can_repair')::boolean THEN
    RAISE EXCEPTION 'No se puede corregir automáticamente: %',context->'blockers' USING ERRCODE='23514';
  END IF;
  IF p_expected IS NULL OR p_expected IS DISTINCT FROM context->>'expected' THEN
    RAISE EXCEPTION 'Los accesos cambiaron. Revise una nueva vista previa.' USING ERRCODE='40001';
  END IF;
  IF length(btrim(coalesce(p_reason,'')))<12 THEN RAISE EXCEPTION 'Indique un motivo de al menos 12 caracteres' USING ERRCODE='22023'; END IF;
  IF p_confirm_email IS NULL OR lower(btrim(p_confirm_email)) IS DISTINCT FROM lower(context->>'email') THEN
    RAISE EXCEPTION 'El correo de confirmación no coincide' USING ERRCODE='22023';
  END IF;
  old_member:=context->'before_access';
  UPDATE public.organization_users SET is_active=false WHERE user_id=p_user AND organization_id=p_org;
  INSERT INTO public.organization_users(organization_id,user_id,role_code,is_active)
    VALUES((context->>'operator_id')::uuid,p_user,'admin',(context->>'profile_active')::boolean)
    ON CONFLICT(organization_id,user_id) DO UPDATE SET role_code='admin',is_active=excluded.is_active;
  SELECT to_jsonb(m) INTO new_member FROM public.organization_users m
    WHERE m.user_id=p_user AND m.organization_id=(context->>'operator_id')::uuid;
  INSERT INTO public.user_access_repair_audit(actor_id,user_id,client_org_id,operator_id,reason,before_access,before_staff,after_access)
    VALUES(actor,p_user,p_org,(context->>'operator_id')::uuid,btrim(p_reason),old_member,context->'before_staff',new_member)
    RETURNING id INTO audit_id;
  RETURN jsonb_build_object('ok',true,'audit_id',audit_id,'user_id',p_user,'profile_active',(context->>'profile_active')::boolean,
    'message','Asociación corregida. Se conservan la cuenta, el correo y el historial.');
END $$;
REVOKE ALL ON FUNCTION public.admin_repair_user_access(uuid,uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_repair_user_access(uuid,uuid,text,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
