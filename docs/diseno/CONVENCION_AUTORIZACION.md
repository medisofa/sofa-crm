# SOFA — Convención para funciones de autorización

Estado: convención adoptada para código nuevo. No reemplaza ni obliga a reescribir las funciones existentes que ya están probadas en producción.

## Por qué existe este documento

Auditoría de seguridad del 2026-10-28 (ver `docs/sql/` y las migraciones `20261028*` de `supabase/migrations/`): se encontró el mismo bug — un rol de staff sin fila en `staff_client_access` recibía acceso a **todos** los clientes en vez de a ninguno — **copiado en 5 funciones distintas** (`app.can_orgs`, `app.visible_org_ids`, `app.role_for_org`, `app.email_user_orgs`, `app.inbox_user_sees`). Cada una reimplementaba la misma regla de negocio a mano, en vez de delegar en un solo punto de verdad.

Al mismo tiempo, el catálogo de funciones de autorización creció a más de 30 nombres distintos para variantes del mismo concepto ("¿puede esta persona hacer X aquí?"):

```
app.can · app.can_operator · app.can_orgs · app.is_staff · app.role_for_org
app.capturer_can · app.capturer_document_ok · app.capturer_document_delete_ok
app.capturer_line_ok · app.capturer_storage_ok · app.capturer_storage_delete_ok
app.capturer_submission_ok · app.claim_dossier_ok · app.claim_tariff_ok
app.clinical_mfa_ok · app.clinical_patient_ok · app.clinical_require
app.collection_access · app.consultorio_access · app.direction_require
app.ecf_require · app.hab_access · app.patient_access · app.plan_access
app.pm_require · app.portal_require · app.portal_subject_ok · app.rbac_admin_ok
app.sa_require · app.sales_require · app.sub_require_admin · app.supply_access
app.ars_admin_require · app.bank_require · app.case_staff · app.legal_audit_staff
app.recon_role · app.inbox_role · app.email_admin_op · app.tariff_admin_check
```

Ninguna de estas es incorrecta por sí sola — todas, revisadas una por una, están bien escritas. El problema es que **no hay una sola función central** para la regla más común ("¿esta persona tiene uno de estos roles en esta organización?"), así que cada módulo nuevo termina escribiendo la suya. Eso hace que:

- un bug en esa regla (como el de arriba) haya que corregirlo N veces en vez de una,
- auditar el sistema tome mucho más tiempo (hay que descubrir cada nombre nuevo antes de poder revisarlo),
- sea más fácil que un módulo nuevo quede sin ninguna de las dos — ni usando la función central ni creando la suya — por no saber que debía hacerlo.

## La regla para código nuevo

**Antes de escribir una función de autorización nueva, usa una de estas tres primero:**

| Función | Para qué |
|---|---|
| `app.can(p_org uuid, p_roles text[])` | "¿Tiene uno de estos roles en esta organización (cliente u operador)?" — el caso más común. |
| `app.can_operator(p_operator uuid, p_roles text[])` | Igual que `can`, pero cuando la organización es siempre la operadora de SOFA (no un cliente). |
| `app.is_staff(p_roles text[])` | "¿Es personal de SOFA con uno de estos roles?", sin importar en qué cliente. |

Si tu caso es exactamente "¿tiene este rol en esta org?", **no crees una función nueva**: llama a `app.can()` directo desde tu política RLS o tu función `SECURITY DEFINER`.

### Cuándo sí se justifica una función propia

Cuando la autorización depende de algo más que organización + rol — por ejemplo, si la secretaria está asignada a ese médico específico (`capturer_scopes`), si el expediente tiene los documentos completos, o si la historia clínica de ese consultorio está activada. En ese caso:

1. **La función debe delegar en `app.can`/`app.can_operator`/`app.is_staff` para la parte de organización+rol**, y agregar solo la condición extra encima — no reimplementar la consulta a `organization_users` desde cero.
2. **Nombra la función `app.<módulo>_access(...)` o `app.<módulo>_require(...)`**, siguiendo el patrón ya establecido:
   - `_access` / `_ok` / `_can`: devuelve `boolean`, para usar dentro de una política RLS (`USING app.mi_modulo_access(...)`).
   - `_require`: lanza una excepción con mensaje explicando qué falta, para usar dentro de una función `SECURITY DEFINER` que hace una acción (igual que `app.clinical_require`).
3. Si la regla de negocio detrás de la función (no el nombre, la regla) ya existe en otra función del catálogo de arriba, **reusa esa función en vez de escribir una paralela** — aunque el nombre no encaje perfecto. Un nombre un poco genérico es mejor que una regla duplicada.

### Antes de dar por terminada una función nueva

- [ ] ¿Ya existe algo en la tabla de arriba, o en el catálogo de 30, que resuelva esto? Si sí, úsalo.
- [ ] Si es un caso nuevo, ¿delega la parte de organización+rol en `app.can`/`app.can_operator`/`app.is_staff` en vez de volver a escribir la consulta a `organization_users`?
- [ ] ¿El nombre sigue el patrón `_access`/`_require`/`_ok`/`_can` según si devuelve boolean o lanza excepción?
- [ ] ¿Tiene `SET search_path = ''` (toda función `SECURITY DEFINER` del proyecto lo exige)?
- [ ] ¿Está probada contra el esquema real antes de instalarla en producción (no solo en una copia aislada)?

## Lo que este documento NO pide

No pide reescribir las ~30 funciones existentes ni unificar sus nombres — están probadas, funcionando, y tocarlas sin necesidad agrega riesgo sin agregar valor. Esta convención es **hacia adelante**: para que el catálogo deje de crecer sin control y el próximo bug de este tipo se corrija en un solo lugar.
