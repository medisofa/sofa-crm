-- SOFA · CIE-10 sugerido por servicio / SIMON / CUPS
-- Referencia inicial curada desde WHO ICD-10 Browser (2019).
-- Las sugerencias NO sustituyen el diagnóstico documentado por el profesional.

create table if not exists public.cie10_catalog (
  code text primary key,
  title_es text not null,
  title_en text,
  chapter text,
  source_name text not null default 'WHO ICD-10 Browser',
  source_version text not null default '2019',
  source_url text not null default 'https://icd.who.int/browse10/2019/en/',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.cie10_catalog enable row level security;
drop policy if exists cie10_catalog_read on public.cie10_catalog;
create policy cie10_catalog_read on public.cie10_catalog for select to authenticated using (is_active);
grant select on public.cie10_catalog to authenticated;

insert into public.cie10_catalog(code,title_es,title_en,chapter)
values
('Z71.3','Consejo y vigilancia dietética','Dietary counselling and surveillance','XXI'),
('Z13.2','Examen especial de pesquisa para trastornos nutricionales','Special screening examination for nutritional disorders','XXI'),
('E66.9','Obesidad, no especificada','Obesity, unspecified','IV'),
('F50.9','Trastorno de la conducta alimentaria, no especificado','Eating disorder, unspecified','V'),
('R13','Disfagia','Dysphagia','XVIII'),
('E46','Desnutrición proteico-calórica no especificada','Unspecified protein-energy malnutrition','IV'),
('E43','Desnutrición proteico-calórica severa no especificada','Unspecified severe protein-energy malnutrition','IV'),
('R63.3','Dificultades para la alimentación','Feeding difficulties','XVIII'),
('E11.9','Diabetes mellitus tipo 2 sin complicaciones','Type 2 diabetes mellitus without complications','IV'),
('I10','Hipertensión esencial (primaria)','Essential (primary) hypertension','IX'),
('E78.5','Hiperlipidemia, no especificada','Hyperlipidaemia, unspecified','IV')
on conflict(code) do update set
 title_es=excluded.title_es,title_en=excluded.title_en,chapter=excluded.chapter,
 source_name='WHO ICD-10 Browser',source_version='2019',
 source_url='https://icd.who.int/browse10/2019/en/',is_active=true,updated_at=now();

create table if not exists public.cie10_suggestion_rules (
  id bigint generated always as identity primary key,
  cie10_code text not null references public.cie10_catalog(code),
  service_type_code text,
  procedure_keyword text,
  simon text,
  cups text,
  priority smallint not null default 50,
  confidence text not null default 'media' check (confidence in ('alta','media','baja')),
  rationale text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(cie10_code,service_type_code,procedure_keyword,simon,cups)
);

alter table public.cie10_suggestion_rules enable row level security;
drop policy if exists cie10_rules_read on public.cie10_suggestion_rules;
create policy cie10_rules_read on public.cie10_suggestion_rules for select to authenticated using (is_active);
grant select on public.cie10_suggestion_rules to authenticated;

-- Reglas de alta confianza: el nombre del servicio expresa el motivo clínico de forma directa.
insert into public.cie10_suggestion_rules(cie10_code,procedure_keyword,priority,confidence,rationale)
values
('E66.9','obesidad',10,'alta','El servicio está explícitamente relacionado con obesidad. Confirmar el diagnóstico documentado y su especificidad.'),
('F50.9','trastornos de la conducta alimentaria',10,'alta','El servicio está explícitamente relacionado con trastornos de la conducta alimentaria. Confirmar el diagnóstico documentado.'),
('R13','disfagia',10,'alta','El servicio corresponde a evaluación de disfagia. Confirmar que la disfagia esté documentada.'),
('Z13.2','tamizaje de riesgo nutricional',10,'alta','El servicio es un tamizaje de riesgo nutricional.'),
('Z71.3','consulta inicial de nutrición',20,'media','Consulta nutricional: sugerencia de contacto/consejería dietética cuando corresponda a la documentación.'),
('Z71.3','consulta de seguimiento nutrición',20,'media','Seguimiento nutricional: confirmar motivo clínico documentado.'),
('Z71.3','diseño y entrega de plan nutricional',20,'media','Plan nutricional: sugerencia de consejería dietética cuando corresponda.'),
('Z71.3','diseño del plan nutricional',20,'media','Plan nutricional: sugerencia de consejería dietética cuando corresponda.'),
('Z71.3','evaluación antropométrica',25,'media','Evaluación nutricional/antropométrica: confirmar motivo clínico.'),
('Z71.3','análisis de composición corporal',25,'media','Evaluación nutricional: confirmar motivo clínico.'),
('Z71.3','calorimetría indirecta',25,'media','Evaluación nutricional/metabólica: confirmar motivo clínico.')
on conflict do nothing;

-- Regla por CUPS de interconsulta nutricional.
insert into public.cie10_suggestion_rules(cie10_code,cups,priority,confidence,rationale)
values
('Z71.3','890406',30,'media','CUPS asociado a interconsulta de nutrición/dietética; confirmar diagnóstico principal documentado.')
on conflict do nothing;

-- Reglas de baja confianza: la terapia puede obedecer a múltiples diagnósticos.
insert into public.cie10_suggestion_rules(cie10_code,procedure_keyword,priority,confidence,rationale)
values
('E46','nutricion enteral',60,'baja','La nutrición enteral puede asociarse a desnutrición, pero solo use E46 si está documentada.'),
('E46','nutricion parenteral',60,'baja','La nutrición parenteral puede asociarse a desnutrición, pero solo use E46 si está documentada.'),
('E46','terapia nutricional',65,'baja','La terapia nutricional no determina por sí sola el diagnóstico. Use E46 únicamente si existe desnutrición documentada.'),
('R63.3','sonda de alimentacion',70,'baja','Una sonda de alimentación puede utilizarse por múltiples causas. R63.3 solo aplica si existe dificultad de alimentación documentada.')
on conflict do nothing;

create or replace function public.cie10_suggest(
  p_procedure uuid default null,
  p_query text default null,
  p_limit integer default 12
)
returns table(
  code text,
  title_es text,
  title_en text,
  confidence text,
  rationale text,
  matched_by text,
  simon text,
  cups text
)
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_name text;
  v_type text;
  v_simon text;
  v_cups text;
  v_q text := lower(trim(coalesce(p_query,'')));
begin
  if auth.uid() is null then
    raise exception 'Inicia sesión para consultar CIE-10.' using errcode='42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 30 then p_limit := 12; end if;

  if p_procedure is not null then
    select lower(coalesce(s.name,'')), s.service_type_code, s.simon, s.cups
      into v_name,v_type,v_simon,v_cups
      from public.v_service_catalog s
     where s.id=p_procedure and s.is_active;
  end if;

  if v_q <> '' then
    return query
    select c.code,c.title_es,c.title_en,
           'manual'::text as confidence,
           'Coincidencia de búsqueda en el catálogo CIE-10 de referencia.'::text,
           'busqueda'::text,
           v_simon,v_cups
      from public.cie10_catalog c
     where c.is_active
       and (lower(c.code) like '%'||v_q||'%' or lower(c.title_es) like '%'||v_q||'%' or lower(coalesce(c.title_en,'')) like '%'||v_q||'%')
     order by case when lower(c.code)=v_q then 0 when lower(c.code) like v_q||'%' then 1 else 2 end,c.code
     limit p_limit;
    return;
  end if;

  return query
  select c.code,c.title_es,c.title_en,r.confidence,r.rationale,
         trim(both ',' from concat_ws(',',
           case when r.procedure_keyword is not null then 'servicio' end,
           case when r.service_type_code is not null then 'tipo' end,
           case when r.simon is not null then 'SIMON' end,
           case when r.cups is not null then 'CUPS' end
         ))::text as matched_by,
         v_simon,v_cups
    from public.cie10_suggestion_rules r
    join public.cie10_catalog c on c.code=r.cie10_code and c.is_active
   where r.is_active
     and (r.procedure_keyword is null or v_name like '%'||lower(r.procedure_keyword)||'%')
     and (r.service_type_code is null or r.service_type_code=v_type)
     and (r.simon is null or r.simon=v_simon)
     and (r.cups is null or r.cups=v_cups)
   order by r.priority,
            case r.confidence when 'alta' then 1 when 'media' then 2 else 3 end,
            c.code
   limit p_limit;
end
$$;

revoke all on function public.cie10_suggest(uuid,text,integer) from public,anon;
grant execute on function public.cie10_suggest(uuid,text,integer) to authenticated;

comment on function public.cie10_suggest(uuid,text,integer) is
'Sugiere CIE-10 a partir del servicio/SIMON/CUPS o búsqueda manual. La selección final debe concordar con el diagnóstico documentado por el profesional.';
