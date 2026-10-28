# SOFA — Auditoría de escalabilidad: 25 a 200 clientes operativos
**Fecha:** 2026-10-18. **Alcance:** Supabase `bpwjhgpzhzhiocoxrvzq` y repositorio `medisofa/sofa-crm`. **Sin pruebas de carga en producción** y sin modificaciones a datos.

## Línea base observada
- `organizations`: 6 registros (no equivalen necesariamente a seis clientes operativos).
- `service_lines`: 240 registros; `email_queue`: 6; `audit_log`: 2,493 registros contados.
- `max_connections`: 60 (configuración PostgreSQL; no es el máximo de clientes SaaS).
- Tamaño total aproximado (tabla+índices): `service_lines` 1,216 kB; `audit_log` 6,032 kB; `email_queue` 200 kB.
- Índices existentes por organización/estado en reclamaciones, por organización/fecha en auditoría, por estado/programación en cola, por organización/período en radicaciones.
- Se encontraron políticas RLS por operación en tablas críticas. Su existencia **no demuestra aislamiento correcto**: falta prueba con dos identidades reales de diferentes organizaciones.
- Estadísticas de consultas secuenciales son acumuladas y en tablas pequeñas pueden ser normales. No implican cuello de botella sin planes `EXPLAIN` y mediciones.

## Modelo de demanda para las rondas
**Supuestos ilustrativos, NO métricas de SOFA:** 80 reclamaciones por cliente/mes, 2 usuarios por cliente, 10 % de usuarios simultáneos en hora pico, 2 documentos por reclamación, 300 kB por documento, 4 eventos de auditoría por reclamación. Cada fila es proyección, no resultado de un test.

| Clientes | Reclamaciones/mes | Usuarios | Simultáneos supuestos | Documentos/mes | Archivos/mes (GB decimales) | Eventos auditoría/mes |
|---:|---:|---:|---:|---:|---:|---:|
| 25 | 2,000 | 50 | 5 | 4,000 | 1.2 | 8,000 |
| 50 | 4,000 | 100 | 10 | 8,000 | 2.4 | 16,000 |
| 75 | 6,000 | 150 | 15 | 12,000 | 3.6 | 24,000 |
| 100 | 8,000 | 200 | 20 | 16,000 | 4.8 | 32,000 |
| 125 | 10,000 | 250 | 25 | 20,000 | 6.0 | 40,000 |
| 150 | 12,000 | 300 | 30 | 24,000 | 7.2 | 48,000 |
| 175 | 14,000 | 350 | 35 | 28,000 | 8.4 | 56,000 |
| 200 | 16,000 | 400 | 40 | 32,000 | 9.6 | 64,000 |

Los archivos mensuales proyectados no incluyen réplicas, versiones, adjuntos mayores, backups ni overhead. Se necesita medir distribución real de reclamaciones y tamaño de documentos para ajustar.

## Rondas de validación (cada una en staging con datos sintéticos)
1. **25 clientes:** registro/captura, listado paginado, RLS de dos organizaciones, carga de documentos.
2. **50 clientes:** transiciones de reclamaciones, duplicados y tarifas vigentes.
3. **75 clientes:** retiros, radicaciones y consultas filtradas por organización/ARS/período.
4. **100 clientes:** glosas, pagos parciales, conciliación y auditoría.
5. **125 clientes:** subida simultánea de documentos, cuotas y almacenamiento.
6. **150 clientes:** cola asíncrona, backoff, límites Gmail, idempotencia y observabilidad.
7. **175 clientes:** concurrencia, bloqueos, fallos transitorios y recuperación.
8. **200 clientes:** ensayo de operación completa con usuarios simultáneos y escenarios de picos.

## Criterios sugeridos de aprobación (metas, no mediciones)
- Consultas críticas p95 <= 500 ms en backend bajo carga objetivo, medido desde el cliente y por SQL.
- Operaciones interactivas p95 <= 2 s (sin carga de archivos grandes).
- Errores inesperados < 1 % por escenario y sin pérdida de registros.
- 0 accesos cruzados entre organizaciones; 0 duplicados en reclamaciones ante reintentos.
- Cola estable (edad del mensaje más antiguo y tasa de procesamiento dentro de umbrales definidos); no habilitar correo real durante pruebas.
- Backups y reversión probados antes de promover cambios.

## Riesgos y acciones prioritarias
1. **Aislamiento multiempresa:** revisar SQL completo de políticas RLS y probar autenticación de dos organizaciones; usar índices que incluyan organization_id en consultas frecuentes.
2. **Concurrencia y conexión:** instrumentar conexiones activas, pooler, tiempos y `pg_stat_statements` si está disponible; 60 conexiones PostgreSQL no equivale a 60 usuarios.
3. **Auditoría:** 2,493 eventos hoy; proyectar crecimiento, retención legal, índices, paginación y archivado antes de particionar.
4. **Documentos:** definir cuota y lifecycle por cliente, compresión, expiración de URLs firmadas y limpieza segura; mantener bucket privado.
5. **Correo:** Gmail no es canal de campañas masivas; separar notificaciones transaccionales y limitar tasas. Mantener procesador productivo bloqueado.
6. **Consultas:** auditar rutas con `select('*')`, filtros por tenant, paginación, N+1 y agregados repetidos.
7. **Seguridad:** pruebas de rol médico/secretaria/admin, auditoría de cambios y accesos indebidos.
8. **Continuidad:** RPO/RTO explícitos, restauración ensayada, límites de costos y alertas de presupuesto.

## Protocolo de prueba sin afectar producción
- Crear entorno staging aislado con credenciales y proyecto propios.
- Datos 100 % sintéticos; no copiar pacientes ni secretos reales.
- Instrumentar p50/p95/p99, throughput, errores, CPU, memoria, pool y almacenamiento.
- Ejecutar escalones 25→50→75→100→125→150→175→200 con enfriamiento y rollback.
- Comparar cada ronda contra los criterios; no declarar capacidad validada sin evidencias.
- No desplegar migraciones o índices adicionales antes de revisar planes SQL y dependencias.

## Estado
**Auditoría de inventario y modelado completados.** **Pruebas de carga no ejecutadas** (no hay staging aislado ni autorización para generar carga sobre producción). No se han aplicado cambios en Supabase, no se ha habilitado Gmail y HemoCura permanece separado.
