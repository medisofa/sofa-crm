# SOFA · Google Sheets + Google Form para captura externa ARS

Hoja oficial:
https://docs.google.com/spreadsheets/d/1VeUb9RQ_jGBN9chr6QCiV-8Gp-2b2JKaj159qo6a-ps/edit

## Flujo
1. Secretaria sin acceso a SOFA completa Google Form.
2. Google Form escribe en la hoja vinculada.
3. Personal SOFA descarga la pestaña de respuestas como CSV.
4. En SOFA: Facturación ARS → Carga Google Sheets / Form.
5. SOFA pre-valida médico, ARS, servicio contractual, autorización y tarifa.
6. Solo las filas válidas se crean como reclamaciones.

## Seguridad
- No publicar la hoja.
- No habilitar "Cualquiera con el enlace puede ver" para datos de pacientes.
- Compartir únicamente con usuarios autorizados.
- Los montos distintos de la tarifa contractual se detienen para revisión.
- El backend de SOFA conserva el bloqueo de duplicados.

## Google Form
El archivo `docs/google/SOFA_Crear_Formulario_Captura_ARS.gs` crea y vincula automáticamente el formulario a la hoja oficial.
