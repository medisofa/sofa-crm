# Revisión frontend SOFA — 27/10/2026

Alcance: copia local sofa-usuarios-seguro. Tres agentes: diseño visual, usabilidad por rol y seguridad de interfaz. Prioridad confirmada por usuario: Usuarios y accesos; temas claro y oscuro seleccionables.

## Aplicado localmente
- Consultorio/organización activa visible en cabecera móvil, sin ampliar organizaciones permitidas.
- Buscador destacado y accesos agrupados en bloques con separación visual; colores desde tokens de tema existentes.
- Explicación cuando acciones sensibles están protegidas o afectan a la cuenta propia.
- Confirmación omitida muestra error visible, anuncio y foco; sigue bloqueando la escritura.

## Próximas mejoras
1. Mostrar organización destino exacta en reparación, obtenida del backend autorizado; no inventar nombres.
2. Simplificar acciones secundarias manteniendo revalidación por UUID/organización/rol.
3. Corregir etiqueta de consultorio en pacientes: actualmente se construye con nombre del médico y puede sobrescribirse por organización.
4. Mejorar contraste de familias del menú y aclarar que sus números son cantidad de módulos, no pendientes.
5. Probar teclado, lector de pantalla y contexto médico activo en agenda y pacientes.

## Límites
No desplegado. Browser usa RPC simulados. No certifica autorización backend ni integridad de datos reales. No elimina usuarios, modifica roles ni instala SQL en producción.
