# SOFA · Soluciones de Facturación Médica — Frontend

Aplicación web estática (HTML + CSS + JavaScript con ES Modules) que se publica en **GitHub Pages** y usa **Supabase** como backend (Auth, PostgreSQL con RLS y Storage).

- Versión: **1.4.0** (Iteración 14 · Post-radicación, trazabilidad y honorarios)
- Librería: `@supabase/supabase-js` **2.117.2**, copia local en `vendor/` (sin CDN externo)
- Sin frameworks ni proceso de compilación: los archivos se suben tal cual.

## Seguridad en una línea

El navegador solo conoce la **URL del proyecto** y la **clave publicable** (`sb_publishable_…`). Quién ve qué lo decide PostgreSQL con Row Level Security. **Nunca** subas a este repositorio la contraseña de la base de datos, la Secret key (`sb_secret_…`) ni la `service_role`: la aplicación se niega a arrancar si detecta una de ellas en `js/config.js`.

## Estructura

```text
sofa-crm/
├── index.html            Aplicación (protegida: exige sesión)
├── login.html            Iniciar sesión · recuperar contraseña · nueva contraseña
├── manifest.json, sw.js  PWA (solo cachea el cascarón, nunca datos)
├── 404.html, .nojekyll   Ajustes para GitHub Pages
├── css/                  variables.css · components.css · app.css
├── js/
│   ├── config.js         ← ÚNICO archivo que debes editar
│   ├── supabase.js       Cliente y verificación de claves
│   ├── auth.js           Sesión, contexto (my_context), inactividad
│   ├── router.js         Rutas por hash (#/modulo)
│   ├── app.js            Arranque y layout
│   ├── login.js          Pantallas de acceso
│   ├── services/         Consultas a Supabase por dominio
│   ├── modules/          Pantallas (inicio, clientes, codificación, ARS, usuarios, parámetros, perfil, diagnóstico)
│   └── utils/            dom (anti-XSS), ui (estados y errores), permissions, formatters, validation
├── assets/icons/         Íconos de la app
└── vendor/               supabase-js 2.117.2 (licencia MIT incluida)
```

Los scripts SQL (`001`–`029`, más `026_revertir.sql` y `028_revertir.sql`) y las Edge Functions `admin-users` y `market-intel` se entregan aparte, en la carpeta `sofa-supabase/`, y los scripts de respaldo en `respaldos/`. **No los subas a un repositorio público**: describen las reglas internas del negocio. Guárdalos en tu equipo o en un repositorio privado.

## Instalación (resumen)

1. Edita `js/config.js` con tu Project URL y Publishable key (Supabase › Project Settings › API Keys).
2. Crea el repositorio `sofa-crm` en GitHub y sube el contenido de esta carpeta.
3. Activa GitHub Pages: Settings › Pages › Deploy from a branch › `main` › `/ (root)`.
4. En Supabase › Authentication › URL Configuration pon la URL de Pages como Site URL y agrega `https://TU-USUARIO.github.io/sofa-crm/**` en Redirect URLs.
5. Abre `https://TU-USUARIO.github.io/sofa-crm/` e inicia sesión con tu usuario Super Admin.

La guía paso a paso con capturas de verificación está en `GUIA_Iteracion3.html`, que viene en el paquete de entrega.

## Publicar una versión nueva

1. Sube los archivos modificados.
2. Cambia `VERSION` en `sw.js` (por ejemplo `sofa-shell-1.2.1`) y `APP_VERSION` en `js/version.js` (no en `config.js`).
3. Los usuarios verán el aviso "Hay una versión nueva de SOFA. Recarga la página".

## Módulos disponibles en 1.4.0

| Módulo | Estado |
|---|---|
| Login, recuperación de contraseña, cierre por inactividad (30 min) | Listo |
| Inicio: cifras por rol, seguimientos de hoy y plan de 90 días | Listo |
| Pipeline (8 etapas), prospectos con aviso de duplicados, diagnóstico de fugas, conversión a cliente | Listo |
| Clientes PSS: alta directa, ficha con prestadores, códigos por ARS, contactos, oportunidades, tareas e historial | Listo |
| Contactos · Aliados referidores · Tareas | Listo |
| Codificación y tarifarios: conceptos, códigos, tarifas con vigencia, negociadas, importación y brechas | Listo |
| ARS | Listo |
| Usuarios y roles: invitación por correo (Edge Function admin-users), cambio de rol, revisión de accesos · Parámetros · Mi perfil · Diagnóstico | Listo |
| Radicaciones (lote médico × ARS × período): validación de 13 reglas, factura fiscal del contador con bloqueo por diferencia (D2), método/lote/evidencia de entrega, pago distribuido por reclamación (D4), carga masiva, checklist, expediente digital, estados hasta Radicada | Listo |
| Documentos | Listo |
| Glosas: registro por servicio, apelación, resultado parcial, Pareto y tasa por ARS | Listo |
| Pagos: reparto entre radicaciones, conciliación por ARS, por cobrar, anulación | Listo |
| Honorarios SOFA: cuotas, % cobrado, facturas, cobros y NCF | Listo |
| Trabajo de hoy · Dashboard (operación y crecimiento) · Aging · 7 reportes con CSV e impresión | Listo |
| Habilitación MISPAS: checklist por tipo, semáforo, etapas con reglas, evidencias, informe y renovación | Listo |
| Inteligencia de mercado: noticias del sector (Edge Function market-intel), competencia y referentes, banco de ideas · Buenas prácticas | Listo |
| Captura rápida: médico → ARS → paciente → servicio contratado; SIMON, CUPS y tarifa automáticos; alerta de diferencia tarifaria; servicio no contratado | Listo · 1.2.0 |
| Reclamaciones: folio REC, estado, ubicación física y responsable por servicio; acciones masivas; auditoría del expediente (D5); línea de tiempo | Listo · 1.2.0 |
| Retiros físicos: programar, confirmar recibidas vs. esperadas, Reporte de Retiro con folio RET imprimible | Listo · 1.2.0 |
| Tarifario contractual Médico × ARS × Servicio × vigencia, historial e importador con reporte previo | Listo · 1.2.0 |
| Rol Capturador / Secretaria (mínimo privilegio, médicos asignados) y rol Operaciones SOFA | Listo · 1.2.0 |
| Expediente por reclamación: requisitos según servicio, ARS y modalidad; subir archivo o marcar en físico; COMPLETO / INCOMPLETO; excepción auditada | Listo · 1.3.0 |
| Requisitos documentales (reglas con vista previa) · Pre-radicación por lote · Envío a la ARS (Enviada → Radicada) · Aviso de retiro por WhatsApp | Listo · 1.3.0 |
| Post-radicación: reenvío de devueltas en radicación complementaria, línea de tiempo de 14 hitos, tiempos por etapa, aprobado vs. pagado, folios PAG/GLO | Listo · 1.4.0 |
| Honorarios: cuota prorrateada por días activos, facturas con honorarios rezagados, alerta de factura sin NCF | Listo · 1.4.0 |
