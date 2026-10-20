-- SOFA role responsibility alignment.
-- Tested in production inside BEGIN/ROLLBACK before application.

update public.roles set
  name = case code
    when 'super_admin' then 'Super Admin SOFA'
    when 'admin' then 'Administrador SOFA'
    when 'operations' then 'Operaciones SOFA'
    when 'billing' then 'Facturación y Radicación'
    when 'glosas' then 'Cobros, Conciliación y Glosas'
    when 'assistant' then 'Comercial / Onboarding'
    when 'auditor' then 'Auditor de Expedientes'
    when 'client' then 'Médico / Cliente'
    when 'capturer' then 'Secretaria / Capturista'
    when 'prospect' then 'Prospecto'
    else name end,
  description = case code
    when 'super_admin' then 'Gobierno completo del sistema, seguridad, usuarios, parámetros y datos críticos.'
    when 'admin' then 'Administración general de SOFA y supervisión operativa; sin sustituir controles exclusivos del Super Admin.'
    when 'operations' then 'Recepción, retiro físico, validación, pre-radicación, calidad y puesta en marcha.'
    when 'billing' then 'Facturación y radicación de reclamaciones validadas; no registra pagos ARS ni administra glosas.'
    when 'glosas' then 'Pagos ARS, conciliación, distribución, glosas, reconsideraciones y recuperación.'
    when 'assistant' then 'CRM, propuestas, onboarding y seguimiento comercial; sin operación financiera ARS.'
    when 'auditor' then 'Auditoría de expedientes, evidencia, trazabilidad y controles; preferentemente solo lectura.'
    when 'client' then 'Médico o dueño de la práctica: consulta y gestiona su operación dentro del alcance contratado.'
    when 'capturer' then 'Secretaria o capturista: agenda, pacientes y captura de reclamaciones de médicos asignados.'
    when 'prospect' then 'Futuro cliente: incorporación comercial; no es miembro operativo de una organización cliente.'
    else description end;

drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments
for insert to authenticated
with check(app.can(organization_id,array['super_admin','admin','glosas']));

drop policy if exists payment_allocations_insert on public.payment_allocations;
create policy payment_allocations_insert on public.payment_allocations
for insert to authenticated
with check(app.can(organization_id,array['super_admin','admin','glosas']));
