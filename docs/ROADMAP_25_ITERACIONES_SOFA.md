# SOFA — 25 iteraciones de consolidación, Gmail y valor operativo

**Alcance:** `medisofa/sofa-crm`, Supabase `bpwjhgpzhzhiocoxrvzq`. **Exclusión:** HemoCura. Este documento es un plan de ejecución con criterios de aceptación, no evidencia de implementación de todas las fases.

## Bloque A — Seguridad y correo (01–05)
| Iteración | Entregable | Criterio de aceptación |
|---|---|---|
| 01 | Guardas de cola y allowlist Gmail | Con allowlist activa, la cola normal responde 403 sin llamar `email_claim_batch`. **Código preparado**. |
| 02 | Suite de pruebas de función | Casos de 401, 403, 429, 5xx, timeout y Gmail sin credenciales; pruebas pasan en entorno aislado. |
| 03 | Auditoría OAuth | Refresh token válido, scope mínimo gmail.send, secretos solo servidor, rotación documentada. |
| 04 | Despliegue de prueba aislada | JWT verificado, encabezado secreto, destinatario consentido y sin tocar cola productiva. |
| 05 | Piloto Gmail de un mensaje | Correo técnico llega, sin datos de pacientes, sin duplicación y registro verificable. |

## Bloque B — Secretaria 360° (06–10)
| Iteración | Entregable | Criterio de aceptación |
|---|---|---|
| 06 | Auditoría del formulario de captura | Mapa de campos obligatorios, duplicados y validaciones contra contrato ARS. |
| 07 | Captura rápida de reclamación | Paciente, ARS, servicio, autorización, fecha y monto en flujo simplificado. |
| 08 | Validación preventiva | Avisos por faltantes, tarifas incorrectas y autorizaciones incompletas. |
| 09 | Recepción/retiro de documentos | Registro por lote, responsable, fecha y comprobante descargable. |
| 10 | Bandeja diaria de secretaria | Pendientes, correcciones y casos próximos a vencimiento filtrables. |

## Bloque C — Operaciones SOFA (11–15)
| Iteración | Entregable | Criterio de aceptación |
|---|---|---|
| 11 | Estados por reclamación | Captura → recepción → validación → radicación → pago/glosa trazable. |
| 12 | Reglas de transición | Permisos, fechas y bitácora en cada cambio; sin saltos ilegítimos. |
| 13 | Radicación ARS | Relación entre reclamación, lote, ARS, período y comprobante. |
| 14 | Gestión de glosas | Motivo, monto, fecha, respuesta y recuperación individual. |
| 15 | Conciliación de pagos | Pagos parciales, saldos y honorarios consistentes por reclamación. |

## Bloque D — Portal médico (16–20)
| Iteración | Entregable | Criterio de aceptación |
|---|---|---|
| 16 | Panel financiero | Facturado, radicado, cobrado y pendiente conciliados. |
| 17 | Antigüedad de cuentas | Tramos 0–30, 31–60, 61–90 y más de 90 días. |
| 18 | Alertas al médico | Glosas y documentos pendientes con enlaces autenticados. |
| 19 | Reporte mensual | PDF/CSV o vista exportable, con corte y trazabilidad. |
| 20 | Control de acceso | Cada médico ve solo sus reclamaciones y pagos autorizados. |

## Bloque E — Calidad, estabilidad y lanzamiento (21–25)
| Iteración | Entregable | Criterio de aceptación |
|---|---|---|
| 21 | Auditoría de rutas y módulos | Rutas sin módulos y módulos duplicados identificados y corregidos. |
| 22 | Inventario de tablas | Matriz tabla→módulo→RPC→uso; ninguna eliminación por tabla vacía. |
| 23 | Pruebas de regresión | Captura, radicación, documentos, pagos, correo y roles pasan. |
| 24 | Rendimiento y móvil | Captura optimizada, errores legibles, tiempos medidos en dispositivos reales. |
| 25 | Publicación gradual | Backup, revisión PR, pruebas de aceptación, plan de reversión y aprobación. |

## Restricciones de publicación
- No modificar secretos OAuth desde el repositorio.
- No desplegar función real sin confirmación de credenciales, autenticación y autorización de prueba.
- No consumir los seis correos pendientes detectados sin validación de destinatarios y contenido.
- No fusionar PR de correo en `main` hasta que la suite de pruebas y revisión de seguridad estén aprobadas.
- No borrar tablas por ausencia de registros; analizar dependencias antes de migrar.
- No mezclar los proyectos SOFA y HemoCura.

## Métricas de aceptación
- 0 correos enviados sin autorización; 0 exposición de secretos.
- 0 acceso entre organizaciones o médicos no autorizados.
- 100 % de reclamaciones con estados y bitácora rastreables.
- Tiempos de captura, glosas y cobros medidos contra línea base antes de declarar mejoras.
