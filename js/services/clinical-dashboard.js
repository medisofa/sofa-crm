/** Inicio clínico: solo datos administrativos del día y del consultorio activo.
 * RLS sigue decidiendo los médicos visibles; nunca se cambia de identidad ni de permisos.
 */
import { sb } from '../supabase.js';
import { canSee } from '../utils/permissions.js';

export function clinicalDay(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Santo_Domingo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  const part = (name) => parts.find((p) => p.type === name).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}

export async function loadClinicalDashboard(ctx, now = new Date()) {
  const organizationId = ctx.viewAs?.orgId || ctx.membership?.organization_id || null;
  const result = {
    date: clinicalDay(now), organizationId,
    scopeLabel: ctx.viewAs ? (ctx.role === 'client' && !ctx.viewAs.targetName ? 'Consultorio completo · vista de soporte' : 'Vista de soporte · solo lectura') : ctx.role === 'client' ? 'Tu consultorio' : 'Médicos visibles según tu asignación',
    unavailable: null, metrics: { total: null, waiting: null, inConsultation: null, attended: null, pendingConfirmation: null },
    appointments: [], totalAppointments: null, errors: {}
  };
  // La sesión de soporte conserva la identidad del administrador. No simular una
  // asignación individual usando los permisos amplios de esa identidad.
  if (ctx.viewAs && (ctx.role !== 'client' || ctx.viewAs.targetName)) {
    result.unavailable = 'Este inicio no muestra agendas individuales en modo soporte.';
    return result;
  }
  if (!organizationId) {
    result.unavailable = 'No se encontró el consultorio activo. Selecciona tu organización o vuelve a iniciar sesión.';
    return result;
  }
  if (!canSee('agenda', ctx.role) && !canSee('flujo-pacientes', ctx.role)) {
    result.unavailable = 'Tu perfil no tiene acceso a la agenda ni al flujo de pacientes.';
    return result;
  }
  const client = sb();
  const scope = (query) => query.eq('organization_id', organizationId).eq('appointment_date', result.date);
  const countStatus = (status) => scope(client.from('appointments').select('id', { count: 'exact', head: true })).eq('status', status);
  const queries = [
    scope(client.from('appointments').select('id,appointment_time,patient_name,status,provider_id,providers(full_name)', { count: 'exact' }))
      .neq('status', 'cancelada').order('appointment_time', { ascending: true, nullsFirst: false }).order('id').limit(8),
    countStatus('en_espera'), countStatus('en_consulta'), countStatus('atendida'), countStatus('programada')
  ];
  const keys = ['agenda', 'waiting', 'inConsultation', 'attended', 'pendingConfirmation'];
  const settled = await Promise.allSettled(queries);
  settled.forEach((item, index) => {
    const key = keys[index];
    const response = item.status === 'fulfilled' ? item.value : null;
    if (!response || response.error || !Number.isFinite(response.count)) {
      result.errors[key] = 'No disponible. Actualiza para volver a consultar.';
      return;
    }
    if (key === 'agenda') {
      result.appointments = response.data || [];
      result.totalAppointments = response.count;
      result.metrics.total = response.count;
    } else result.metrics[key] = response.count;
  });
  return result;
}
