# SOFA · Edge Functions

Fuentes versionadas de las Edge Functions que corren en Supabase.
Cada carpeta corresponde a un `function_slug` desplegado con el mismo nombre.

## Cómo deberían estar sincronizadas

**Regla de oro**: lo que está en producción tiene que estar en este directorio, y viceversa.

| Función | Estado actual |
|---|---|
| `admin-users` | ✅ sincronizada (redesplegada 2026-11-12 tras incidente de deploy cruzado con HemoCura) |
| `crear-usuario` | ✅ sincronizada (snapshot desde prod v11 — era orphan hasta 5.34.1) |
| `restablecer-clave` | ✅ sincronizada (snapshot desde prod v4 — era orphan hasta 5.34.1) |
| `market-intel` | ✅ sincronizada (snapshot desde prod v5 — era orphan hasta 5.34.1) |
| `enviar-correos` | ⚠ **drift — repo adelantado**. El repo implementa 3 proveedores (`Simulado`, `Resend`, `Gmail`); producción sigue en v1 con solo `Simulado` (desde 2026-10-21). Antes de desplegar `resend` o `gmail` como proveedor activo hay que: (1) configurar el secreto correspondiente en Supabase, (2) redesplegar `enviar-correos` desde este repo, (3) cambiar `CORREO_PROVEEDOR`. |

## Convención para despliegues

Para que no vuelva a ocurrir el incidente del 10-nov (código de otro proyecto encima de SOFA):

1. **Siempre desplegar desde este repo**, con el `project_ref` correcto:
   ```
   supabase functions deploy <nombre> --project-ref bpwjhgpzhzhiocoxrvzq
   ```
2. **Nunca** desde un checkout de otro proyecto que casualmente tenga el mismo slug.
3. Cada redeploy manual debería acompañarse de un PR que actualice el archivo correspondiente aquí, aunque el cambio sea solo un comentario de bump de versión.

## Revisión periódica

El PR que detectó el incidente (de un fork de auditoría en sesión 5.34.1) comparó los SHA256 (`ezbr_sha256`) de cada función desplegada contra lo versionado. Un script simple:

```bash
# Listar desplegadas
curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  "https://api.supabase.com/v1/projects/bpwjhgpzhzhiocoxrvzq/functions" \
  | jq -r '.[] | .slug'

# Comparar contenido
# (requiere el token con permisos sobre Edge Functions)
```

Se podría automatizar en un workflow de CI como el de smoke import check (ver `.github/workflows/smoke-import-check.yml`), pero necesita un token guardado como secret del repo.
