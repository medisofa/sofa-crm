-- 262 · Historia clínica por especialidad: catálogo de especialidades, plantillas de nutrición (adultos y
-- pediátrica) con bioimpedancia, índice cintura-talla, ICC, GEB/GET y puntaje Z de la OMS en niños.
-- Ya aplicado en producción (20/11/2026).
--
-- Decisiones:
--  · Los campos `calc` los calcula el navegador (js/utils/antropometria.js) y se guardan en la nota como texto,
--    igual que cualquier campo: la nota firmada conserva el valor que vio el médico. El servidor no los valida.
--  · `heading` es solo un subtítulo visual (sin key): no se guarda nada.
--  · providers.specialty sigue siendo texto libre (lo que se imprime); specialty_code es la versión normalizada
--    que decide la plantilla por defecto.
--  · clinical_default_template no devuelve datos del paciente: solo un código de plantilla, y exige el mismo
--    acceso de lectura a la historia que el resto de la pantalla.
do $$ begin
  if to_regclass('public.clinical_templates') is null or to_regclass('public.providers') is null
     or to_regprocedure('app.clinical_require(uuid,boolean,uuid)') is null then
    raise exception '262 requiere la historia clínica (110) y providers.';
  end if;
end $$;

create table if not exists public.specialties (
  code text primary key,
  name text not null,
  template_code text references public.clinical_templates(code),
  sort_order int not null default 100
);
alter table public.specialties enable row level security;
drop policy if exists specialties_read on public.specialties;
create policy specialties_read on public.specialties for select to authenticated using (true);
revoke insert, update, delete on public.specialties from anon, authenticated;

alter table public.providers add column if not exists specialty_code text references public.specialties(code);

-- Plantillas nuevas
insert into public.clinical_templates (code, specialty, name, fields, version, is_active, sort_order) values
('nutricion', 'Nutrición', 'Consulta de nutrición (adultos)', $j$[
 {"key":"motivo","type":"textarea","label":"Motivo de consulta y objetivo","section":"S","required":true},
 {"key":"historia_dietetica","type":"textarea","label":"Historia dietética (recordatorio de 24 h, frecuencia de consumo)","section":"S"},
 {"key":"habitos","type":"textarea","label":"Hábitos (sueño, agua, alcohol, tabaco)","section":"S"},
 {"key":"actividad_fisica","type":"select","label":"Actividad física","options":["Sedentario","Ligera","Moderada","Intensa","Muy intensa"],"section":"S"},
 {"key":"edad_calc","type":"calc","formula":"edad","label":"Edad","section":"O"},
 {"key":"peso","type":"number","label":"Peso (kg)","section":"O","required":true},
 {"key":"talla","type":"number","label":"Talla (cm)","section":"O","required":true},
 {"key":"imc","type":"calc","formula":"imc","label":"IMC (kg/m²)","section":"O"},
 {"key":"imc_clasif","type":"calc","formula":"imc_clasif","label":"Clasificación del IMC (OMS)","section":"O"},
 {"key":"cintura","type":"number","label":"Cintura (cm)","section":"O"},
 {"key":"cadera","type":"number","label":"Cadera (cm)","section":"O"},
 {"key":"ict","type":"calc","formula":"ict","label":"Índice cintura-talla","section":"O"},
 {"key":"icc","type":"calc","formula":"icc","label":"Índice cintura-cadera","section":"O"},
 {"type":"heading","label":"Bioimpedancia","section":"O"},
 {"key":"bia_equipo","type":"text","label":"Equipo de bioimpedancia","section":"O"},
 {"key":"bia_grasa_pct","type":"number","label":"Grasa corporal (%)","section":"O"},
 {"key":"masa_grasa_kg","type":"calc","formula":"masa_grasa_kg","label":"Masa grasa (kg)","section":"O"},
 {"key":"masa_libre_grasa_kg","type":"calc","formula":"masa_libre_grasa_kg","label":"Masa libre de grasa (kg)","section":"O"},
 {"key":"bia_musculo_kg","type":"number","label":"Masa muscular (kg)","section":"O"},
 {"key":"bia_agua_pct","type":"number","label":"Agua corporal total (%)","section":"O"},
 {"key":"bia_grasa_visceral","type":"number","label":"Grasa visceral (nivel)","section":"O"},
 {"key":"bia_metabolismo_basal","type":"number","label":"Metabolismo basal del equipo (kcal)","section":"O"},
 {"key":"bia_edad_metabolica","type":"number","label":"Edad metabólica (años)","section":"O"},
 {"type":"heading","label":"Requerimiento energético","section":"O"},
 {"key":"geb_mifflin","type":"calc","formula":"geb_mifflin","label":"GEB Mifflin-St Jeor","section":"O"},
 {"key":"geb_harris","type":"calc","formula":"geb_harris","label":"GEB Harris-Benedict","section":"O"},
 {"key":"get","type":"calc","formula":"get","label":"Gasto energético total","section":"O"},
 {"key":"laboratorios","type":"textarea","label":"Laboratorios relevantes","section":"O"},
 {"key":"diagnostico_nutricional","type":"textarea","label":"Diagnóstico nutricional","section":"A","required":true},
 {"key":"diagnosticos","type":"cie10","label":"Diagnósticos CIE-10 (separados por coma)","section":"A","required":true},
 {"key":"meta_kcal","type":"number","label":"Meta de energía (kcal/día)","section":"P"},
 {"key":"meta_proteina_g","type":"number","label":"Proteína (g/día)","section":"P"},
 {"key":"meta_carbohidratos_g","type":"number","label":"Carbohidratos (g/día)","section":"P"},
 {"key":"meta_grasas_g","type":"number","label":"Grasas (g/día)","section":"P"},
 {"key":"plan","type":"textarea","label":"Plan alimentario e indicaciones","section":"P","required":true},
 {"key":"proxima_cita","type":"date","label":"Próxima cita","section":"P"}
]$j$::jsonb, 1, true, 50),
('nutricion_pediatrica', 'Nutrición pediátrica', 'Consulta de nutrición pediátrica', $j$[
 {"key":"motivo","type":"textarea","label":"Motivo de consulta y objetivo","section":"S","required":true},
 {"key":"acompanante","type":"text","label":"Acompañante y parentesco","section":"S"},
 {"key":"alimentacion","type":"textarea","label":"Alimentación (lactancia, ablactación, recordatorio de 24 h)","section":"S"},
 {"key":"actividad_fisica","type":"select","label":"Actividad física","options":["Sedentario","Ligera","Moderada","Intensa","Muy intensa"],"section":"S"},
 {"key":"edad_calc","type":"calc","formula":"edad","label":"Edad","section":"O"},
 {"key":"peso","type":"number","label":"Peso (kg)","section":"O","required":true},
 {"key":"talla","type":"number","label":"Longitud o talla (cm)","section":"O","required":true},
 {"key":"medicion","type":"select","label":"Medido","options":["Acostado","De pie"],"section":"O"},
 {"key":"perimetro_cefalico","type":"number","label":"Perímetro cefálico (cm)","section":"O"},
 {"key":"cintura","type":"number","label":"Cintura (cm)","section":"O"},
 {"key":"imc","type":"calc","formula":"imc","label":"IMC (kg/m²)","section":"O"},
 {"key":"ict","type":"calc","formula":"ict","label":"Índice cintura-talla","section":"O"},
 {"type":"heading","label":"Puntaje Z (OMS)","section":"O"},
 {"key":"z_peso_edad","type":"calc","formula":"z_peso_edad","label":"Peso para la edad","section":"O"},
 {"key":"z_talla_edad","type":"calc","formula":"z_talla_edad","label":"Talla para la edad","section":"O"},
 {"key":"z_peso_talla","type":"calc","formula":"z_peso_talla","label":"Peso para la talla","section":"O"},
 {"key":"z_imc_edad","type":"calc","formula":"z_imc_edad","label":"IMC para la edad","section":"O"},
 {"key":"z_pc_edad","type":"calc","formula":"z_pc_edad","label":"Perímetro cefálico para la edad","section":"O"},
 {"type":"heading","label":"Bioimpedancia","section":"O"},
 {"key":"bia_equipo","type":"text","label":"Equipo de bioimpedancia","section":"O"},
 {"key":"bia_grasa_pct","type":"number","label":"Grasa corporal (%)","section":"O"},
 {"key":"masa_grasa_kg","type":"calc","formula":"masa_grasa_kg","label":"Masa grasa (kg)","section":"O"},
 {"key":"masa_libre_grasa_kg","type":"calc","formula":"masa_libre_grasa_kg","label":"Masa libre de grasa (kg)","section":"O"},
 {"key":"bia_musculo_kg","type":"number","label":"Masa muscular (kg)","section":"O"},
 {"key":"bia_agua_pct","type":"number","label":"Agua corporal total (%)","section":"O"},
 {"key":"laboratorios","type":"textarea","label":"Laboratorios relevantes","section":"O"},
 {"key":"diagnostico_nutricional","type":"textarea","label":"Diagnóstico nutricional","section":"A","required":true},
 {"key":"diagnosticos","type":"cie10","label":"Diagnósticos CIE-10 (separados por coma)","section":"A","required":true},
 {"key":"meta_kcal","type":"number","label":"Meta de energía (kcal/día)","section":"P"},
 {"key":"meta_proteina_g","type":"number","label":"Proteína (g/día)","section":"P"},
 {"key":"plan","type":"textarea","label":"Plan alimentario e indicaciones a los padres","section":"P","required":true},
 {"key":"proxima_cita","type":"date","label":"Próxima cita","section":"P"}
]$j$::jsonb, 1, true, 55)
on conflict (code) do nothing;

-- Pediatría: agrega «Medido», edad y puntaje Z (versión 2). Solo si sigue en la versión 1.
update public.clinical_templates set version = 2, fields = $j$[
 {"key":"motivo","type":"textarea","label":"Motivo de consulta","section":"S","required":true},
 {"key":"acompanante","type":"text","label":"Acompañante y parentesco","section":"S"},
 {"key":"enfermedad_actual","type":"textarea","label":"Historia de la enfermedad actual","section":"S","required":true},
 {"key":"alimentacion","type":"textarea","label":"Alimentación","section":"S"},
 {"key":"vacunas","type":"select","label":"Vacunas al día","options":["Sí","No","Incompletas","Se desconoce"],"section":"S"},
 {"key":"desarrollo","type":"textarea","label":"Desarrollo psicomotor","section":"S"},
 {"key":"edad_calc","type":"calc","formula":"edad","label":"Edad","section":"O"},
 {"key":"peso","type":"number","label":"Peso (kg)","section":"O"},
 {"key":"talla","type":"number","label":"Talla (cm)","section":"O"},
 {"key":"medicion","type":"select","label":"Medido","options":["Acostado","De pie"],"section":"O"},
 {"key":"perimetro_cefalico","type":"number","label":"Perímetro cefálico (cm)","section":"O"},
 {"key":"temp","type":"number","label":"Temperatura (°C)","section":"O"},
 {"key":"fc","type":"number","label":"Frecuencia cardiaca (lpm)","section":"O"},
 {"type":"heading","label":"Puntaje Z (OMS)","section":"O"},
 {"key":"z_peso_edad","type":"calc","formula":"z_peso_edad","label":"Peso para la edad","section":"O"},
 {"key":"z_talla_edad","type":"calc","formula":"z_talla_edad","label":"Talla para la edad","section":"O"},
 {"key":"z_peso_talla","type":"calc","formula":"z_peso_talla","label":"Peso para la talla","section":"O"},
 {"key":"z_imc_edad","type":"calc","formula":"z_imc_edad","label":"IMC para la edad","section":"O"},
 {"key":"z_pc_edad","type":"calc","formula":"z_pc_edad","label":"Perímetro cefálico para la edad","section":"O"},
 {"key":"examen_fisico","type":"textarea","label":"Examen físico","section":"O","required":true},
 {"key":"diagnosticos","type":"cie10","label":"Diagnósticos CIE-10 (separados por coma)","section":"A","required":true},
 {"key":"plan","type":"textarea","label":"Plan y tratamiento (dosis por kg)","section":"P","required":true},
 {"key":"proxima_cita","type":"date","label":"Próxima cita","section":"P"}
]$j$::jsonb where code = 'pediatria' and version = 1;

insert into public.specialties (code, name, template_code, sort_order) values
 ('medicina_general', 'Medicina general', 'general_soap', 10),
 ('medicina_interna', 'Medicina interna', 'general_soap', 15),
 ('gineco_obstetricia', 'Ginecología y obstetricia', 'gineco_obstetricia', 20),
 ('pediatria', 'Pediatría', 'pediatria', 30),
 ('cardiologia', 'Cardiología', 'cardiologia', 40),
 ('nutricion', 'Nutrición', 'nutricion', 50),
 ('nutricion_pediatrica', 'Nutrición pediátrica', 'nutricion_pediatrica', 55),
 ('otra', 'Otra especialidad', 'general_soap', 99)
on conflict (code) do update set name = excluded.name, template_code = excluded.template_code, sort_order = excluded.sort_order;

-- Normaliza lo que ya está escrito (solo donde aún no hay código).
update public.providers set specialty_code = case
    when specialty ~* 'nutri.*pedi' then 'nutricion_pediatrica'
    when specialty ~* 'nutri' then 'nutricion'
    when specialty ~* 'cardio' then 'cardiologia'
    when specialty ~* 'interna' then 'medicina_interna'
    when specialty ~* 'gine|obste' then 'gineco_obstetricia'
    when specialty ~* 'pediat' then 'pediatria'
    when specialty ~* 'general' then 'medicina_general'
  end
 where specialty_code is null and specialty is not null;

-- La lista de plantillas también dice para qué especialidades es la predeterminada.
create or replace function public.clinical_templates_list()
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'specialty', t.specialty, 'name', t.name, 'version', t.version, 'fields', t.fields,
           'for_specialties', (select coalesce(jsonb_agg(s.code), '[]'::jsonb) from public.specialties s where s.template_code = t.code)) order by t.sort_order), '[]'::jsonb)
    from public.clinical_templates t where t.is_active;
$function$;

-- Plantilla sugerida para una nota nueva: la del médico que usa el sistema; si no es médico (secretaria,
-- administración), la del médico de la cita; si no, la del único médico con especialidad del consultorio.
create or replace function public.clinical_default_template(p_patient uuid, p_appointment uuid default null)
 returns text language plpgsql stable security definer set search_path to ''
as $function$
declare v_org uuid; v_tpl text;
begin
  select organization_id into v_org from public.patients where id = p_patient;
  if v_org is null then raise exception 'El paciente no existe. Actualice la lista.' using errcode = 'P0002'; end if;
  perform app.clinical_require(v_org, false, p_patient);
  select s.template_code into v_tpl from public.providers p join public.specialties s on s.code = p.specialty_code
   where p.user_id = auth.uid() and p.organization_id = v_org and p.is_active limit 1;
  if v_tpl is null and p_appointment is not null then
    select s.template_code into v_tpl from public.appointments a join public.providers p on p.id = a.provider_id
      join public.specialties s on s.code = p.specialty_code
     where a.id = p_appointment and a.organization_id = v_org;
  end if;
  if v_tpl is null then
    select min(s.template_code) into v_tpl from public.providers p join public.specialties s on s.code = p.specialty_code
     where p.organization_id = v_org and p.is_active
    having count(distinct s.template_code) = 1;
  end if;
  return coalesce(v_tpl, 'general_soap');
end
$function$;
revoke all on function public.clinical_default_template(uuid, uuid) from public, anon;
grant execute on function public.clinical_default_template(uuid, uuid) to authenticated;
