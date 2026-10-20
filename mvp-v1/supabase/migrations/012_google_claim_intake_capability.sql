-- SOFA · capacidad de carga externa Google Sheets / Google Form
insert into public.role_capabilities
(role_code,capability_code,can_view,can_create,can_edit,can_approve,requires_mfa,risk_level,training_required,training_version)
values
('super_admin','claims.google_import',true,true,true,true,true,'high',true,1),
('admin','claims.google_import',true,true,true,false,true,'high',true,1),
('operations','claims.google_import',true,true,true,false,true,'high',true,1),
('billing','claims.google_import',true,true,true,false,true,'high',true,1)
on conflict(role_code,capability_code) do update set
 can_view=excluded.can_view,can_create=excluded.can_create,can_edit=excluded.can_edit,
 can_approve=excluded.can_approve,requires_mfa=excluded.requires_mfa,risk_level=excluded.risk_level,
 training_required=excluded.training_required,training_version=excluded.training_version,updated_at=now();
