# ARS Portal Bridge — Diseño técnico

**Fecha:** 2026-11-11  
**Versión objetivo:** 5.40.0  
**Estado:** Implementado

---

## Contexto

SOFA CRM registra reclamaciones médicas para proveedores dominicanos. Cada ARS (Administradora de Riesgos de Salud) tiene un Portal PSS (Portal de Servicios en Salud) donde se solicitan autorizaciones. El operador actualmente copia datos manualmente: nombre, NSS, cédula, diagnóstico CIE-10, código del procedimiento.

Este diseño agrega un "puente" que copia esos datos al portapapeles y abre el portal en una pestaña nueva con un solo clic.

---

## Decisiones de diseño

| Pregunta | Decisión | Razón |
|---|---|---|
| ¿Config estática o editable por admin? | **Editable por admin** (columna `portal_url` en tabla `ars`) | Sin deploy para actualizar URLs. Patrón ya establecido (`submission_channel`). |
| ¿Dónde aparece el botón? | **Solo en `capture.js`** | Es el único punto donde el operador necesita ir al portal antes de capturar la autorización. |

---

## Componentes

### 1. Migración de BD: `supabase/migrations/238_ars_portal_bridge.sql`

**Cambios:**
1. `ALTER TABLE public.ars ADD COLUMN IF NOT EXISTS portal_url text;`
2. `CREATE OR REPLACE FUNCTION public.ars_save(...)` — agrega `p_portal_url text DEFAULT NULL`; en INSERT incluye `portal_url`; en UPDATE usa `CASE WHEN p_portal_url IS NOT NULL THEN nullif(trim(p_portal_url),'') ELSE portal_url END`.
3. `CREATE OR REPLACE FUNCTION public.ars_catalog(...)` — agrega `'portal_url', a.portal_url` al `jsonb_build_object`.

**Seguridad:** Ambas funciones conservan `SECURITY DEFINER` y el guard `app.ars_admin_require()` existente. Sin nueva superficie de acceso.

**Columna nullable:** `portal_url` acepta NULL. Las ARS sin URL configurada simplemente no muestran el botón en captura.

### 2. `js/config/ars-portals.js` (nuevo)

```js
export const ARS_PORTAL_DEFAULTS = {};
```

Vacío por defecto. Los administradores llenan las URLs desde el módulo de ARS.

### 3. `js/services/ars-bridge.js` (nuevo)

Funciones exportadas:
- `launchARSPortal(ars, claim)` — resuelve URL, copia payload, abre tab, retorna bool
- `buildPortalPayload(ars, claim)` — construye texto plano con los datos del claim
- `resolvePortalUrl(ars)` — prioridad: portal_url DB → ARS_PORTAL_DEFAULTS → null

Payload incluye: `ARS`, `NSS`, `Cédula`, `Paciente`, `Fecha`, `Diagnóstico CIE-10`, `Servicio`, `SIMON`, `CUPS` (omite campos vacíos).

Fallback de clipboard: `execCommand('copy')` vía textarea temporal si `navigator.clipboard` rechaza.

Fallback de popup bloqueado: toast con la URL como texto para abrir manualmente.

### 4. `js/services/claims.js` — proyección `activeArs()`

```js
// Antes:
export async function activeArs() {
  return must(await sb().from('ars').select('id, code, name').eq('is_active', true).order('name'));
}

// Después:
export async function activeArs() {
  return must(await sb().from('ars').select('id, code, name, portal_url').eq('is_active', true).order('name'));
}
```

### 5. `js/modules/ars.js` — formulario de edición

**En `arsForm(a)`:**
- Nuevo campo `const portalUrl = h('input', { type: 'url', value: a?.portal_url || '', maxlength: '300', placeholder: 'https://portalpss.arsejemplo.com.do/' })`
- Se agrega al grid de campos junto a `channel`
- En `rpc('ars_save', {...})` se agrega `p_portal_url: portalUrl.value`

**En `card(a)`:**
- Si `a.portal_url`, muestra una pill con el dominio de la URL

### 6. `js/modules/capture.js` — panel puente dinámico

**En el template HTML:**
```html
<!-- Reemplaza el <div class="hint"> estático: -->
<div id="arsPortalBridge" style="grid-column:1/-1" aria-live="polite"></div>
```

**Nueva función `updatePortalBridge()`:**
Consulta `S.ars.find(a => a.id === el('c_ars').value)` para obtener `portal_url`.
- Sin ARS o sin URL: renderiza el hint original con texto de elegibilidad
- Con URL: renderiza panel azul con texto de instrucción + botón "Ir al portal ARS"

El botón llama a `launchARSPortal(selectedArs, { member, patientDoc, patientName, serviceDate, diagnosis, procedureName: S.service?.name, simon: S.service?.simon, cups: S.service?.cups })`.

**Nuevo watcher:** `el('c_ars').addEventListener('change', updatePortalBridge)`.

**Import agregado:** `import { launchARSPortal } from '../services/ars-bridge.js';`

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---|---|
| `supabase/migrations/238_ars_portal_bridge.sql` | Nuevo — migración |
| `js/config/ars-portals.js` | Nuevo — config |
| `js/services/ars-bridge.js` | Nuevo — servicio |
| `js/services/claims.js` | Modifica 1 línea — proyección |
| `js/modules/ars.js` | Modifica ~12 líneas — UI admin |
| `js/modules/capture.js` | Modifica ~20 líneas — UI operador |

---

## Lo que NO cambia

- RPC `capture_claim` — sin modificar
- Función `captureClaim()` — sin modificar
- RLS existente — sin modificar
- Flujo de guardado de reclamaciones — sin modificar
- El campo `#c_auth` y `#c_authdate` — sin modificar (el número de autorización lo sigue ingresando manualmente el operador después de ir al portal)

---

## Casos borde

| Caso | Comportamiento |
|---|---|
| ARS sin `portal_url` y sin default en config | Muestra hint estático. Sin botón. |
| `navigator.clipboard` rechaza | Fallback `execCommand`. Toast de éxito igual. |
| Navegador bloquea `window.open` | Toast con URL como texto para copiar/abrir manualmente. |
| Operador no ha llenado NSS o paciente | El botón está disponible de todas formas (los campos vacíos se omiten del payload). |
| ARS desactivada (no aparece en captura) | Irrelevante — el select solo muestra ARS activas. |

---

## Flujo del usuario

1. Operador selecciona médico, ARS y fecha → el panel de puente aparece si hay URL configurada
2. Llena nombre del paciente y NSS
3. Pulsa **"Ir al portal ARS"**
4. Clipboard recibe los datos formateados
5. Se abre el portal de la ARS en nueva pestaña
6. Toast: "Datos copiados al portapapeles — Portal PSS [ARS] abierto"
7. El operador pega los datos en el portal, obtiene el número de autorización
8. Vuelve a SOFA, escribe el número en `#c_auth` y pulsa Guardar
