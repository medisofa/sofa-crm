/** Solo lectura: la constancia no cambia estados ni acredita recepción por sí sola. */
import {sb} from '../supabase.js';
import {getSubmission,listLines} from './submissions.js';
import {getFiscal} from './claims.js';
const must=({data,error})=>{if(error)throw error;return data;};
export async function deliveryReportData(id){
 const sub=await getSubmission(id);if(!sub)throw new Error('Lote no encontrado o sin acceso.');
 const [lines,provider,org,fiscal]=await Promise.all([
  listLines(id),sb().from('providers').select('id,full_name,tax_id,specialty').eq('id',sub.provider_id).maybeSingle().then(must),
  sb().from('organizations').select('id,legal_name,phone,email,tax_id').eq('id',sub.organization_id).maybeSingle().then(must),
  getFiscal(id)
 ]);
 return {sub:{...sub,...fiscal},lines,provider:provider||{},org:org||{}};
}
