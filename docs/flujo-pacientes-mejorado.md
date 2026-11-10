# Flujo de pacientes · 5.38.0

Las tarjetas presentan hora, nombre completo, médico, servicio y sala en bloques separados. Las acciones van debajo y ocupan el ancho de la tarjeta. Las columnas se adaptan al ancho disponible y en móvil se muestran en una columna.

Los filtros de consultorio y fecha tienen etiquetas visibles. La búsqueda local encuentra pacientes, médicos y servicios del día seleccionado. «Actualizar» permite recargar manualmente y se muestra la hora de la última actualización en Santo Domingo.

La actualización automática conserva los controles, la búsqueda, el foco y la sala escrita en el diálogo. Se cancela al abandonar la pantalla y descarta respuestas anteriores cuando cambian los filtros. Los errores no borran las tarjetas cargadas del mismo contexto; cambiar consultorio o fecha sí retira los datos del contexto anterior.

El tiempo transcurrido solo se muestra para la fecha actual de República Dominicana. Los registros de días anteriores se identifican como tales y las fechas históricas no acumulan minutos hasta hoy.

Se mantienen los cinco estados y las transiciones de Agenda: registrar llegada y volver a espera usan en_espera; llamar a consulta solicita la sala. Atendida sigue dependiendo de la reclamación o cobro. El modo soporte muestra el tablero sin acciones de escritura. No cambia el backend ni los permisos.

Validación con datos ficticios en Chromium: nombres largos, cinco tamaños de pantalla, búsqueda y foco durante la actualización, errores y reintento, diálogo estable, RPC exactos y soporte de solo lectura.
