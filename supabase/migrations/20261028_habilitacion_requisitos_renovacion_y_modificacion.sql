-- 28/10/2026: requisitos reales de habilitación tomados de https://dhses.msp.gob.do/ (MSP/DHSES)
-- y confirmados por el usuario del sistema. Aplicado en producción (Supabase, proyecto
-- bpwjhgpzhzhiocoxrvzq) en varios pasos; registrado aquí para el historial.
--
-- Apertura (primera vez, DHSES-REQ-001): ya estaba cargada en el área
-- "0. Expediente DGHA (orden oficial)" desde antes — se verificó, coincide, no se tocó.
--
-- Renovación (DHSES-REQ-003): hasta hoy reusaba el checklist de apertura. Se agrega
-- applies_to_kind a habilitation_requirements (todas las filas existentes conservan los 3
-- tipos de trámite por defecto) y se cargan sus 13 requisitos propios, solo para 'renovacion'.
--
-- Modificación: tiene 6 motivos distintos con listas y tarifas diferentes (ampliación de
-- servicios, cambio de nivel, cambio de nombre, cambio de propietario, cambio de director
-- médico, cambio de razón social). Se agrega case_subkind a habilitation_cases y
-- applies_to_subkind a habilitation_requirements para representarlo, con sus 20 requisitos.
--
-- create_habilitation_case() ahora arma el checklist según tipo de establecimiento + tipo de
-- trámite + (si es modificación) motivo — antes solo miraba el tipo de establecimiento.

alter table public.habilitation_requirements
  add column if not exists applies_to_kind text[] not null default array['apertura','renovacion','actualizacion'];
alter table public.habilitation_cases add column if not exists case_subkind text;
alter table public.habilitation_requirements add column if not exists applies_to_subkind text[];

-- 13 requisitos de Renovación (DHSES-REQ-003 V16 05-10-2022)
insert into public.habilitation_requirements
  (code, area, requirement, evidence_hint, applies_to, applies_to_kind, is_critical, sort_order, is_active, confirmed_with_mispas, source, source_version)
values
  ('HAB-REN-01', 'Renovación · Documentos generales', 'Duplicado de los planos arquitectónicos aprobados por el Ministerio de Salud', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 1, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-02', 'Renovación · Documentos generales', 'Certificación de No Objeción a la construcción de un establecimiento de salud', 'Copia',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 2, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-03', 'Renovación · Documentos generales', 'Certificado de Registro Nacional de Contribuyente (RNC) actualizado del establecimiento', 'Copia',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 3, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-04', 'Renovación · Documentos generales', 'Certificado de Registro de Nombre Comercial (ONAPI) actualizado', 'Copia. El titular del ONAPI debe coincidir con el RNC o figurar en el Registro Mercantil',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 4, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-05', 'Renovación · Documentos generales', 'Certificado de Registro Mercantil actualizado', 'Copia',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 5, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-06', 'Renovación · Documentos generales', 'Reporte de Equipos Médicos del establecimiento actualizado', 'Según modelo DHSES-RE-005 (descargable en dhses.msp.gob.do)',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 6, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-07', 'Renovación · Documentos generales', 'Documentos del personal de salud (RR.HH.) actualizados', 'Por cada profesional, en el orden del Reporte de RR.HH.: cédula, título de grado (No. de registro y folio legibles), exequátur, título de especialidad si aplica, certificación del colegio correspondiente o carta de colegiatura activa (Médicos, Odontólogos, Psicólogos, Bioanalistas). Títulos emitidos por hospitales desde 2004 no son válidos: debe ser el de la universidad. Títulos del extranjero desde 2004 deben estar legalizados e incluir certificación del MESCYT',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 7, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-08', 'Renovación · Documentos generales', 'Reporte de Recursos Humanos de Salud y Administrativos actualizado', 'Según modelo DHSES-RE-004. Debe cubrir los servicios que ofrece el establecimiento: un servicio especializado sin su especialista queda sin cobertura en la Cartera de Servicios aprobada',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 8, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-09', 'Renovación · Documentos generales', 'Formulario de datos del establecimiento, director médico y propietario', 'Según modelo; lo completan exclusivamente el propietario y el director médico',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 9, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-10', 'Renovación · Documentos generales', 'Original de la última licencia vencida o Certificación de Estatus emitida por la Dirección', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 10, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-11', 'Renovación · Documentos generales', 'Carta de solicitud según el tipo de renovación', 'Según modelo',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 11, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-12', 'Renovación · Documentos generales', 'Constancia de Recepción de Solicitud y Constancia de Pago', 'Emitidas por la Ventanilla Única de Servicios del MSP',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 12, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022'),
  ('HAB-REN-13', 'Renovación · Documentos generales', 'Cartera de listado de servicios ofertados', 'En papel timbrado, fechado, sellado y firmado por el propietario/presidente o director técnico/médico, con nombre del establecimiento, ubicación, teléfono y correo electrónico',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['renovacion'], true, 13, true, true, 'MSP-DHSES', 'DHSES-REQ-003 V16 05-10-2022');

-- 20 requisitos de Modificación, por motivo (tarifas de referencia, no automatizadas:
-- ampliación RD$6,741.17 · cambio de nivel RD$10,000.00 · cambio de nombre/propietario/
-- director/razón social RD$6,741.17)
insert into public.habilitation_requirements
  (code, area, requirement, evidence_hint, applies_to, applies_to_kind, applies_to_subkind, is_critical, sort_order, is_active, confirmed_with_mispas, source, source_version)
values
  ('HAB-MOD-01', 'Modificación · Documentos según motivo', 'Constancia de Recepción de Solicitud y Constancia de Pago', 'Ventanilla Única de Servicios del MSP. El monto depende del motivo de la modificación',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario','cambio_director'], true, 1, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-02', 'Modificación · Documentos según motivo', 'Original de la última licencia vencida o Certificación de Estatus', 'Emitida por la Dirección de Habilitación',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario','cambio_director'], true, 2, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-03', 'Modificación · Documentos según motivo', 'Carta de solicitud según el tipo de modificación', 'Dirigida al Director(a) de Habilitación de Servicios y Establecimientos de Salud, según modelo',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario','cambio_director'], true, 3, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-04', 'Modificación · Documentos según motivo', 'Formulario de datos generales del establecimiento, director médico y propietario', 'Lo completan exclusivamente el propietario y el director médico',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario','cambio_director','cambio_razon_social'], true, 4, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-05', 'Modificación · Documentos según motivo', 'Listado de servicios ofertados', 'En papel timbrado, fechado, sellado y firmado por el propietario/presidente o director técnico/médico, con nombre del establecimiento, ubicación, teléfono y correo electrónico',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel','cambio_nombre','cambio_propietario'], true, 5, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-06', 'Modificación · Documentos según motivo', 'Certificación vigente de la Comisión Nacional de Energía y copia de la Resolución', 'Solo si la ampliación incluye estudios diagnósticos (Rayos X, Radioterapia, Tomografía, etc.)',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel'], false, 6, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-07', 'Modificación · Documentos según motivo', 'Reporte de Equipos Médicos (tipo, marca, serie y ubicación)', 'Impreso y en CD, en Excel, según el modelo DHSES-RE-005',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel'], true, 7, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-08', 'Modificación · Documentos según motivo', 'Documentos del personal de salud (RR.HH.)', 'En el orden del Reporte de RR.HH.: cédula, título de grado (No. de registro y folio legibles), exequátur, título de especialidad si aplica, certificación del colegio de Odontólogos o carta de colegiatura activa (Médicos, Psicólogos, Bioanalistas)',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel'], true, 8, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-09', 'Modificación · Documentos según motivo', 'Reporte de Recursos Humanos de Salud y Administrativos', 'Impreso y en CD, según el modelo DHSES-RE-004; debe responder al listado de servicios que ofrece el centro',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel'], true, 9, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-10', 'Modificación · Documentos según motivo', 'Planos y Certificación de No Objeción a la construcción', 'Solo si hubo transformaciones en la planta física (instalaciones sanitarias, ruta de evacuación, sistema contra incendios/extintores, ruta de desechos hospitalarios si tiene servicios quirúrgicos); con nombre, firma y No. CODIA del arquitecto actuante',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['ampliacion_servicios','cambio_nivel'], false, 10, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-11', 'Modificación · Documentos según motivo', 'Copia del nuevo Certificado de Registro de Nombre Comercial (ONAPI)', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_nombre','cambio_propietario'], true, 11, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-12', 'Modificación · Documentos según motivo', 'Copia del Certificado de Registro Nacional de Contribuyente (RNC) del establecimiento', 'Debe coincidir el nombre con el certificado de ONAPI',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_nombre','cambio_propietario'], true, 12, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-13', 'Modificación · Documentos según motivo', 'Documentación legal de venta y compra del establecimiento', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_propietario'], true, 13, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-14', 'Modificación · Documentos según motivo', 'Documentos del nuevo Director Médico', 'Copia de cédula, título de grado, exequátur, título de especialidad (si aplica), certificación del colegio de Odontólogos o trámite, y carta de colegiatura activa (Médicos, Psicólogos, Bioanalistas según aplique)',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_director'], true, 14, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-15', 'Modificación · Documentos según motivo', 'Recibo de pago de la tasa de tramitación', 'Cheque certificado a nombre del Ministerio de Salud Pública, emitido por la Ventanilla Única',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], true, 15, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-16', 'Modificación · Documentos según motivo', 'Certificación vigente del RNC emitida por la DGII', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], true, 16, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-17', 'Modificación · Documentos según motivo', 'Copia del Registro Mercantil', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], true, 17, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-18', 'Modificación · Documentos según motivo', 'Copia del Registro de ONAPI actualizado', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], true, 18, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-19', 'Modificación · Documentos según motivo', 'Copia de la Licencia de Habilitación vigente', null,
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], true, 19, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación'),
  ('HAB-MOD-20', 'Modificación · Documentos según motivo', 'Dossier completo en original (Licencia, listado de RR.HH., cartera de servicios y resolución)', 'Solo si el centro ya tiene licencia emitida por esta Dirección',
    array['Centro diagnóstico','Centro médico','Clínica','Consultorio','Laboratorio','Otro'], array['actualizacion'], array['cambio_razon_social'], false, 20, true, true, 'MSP-DHSES', 'Servicios: Modificación de Habilitación');

-- renombrar/retirar la firma vieja de 8 argumentos (CREATE OR REPLACE con un parámetro nuevo
-- crea un segundo overload en vez de reemplazar el original — mismo patrón ya visto antes
-- en la sesión con otras funciones)
alter function public.create_habilitation_case(text, text, uuid, uuid, text, numeric, date, text) rename to create_habilitation_case_deprecated_8arg;
revoke all on function public.create_habilitation_case_deprecated_8arg(text, text, uuid, uuid, text, numeric, date, text) from public, anon, authenticated;

create or replace function public.create_habilitation_case(p_name text, p_type text, p_org uuid DEFAULT NULL::uuid, p_lead uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'apertura'::text, p_fee numeric DEFAULT 0, p_target date DEFAULT NULL::date, p_notes text DEFAULT NULL::text, p_subkind text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_op uuid; v_id uuid := gen_random_uuid(); v_kind text := coalesce(p_kind, 'apertura');
begin
  select id into v_op from app.my_operator_ids() as t(id) limit 1;
  if v_op is null then raise exception 'Solo el personal de SOFA abre casos de habilitación' using errcode = '42501'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 then raise exception 'Indique el nombre del establecimiento' using errcode = '22023'; end if;
  if v_kind = 'actualizacion' and nullif(trim(coalesce(p_subkind, '')), '') is null then
    raise exception 'Indique el motivo de la modificación' using errcode = '22023';
  end if;
  insert into public.habilitation_cases (id, operator_id, organization_id, lead_id, establishment_name, establishment_type, case_kind, case_subkind, fee_amount, target_date, notes)
  values (v_id, v_op, p_org, p_lead, trim(p_name), p_type, v_kind, nullif(trim(coalesce(p_subkind, '')), ''), coalesce(p_fee, 0), p_target, nullif(trim(coalesce(p_notes, '')), ''));
  insert into public.habilitation_items (case_id, area, requirement_id, requirement, is_critical, sort_order, status)
  select v_id, r.area, r.id, r.requirement, r.is_critical, r.sort_order, 'pendiente'
    from public.habilitation_requirements r
   where r.is_active and p_type = any (r.applies_to) and v_kind = any (r.applies_to_kind)
     and (r.applies_to_subkind is null or p_subkind = any (r.applies_to_subkind));
  insert into public.activities (operator_id, organization_id, entity_type, entity_id, activity_type, body)
  values (v_op, p_org, 'habilitation', v_id, 'sistema', format('Caso de habilitación abierto: %s (%s, %s)', trim(p_name), p_type, v_kind));
  return v_id;
end $function$;

revoke all on function public.create_habilitation_case(text, text, uuid, uuid, text, numeric, date, text, text) from public, anon;
grant execute on function public.create_habilitation_case(text, text, uuid, uuid, text, numeric, date, text, text) to authenticated;
