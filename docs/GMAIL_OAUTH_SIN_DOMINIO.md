# SOFA · Gmail OAuth sin dominio propio (preparación, NO desplegado)

Remitente: `medicasofa@gmail.com`. No utilizar Resend como remitente Gmail no verificado.

## Requisitos
1. Acceder a Google Cloud Console con la cuenta que administrará la integración.
2. Crear un proyecto específico de SOFA y habilitar **Gmail API**.
3. Configurar la pantalla de consentimiento OAuth, usuarios de prueba y permisos. Solicitar únicamente `https://www.googleapis.com/auth/gmail.send`.
4. Crear credenciales OAuth apropiadas para el flujo de autorización de servidor y obtener un refresh token de `medicasofa@gmail.com`. La política de consentimiento en modo prueba puede hacer que el refresh token caduque; verificar antes de producción.
5. Guardar en **Supabase SOFA** Edge Functions Secrets: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`, `GMAIL_REMITENTE=medicasofa@gmail.com`, `CORREO_DESTINATARIOS_PRUEBA=medicasofa@gmail.com`.
6. Conservar `CORREO_PROVEEDOR=simulado` y `CORREO_ENVIO_REAL_HABILITADO=false` hasta pruebas y aprobación.
7. Validar seguridad del programador: despliegue actual tiene `verify_jwt=true` y POST requiere además `x-sofa-secreto`. No desactivar controles.
8. Realizar pruebas aisladas y con una cola de prueba; el procesador actual consume lotes de la cola compartida. La allowlist rechaza otros destinatarios pero los marca como fallidos, por lo que **no se debe ejecutar sobre la cola productiva sin aislamiento**.
9. Validar límites de Gmail, MIME, manejo de tokens, errores y duplicados. Gmail API no ofrece por sí sola garantía de idempotencia para reintentos tras timeout.
10. Solo después de revisión y autorización, desplegar, configurar `CORREO_PROVEEDOR=gmail` y activar con lotes mínimos. No usar para campañas masivas ni enviar datos clínicos sensibles.

## Estado
Código preparado en rama de GitHub, sin credenciales, sin despliegue y sin envíos. El usuario debe autorizar OAuth y crear sus secretos en Google Cloud/Supabase. HemoCura no se modifica.

## Prueba aislada nueva (sin consumir cola de producción)
Se añadió modo `prueba_gmail` a `enviar-correos`. Está bloqueado salvo que `CORREO_PRUEBA_HABILITADA=true` y el destinatario esté en `CORREO_DESTINATARIOS_PRUEBA`.
- POST JSON: `{"modo":"prueba_gmail","destinatario":"medicasofa@gmail.com"}`.
- Requiere JWT válido en Authorization y encabezado `x-sofa-secreto`. Enviar desde un cliente de pruebas seguro, nunca desde el frontend público.
- El cuerpo y asunto son fijos, sin información clínica. No se invoca `email_claim_batch` ni se cambia `email_queue`.
- El envío de prueba es **real** si se habilita la bandera y las credenciales; solicitar autorización antes de ejecutar.
- Después de una prueba aprobada, volver `CORREO_PRUEBA_HABILITADA=false`.
- En el último corte de auditoría había **6 correos pendientes** en la cola de producción: no activar el procesamiento normal sobre ellos hasta revisarlos.

## Estado de secretos
Este conector no dispone de una acción para escribir secretos de Edge Functions. El propietario debe configurarlos desde el panel privado de Supabase. No compartir los valores en chats, commits o capturas.

## Iteración de endurecimiento
- Se agregó `CORREO_PROCESAR_COLA_HABILITADO`, cuyo valor por defecto es distinto de `true`: no consume cola productiva aunque se invoque POST normal.
- La prueba aislada `modo=prueba_gmail` continúa sujeta a `CORREO_PRUEBA_HABILITADA=true`, lista de destinatarios y autenticación.
- Se reforzó codificación UTF-8 y validación de direcciones.
- No confundir preparación con certificación: faltan tests automatizados y revisión de tipos/compilación de Deno, credenciales OAuth y validación de errores reales.
- Para procesar la cola productiva se requiere autorización separada y `CORREO_PROCESAR_COLA_HABILITADO=true`; antes revisar los seis registros pendientes detectados y su legitimidad.
