/**
 * SOFA · Crea un Google Form para captura externa de Facturación ARS
 * y lo vincula a la hoja oficial SOFA - Captura Externa Facturación ARS.
 *
 * Uso:
 * 1) Abra script.google.com con la cuenta autorizada.
 * 2) Cree un proyecto nuevo y pegue este archivo.
 * 3) Ejecute crearFormularioSOFA().
 * 4) Autorice Forms + Drive cuando Google lo solicite.
 */
const SOFA_SPREADSHEET_ID = '1VeUb9RQ_jGBN9chr6QCiV-8Gp-2b2JKaj159qo6a-ps';

function crearFormularioSOFA() {
  const form = FormApp.create('SOFA - Captura Externa Facturación ARS');
  form.setDescription(
    'Formulario para secretarias o asistentes que no tienen acceso directo a SOFA. ' +
    'La información será revisada y validada por SOFA antes de convertirse en reclamación.'
  );
  form.setConfirmationMessage('Registro recibido. SOFA validará la información antes de procesarla.');
  form.setProgressBar(true);

  form.addTextItem().setTitle('Médico / Prestador *').setRequired(true);
  form.addTextItem().setTitle('Correo del médico').setRequired(false);
  form.addTextItem().setTitle('ARS *').setRequired(true);
  form.addDateItem().setTitle('Fecha del servicio *').setRequired(true);

  const modalidad = form.addListItem().setTitle('Modalidad');
  modalidad.setChoiceValues(['ambulatorio','emergencia','internamiento']).setRequired(false);

  form.addTextItem().setTitle('Paciente *').setRequired(true);
  form.addTextItem().setTitle('NSS / No. afiliado *').setRequired(true);
  form.addTextItem().setTitle('No. autorización').setRequired(false);
  form.addDateItem().setTitle('Fecha autorización').setRequired(false);
  form.addTextItem().setTitle('Cédula paciente').setRequired(false);
  form.addTextItem().setTitle('Diagnóstico CIE-10').setHelpText('Opcional. Si no conoce el código, déjelo vacío: SOFA sugerirá CIE-10 según servicio, SIMON y CUPS antes de importar. La selección final debe corresponder al diagnóstico documentado.').setRequired(false);
  form.addTextItem().setTitle('Centro / clínica').setRequired(false);
  form.addTextItem().setTitle('Servicio / Procedimiento *').setRequired(true);
  form.addTextItem().setTitle('Cantidad').setRequired(false);
  form.addTextItem().setTitle('Monto a reclamar').setRequired(false);
  form.addParagraphTextItem().setTitle('Observaciones').setRequired(false);

  form.setDestination(FormApp.DestinationType.SPREADSHEET, SOFA_SPREADSHEET_ID);

  const ss = SpreadsheetApp.openById(SOFA_SPREADSHEET_ID);
  const props = PropertiesService.getScriptProperties();
  props.setProperty('SOFA_FORM_ID', form.getId());
  props.setProperty('SOFA_FORM_EDIT_URL', form.getEditUrl());
  props.setProperty('SOFA_FORM_PUBLIC_URL', form.getPublishedUrl());

  const ins = ss.getSheetByName('Instrucciones');
  if (ins) {
    ins.getRange('A11:B13').setValues([
      ['Google Form creado', form.getEditUrl()],
      ['Enlace para secretaria', form.getPublishedUrl()],
      ['ID del formulario', form.getId()]
    ]);
  }

  Logger.log('Editar formulario: ' + form.getEditUrl());
  Logger.log('Enlace para secretaria: ' + form.getPublishedUrl());
}
