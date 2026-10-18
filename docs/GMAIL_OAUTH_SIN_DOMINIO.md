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
