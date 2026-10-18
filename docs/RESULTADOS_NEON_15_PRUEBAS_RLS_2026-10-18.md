SOFA - RESULTADOS NEON / 15 PRUEBAS RLS / 2026-10-18

Entorno: Neon SoFa, neondb, sofa_test; datos ficticios; Supabase produccion sin cambios.

01 A lee A: PASS
02 A no lee B: PASS
03 B lee B: PASS
04 B no lee A: PASS
05 Staff sin MFA no lee: PASS
06 Staff con MFA simulada lee A: PASS
07 Staff con MFA simulada no lee B: PASS
08 Identidad desconocida bloqueada: PASS
09 Excepcion vencida bloqueada: PASS
10 Organizacion principal permitida: PASS
11 Cliente no accede a operador: PASS
12 MFA falsa no concede acceso: PASS
13 UPDATE ajeno afecta 0 filas: PASS
14 DELETE ajeno afecta 0 filas: PASS
15 INSERT ajeno denegado: PASS (insufficient_privilege capturado). La primera tentativa fallo por usar un ID explicito GENERATED ALWAYS; se corrigio. Se verifico una reclamacion A y una B.

HALLAZGO CRITICO: la funcion de ensayo sofa_test.allowed_org obtiene identidad de current_setting('sofa_test.user_id',true). El rol de ensayo puede modificar esta variable. Se demostro que al establecer doctor_b podia leer la reclamacion B. Los 15 resultados funcionales NO certifican resistencia a suplantacion de identidad.

Mitigacion: no exponer SQL directo a clientes; en Supabase usar auth.uid() con JWT verificado, y pruebas HTTP reales. En Neon emplear identidades/roles no intercambiables o una pasarela de autenticacion verificada. La bandera MFA del ensayo es simulada y tampoco es garantia de MFA real.

No se ejecutaron migraciones en Supabase. No se han certificado Auth, Storage, RPC ni Edge Functions. Los borradores de migracion no estan listos para despliegue.
