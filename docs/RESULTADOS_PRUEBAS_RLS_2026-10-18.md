# Resultados RLS SOFA — 2026-10-18

Proyecto: bpwjhgpzhzhiocoxrvzq. Pruebas SQL solo lectura con SET LOCAL ROLE authenticated y request.jwt.claim.sub; transacciones ROLLBACK. No se modificó producción.

| Identidad simulada | Reclamaciones ajenas | Pagos ajenos | Documentos ajenos | Radicaciones ajenas | Contexto |
|---|---:|---:|---:|---:|---|
| Médico A | 0 | 0 | 0 | no medido | 0 organizaciones visibles: control negativo débil |
| Médico B | 0 | 0 | 0 | 0 | 1 organización visible |
| Médico C | 0 | 0 | 0 | 0 | 1 organización visible |
| Capturadora A | 0 | 0 | 0 | 0 | 0 organizaciones visibles; falta control positivo por scope |
| Capturadora B | 240 | 2 | 0 | 2 | 4 membresías activas, 3 organizaciones visibles, 1 provider scope |

**Interpretación:** La cuenta de Capturadora B también tiene membresías de tipo client en otras organizaciones. El filtro de «organización distinta de la referencia» devuelve datos de organizaciones a las que la misma cuenta está vinculada. No es una fuga RLS confirmada; sí requiere revisión de segregación de funciones y autorización de membresías. No eliminar membresías sin aprobación.

**Pendientes de certificación:** pruebas positivas con reclamaciones sintéticas A/B, dos secretarias sin membresías compartidas, operaciones INSERT/UPDATE/DELETE, Storage API con URLs firmadas, sesiones HTTP reales y Edge Functions que usan service_role. Los resultados SQL simulados no certifican autenticación real ni descarga de archivos.

**Conclusión:** dos médicos de organización única no pudieron leer registros ajenos en estas consultas. No se puede afirmar ausencia total de accesos cruzados.