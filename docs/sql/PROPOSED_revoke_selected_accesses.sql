-- CANDIDATO QA: validar constraints, triggers y RLS reales antes de instalar.
-- Revoca solo asociaciones seleccionadas. No borra identidades ni cambia roles.
BEGIN;
CREATE TABLE IF NOT EXISTS public.user_access_revocation_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid NOT NULL,
 user_id uuid NOT NULL, organization_ids uuid[] NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 1000),
 before_access jsonb NOT NULL, after_access jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_access_revocation_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_access_revocation_audit FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION app.access_revoke_context(p_user uuid,p_orgs uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); selected uuid[]; entries jsonb; all_entries jsonb;
 blockers jsonb:='[]'::jsonb; profile_state jsonb;
BEGIN
 IF actor IS NULL OR coalesce(auth.jwt()->>'aal','aal1')<>'aal2' THEN
  RAISE EXCEPTION 'Se requiere sesión con verificación en dos pasos' USING ERRCODE='42501';
 END IF;
 IF p_user IS NULL OR actor=p_user THEN
  RAISE EXCEPTION 'No puede cambiar sus propios accesos' USING ERRCODE='42501';
 END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO selected FROM unnest(p_orgs) x WHERE x IS NOT NULL;
 IF coalesce(cardinality(selected),0)=0 OR cardinality(selected)>100 OR
    cardinality(selected)<>cardinality(p_orgs) THEN
  RAISE EXCEPTION 'Seleccione entre 1 y 100 organizaciones distintas' USING ERRCODE='22023';
 END IF;
 -- Comprobar autorización para todas las organizaciones antes de leer al objetivo.
 IF EXISTS (
  SELECT 1 FROM unnest(selected) x
  LEFT JOIN public.organizations o ON o.id=x
  WHERE o.id IS NULL OR o.kind NOT IN ('client','operator') OR NOT EXISTS (
   SELECT 1 FROM public.organization_users a
   JOIN public.profiles p ON p.id=a.user_id
   JOIN public.organizations op ON op.id=a.organization_id AND op.kind='operator'
   WHERE a.user_id=actor AND a.role_code='super_admin' AND a.is_active
    AND p.is_active AND NOT p.must_change_password
    AND a.organization_id=CASE WHEN o.kind='operator' THEN o.id ELSE o.operator_id END
  )
 ) THEN RAISE EXCEPTION 'No tiene autorización para todos los accesos seleccionados' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('active',p.is_active,'must_change_password',p.must_change_password)
  INTO profile_state FROM public.profiles p WHERE p.id=p_user;
 IF profile_state IS NULL OR (SELECT count(*) FROM public.organization_users m
  WHERE m.user_id=p_user AND m.organization_id=ANY(selected))<>cardinality(selected) THEN
  RAISE EXCEPTION 'Cuenta o acceso no disponible' USING ERRCODE='P0002';
 END IF;
 IF EXISTS(SELECT 1 FROM public.organization_users m WHERE m.user_id=p_user AND m.role_code='super_admin') THEN
  blockers:=blockers||jsonb_build_array('Cuenta protegida: tiene o tuvo acceso Super Admin.');
 END IF;
 IF EXISTS(SELECT 1 FROM public.providers p WHERE p.user_id=p_user) THEN
  blockers:=blockers||jsonb_build_array('Cuenta vinculada a un médico: requiere revisión de dependencias clínicas.');
 END IF;
 SELECT jsonb_agg(jsonb_build_object('organization_id',m.organization_id,'role_code',m.role_code,'is_active',m.is_active) ORDER BY m.organization_id)
 INTO entries FROM public.organization_users m WHERE m.user_id=p_user AND m.organization_id=ANY(selected);
 SELECT jsonb_agg(to_jsonb(m) ORDER BY m.organization_id) INTO all_entries
 FROM public.organization_users m WHERE m.user_id=p_user;
 RETURN jsonb_build_object('user_id',p_user,'accesses',entries,'can_revoke',jsonb_array_length(blockers)=0,
  'blockers',blockers,'expected',md5(jsonb_build_object('user',p_user,'selection',selected,'all_accesses',all_entries,'profile',profile_state)::text));
END $$;
REVOKE ALL ON FUNCTION app.access_revoke_context(uuid,uuid[]) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_access_revoke_preview(p_user uuid,p_orgs uuid[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT app.access_revoke_context(p_user,p_orgs)
$$;
REVOKE ALL ON FUNCTION public.admin_access_revoke_preview(uuid,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_access_revoke_preview(uuid,uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_access_revoke_apply(p_user uuid,p_orgs uuid[],p_reason text,p_expected text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ctx jsonb; actor uuid:=auth.uid(); audit_id uuid; after_entries jsonb;
BEGIN
 ctx:=app.access_revoke_context(p_user,p_orgs);
 -- Locks ordenados: incluyen actor, objetivo, organizaciones y membresías existentes.
 PERFORM p.id FROM public.profiles p WHERE p.id IN(actor,p_user) ORDER BY p.id FOR UPDATE;
 PERFORM o.id FROM public.organizations o WHERE o.id=ANY(p_orgs) OR o.id IN (
  SELECT x.operator_id FROM public.organizations x WHERE x.id=ANY(p_orgs)
 ) ORDER BY o.id FOR UPDATE;
 PERFORM m.user_id FROM public.organization_users m WHERE m.user_id IN(actor,p_user)
 ORDER BY m.user_id,m.organization_id FOR UPDATE;
 ctx:=app.access_revoke_context(p_user,p_orgs);
 IF NOT (ctx->>'can_revoke')::boolean THEN
  RAISE EXCEPTION 'No se puede revocar automáticamente: %',ctx->'blockers' USING ERRCODE='23514';
 END IF;
 IF p_expected IS NULL OR p_expected IS DISTINCT FROM ctx->>'expected' THEN
  RAISE EXCEPTION 'Los accesos cambiaron. Revise una nueva vista previa.' USING ERRCODE='40001';
 END IF;
 IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1000 THEN
  RAISE EXCEPTION 'Indique un motivo entre 12 y 1000 caracteres' USING ERRCODE='22023';
 END IF;
 UPDATE public.organization_users SET is_active=false WHERE user_id=p_user AND organization_id=ANY(p_orgs);
 SELECT jsonb_agg(jsonb_build_object('organization_id',m.organization_id,'role_code',m.role_code,'is_active',m.is_active) ORDER BY m.organization_id)
 INTO after_entries FROM public.organization_users m WHERE m.user_id=p_user AND m.organization_id=ANY(p_orgs);
 INSERT INTO public.user_access_revocation_audit(actor_id,user_id,organization_ids,reason,before_access,after_access)
 VALUES(actor,p_user,p_orgs,btrim(p_reason),ctx->'accesses',after_entries) RETURNING id INTO audit_id;
 RETURN jsonb_build_object('ok',true,'audit_id',audit_id,'user_id',p_user,'accesses',after_entries);
END $$;
REVOKE ALL ON FUNCTION public.admin_access_revoke_apply(uuid,uuid[],text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_access_revoke_apply(uuid,uuid[],text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
