# SOFA — Integración segura de auditoría de reclamaciones
Estado: núcleo aislado en rama; no desplegado ni conectado al portal.

## Evidencia observada
- Repositorio medisofa/sofa-crm y Supabase bpwjhgpzhzhiocoxrvzq.
- 280 service_lines: 40 reales y 240 DEMO, contados sin datos personales.
- Las funciones claim_duplicate_candidates y validate_submission ya detectan/bloquean coincidencias de alto riesgo.
- claim_audits tiene política SELECT, pero no INSERT del cliente.
- organizations.is_demo distingue las organizaciones. Migraciones 223 a 231 constan aplicadas; cada reporte requiere prueba propia.

## Integración en cinco etapas
1. Admisión: campos completos y cobertura solo con respuesta oficial autorizada.
2. Auditoría y códigos: catálogo versionado, reglas por ARS, tarifas vigentes y contrato.
3. Fiscal: validar comprobantes NCF/e-CF según operación y emisor, sin inventar números.
4. Consejo de agentes: explicar inconsistencias y evidencias; decisión humana obligatoria.
5. Conciliación: enlazar pagos y glosas; sin envío automático a ARS.

## Controles previos
- Servicio backend con JWT, roles, membresía y tenant comprobados.
- Por defecto excluir is_demo=true de todos los globales, automatizaciones y salidas.
- No enviar PII/salud a modelos externos sin base legal y garantías de privacidad.
- Persistir trazabilidad en endpoint autorizado con RLS, sin conceder INSERT abierto a claim_audits.
- Ausencia de conexión oficial, diagnóstico no validado o regla fiscal faltante = pendiente, nunca aprobado.
- Pruebas de contratos, RLS multi-tenant, 40 reales / 240 DEMO y revisión humana antes de activar.

## Entrega parcial
js/services/claim-audit-agents.js implementa una función pura sin I/O ni LLM que devuelve chequeos y exige revisión humana. No está importada en la aplicación; requiere pruebas y conexión backend antes de uso operativo.