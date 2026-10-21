/** SOFA · Solicitudes personalizadas al cliente desde su ficha CRM.
 * Registra la solicitud en el historial y abre el canal elegido con el mensaje prellenado.
 * No afirma entrega: WhatsApp/correo deben ser confirmados por el usuario en la app correspondiente.
 */
import { html } from '../utils/dom.js';
import { formDialog, opt, fieldError, toast, friendlyError } from '../utils/ui.js';
import { listContacts, addActivity } from '../services/crm.js';
import { createTask } from '../services/tasks.js';
import { waLink } from '../utils/whatsapp.js';

const REQUEST_TYPES = [
  ['documentos', 'Documentación pendiente'],
  ['reclamacion', 'Corrección de reclamación'],
  ['autorizacion', 'Confirmación / autorización'],
  ['datos', 'Datos faltantes'],
  ['codigo_ars', 'Código o trámite ARS'],
  ['habilitacion', 'Habilitación MISPAS'],
  ['otro', 'Solicitud particular']
];

const DEFAULTS = {
  documentos: 'Necesitamos completar documentación pendiente para continuar con su gestión.',
  reclamacion: 'Necesitamos revisar información de una o más reclamaciones antes de continuar el proceso.',
  autorizacion: 'Necesitamos confirmar información relacionada con una autorización.',
  datos: 'Necesitamos completar información pendiente para continuar con la gestión.',
  codigo_ars: 'Necesitamos información o documentación para continuar el trámite relacionado con su ARS.',
  habilitacion: 'Necesitamos completar información o documentación del proceso de habilitación.',
  otro: ''
};

const addDays = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
};

export async function clientRequestDialog(ctx, org) {
  let contacts = [];
  try { contacts = await listContacts({ organizationId: org.id }); } catch { contacts = []; }

  const recipients = [
    { id: 'org', label: org.legal_name, whatsapp: org.whatsapp || '', email: org.email || '' },
    ...contacts.map((c) => ({ id: c.id, label: c.full_name, whatsapp: c.whatsapp || c.phone || '', email: c.email || '' }))
  ];

  return formDialog({
    title: `Nueva solicitud · ${org.legal_name}`,
    submitLabel: 'Preparar mensaje',
    wide: true,
    body: html`
      <div class="note info"><b>Solicitud trazable.</b> SOFA registrará el mensaje en el historial del cliente y abrirá WhatsApp o correo con el texto prellenado. El envío final se confirma en ese canal.</div>
      <div class="form-grid">
        <div class="field"><label for="rq_to">Destinatario *</label>
          <select id="rq_to" name="recipient">${recipients.map((r) => opt(r.id, r.label, 'org'))}</select>
        </div>
        <div class="field"><label for="rq_channel">Canal *</label>
          <select id="rq_channel" name="channel"><option value="whatsapp">WhatsApp</option><option value="correo">Correo</option></select>
        </div>
        <div class="field"><label for="rq_type">Tipo de solicitud *</label>
          <select id="rq_type" name="request_type">${REQUEST_TYPES.map(([k,l]) => opt(k,l,'documentos'))}</select>
        </div>
        <div class="field"><label for="rq_due">Responder antes de</label>
          <input id="rq_due" name="due_date" type="date" value="${addDays(2)}">
        </div>
        <div class="field" style="grid-column:1/-1"><label for="rq_subject">Asunto</label>
          <input id="rq_subject" name="subject" maxlength="160" value="Solicitud de información · SOFA">
        </div>
        <div class="field" style="grid-column:1/-1"><label for="rq_body">Solicitud específica *</label>
          <textarea id="rq_body" name="body" rows="5" maxlength="1800">Necesitamos completar documentación pendiente para continuar con su gestión.</textarea>
          <span class="hint">Evita incluir datos clínicos sensibles innecesarios en canales externos.</span>
        </div>
        <label class="check small" style="grid-column:1/-1"><input type="checkbox" name="follow_up" checked> Crear tarea interna de seguimiento</label>
      </div>`,
    onOpen: (form) => {
      form.elements.request_type.addEventListener('change', () => {
        const current = form.elements.body.value.trim();
        const priorDefaults = Object.values(DEFAULTS).filter(Boolean);
        if (!current || priorDefaults.includes(current)) form.elements.body.value = DEFAULTS[form.elements.request_type.value] || '';
      });
    },
    onSubmit: async (d, form) => {
      const recipient = recipients.find((r) => r.id === d.recipient) || recipients[0];
      const body = String(d.body || '').trim();
      if (body.length < 8) { fieldError(form.elements.body, 'Describe la solicitud (mínimo 8 caracteres).'); return false; }

      const dueText = d.due_date ? `\n\nAgradecemos responder antes del ${d.due_date.split('-').reverse().join('/')}.` : '';
      const message = `Hola ${recipient.label},\n\n${body}${dueText}\n\nSOFA · Soluciones de Facturación Médica`;

      let target = '';
      if (d.channel === 'whatsapp') {
        target = waLink(recipient.whatsapp, message);
        if (!target) { fieldError(form.elements.recipient, 'El destinatario no tiene un WhatsApp válido registrado.'); return false; }
      } else {
        if (!recipient.email) { fieldError(form.elements.recipient, 'El destinatario no tiene correo registrado.'); return false; }
        target = `mailto:${encodeURIComponent(recipient.email)}?subject=${encodeURIComponent(d.subject || 'Solicitud de información · SOFA')}&body=${encodeURIComponent(message)}`;
      }

      try {
        await addActivity(ctx.operatorId, {
          entityType: 'organization', entityId: org.id, organizationId: org.id
        }, d.channel === 'correo' ? 'correo' : 'whatsapp',
        `SOLICITUD · ${REQUEST_TYPES.find(([k]) => k === d.request_type)?.[1] || 'Solicitud particular'} · ${body}`,
        {
          outcome: `Mensaje preparado para ${recipient.label}`,
          nextStep: d.due_date ? 'Confirmar respuesta del cliente' : null,
          nextStepDate: d.due_date || null,
          contactPerson: recipient.label
        });

        if (d.follow_up && d.due_date) {
          await createTask(ctx.operatorId, {
            title: `Seguimiento solicitud · ${recipient.label}`,
            priority: 'media',
            due_date: d.due_date,
            notes: body
          }, { type: 'organization', id: org.id, organizationId: org.id });
        }

        window.open(target, '_blank', 'noopener');
        toast('Solicitud registrada; canal abierto con el mensaje prellenado.', 'ok');
        return true;
      } catch (err) {
        toast(friendlyError(err), 'bad');
        return false;
      }
    }
  });
}
