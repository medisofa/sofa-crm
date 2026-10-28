# Usuarios y accesos: una fila por cuenta

Implementación local de frontend, versión 5.22.4. No publicada.

El listado anterior pintaba cada fila de users_overview/listMemberships como usuario independiente. Una misma cuenta con varios roles u organizaciones se repetía y sus acciones globales aparecían varias veces. La lectura del código identifica el problema de presentación, pero no demuestra duplicidad de cuentas Auth en producción.

## Cambio

- Agrupación por user_id, nunca por nombre o correo.
- Roles, organización, estado y validación dentro de cada cuenta.
- Membresías repetidas con igual user_id/organización/rol se muestran una vez. Si sus estados o datos de validación difieren, se avisa de contradicción y se bloquean acciones ambiguas.
- Restablecimiento, envío de acceso y activación/desactivación se presentan una vez por cuenta según los permisos existentes. Cambio de rol y validación siguen vinculados a un acceso concreto.
- La protección de la propia cuenta y de Super Admin considera todos los accesos, incluidos los que no coinciden con el filtro.
- Estados activos/inactivos mezclados no se convierten en un estado global supuesto; se oculta activación global ambigua. Validación de un acceso no activa una cuenta con múltiples membresías.
- Identificadores distintos con igual correo no se fusionan. Se señalan y no se ofrecen acciones basadas en ese correo ambiguo.
- Búsqueda por nombre, correo e identificador; conteos de cuentas únicas y accesos; filtros combinados deben coincidir en el mismo acceso.
- Exportación CSV de las cuentas filtradas, una fila por cuenta con todos sus accesos. Categorías pueden solaparse porque una cuenta puede tener varias membresías.
- Validación individual identifica usuario+rol+organización, evitando seleccionar por accidente el primer acceso del mismo rol en otro consultorio.

No se borraron usuarios, perfiles, membresías ni datos; no se modificaron los controles que separan personal SOFA de médicos/secretarias ni las autorizaciones del servidor.

## Validación

Seis pruebas nuevas de agrupación, correo compartido, datos contradictorios, estados mixtos, filtros y protección de Super Admin. Prueba de Chromium con módulos reales y RPC simulados: 9 filas fuente se muestran como 6 cuentas con 8 accesos distintos; cuenta con dos consultorios aparece una vez; acciones únicas; validación dirigida al consultorio elegido; protección bajo filtros; búsqueda, CSV agrupado y móvil sin desborde.

Las capturas de artifacts/sofa-usuarios utilizan datos ficticios. No se ejecutaron envíos, restablecimientos, cambios de rol ni activaciones sobre una base real. Falta comprobar el RPC y el flujo con sesiones reales en QA antes de publicar.


## Candidato aislado sobre main actual

Base verificada: aeb3c32, repositorio medisofa/sofa-crm. Rama local: fix/usuarios-cuentas-seguras. Esta copia no incluye los demás rediseños ni las propuestas SQL del checkout anterior.

Validación de esta entrega: 10 pruebas unitarias de cuentas y acciones; prueba reproducible de Chromium en tests/browser/user-accounts.mjs con RPC simuladas; todos los módulos JavaScript del candidato analizados sin errores de sintaxis; git diff --check sin errores. Las 61 pruebas mencionadas anteriormente pertenecían al checkout de trabajo más amplio, no a este candidato aislado.

Refuerzos: las acciones resuelven cuenta y membresía desde el modelo cargado; no usan correo, nombre ni estado activo del botón como fuente de identidad. Se rechazan selecciones inexistentes, acciones desconocidas, la propia cuenta, Super Admin protegido y roles sin capacidad. La activación desde validación exige disponibilidad de readiness y reporte de roles; si faltan, queda incompleta y no activa. La selección de secretarias evita usar resultados de otro consultorio que lleguen tarde y conserva asignaciones fuera de la lista editada.

Límite del API existente: set_capturer_scope reemplaza una lista global por usuario. Se relee y preserva el alcance ajeno antes de enviar, pero no se certifica atomicidad frente a dos editores concurrentes. Debe probarse en QA y, si se permite concurrencia, resolverse con control transaccional del servidor.

Publicación: GitHub Pages usa main / y app.sofamedica.com. La cuenta de GitHub conectada tiene pull=true y push=false. El archivo público users.js consultado no incluía groupUserAccounts y el helper nuevo respondió 404. No se ejecutaron push ni despliegue.

Pendientes de aceptación: sesiones reales de dos organizaciones en QA, denegación por servidor de consultas/escrituras ajenas, compatibilidad de RPC, MFA/perfil inactivo, cambios de rol válidos e inválidos y concurrencia de asignaciones. Ninguna prueba simulada permite declarar seguro todo el sistema ni levantar el NO-GO anterior.

Reproducción:

    node --test tests/frontend/user-accounts.test.mjs
    SOFA_PLAYWRIGHT_MODULE=/ruta/playwright/index.mjs node tests/browser/user-accounts.mjs

El navegador puede configurarse con SOFA_CHROMIUM. La prueba bloquea tráfico externo y usa datos ficticios. No envía invitaciones, cambios de contraseña ni cambios de rol reales.
