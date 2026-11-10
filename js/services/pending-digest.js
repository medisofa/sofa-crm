/** Resumen del usuario autenticado. Solo preferencias y lectura; no transmite mensajes. */
import {rpc} from './iter18.js';
export const getDailyDigestSettings=()=>rpc('my_daily_digest_settings');
export const saveDailyDigestSettings=(phone,time)=>rpc('set_daily_digest_settings',{p_phone:phone,p_local_time:time});
export const getDailyDigestPreview=()=>rpc('my_daily_digest_preview');
export const DIGEST_TYPES=Object.freeze([
 ['captura_incompleta','Capturas incompletas'],['lote_por_radicar','Lotes por radicar'],
 ['glosa_responder','Glosas por responder'],['cobro_escalar','Cobros por escalar']
]);
const count=v=>Number.isFinite(Number(v))&&Number(v)>=0?Math.floor(Number(v)):0;
/** Lista cerrada de campos: no reenvía títulos, nombres de pacientes, NSS ni diagnósticos. */
export function dailyDigestText(preview){
 const total=preview?.totals||{},byType=new Map((preview?.counts||[]).map(c=>[c.type,c]));
 const date=/^\d{4}-\d{2}-\d{2}$/.test(preview?.date||'')?preview.date.split('-').reverse().join('/'):'hoy';
 return [`SOFA · Pendientes del ${date}`,`Total: ${count(total.total)} · Vencidos: ${count(total.overdue)} · Prioridad alta: ${count(total.high)}`,
  `Sin responsable: ${count(total.unassigned)}`,...DIGEST_TYPES.map(([type,label])=>`${label}: ${count(byType.get(type)?.total)}`),
  'Consulta el detalle actualizado en tu bandeja:', 'https://app.sofamedica.com/#/mi-bandeja'].join('\n');
}
