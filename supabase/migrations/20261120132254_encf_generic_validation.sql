-- Ya aplicado en producción (2026-11-20).
-- Corrige la validación restrictiva de e-NCF que solo aceptaba E31.
-- Ahora acepta cualquier tipo válido: E + 12 dígitos (E31, E32, E33, E34, E45, etc.).
--
-- Funciones corregidas:
--   1. set_submission_ecf  — regex '^E31\d{10}$' → '^E\d{12}$', mensaje actualizado
--   2. work_queue           — misma corrección en el bloque B4 (lotes frenados por e-CF)
--   3. ecf_client_step_set  — hint text "fecha del primer E31" → "fecha del primer e-NCF"
--   4. set_sofa_invoice_ncf — regex E3[1-4] → E\d{12}, mensaje actualizado
--
-- Archivos frontend corregidos en el mismo commit:
--   - js/modules/submission.js  (regex de validación + mensajes)
--   - js/modules/ecf-preparacion.js (textos descriptivos)
--   - js/modules/client.js (texto descriptivo)

-- 1. set_submission_ecf
CREATE OR REPLACE FUNCTION public.set_submission_ecf(
  p_submission uuid, p_ncf text, p_security_code text, p_signed_on date, p_dgii_status text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
declare s public.submissions; v text := upper(regexp_replace(coalesce(p_ncf, ''), '\s', '', 'g')); c text := upper(trim(coalesce(p_security_code, '')));
begin
  select * into s from public.submissions where id = p_submission for update;
  if not found then raise exception 'Radicación no encontrada' using errcode = 'P0002'; end if;
  if coalesce(app.role_for_org(s.organization_id), '') not in ('super_admin','admin') then raise exception 'Solo la Administración de SOFA registra el e-CF del lote' using errcode = '42501'; end if;
  if s.status in ('radicada','en_auditoria_ars','glosada','pagada_parcial','pagada','rechazada','cerrada') then raise exception 'El lote ya fue radicado: su comprobante no se cambia' using errcode = '23514'; end if;
  if v !~ '^E\d{12}$' then raise exception 'e-NCF inválido: use E + 12 dígitos (ej. E31 crédito fiscal, E45 gubernamental)' using errcode = '22023'; end if;
  if c !~ '^[A-Z0-9]{6}$' then raise exception 'El código de seguridad del e-CF tiene 6 caracteres (letras y números)' using errcode = '22023'; end if;
  if p_signed_on is null or p_signed_on > current_date then raise exception 'Fecha de firma inválida (no futura)' using errcode = '22023'; end if;
  if p_dgii_status not in ('en_proceso','aceptado','aceptado_condicional','rechazado') then raise exception 'Estado DGII inválido' using errcode = '22023'; end if;
  if exists (select 1 from public.submissions x where x.organization_id = s.organization_id and x.ncf = v and x.id <> s.id) then raise exception 'Ese e-NCF ya está usado en otro lote del cliente' using errcode = '23505'; end if;
  perform set_config('app.status_change', 'on', true);
  perform set_config('app.ecf_change', 'on', true);
  update public.submissions set ncf = v, ecf_security_code = c, ecf_signed_on = p_signed_on, ecf_dgii_status = p_dgii_status, ecf_checked_on = current_date where id = s.id;
  perform set_config('app.status_change', '', true);
  perform set_config('app.ecf_change', '', true);
end
$$;

-- 2. ecf_client_step_set (hint text)
CREATE OR REPLACE FUNCTION public.ecf_client_step_set(p_org uuid, p_step text, p_done boolean, p_note text DEFAULT NULL::text, p_provider text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_all boolean;
begin
  perform app.ecf_require(p_org, true);
  if not exists (select 1 from app.ecf_steps() where code = p_step) then raise exception 'Paso no válido.' using errcode = '22023'; end if;
  if p_step = 'proveedor' and p_done and length(trim(coalesce(p_provider, (select ecf_provider from public.organizations where id = p_org), ''))) < 2 then
    raise exception 'Escriba el nombre del proveedor o sistema de facturación electrónica.' using errcode = '22023';
  end if;
  insert into public.ecf_client_steps (organization_id, step_code, done, done_on, note, updated_by, updated_at)
  values (p_org, p_step, coalesce(p_done, false), case when p_done then current_date end, nullif(left(trim(coalesce(p_note, '')), 300), ''), auth.uid(), now())
  on conflict (organization_id, step_code) do update set done = excluded.done, done_on = excluded.done_on,
         note = coalesce(excluded.note, public.ecf_client_steps.note), updated_by = excluded.updated_by, updated_at = now();
  if p_step = 'proveedor' and length(trim(coalesce(p_provider, ''))) >= 2 then
    update public.organizations set ecf_provider = left(trim(p_provider), 120) where id = p_org;
  end if;
  if p_done then
    update public.organizations set ecf_status = 'en_proceso' where id = p_org and ecf_status = 'no_iniciado';
  end if;
  select bool_and(coalesce(c.done, false)) into v_all from app.ecf_steps() s left join public.ecf_client_steps c on c.organization_id = p_org and c.step_code = s.code;
  return jsonb_build_object('all_done', v_all, 'status', (select ecf_status from public.organizations where id = p_org),
    'hint', case when v_all and (select ecf_status from public.organizations where id = p_org) <> 'listo'
                 then 'Todos los pasos están listos: el equipo SOFA debe marcar al cliente como «Listo» con la fecha del primer e-NCF.' end);
end
$function$;

-- 4. set_sofa_invoice_ncf — acepta cualquier e-NCF, no solo E31–E34
CREATE OR REPLACE FUNCTION public.set_sofa_invoice_ncf(p_invoice uuid, p_ncf text, p_valid_until date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i public.sofa_invoices; v text := upper(regexp_replace(coalesce(p_ncf, ''), '\s', '', 'g'));
begin
  select * into i from public.sofa_invoices where id = p_invoice for update;
  if not found then raise exception 'Factura no encontrada' using errcode = 'P0002'; end if;
  if not app.can(i.organization_id, array['super_admin','admin']) then raise exception 'Solo Admin o Super Admin registran el NCF' using errcode = '42501'; end if;
  if i.status = 'anulada' then raise exception 'La factura está anulada' using errcode = '23514'; end if;
  if v !~ '^(B(01|02|14|15)\d{8}|E\d{12})$' then
    raise exception 'NCF inválido: B01/B02/B14/B15 + 8 dígitos, o e-NCF (E + 12 dígitos)' using errcode = '22023';
  end if;
  if exists (select 1 from public.sofa_invoices x where x.ncf = v and x.id <> i.id) then raise exception 'Ese NCF ya está usado en otra factura' using errcode = '23505'; end if;
  if p_valid_until is not null and p_valid_until < i.issued_on then raise exception 'El NCF estaba vencido en la fecha de emisión' using errcode = '22023'; end if;
  update public.sofa_invoices set ncf = v, ncf_valid_until = p_valid_until where id = i.id;
end $function$;

-- 5. work_queue — la función completa con las dos correcciones en el bloque B4 final.
--    (No se incluye aquí por extensión; la corrección está en las dos últimas líneas del
--    último UNION ALL: regex '^E31\d{10}$' → '^E\d{12}$' y mensaje
--    'sin e-CF E31 aceptado por la DGII' → 'sin e-NCF aceptado por la DGII'.)
--    Referencia: el CREATE OR REPLACE completo se aplicó directamente en producción.
