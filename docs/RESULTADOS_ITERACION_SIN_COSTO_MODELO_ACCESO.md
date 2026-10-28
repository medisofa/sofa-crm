# SOFA — Resultado de iteración de pruebas sin costo (2026-10-18)

## Entorno y límites
- Sin rama Supabase de pago; no se modificó producción.
- Se ejecutó localmente `python test_policy.py` usando únicamente `unittest` de Python.
- Resultado: **4 pruebas / 4 aprobadas**.
- Archivo versionado: `tests/security/test_external_membership_policy_model.py`.
- Son pruebas de **modelo de autorización**, no pruebas de RLS real ni certificación del MVP.

## Inventario de membresías activas, lectura de producción
- Organizaciones cliente: `capturer` 2 membresías (2 usuarios), `client` 10 membresías (8 usuarios).
- Organización operadora: `admin` 1, `assistant` 2, `auditor` 1, `billing` 1, `glosas` 1, `super_admin` 1.
- Un usuario externo mantiene varias membresías; se requiere distinguir acceso de prueba de acceso legítimo antes de limpieza.

## Defecto crítico que debe corregirse antes de desplegar el SQL propuesto
El borrador `docs/sql/PROPOSED_external_single_org_guard.sql` únicamente valida la excepción **al crear/actualizar membresías**. Una excepción que expire posteriormente no desactiva automáticamente la membresía; por tanto las políticas de lectura actuales podrían seguir concediendo acceso. **No desplegar este borrador sin integrar el control de vigencia en la resolución de organizaciones visibles, o una revocación transaccional y comprobable.**

Además, la rama de excepción de staff en el borrador comprueba una membresía operadora; antes de activarla debe verificarse que un usuario externo no puede autocrearse una membresía de operador por API/RPC. La prueba de staff es un modelo simplificado y no representa íntegramente `staff_client_access`.

## Puertas de salida
1. Respaldo de producción actual, completo y **restauración verificada**, incluyendo Auth y objetos Storage.
2. Inventario aprobado de qué identidades y registros son realmente de prueba.
3. Migración revisada que impida acceso tras caducar excepciones, sin romper el personal interno.
4. Pruebas con JWT reales y RLS, CRUD, RPC, Storage, Edge Functions, staff con MFA.
5. Solo entonces limpieza selectiva y certificación GO.

## Estado
Cero gastos, cero modificaciones en producción, cuatro pruebas de modelo aprobadas; **NO certificado**.
