# Clientes con operación previa ante ARS

Use **Operación previa: reclamaciones y pagos de ARS** desde Puesta en marcha, la ficha del cliente → Radicaciones, Reclamaciones, Pagos → Cartera anterior y auditoría, o Aplicar pago → Auditoría de radicaciones anteriores.

## Carga de apertura

1. Seleccione cliente, médico y ARS. Indique el código de prestador ya otorgado, el inicio de gestión SOFA y el corte de los saldos informados. Si el código ya existe, se reutiliza; una discrepancia requiere revisión en Códigos ARS y no lo sobrescribe.
2. Seleccione uno o varios Excel/CSV del mismo médico y ARS. La primera hoja debe tener los encabezados de la plantilla.
3. Revise los errores junto al archivo, fila y valor original. Corrija en pantalla y descargue una copia corregida si la necesita.
4. Administración verifica el soporte, autoriza la carga, valida nuevamente y confirma el guardado. Facturación puede preparar y revisar archivos; no autoriza saldos financieros de apertura.
5. Audite cada radicación: saldo cotejado, con hallazgos o ya registrada en SOFA. La revisión conserva usuario, fecha, soporte y trazabilidad de las rectificaciones.

## Ambos formatos

- `resumen`: un total de control por radicación, con fecha original de radicación y facturado. No inventa reclamaciones para completar el total.
- `reclamacion`: una fila por reclamación, con referencia original y facturado. Si no existe folio original, NSS + autorización + fecha de servicio + servicio/SIMON/CUPS permiten formar una clave de cotejo, identificada como tal; no se crea un folio operativo nuevo. Puede acompañar al resumen o generar el total mediante la suma del detalle.
- `pago`: un abono identificado por referencia, fecha e importe. La reclamación es opcional si el soporte solo informa un pago global de la radicación.
- `codigo`: permite acreditar únicamente el código de prestador existente.

Los grupos se identifican por médico + ARS + referencia original de radicación. Resumen y detalle se cotejan: nunca se suman entre sí. Se rechazan resúmenes repetidos, reclamaciones repetidas, pagos duplicados para la misma reclamación y detalles que superen el control.

En resumen/reclamación, **Pagado** significa acumulado al corte; en pago, el importe del abono. Los pagos detallados justifican el acumulado, no se suman nuevamente encima de él. Use **0** para confirmar ausencia de pago; vacío significa desconocido y bloquea la conformidad del saldo hasta rectificarlo con soporte.

**Saldo = facturado − pagado − retención − glosa aceptada − cobros posteriores.** Una diferencia no se convierte automáticamente en glosa. Un exceso se identifica como crédito por revisar. Los importes se expresan en DOP/RD$ y admiten hasta dos decimales.

## Auditoría y continuidad

La cartera se conserva en un registro de apertura separado: no vuelve a radicar lotes, no crea servicios ficticios, no registra de nuevo depósitos y no genera honorarios o facturas automáticamente. Los indicadores de producción nueva permanecen separados de los antecedentes.

Las coincidencias con radicaciones/reclamaciones existentes se señalan para resolver duplicidad. Marcar «ya registrada en SOFA» excluye ese antecedente de los totales de apertura. Los totales sin detalle, los pagos sin soporte completo y los cobros posteriores al inicio SOFA conservan alertas visibles.

Solo después de cotejar el saldo se habilita documentar un cobro con fecha posterior al corte. El sistema comprueba que no exista en Pagos SOFA y que la referencia no esté repetida para ese antecedente. Los honorarios sobre recuperaciones posteriores requieren revisar el alcance contratado; esta carga no los calcula ni los factura.

Administración puede rectificar cifras iniciales con soporte. Se conservan las filas originales, las correcciones previas a la autorización y la auditoría de cambios. Una rectificación exige otra revisión; una pantalla antigua no puede confirmar cifras que otro usuario modificó.

La carga reconoce el código de prestador como otorgado y la cartera revisada puede acreditar la operación previa en el onboarding. No sustituye los documentos, contratos ni otros requisitos de activación.
