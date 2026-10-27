# Corregir una cuenta propia asignada por error a un cliente

Versión candidata 5.22.5, rama feat/correccion-asignacion-usuarios. No desplegada.

## Diferencia respecto al listado agrupado

Agrupar cuentas no corrige una membresía equivocada. La nueva acción «Corregir asignación» abre una vista con identidad, asociación actual, cambio solicitado, impacto, motivo y confirmación escrita del correo.

En el caso planteado, la operación conserva la identidad y desactiva la membresía errónea de cliente; después asigna Administrador en el operador correspondiente. No se elimina el usuario de Auth ni se crean otra identidad o contraseña. La cuenta mantiene su estado activo/inactivo anterior. El servidor registra actor, motivo y accesos antes/después.

La función de asignación habitual conserva la prohibición de mezclar roles activos de cliente y personal. No se quitó esa protección para resolver este caso.

## Autorización y bloqueos

- Sesión real con aal2, perfil activo sin cambio de contraseña pendiente y membresía Super Admin del mismo operador.
- Rechazo de la propia cuenta, Super Admin actual/anterior, vínculos de médico, historia clínica habilitada/no verificable, otros accesos activos y asociaciones de otro operador.
- Vista previa con comprobación de versión; el servidor revalida después de bloquear identidad, perfil, organización y membresías.
- Motivo de al menos 12 caracteres y confirmación del correo obtenidos de la cuenta seleccionada por UUID, no búsqueda pública por correo.
- Operación transaccional. Si falla un trigger o auditoría, no queda aplicada parcialmente.
- Auditoría sin permisos directos para anon/authenticated; helper privado y RPC no ejecutable por anon.

Los vínculos inactivos se conservan como historia. El flujo no borra documentos, notas, pagos ni trazabilidad. No se agregó eliminación física de cuentas: este caso no la requiere, y una eliminación exigiría inventariar referencias y su efecto antes de aprobarla.

## Instalación y uso pendientes

El backend está en docs/sql/PROPOSED_user_access_repair.sql como candidato explícito para QA. No forma parte de las migraciones automáticas. Se debe contrastar con el esquema y triggers completos restaurados antes de instalarlo en producción. Publicar solo el frontend no instala esas funciones.

Una vez aprobado e instalado el backend en QA:

1. Entrar con un Super Admin distinto de la cuenta objetivo y MFA verificado.
2. Usuarios y accesos → cuenta → membresía de cliente → Corregir asignación.
3. Revisar UUID, correo, organización y bloqueos. Si existe un vínculo clínico, detener la corrección automática e investigar su origen.
4. Escribir el motivo, repetir el correo y confirmar el destino Administrador SOFA.
5. Comprobar el nuevo acceso, la membresía anterior inactiva y el registro de auditoría. Probar denegación del acceso anterior con una sesión real del usuario.

Si el backend no está habilitado, la interfaz lo indica y no intenta modificar la cuenta. La captura aportada no permite saber qué bloqueos reales tendrá esa cuenta.

## Evidencia reproducible

    bash scripts/run_user_repair_qa.sh
    node --test tests/frontend/user-accounts.test.mjs
    SOFA_PLAYWRIGHT_MODULE=/ruta/playwright/index.mjs node tests/browser/user-accounts.mjs

Pruebas locales: 17 aserciones SQL, 11 rechazos esperados, concurrencia de dos solicitudes con una sola corrección/auditoría, 11 pruebas frontend y navegador con formularios reales/RPC simuladas. PostgreSQL 17 desechable con datos sintéticos; no es una copia del esquema clínico completo.

El resultado no certifica todos los triggers, funciones de autorización o consultas de producción. Sigue pendiente QA real, restauración/rollback y validación de dependencias de la auditoría anterior. No se ejecutaron operaciones sobre la cuenta real del usuario.
