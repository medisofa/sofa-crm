/** SOFA · Catálogos de interfaz (espejo de las restricciones CHECK de la base de datos) */
export const STAGES = [
  { code: 'prospecto', label: 'Prospecto', prob: 10 },
  { code: 'contactado', label: 'Contactado', prob: 20 },
  { code: 'reunion', label: 'Reunión', prob: 35 },
  { code: 'evaluacion', label: 'Evaluación', prob: 45 },
  { code: 'propuesta', label: 'Propuesta', prob: 60 },
  { code: 'negociacion', label: 'Negociación', prob: 75 },
  { code: 'cliente', label: 'Cliente', prob: 100 },
  { code: 'perdido', label: 'Perdido', prob: 0 }
];
export const stageLabel = (c) => STAGES.find((s) => s.code === c)?.label || c;
export const OPEN_STAGES = STAGES.filter((s) => !['cliente', 'perdido'].includes(s.code)).map((s) => s.code);
export const SOURCES = ['Instagram', 'WhatsApp Business', 'Referido contador', 'Charla sociedad médica', 'Red existente', 'Cliente actual (venta cruzada)', 'Otro'];
export const SERVICES = [
  { code: 'facturacion', name: 'Facturación médica' }, { code: 'glosas', name: 'Gestión de glosas' },
  { code: 'codificacion', name: 'Codificación ARS' }, { code: 'contable', name: 'Gestión contable' },
  { code: 'administrativa', name: 'Gestión administrativa' }, { code: 'habilitacion', name: 'Habilitación' },
  { code: 'redes', name: 'Redes sociales' }, { code: 'asistente_virtual', name: 'Asistente virtual' }
];
export const serviceName = (c) => SERVICES.find((s) => s.code === c)?.name || c;
export const ORG_TYPES = ['Médico independiente', 'Consultorio', 'Centro médico', 'Clínica', 'Laboratorio', 'Centro diagnóstico', 'Otro'];
export const ORG_STATUS = { incorporacion: ['Incorporación', 'info'], activo: ['Activo', 'ok'], suspendido: ['Suspendido', 'warn'], inactivo: ['Inactivo', ''] };
export const PROVIDER_TYPES = { medico: 'Médico', centro: 'Centro', laboratorio: 'Laboratorio', otro: 'Otro' };
export const CODE_STATUS = { sin_codigo: ['Sin código', 'bad'], solicitado: ['Solicitado', 'warn'], codificado: ['Codificado', 'ok'] };
export const ACTIVITY_TYPES = { llamada: 'Llamada', whatsapp: 'WhatsApp', correo: 'Correo', reunion: 'Reunión', nota: 'Nota', sistema: 'Sistema' };
export const PRIORITIES = { alta: ['Alta', 'bad'], media: ['Media', 'warn'], baja: ['Baja', ''] };
export const PARTNER_TYPES = ['Contador', 'Administrador de centro', 'Médico', 'Otro'];
export const LOST_REASONS = ['Precio', 'Eligió otro gestor', 'No es el momento', 'Lo hace su personal interno', 'Sin respuesta', 'Otro'];

/** Radicaciones: nombre y color de cada estado (espejo de submission_statuses) */
export const SUB_STATUS = {
  borrador: ['Borrador', ''], recibida: ['Recibida', 'info'], pendiente_documentos: ['Pendiente de documentos', 'warn'],
  en_depuracion: ['En depuración', 'info'], lista_para_radicar: ['Lista para radicar', 'ok'], radicada: ['Radicada', 'info'],
  en_auditoria_ars: ['En auditoría ARS', 'info'], glosada: ['Glosada', 'warn'], pagada_parcial: ['Pagada parcial', 'warn'],
  pagada: ['Pagada', 'ok'], rechazada: ['Rechazada', 'bad'], cerrada: ['Cerrada', '']
};
export const subStatus = (c) => SUB_STATUS[c] || [c, ''];
/** Texto del botón para cada transición */
export const TRANSITION_LABELS = {
  recibida: 'Marcar recibida', pendiente_documentos: 'Pendiente de documentos', en_depuracion: 'Pasar a depuración',
  lista_para_radicar: 'Lista para radicar', radicada: 'Radicar ante la ARS', en_auditoria_ars: 'En auditoría ARS',
  rechazada: 'Rechazada por la ARS', cerrada: 'Cerrar'
};

/** Glosas: nombre y color de cada estado */
export const GLOSA_STATUS = {
  pendiente: ['Pendiente', 'warn'], analizada: ['Analizada', 'info'], apelada: ['Apelada', 'info'], en_revision: ['En revisión', 'info'],
  aceptada: ['Aceptada (pérdida)', 'bad'], revertida: ['Revertida (recuperada)', 'ok'], parcial: ['Resuelta parcial', 'warn'], cerrada: ['Cerrada', '']
};
export const glosaStatus = (c) => GLOSA_STATUS[c] || [c, ''];
export const PAYMENT_METHODS = [['transferencia', 'Transferencia'], ['cheque', 'Cheque'], ['deposito', 'Depósito'], ['otro', 'Otro']];
export const INVOICE_STATUS = { emitida: ['Emitida', 'info'], pagada_parcial: ['Cobro parcial', 'warn'], pagada: ['Cobrada', 'ok'], anulada: ['Anulada', ''] };
export const FEE_SOURCE = { pago: '% de lo cobrado', cuota: 'Cuota mensual', radicacion: 'Por radicación', manual: 'Manual' };
