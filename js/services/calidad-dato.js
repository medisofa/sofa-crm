/**
 * SOFA · 5.1 · I61 · Calidad del dato en la captura.
 * Revisión en vivo de la cédula, el NSS y el diagnóstico (mensajes en la misma casilla) y acceso a la configuración y al indicador por secretaria.
 * Las reglas de verdad viven en PostgreSQL (capture_claim_dx, dq_check_claim): aquí solo se muestran y se adelanta lo que se puede saber sin llamar al servidor.
 * El servidor decide si una regla bloquea (modo «bloquear» + interruptor global encendido) o solo advierte.
 */
import { sb } from '../supabase.js';
import { cedulaValida } from './ocr-reglas.js';

export { cedulaValida };
const must = ({ data, error }) => { if (error) throw error; return data; };
export const soloDigitos = (s) => String(s || '').replace(/[\s-]/g, '');

/** Pistas inmediatas (sin red) para la cédula: solo para no esperar al servidor al digitar. El servidor siempre vuelve a revisar. */
export function pistaCedula(texto) {
  const d = soloDigitos(texto);
  if (!d) return null;
  if (!/^[0-9]+$/.test(d) || d.length !== 11) {
    return { nivel: 'bloquea', mensaje: `La cédula debe tener 11 números (tiene ${d.length}). Revísela contra la cédula del paciente; si no tiene cédula (menor o extranjero), deje la casilla vacía y anote el documento en Observaciones.` };
  }
  if (!cedulaValida(d)) return { nivel: 'advierte', mensaje: 'El dígito verificador de la cédula no coincide. Revise el número contra la cédula del paciente (casi siempre es un dígito cambiado).' };
  return null;
}

/** Revisión en vivo en el servidor. Devuelve {issues:[{campo,codigo,mensaje,efectivo}], bloqueos, advertencias, dx, enforce}. */
export async function revisarCaptura({ org, ars, procedure, diagnosis, doc, member }) {
  return must(await sb().rpc('dq_check_claim', {
    p_org: org, p_ars: ars || null, p_procedure: procedure || null, p_diagnosis: diagnosis || null, p_doc: doc || null, p_member: member || null
  }));
}

/** Captura con diagnóstico (capture_claim_dx). Mismos parámetros que captureClaim de services/claims.js más v.diagnosis. Devuelve también «advertencias». */
export async function capturarConDiagnostico(v) {
  return must(await sb().rpc('capture_claim_dx', {
    p_provider: v.provider, p_ars: v.ars, p_procedure: v.procedure, p_service_date: v.serviceDate,
    p_patient_name: v.patientName, p_member: v.member, p_authorization: v.authorization || null, p_patient_doc: v.patientDoc || null,
    p_amount: v.amount ?? null, p_quantity: v.quantity || 1, p_care_mode: v.careMode || null, p_clinic: v.clinic || null, p_notes: v.notes || null,
    p_discrepancy_reason: v.discrepancyReason || null, p_not_contracted: v.notContracted || 'bloquear', p_exception_reason: v.exceptionReason || null,
    p_allow_duplicate: !!v.allowDuplicate, p_center: null, p_diagnosis: v.diagnosis || null
  }));
}

/** Muestra (o quita) el aviso bajo una casilla. nivel: 'bloquea' | 'advierte' | null. No usa innerHTML. */
export function mostrarAviso(input, mensaje, nivel) {
  const campo = input?.closest('.field'); if (!campo) return;
  campo.querySelector('.dq-aviso')?.remove();
  input.removeAttribute('data-dq');
  if (!mensaje) return;
  const e = document.createElement('div');
  e.className = `dq-aviso ${nivel === 'bloquea' ? 'dq-blq' : 'dq-adv'}`;
  e.setAttribute('role', nivel === 'bloquea' ? 'alert' : 'status');
  e.id = `${input.id}-dq`;
  e.textContent = (nivel === 'bloquea' ? 'Corrija: ' : 'Revise: ') + mensaje;
  campo.appendChild(e);
  input.setAttribute('data-dq', nivel === 'bloquea' ? 'bloquea' : 'advierte');
}
export function limpiarAvisos(...inputs) { inputs.forEach((i) => mostrarAviso(i, '', null)); }

// ── Configuración (solo Super Admin, Administrador, Operaciones y Facturación la leen; editar: Super Admin y Administrador) ──
export const configuracion = async () => must(await sb().rpc('dq_overview'));
export const guardarRegla = async (r) => must(await sb().rpc('dq_rule_save', {
  p_id: r.id || null, p_name: r.name, p_ars: r.ars_id || null, p_procedure: r.procedure_id || null, p_kind: r.kind,
  p_prefixes: r.dx_prefixes || [], p_mode: r.mode, p_status: r.status, p_message: r.message || null
}));
export const borrarRegla = async (id) => must(await sb().rpc('dq_rule_delete', { p_id: id }));
export const guardarComprobacion = async (code, mode, status) => must(await sb().rpc('dq_check_set', { p_code: code, p_mode: mode, p_status: status }));
export const guardarFormatoNss = async (f) => must(await sb().rpc('dq_nss_format_save', {
  p_ars: f.ars_id || null, p_min: f.min_len, p_max: f.max_len, p_digits_only: !!f.digits_only, p_example: f.example || null
}));
export const borrarFormatoNss = async (ars) => must(await sb().rpc('dq_nss_format_delete', { p_ars: ars }));
export const marcarMotivo = async (code, esError) => must(await sb().rpc('dq_error_reason_set', { p_reason: code, p_is_error: !!esError }));
export const interruptor = async (on, motivo) => must(await sb().rpc('dq_set_enforce', { p_on: !!on, p_note: motivo }));
export const guardarMeta = async (pct) => must(await sb().rpc('dq_set_target', { p_pct: pct }));
export const indicadorSecretarias = async (desde, hasta, org) => must(await sb().rpc('dq_secretary_quality', { p_from: desde || null, p_to: hasta || null, p_org: org || null }));
export const opcionesArs = async () => must(await sb().from('ars').select('id, name').eq('is_active', true).order('name'));
export const opcionesServicios = async () => must(await sb().from('procedures').select('id, internal_code, description').eq('is_active', true).order('description').limit(1000));
export const opcionesClientes = async () => must(await sb().from('organizations').select('id, legal_name, trade_name').eq('kind', 'client').order('legal_name'));
