/** Serializes private server checkpoints; version conflicts never overwrite another tab. */
export function createIntakeAutosave({rpc,owner,id,serialize,onStatus,delay=450}){
 const versions=new Map();let dirty=false,saving=0,sequence=0,timer=null,tail=Promise.resolve(),error=null;
 function mark(){dirty=true;sequence++;onStatus('saving','Cambios pendientes de guardar…');clearTimeout(timer);timer=setTimeout(()=>flush().catch(()=>{}),delay);}
 async function flush(){
  clearTimeout(timer);timer=null;
  if(!dirty){await tail;return;}
  const batch=id(),payload=serialize(),captured=sequence;
  if(!payload.rows.length&&!payload.editor)return;
  saving++;onStatus('saving','Guardando progreso en SoFa…');
  const work=tail.catch(()=>{}).then(()=>rpc('google_intake_drafts_v1',{p_action:'save',p_id:batch,p_version:versions.get(batch)||0,p_payload:payload,p_owner:owner})).then(result=>{
   if(!Number.isSafeInteger(Number(result?.version))||Number(result.version)<1||!result.updated_at||Number.isNaN(Date.parse(result.updated_at)))throw Error('No se recibió una confirmación válida del guardado.');
   versions.set(batch,Number(result.version));
   if(captured===sequence&&batch===id()){dirty=false;error=null;onStatus('saved',`Guardado en SoFa · ${new Date(result.updated_at).toLocaleTimeString('es-DO',{hour:'2-digit',minute:'2-digit',second:'2-digit',timeZone:'America/Santo_Domingo'})}`);}
   return result;
  }).catch(reason=>{if(batch===id()){dirty=true;error=reason;onStatus('error',`No se pudo guardar el progreso: ${reason.message}. Mantenga esta pestaña abierta y reintente.`);}throw reason;}).finally(()=>{saving--;});
  tail=work;return work;
 }
 function adopt(batch,version){
  if(saving)throw Error('Espere a que termine el guardado actual.');
  clearTimeout(timer);timer=null;versions.set(batch,version||0);sequence++;dirty=false;error=null;tail=Promise.resolve();
 }
 return {mark,flush,adopt,version:batch=>versions.get(batch)||0,pending:()=>dirty||saving>0,error:()=>error};
}
