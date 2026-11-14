-- Ya aplicado en producción vía mcp__Supabase__apply_migration
-- 7 RPCs que reemplazan la descarga masiva de filas en bi.js
-- Todas son SECURITY INVOKER (respetan RLS) y STABLE

-- 1. bi_events_by_month_kind(p_from, p_to, p_org_id, p_ars_id, p_real_only)
--    → month, kind, total, cnt
--    Reemplaza: financialEvents() — 20K filas → ~50 filas agregadas

-- 2. bi_events_by_ars_kind(p_from, p_to, p_org_id, p_ars_id, p_real_only)
--    → ars_id, kind, total
--    Reemplaza: financialEvents() agrupado por ARS — 20K filas → ~30 filas

-- 3. bi_collection_days_by_ars(p_from, p_to, p_org_id, p_ars_id, p_real_only)
--    → ars_id, sum_days, cnt
--    Reemplaza: collectionDays() — 20K filas → ~10 filas

-- 4. bi_open_balance_by_ars(p_org_id, p_ars_id, p_real_only)
--    → ars_id, ars_name, total_balance
--    Reemplaza: openBalances() agrupado por ARS — 20K filas → ~10 filas

-- 5. bi_open_balance_by_client(p_org_id, p_ars_id, p_real_only)
--    → cliente, radicaciones, radicado, pagado, disputa, saldo, vencido
--    Reemplaza: openBalances() agrupado por cliente (cartera) — 20K filas → ~50 filas

-- 6. bi_service_mix_agg(p_from, p_to, p_org_id, p_ars_id, p_real_only)
--    → internal_code, description, total_lines, total_quantity, total_amount
--    Reemplaza: serviceMix() — 20K filas → ~200 filas

-- 7. bi_glosa_pareto_agg(p_org_id, p_ars_id, p_real_only)
--    → reason_name, category, servicios, glosado, aceptado, recuperado
--    Reemplaza: glosaPareto() — 5K filas → ~30 filas
