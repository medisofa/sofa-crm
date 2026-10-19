# SOFA MVP v1 — checklist de GO

No confundir "código creado" con "producción aprobada".

## G1 Respaldo
- [ ] Backup PostgreSQL/Auth actual.
- [ ] Bytes de Storage respaldados.
- [ ] Checksums.
- [ ] Restauración verificada en entorno aislado.

## G2 Migraciones
- [ ] 001_core.sql en entorno aislado.
- [ ] 002_operations.sql.
- [ ] 003_hardening.sql.
- [ ] 004_mfa_staff.sql.
- [ ] 005_storage.sql.
- [ ] Rollback documentado antes de migrar datos reales.

## G3 Seguridad
- [ ] Médico A no ve B.
- [ ] Secretaria A solo ve sus médicos asignados.
- [ ] Excepción multicliente vigente funciona.
- [ ] Excepción vencida/revocada bloquea.
- [ ] Staff sin AAL2 no ve clientes.
- [ ] Staff con AAL2 y alcance sí ve clientes asignados.
- [ ] Storage A/B.
- [ ] RPC A/B.
- [ ] JWT expirado/revocado.

## G4 Flujo
- [ ] Captured -> received -> validated.
- [ ] Radicación agrupa solo mismo médico/ARS/período.
- [ ] Submitted -> denial o payment.
- [ ] Pago parcial y completo.
- [ ] Cierre.
- [ ] Eventos/auditoría.

## G5 Aplicación
- [ ] npm install.
- [ ] npm run typecheck.
- [ ] npm run build.
- [ ] Login y refresh de sesión.
- [ ] Errores sin exponer detalles internos.
- [ ] Cabeceras de seguridad.
- [ ] Paginación con >10k reclamaciones sintéticas.

## G6 Operación
- [ ] Monitoreo.
- [ ] Runbook de incidente.
- [ ] Responsable de rollback.
- [ ] Primer cliente piloto.
- [ ] GO firmado.
