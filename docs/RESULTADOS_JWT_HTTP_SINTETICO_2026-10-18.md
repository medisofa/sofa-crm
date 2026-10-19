SOFA / Iteracion JWT HTTP de ensayo - 2026-10-18

Repositorio: medisofa/sofa-crm, rama feature/gmail-oauth-staging.

Pruebas del archivo tests/security/test_jwt_http_harness.py reproducidas y ejecutadas localmente con pytest: 11 passed in 0.43s.

Casos: acceso propio A y B; denegacion cruzada A/B; token ausente; token expirado; emisor incorrecto; audiencia incorrecta; sujeto desconocido; firma manipulada; intento de elevacion de rol/tenant por claim.

Estas pruebas usan FastAPI TestClient, PyJWT RS256 y claves efimeras generadas durante el test. NO conectan con Neon ni Supabase y no constituyen una prueba end-to-end del sistema SOFA.

En Neon se volvio a confirmar por separado que el rol sofa_test_doctor_a, incluso tras establecer sofa_test.user_id='doctor_b', solo consulta reclamaciones A.

Pendiente: integrar un gateway JWT verificado con roles SQL restringidos y ejecutar pruebas HTTP reales contra un staging aislado; validar Auth, Storage, RPC y MFA de Supabase antes de produccion.

Costo adicional contratado: 0. Cambios Supabase produccion: 0.
