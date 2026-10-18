# SOFA — Política de mínimo privilegio para usuarios externos

## Regla obligatoria
1. Cada usuario externo (médico, secretaria/capturer, client) tiene **una sola organización cliente activa por defecto**.
2. Una segunda organización requiere **autorización explícita, documentada, con motivo, responsable, fecha de caducidad y alcance**.
3. La pertenencia a múltiples organizaciones no debe derivarse de compartir correo, proveedor o rol.
4. El personal interno SOFA pertenece a la organización operadora y puede acceder a múltiples clientes **solo según rol, MFA y asignaciones operativas**.
5. El acceso del personal interno no debe servir para conceder acceso multicliente a una cuenta externa.

## Plan de corrección seguro
- Inventariar usuarios externos con más de una membresía activa.
- Comparar cada membresía con contratos, autorización del médico y asignación de secretaria.
- Clasificar cada vínculo como autorizado, no autorizado o pendiente de validación.
- **No desactivar vínculos en producción sin identificar cuáles son legítimos.**
- Una vez aprobado, desactivar solo vínculos no autorizados, registrar antes/después y disponer de reversión.
- Implementar un mecanismo de excepción explícita y auditable antes de crear una restricción automática que podría bloquear operaciones existentes.
- Añadir pruebas de SELECT, INSERT, UPDATE, DELETE y Storage para dos clientes independientes; probar roles internos SOFA por separado.

## Estado
Política y procedimiento definidos en rama de desarrollo. **No aplicada aún como restricción SQL en producción**. La cuenta externa multiorganización detectada requiere revisión de legitimidad de cada vínculo. No se ha modificado ninguna membresía.
