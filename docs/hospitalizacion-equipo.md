# Hospitalización y seguimiento de SoFa · 5.35.0

El médico registra el centro, paciente, teléfono de contacto opcional, ARS (o privado), ingreso, alta opcional y observaciones administrativas. Puede guardar el borrador y agregar varios servicios con sus fechas, cantidades e importes. El guardado del encabezado y teléfono es atómico: si falla, no queda un encabezado duplicado o parcial.

**Enviar y avisar a SoFa** requiere al menos un servicio y fecha de ingreso. El envío deja el reporte en firme y crea una notificación interna para Administración, Operaciones y Facturación autorizadas en ese cliente. El aviso no incluye nombre, documento ni teléfono del paciente. Abrirlo lleva al reporte dentro de Hospitalización. El mismo envío no duplica avisos.

El equipo ve reportes enviados dentro de su acceso, con centro, médico, datos administrativos y servicios. Esta supervisión es de solo lectura; no modifica el reporte ni accede a notas o documentos del paciente desde esta pantalla. No se ha añadido una asignación de responsable ni estados operativos adicionales: se conservan los estados del reporte existentes.

**Gestionar centros** permite a Administración y Operaciones agregar centros y asociarlos a los médicos de sus clientes autorizados. Seleccione el médico, agregue el centro al catálogo, marque los centros donde trabaja, elija principal si corresponde y pulse **Guardar centros del médico**. Facturación tiene lectura hospitalaria, sin permisos para gestionar centros.

El modo **Ver como** conserva su lectura acotada al consultorio y no habilita modificaciones. Salga del modo soporte para gestionar centros con su perfil de SoFa.

Se probaron el reporte completo, dos servicios, importes actualizados, recuperación de errores, fechas, notificaciones sin duplicados, acceso entre roles y clientes, y pantallas de 320/390/1440 px con datos ficticios. Las pruebas de base de datos se revirtieron sin conservar registros de prueba.
