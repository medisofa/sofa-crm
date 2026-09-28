# SOFA · Soluciones de Facturación Médica — Frontend

Aplicación web estática (HTML + CSS + JavaScript con ES Modules) que se publica en **GitHub Pages** y usa **Supabase** como backend (Auth, PostgreSQL con RLS y Storage).

- Versión: **0.7.0** (Iteración 7 · Tarifarios y codificación)
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

Los scripts SQL (`001`–`017`) se entregan aparte, en la carpeta `sofa-supabase/`. **No los subas a un repositorio público**: describen las reglas internas del negocio. Guárdalos en tu equipo o en un repositorio privado.

## Instalación (resumen)

1. Edita `js/config.js` con tu Project URL y Publishable key (Supabase › Project Settings › API Keys).
2. Crea el repositorio `sofa-crm` en GitHub y sube el contenido de esta carpeta.
3. Activa GitHub Pages: Settings › Pages › Deploy from a branch › `main` › `/ (root)`.
4. En Supabase › Authentication › URL Configuration pon la URL de Pages como Site URL y agrega `https://TU-USUARIO.github.io/sofa-crm/**` en Redirect URLs.
5. Abre `https://TU-USUARIO.github.io/sofa-crm/` e inicia sesión con tu usuario Super Admin.

La guía paso a paso con capturas de verificación está en `GUIA_Iteracion3.html`, que viene en el paquete de entrega.

## Publicar una versión nueva

1. Sube los archivos modificados.
2. Cambia `VERSION` en `sw.js` (por ejemplo `sofa-shell-0.3.1`) y `APP_VERSION` en `js/config.js`.
3. Los usuarios verán el aviso "Hay una versión nueva de SOFA. Recarga la página".

## Módulos disponibles en 0.7.0

| Módulo | Estado |
|---|---|
| Login, recuperación de contraseña, cierre por inactividad (30 min) | Listo |
| Inicio: cifras por rol, seguimientos de hoy y plan de 90 días | Listo |
| Pipeline (8 etapas), prospectos con aviso de duplicados, diagnóstico de fugas, conversión a cliente | Listo |
| Clientes PSS: alta directa, ficha con prestadores, códigos por ARS, contactos, oportunidades, tareas e historial | Listo |
| Contactos · Aliados referidores · Tareas | Listo |
| Codificación y tarifarios: conceptos, códigos, tarifas con vigencia, negociadas, importación y brechas | Listo |
| ARS | Listo |
| Usuarios y roles · Parámetros · Mi perfil · Diagnóstico | Listo |
| Radicaciones: desglose del período, validación de 10 reglas, carga masiva, checklist, expediente digital, estados hasta Radicada | Listo |
| Documentos | Listo |
| Glosas: registro por servicio, apelación, resultado parcial, Pareto y tasa por ARS | Listo |
| Pagos: reparto entre radicaciones, conciliación por ARS, por cobrar, anulación | Listo |
| Honorarios SOFA: cuotas, % cobrado, facturas, cobros y NCF | Listo |
| Dashboard, trabajo de hoy, aging, reportes | Iteración 8 |
