export type TrainingRole =
  | "super_admin"
  | "admin"
  | "operations"
  | "billing"
  | "glosas"
  | "assistant"
  | "auditor"
  | "client"
  | "capturer"
  | "prospect";

export type TrainingStep = {
  title: string;
  description: string;
  href?: string;
  action?: string;
};

export type RoleTraining = {
  label: string;
  mission: string;
  firstActions: TrainingStep[];
  guardrails: string[];
  success: string[];
};

export const ROLE_TRAINING: Record<TrainingRole, RoleTraining> = {
  super_admin: {
    label: "Superadministrador",
    mission: "Administrar la plataforma, organizaciones, accesos y controles críticos sin operar datos fuera del alcance autorizado.",
    firstActions: [
      { title: "Verifica tu acceso seguro", description: "Confirma que tu sesión usa MFA antes de trabajar con organizaciones cliente.", action: "MFA requerido" },
      { title: "Revisa tus organizaciones visibles", description: "Valida que solo aparezcan las organizaciones que te corresponden.", href: "/" },
      { title: "Supervisa reclamaciones", description: "Usa la bandeja de reclamaciones para revisar estados y excepciones.", href: "/claims" }
    ],
    guardrails: ["No compartas credenciales.", "No uses cuentas administrativas para tareas rutinarias.", "Toda excepción multicliente debe ser explícita, temporal y auditable."],
    success: ["Accesos correctos por organización", "MFA activo", "Sin cambios críticos sin trazabilidad"]
  },
  admin: {
    label: "Administrador",
    mission: "Coordinar operación, usuarios y visibilidad de datos dentro del alcance autorizado.",
    firstActions: [
      { title: "Confirma tu contexto", description: "Revisa las organizaciones que tienes disponibles.", href: "/" },
      { title: "Monitorea reclamaciones", description: "Identifica reclamaciones que requieren intervención.", href: "/claims" },
      { title: "Escala excepciones", description: "No fuerces accesos; solicita la excepción correspondiente cuando aplique.", action: "Escalar" }
    ],
    guardrails: ["MFA obligatorio para staff SOFA.", "No modifiques información clínica fuera del flujo autorizado.", "Mantén separación entre organizaciones."],
    success: ["Operación sin cruces de tenant", "Pendientes identificados", "Cambios auditables"]
  },
  operations: {
    label: "Operaciones SOFA",
    mission: "Recibir, validar y preparar reclamaciones para que avancen sin errores evitables.",
    firstActions: [
      { title: "Revisa reclamaciones nuevas", description: "Empieza por las capturadas o recibidas.", href: "/claims" },
      { title: "Valida datos y documentos", description: "Confirma que la reclamación esté completa antes de avanzar.", action: "Validar" },
      { title: "Entrega a facturación", description: "Una reclamación validada debe quedar lista para radicación.", action: "Preparar" }
    ],
    guardrails: ["No cambies montos contractuales manualmente.", "No avances reclamaciones incompletas.", "Reporta discrepancias en vez de ocultarlas."],
    success: ["Menos devoluciones", "Menor tiempo captura→validación", "Reclamaciones completas"]
  },
  billing: {
    label: "Facturación / Radicación",
    mission: "Radicar reclamaciones validadas y asegurar trazabilidad hasta la respuesta de la ARS.",
    firstActions: [
      { title: "Trabaja solo reclamaciones validadas", description: "Evita radicar expedientes incompletos.", href: "/claims" },
      { title: "Confirma ARS y tarifa", description: "El monto debe provenir del contrato vigente.", action: "Verificar" },
      { title: "Radica y registra", description: "La radicación debe dejar evidencia y estado actualizado.", action: "Radicar" }
    ],
    guardrails: ["No radicar sin validación previa.", "No alterar tarifas para cuadrar diferencias.", "Toda radicación debe ser trazable."],
    success: ["First-pass acceptance alto", "Radicaciones dentro de plazo", "Cero montos manuales no autorizados"]
  },
  glosas: {
    label: "Gestión de Glosas",
    mission: "Analizar rechazos, documentar causa raíz y recuperar el mayor monto posible.",
    firstActions: [
      { title: "Identifica reclamaciones observadas o glosadas", description: "Prioriza por monto, antigüedad y fecha límite.", href: "/claims" },
      { title: "Clasifica la causa", description: "Distingue error documental, codificación, tarifa o criterio de ARS.", action: "Clasificar" },
      { title: "Gestiona reconsideración", description: "Documenta respuesta, evidencia y resultado.", action: "Recuperar" }
    ],
    guardrails: ["No borres evidencia de la glosa.", "No reenvíes sin corregir la causa raíz.", "Mantén trazabilidad de cada reconsideración."],
    success: ["Recovery rate", "Menor recurrencia de glosa", "Respuesta dentro de SLA"]
  },
  assistant: {
    label: "Asistente",
    mission: "Apoyar la operación administrativa dentro del alcance asignado.",
    firstActions: [
      { title: "Revisa tu organización", description: "Confirma que estás trabajando en el consultorio correcto.", href: "/" },
      { title: "Consulta reclamaciones", description: "Usa la bandeja para responder preguntas operativas.", href: "/claims" },
      { title: "Escala cambios sensibles", description: "Solicita apoyo cuando una acción exceda tu rol.", action: "Escalar" }
    ],
    guardrails: ["No uses credenciales de otro usuario.", "No ejecutes cambios fuera de tu rol.", "Protege NSS y datos de pacientes."],
    success: ["Información correcta", "Escalamientos oportunos", "Sin acceso indebido"]
  },
  auditor: {
    label: "Auditor",
    mission: "Verificar integridad, trazabilidad y cumplimiento sin modificar la operación.",
    firstActions: [
      { title: "Revisa contexto visible", description: "Confirma el alcance de organizaciones autorizado.", href: "/" },
      { title: "Examina reclamaciones", description: "Contrasta estado, monto y trazabilidad.", href: "/claims" },
      { title: "Documenta hallazgos", description: "Separa evidencia, riesgo y recomendación.", action: "Auditar" }
    ],
    guardrails: ["Preferencia por acceso de solo lectura.", "No corrijas directamente lo que estás auditando.", "Conserva independencia y evidencia."],
    success: ["Hallazgos reproducibles", "Cero cambios operativos no autorizados", "Riesgos priorizados"]
  },
  client: {
    label: "Médico / Cliente",
    mission: "Conocer qué se reclamó, cuánto está pendiente y qué requiere su intervención.",
    firstActions: [
      { title: "Revisa tus reclamaciones", description: "Consulta folio, fecha, paciente, monto y estado.", href: "/claims" },
      { title: "Identifica pendientes", description: "Atiende solicitudes de información o documentación cuando aparezcan.", action: "Resolver pendiente" },
      { title: "Confirma resultados", description: "Usa el estado de cada reclamación para dar seguimiento al cobro.", href: "/claims" }
    ],
    guardrails: ["Solo tendrás acceso a tu organización autorizada.", "No compartas tu usuario con la secretaria.", "Reporta cualquier dato que no reconozcas."],
    success: ["Visibilidad de cartera", "Pendientes respondidos", "Menos seguimiento por WhatsApp"]
  },
  capturer: {
    label: "Secretaria / Capturista",
    mission: "Registrar correctamente cada reclamación desde el origen, con el menor tiempo y error posible.",
    firstActions: [
      { title: "Selecciona el consultorio correcto", description: "Solo verás los médicos y organizaciones asignados.", href: "/capture" },
      { title: "Captura la reclamación", description: "Completa paciente, ARS, fecha, autorización y servicio.", href: "/capture" },
      { title: "Verifica antes de enviar", description: "La tarifa contractual la valida el servidor; revisa los demás datos.", action: "Confirmar" }
    ],
    guardrails: ["Nunca adivines NSS o autorización.", "No modifiques montos para que coincidan.", "No captures para médicos fuera de tu asignación."],
    success: ["Captura completa", "Baja tasa de corrección", "Menor tiempo por reclamación"]
  },
  prospect: {
    label: "Prospecto",
    mission: "Conocer el valor de SOFA antes de convertirse en cliente operativo.",
    firstActions: [
      { title: "Conoce el flujo", description: "SOFA conecta captura, validación, radicación, glosa y pago.", href: "/mi-usuario" },
      { title: "Solicita activación", description: "Para operar reclamaciones necesitas una organización y rol activo.", action: "Contactar SOFA" }
    ],
    guardrails: ["No se muestran datos reales sin autorización.", "El acceso operativo requiere alta formal."],
    success: ["Entender propuesta de valor", "Completar onboarding comercial"]
  }
};

export function trainingForRole(role?: string | null): RoleTraining {
  const key = (role || "client") as TrainingRole;
  return ROLE_TRAINING[key] ?? ROLE_TRAINING.client;
}
