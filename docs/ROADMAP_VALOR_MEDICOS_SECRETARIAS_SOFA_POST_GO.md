# SOFA — Backlog de valor operativo post-GO (2026-10-18)
Estado: planificación, NO desarrollo desplegado. Rama: feature/gmail-oauth-staging.
Objetivo: reducir doble digitación, errores de captura, retrasos de ARS y consultas manuales; aprovechar entidades existentes sin reconstruir el CRM.

## Regla de entrada
Bloqueante: GO de backup restaurado, autorización multicliente, JWT/RLS, flujo completo, auditoría. No desplegar a clientes reales hasta superar el gate.
Para cada iteración: inspeccionar implementación actual; clasificar CONSERVAR / MEJORAR / INTEGRAR / CREAR; escribir migración reversible si hace falta; pruebas de rol A/B y MFA; pruebas UX; evidencia; rollback.
No guardar datos clínicos en GitHub, registros de IA o proveedores no autorizados.

## I01 — Captura rápida secretaria
Problema: captura repetida y omisiones. Propuesta: formulario progresivo con valores sugeridos, validación de ARS/NSS/autorización/fecha/servicio, borrador recuperable y guardado por reclamación. Reusar service_lines/submissions, motor de tarifas existente. No inventar datos. Criterio: 10 casos sintéticos sin pérdida ni duplicación; dos secretarias simultáneas; error legible.

## I02 — Bandeja de pendientes y errores
Propuesta: filtros por médico, centro, ARS, fecha, prioridad, faltantes y estado; acciones permitidas por rol; tareas con responsable y vencimiento. Criterio: una reclamación aparece en una sola cola operativa principal y conserva trazabilidad de cambios.

## I03 — Portal del médico
Propuesta: panel de facturado/radicado/pagado/glosado/pendiente, desglose por período y ARS, solicitudes de aclaración; sin acceso a otros médicos. Reusar pagos/glosas y servicios. Criterio: cifras reconciliadas con registros; acceso A/B aislado.

## I04 — Recepción física
Propuesta: lote de retiro con fecha, responsable, cantidad, detalle por reclamación, faltantes y comprobante imprimible. Criterio: lote conciliable con reclamaciones individuales; evidencia de recepción.

## I05 — Motor de prevalidación
Propuesta: alertas por tarifas vigentes, códigos ARS, campos obligatorios, duplicados y vigencia de autorizaciones cuando exista regla verificable. No afirmar cobertura PDSS sin fuente vigente. Criterio: casos positivos/negativos y explicación legible.

## I06 — Seguimiento por reclamación
Propuesta: máquina de estados por service_line (capturada/recibida/validada/radicada/observada/glosada/pagada/cerrada), transiciones autorizadas, fechas y bitácora inmutable. Criterio: 1 reclamación end-to-end, reversión controlada, sin cambiar estados de otras reclamaciones del lote.

## I07 — Conciliación de pagos y glosas
Propuesta: importación validada de detalle ARS, matching por reclamación, pagos parciales, diferencias, glosas y saldo pendiente; evitar doble contabilización. Criterio: suma por reclamación = totales por ARS y período; idempotencia de importación.

## I08 — Documentos y autorizaciones
Propuesta: checklist documental por médico/ARS/centro, vigencia, permisos Storage por organización y registro de acceso. Criterio: cero lectura cruzada de objetos privados; versiones y vencimientos trazables.

## I09 — Alertas
Propuesta: avisos internos de reclamaciones sin documentos, próximas a vencimiento, glosas sin resolver, cobros pendientes. Notificaciones externas opt-in y minimización de datos. Criterio: no duplicación, entrega registrada, ninguna PHI por WhatsApp sin autorización.

## I10 — Agenda SOFA
Propuesta: tareas por equipo, asignación, vencimientos, carga por responsable y escalamiento. Criterio: permisos por rol y seguimiento medible.

## I11 — BI médico y SOFA
Propuesta: KPIs de tasa de glosa, días de cobro, cartera vencida, productividad de captura y conciliación. Definir fórmulas, períodos y fuentes; no presentar estimaciones como hechos. Criterio: KPIs reconciliados con datos base.

## I12 — Asistente IA controlado
Propuesta: sugerir faltantes, clasificar incidencias y explicar glosas con humano aprobando. No enviar datos de pacientes a servicios no autorizados ni permitir que IA radique/pague/cambie permisos. Criterio: trazabilidad de sugerencias, aprobación humana, pruebas de privacidad.

## Orden de entrega recomendado
Sprint A (primero): I01 + I02 + I06, por su impacto en granularidad por reclamación.
Sprint B: I03 + I04 + I05.
Sprint C: I07 + I08 + I09.
Sprint D: I10 + I11.
Sprint E: I12 solo con evaluación de privacidad y utilidad.

## Métricas de aceptación de producto (línea base antes de fijar metas)
Tiempo mediano de captura por reclamación; porcentaje de reclamaciones incompletas; tasa de duplicados; días desde servicio a radicación; tasa de glosas; días desde radicación a cobro; tickets por médico; reclamaciones por operario y día.
Cada sprint debe medir antes/después con muestras comparables. No atribuir mejoras no medidas.

## Revisión del estado actual
La auditoría previa identificó 41 procesos: 12 existentes, 21 parciales y 8 ausentes; estos módulos son hipótesis de mejora, no 12 ausencias verificadas. Inspeccionar frontend, esquema y flujos antes de escribir código.
