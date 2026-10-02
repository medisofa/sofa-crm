/** SOFA · Catálogos de interfaz (espejo de las restricciones CHECK de la base de datos) */
export const STAGES = [   // 1.5: 10 etapas del proceso real (los códigos de la base de datos se conservan)
  { code: 'prospecto', label: 'Prospecto', prob: 10 },
  { code: 'contactado', label: 'Contactado', prob: 20 },
  { code: 'reunion', label: 'Presentación', prob: 35 },
  { code: 'evaluacion', label: 'Seguimiento', prob: 45 },
  { code: 'propuesta', label: 'Propuesta', prob: 60 },
  { code: 'negociacion', label: 'Negociación', prob: 75 },
  { code: 'acuerdo', label: 'Acuerdo', prob: 85 },
  { code: 'contratado', label: 'Contratado', prob: 95 },
  { code: 'implementacion', label: 'Implementación', prob: 98 },
  { code: 'cliente', label: 'Activo', prob: 100 },
  { code: 'perdido', label: 'Perdido', prob: 0 }
];
/** Etapas posteriores a la firma: exigen que el prospecto ya sea cliente */
export const POST_SALE_STAGES = ['contratado', 'implementacion', 'cliente'];
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
export const ACTIVITY_TYPES = { presencial: 'Visita presencial', llamada: 'Llamada', whatsapp: 'WhatsApp', correo: 'Correo', videollamada: 'Videollamada', reunion: 'Reunión', nota: 'Nota', sistema: 'Sistema' };
/** 1.5 · Documentos comerciales A–E */
export const COMMERCIAL_DOCS = { A: 'Contrato de servicios SOFA', B: 'Autorización de representación', C: 'Carta de presentación a la clínica', D: 'Carta de representación ante ARS', E: 'Formulario de implementación' };
export const COMMERCIAL_DOC_TYPE = { A: 'contrato_sofa', B: 'autorizacion_representacion', C: 'carta_clinica', D: 'carta_ars', E: 'formulario_implementacion' };
export const COMMERCIAL_DOC_STATUS = { generado: ['Generado', 'info'], enviado: ['Enviado', 'warn'], entregado: ['Entregado', 'ok'], firmado: ['Firmado', 'ok'], anulado: ['Anulado', 'bad'] };
export const CONTACT_ROLES = { medico: 'Médico', secretaria: 'Secretaria / asistente', administrador: 'Administrador', contador: 'Contador', otro: 'Otro' };
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

/** Inteligencia de mercado */
export const INTEL_TOPICS = { regulacion: ['Regulación', 'info'], ars: ['ARS', 'info'], facturacion: ['Facturación y glosas', 'warn'], habilitacion: ['Habilitación', 'info'],
  tecnologia: ['Tecnología', ''], competencia: ['Competencia', 'bad'], internacional: ['Internacional', ''], mercado: ['Mercado', ''] };
export const intelTopic = (t) => INTEL_TOPICS[t] || [t, ''];
export const ENTITY_KINDS = { competidor_directo: 'Competidor directo', competidor_indirecto: 'Competidor indirecto', referente_local: 'Referente local',
  referente_internacional: 'Referente internacional', regulador: 'Regulador', gremio: 'Gremio', aliado_potencial: 'Aliado potencial' };
export const THREAT = { alto: ['Amenaza alta', 'bad'], medio: ['Amenaza media', 'warn'], bajo: ['Amenaza baja', 'ok'], 'n/a': ['—', ''] };
export const IDEA_STATUS = { idea: ['Idea', ''], evaluando: ['Evaluando', 'info'], piloto: ['Piloto', 'warn'], lanzado: ['Lanzado', 'ok'], descartado: ['Descartado', ''] };

/** Iteración 12 · Reclamaciones: estado [etiqueta, clase] (espejo de public.claim_statuses) */
export const CLAIM_STATUS = {
  pendiente_configuracion: ['Pendiente de configuración', 'bad'], capturada: ['Capturada', 'info'], pendiente_retiro: ['Pendiente de retiro', 'warn'],
  retirada: ['Retirada', 'info'], en_validacion: ['En validación', 'info'], con_inconsistencia: ['Con inconsistencia', 'bad'], validada: ['Validada', 'ok'],
  lista_para_radicar: ['Lista para radicar', 'ok'], radicada: ['Radicada', 'info'], en_proceso_ars: ['En proceso ARS', 'info'], devuelta: ['Devuelta por la ARS', 'bad'],
  pago_parcial: ['Pago parcial', 'warn'], glosada: ['Glosada', 'bad'], pagada: ['Pagada', 'ok'], cerrada: ['Cerrada', '']
};
export const claimStatus = (c) => CLAIM_STATUS[c] || [c, ''];
/** Filtros rápidos del listado de reclamaciones */
export const CLAIM_GROUPS = {
  todas: { label: 'Todas' },
  captura: { label: 'En captura', statuses: ['pendiente_configuracion', 'capturada', 'pendiente_retiro'] },
  custodia: { label: 'En SOFA / validación', statuses: ['retirada', 'en_validacion', 'con_inconsistencia', 'validada', 'lista_para_radicar'] },
  ars: { label: 'En la ARS', statuses: ['radicada', 'en_proceso_ars', 'devuelta'] },
  cobro: { label: 'Pagadas / glosadas', statuses: ['pago_parcial', 'glosada', 'pagada', 'cerrada'] },
  atencion: { label: 'Requieren atención', statuses: ['pendiente_configuracion', 'con_inconsistencia', 'devuelta'] }
};
/** Botón para cada transición de reclamación */
export const CLAIM_MOVE_LABELS = {
  capturada: 'Volver a Capturada', pendiente_retiro: 'Lista para retiro', retirada: 'Marcar retirada', en_validacion: 'Enviar a validación',
  lista_para_radicar: 'Lista para radicar', validada: 'Devolver a Validada', en_proceso_ars: 'En proceso ARS', devuelta: 'Devuelta por la ARS', cerrada: 'Cerrar'
};
export const DISCREPANCY_STATUS = { pendiente: ['Diferencia pendiente', 'warn'], autorizada: ['Diferencia autorizada', 'ok'], rechazada: ['Diferencia rechazada', 'bad'], superada: ['Superada', ''] };
export const CONTRACT_STATUS = { vigente: ['Vigente', 'ok'], suspendida: ['Suspendida', 'bad'], por_revisar: ['Por revisar', 'warn'] };
export const CARE_MODES = [['ambulatorio', 'Ambulatorio'], ['emergencia', 'Emergencia'], ['internamiento', 'Internamiento']];
export const DELIVERY_METHODS = [['plataforma', 'Plataforma / portal de la ARS'], ['fisico', 'Entrega física'], ['correo', 'Correo'], ['otro', 'Otro']];
export const PICKUP_STATUS = { borrador: ['Programado', 'warn'], confirmado: ['Confirmado', 'ok'], anulado: ['Anulado', ''] };
