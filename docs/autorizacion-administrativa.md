# Autorización administrativa · 5.38.1

Administrador y Super Admin pueden registrar o corregir el número de autorización desde Reclamaciones → ficha → Paciente y registro, incluso cuando la reclamación ya está validada, radicada, pagada o cerrada. No hace falta devolverla a borrador.

La acción exige el nuevo número y un motivo mínimo de diez caracteres. Se conservan los ceros iniciales y se verifica que el valor anterior no haya cambiado mientras el usuario tenía la ficha abierta. Los errores conservan el contenido del formulario.

La corrección modifica exclusivamente el número de autorización y la información de actualización. Conserva fecha de autorización, servicio, tarifa, cantidad, monto, estado, lote, pagos y asignaciones existentes. La bitácora registra autor, motivo y valores anterior/nuevo. No concilia ni reasigna pagos automáticamente.

Los demás perfiles mantienen sus permisos y reglas de edición existentes. El modo soporte no puede utilizar esta corrección. Las reglas de períodos archivados siguen vigentes.

Infraestructura aplicada: admin_claim_authorization_correction. SQL y prueba transaccional privados, fuera del repositorio público. Verificado con usuario QA y registros ficticios en una transacción revertida: ocho estados, ambos roles administrativos, pagos y asignaciones intactos, concurrencia, auditoría, rechazo de cambios monetarios por esta vía y denegación a otros perfiles/soporte. Pruebas Chromium del formulario y regresión del editor general.
