# SOFA MVP v1

Nueva base técnica mínima y escalable para SOFA. No reemplaza ni despliega la aplicación actual. Se construye en una rama aislada para validar antes de cualquier cambio en producción.

## Stack
- Next.js + TypeScript
- Supabase Auth + PostgreSQL + RLS + Storage
- Zod para validación de entradas
- API versionada /api/v1

## Arranque
1. Copia `.env.example` a `.env.local`.
2. Configura solo URL y clave publicable de Supabase.
3. `npm install`
4. `npm run dev`

## Principios
- Multi-tenant por organization_id.
- RLS como control de acceso principal.
- Los endpoints usan el JWT del usuario; no usan service_role.
- Escrituras sensibles por RPC transaccional.
- Sin secretos ni datos de pacientes en el repositorio.
- Auditoría de eventos sin duplicar contenido clínico.

## Gate
No aplicar `supabase/migrations/001_core.sql` a producción hasta disponer de backup restaurable y pasar pruebas A/B de aislamiento, JWT, Storage, RPC y flujo completo de reclamación.
