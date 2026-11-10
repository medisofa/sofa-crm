# Constancia de entrega y códigos ARS · 5.32.0

En **Radicaciones → abrir lote → Constancia de entrega / PDF** se muestra la relación de servicios, datos del prestador y de factura, resumen por servicio y total reclamado. Use **Imprimir / PDF** para generar las copias de entrega. El apartado de recepción permite firma y sello de la ARS. Generar el documento no cambia el estado del lote ni registra automáticamente su recepción. Registre el acuse y adjunte el documento firmado desde el lote.

En **Captura rápida**, después de seleccionar médico y ARS, aparece el código PSS. Al seleccionar un servicio contratado aparece la referencia de contrato de su tarifa. Guardar esos identificadores conserva los datos del paciente en pantalla.

El personal autorizado de SoFa (Asistencia, Operaciones y Facturación) puede realizar el primer registro. Los cambios posteriores requieren Administrador o Super Admin. Los valores ya existentes cuentan como registrados. La regla también se valida en la base de datos y borrar un valor no reinicia el permiso inicial.

El PSS corresponde al médico y ARS. La referencia contractual corresponde al médico, ARS y plan; varias tarifas pueden reutilizar la referencia vigente. La carga desde Excel consulta esa referencia y protege su edición según permisos. No se modifican montos, vigencias ni las fotografías contractuales de reclamaciones anteriores.
