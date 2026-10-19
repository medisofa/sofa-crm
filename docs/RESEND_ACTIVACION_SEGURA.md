# SOFA · Activación segura de Resend (preparación, NO producción)

Proyecto exclusivo: `bpwjhgpzhzhiocoxrvzq` · Repositorio `medisofa/sofa-crm`.
La función actualmente desplegada sigue siendo la versión simulada. Esta rama no debe fusionarse/desplegarse automáticamente sin pruebas.

## 1. Requisitos pendientes
- Adquirir o controlar un dominio corporativo (Gmail no equivale a dominio verificado).
- Verificar dominio en Resend, DNS SPF/DKIM y DMARC conforme a sus instrucciones.
- Crear `RESEND_API_KEY` restringida; guardarla solo en Supabase Edge Function Secrets.
- Definir `CORREO_REMITENTE=SOFA <avisos@dominio-propio>`.
- Mantener `CORREO_PROVEEDOR=simulado` y `CORREO_ENVIO_REAL_HABILITADO=false` hasta la autorización.
- Confirmar `CORREOS_SECRETO` y la autenticación del programador; el despliegue actual usa `verify_jwt=true`, aunque un comentario antiguo afirmaba lo contrario.

## 2. Despliegue controlado
1. Revisar cambios y compilar la función con Deno/Supabase CLI.
2. Validar que los RPC `email_claim_batch`, `email_mark_sent` y `email_mark_failed` conservan contratos y permisos.
3. Revisar cola pendiente: no procesar mensajes anteriores como prueba sin consentimiento.
4. Desplegar primero en un entorno de pruebas aislado, con `verify_jwt=true` y sin secretos de producción.
5. Usar solo destinatarios de prueba consentidos; comprobar idempotencia, errores HTTP 429/5xx, timeout y trazabilidad.
6. En producción, configurar secretos de forma privada. Confirmar dominio verificado y remitente válido.
7. Autorizar explícitamente activación, cambiar proveedor a `resend` y habilitar envío real; iniciar con lotes pequeños.
8. Comprobar mensajes recibidos y entregabilidad. `email_mark_sent` solo confirma aceptación del proveedor, no entrega final.
9. Para revertir, establecer `CORREO_ENVIO_REAL_HABILITADO=false` antes de cambiar proveedor o versión.

## 3. Criterios de salida
- Prueba real en buzón autorizado, sin datos de pacientes.
- Protección del endpoint y del programador comprobada.
- Reintentos sin duplicados, auditoría sin claves ni contenido sensible.
- Sin activación de campañas ni envío masivo.
- Validación de webhooks autenticados para eventos de entrega/rebote en iteración posterior.

## 4. Limitaciones
El código Resend está preparado, no probado en runtime ni desplegado. No se modificaron tablas, credenciales, colas ni configuraciones de Supabase. No tocar el proyecto HemoCura.
