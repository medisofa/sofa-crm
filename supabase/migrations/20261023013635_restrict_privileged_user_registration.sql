-- SOFA: restricción de RPC administrativas
-- Aplicar solo tras validar los consumidores del backend.
-- No afecta confirm_password_changed().

REVOKE EXECUTE ON FUNCTION
  public.register_new_user(
    uuid, uuid, text, uuid[], boolean, boolean, uuid
  )
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.register_prospect_user(uuid, uuid, uuid)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.register_new_user(
    uuid, uuid, text, uuid[], boolean, boolean, uuid
  )
TO service_role;

GRANT EXECUTE ON FUNCTION
  public.register_prospect_user(uuid, uuid, uuid)
TO service_role;

-- Proteger la asignación administrativa de roles.
-- Solo invocable por el backend privilegiado.
REVOKE EXECUTE ON FUNCTION public.admin_assign_role(
  uuid, uuid, text, uuid, boolean
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.admin_assign_role(
  uuid, uuid, text, uuid, boolean
) TO service_role;
