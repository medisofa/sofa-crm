/**
 * SOFA — preauditoría administrativa por reclamación.
 * Módulo puro: sin I/O, sin envío a ARS, sin llamadas LLM y sin escrituras.
 * No reemplaza validate_submission ni una consulta oficial de cobertura.
 */
const trim = value => String(value ?? '').trim();
const isDate = value => { const v = trim(value); if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return false; const d = new Date(v + 'T00:00:00Z'); return !Number.isNaN(d.valueOf()) && d.toISOString().slice(0, 10) === v; };
const result = (code, status, detail, source = 'local_rule') => ({ code, status, detail, source });

/**
 * @param {object} claim Datos administrativos ya autorizados para el usuario/organización.
 * @param {object} context
 * @param {boolean} context.isDemo Bandera obtenida del servidor, no del navegador.
 * @param {Array<object>} context.duplicateCandidates Respuesta autorizada de claim_duplicate_candidates.
 * La cobertura ARS no se acepta como dato autoafirmado por el cliente.
 * @returns {{decision:string,checks:Array<object>,requiresHumanReview:boolean,externalVerified:boolean,isDemo:boolean}}
 */
export function preauditClaim(claim, context = {}) {
  if (!claim || typeof claim !== 'object') throw new TypeError('Reclamación inválida');
  if (typeof context.isDemo !== 'boolean') throw new TypeError('Se requiere isDemo verificado desde servidor');
  const checks = [];
  const required = [
    ['organization_id', 'Organización'], ['member_number', 'NSS'],
    ['service_date', 'Fecha del servicio'], ['authorization_number', 'Autorización'],
  ];
  for (const [field, label] of required) {
    checks.push(result('required_' + field, trim(claim[field]) ? 'pass' : 'block', label + (trim(claim[field]) ? ': presente' : ': falta')));
  }
  checks.push(result('service_date_format', isDate(claim.service_date) ? 'pass' : 'block', 'Fecha de servicio en formato ISO'));
  if (claim.authorization_date) {
    checks.push(result('authorization_date_format', isDate(claim.authorization_date) ? 'pass' : 'block', 'Fecha de autorización en formato ISO'));
  }
  if (claim.amount == null || !Number.isFinite(Number(claim.amount)) || Number(claim.amount) <= 0) {
    checks.push(result('amount', 'block', 'Monto no válido'));
  } else {
    checks.push(result('amount', 'pass', 'Monto administrativo válido; tarifa contractual no verificada'));
  }
  // La tarifa proviene de la fotografía contractual de SOFA, no de la validación ARS.
  if (claim.contracted === false) {
    checks.push(result('contract', 'pending', 'Servicio no contratado: requiere configuración o excepción autorizada'));
  } else if (claim.contracted === true) {
    checks.push(result('contract', 'pass', 'Servicio marcado como contratado; verificar vigencia y soporte documental'));
  } else {
    checks.push(result('contract', 'pending', 'No hay evidencia suficiente del contrato aplicable'));
  }
  const charged = Number(claim.amount);
  const tariff = Number(claim.tariff_amount);
  if (claim.contracted === true && claim.tariff_amount != null &&
      Number.isFinite(charged) && Number.isFinite(tariff) && charged > 0 && tariff > 0) {
    const delta = Math.abs(charged - tariff);
    checks.push(result('tariff', delta < 0.01 ? 'pass' : 'pending',
      delta < 0.01 ? 'Monto coincide con tarifa registrada' : 'Diferencia con tarifa: revisar justificación o autorización'));
  } else {
    checks.push(result('tariff', 'pending', 'Comparación contractual no disponible'));
  }
  if (context.duplicateCandidates == null) {
    checks.push(result('duplicate', 'pending', 'No se ha consultado claim_duplicate_candidates'));
  } else if (!Array.isArray(context.duplicateCandidates)) {
    throw new TypeError('duplicateCandidates debe ser un arreglo');
  } else if (context.duplicateCandidates.some(c => c.blocks_radicacion === true)) {
    checks.push(result('duplicate', 'block', 'Hay coincidencias de alto riesgo pendientes de resolución', 'claim_duplicate_candidates'));
  } else {
    checks.push(result('duplicate', 'pass', 'Sin bloqueos devueltos por el detector de duplicados', 'claim_duplicate_candidates'));
  }
  // Ninguna respuesta ARS enviada desde el navegador cuenta como prueba oficial.
  checks.push(result('ars_coverage', 'pending', 'Afiliación y cobertura requieren consulta oficial autenticada desde backend'));
  checks.push(result('coding', 'pending', 'Codificación/PDSS, diagnóstico y contrato requieren reglas vigentes verificadas'));
  checks.push(result('fiscal', 'pending', 'NCF/e-CF y documentos fiscales requieren verificación específica'));
  const decision = checks.some(c => c.status === 'block') ? 'correction_required' : 'human_review_required';
  return {
    decision,
    checks,
    requiresHumanReview: true,
    externalVerified: false,
    isDemo: context.isDemo,
  };
}
