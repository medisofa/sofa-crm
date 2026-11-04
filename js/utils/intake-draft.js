/** Only known intake fields are stored; drafts stay on the server, never in browser storage. */
export function intakeSnapshot(state,fields,feedback){
 const clean=row=>Object.fromEntries(['__row',...fields].map(key=>[key,row?.[key]??'']));
 const source=state.validated.length?state.validated:state.rows.map(raw=>({raw,original:raw,status:'review'}));
 return {schema:1,origin_id:state.batchId,source_name:state.sourceName||'Carga sin nombre',scope_ids:[...new Set(source.map(row=>row.provider?.organization_id).filter(Boolean))],
  rows:source.map(row=>({raw:clean(row.raw),original:clean(row.original||row.raw),status:row.status,reviewed:!!row.reviewed,tariff:row.tariff??null,
   editCount:row.editCount||0,folio:row.folio||null,claimId:row.claimId||null})),editor:state.editor||null,
  feedback:feedback||null,audit_cursor:state.auditCursor||0};
}
export function replayIntakeAudit(rows,events,{trustSavedSource=false,baseRows=[]}={}){
 const map=new Map(rows.map(raw=>{const seed=baseRows.find(row=>Number(row.raw?.__row)===Number(raw.__row));return [Number(raw.__row),{original:{...raw},status:'review',editCount:0,...seed,raw:{...raw}}];}));
 const conflicts=[];let applied=0;
 for(const event of [...events].sort((a,b)=>Number(a.id)-Number(b.id))){
  const number=Number(String(event.record_id).split(':row:')[1]);const row=map.get(number);
  if(!row){conflicts.push(`Fila ${number}: no existe en el CSV seleccionado`);continue;}
  if(event.operation!=='CORRECCION_CARGA_EXTERNA')continue;
  const values=event.new_values?.values||{},before=event.old_values?.values||{};
  if(values.accion){
   const saved=values.valores||{};
   if(Object.keys(saved).some(key=>key!=='__row'&&String(row.raw[key]??'')!==String(saved[key]??''))){conflicts.push(`Fila ${number}: el archivo no coincide con la revisión registrada`);continue;}
   if(values.accion==='EXCLUSION_FILA'){row.status='excluded';row.reviewed=false;}
   if(values.accion==='RESTAURACION_FILA'){row.status='review';row.reviewed=false;}
   if(values.accion==='APROBACION_FILA'&&trustSavedSource){row.reviewed=true;row.status='ready';}
   applied++;continue;
  }
  const fields=(event.new_values?.fields||[]).filter(key=>key!=='__row'&&Object.hasOwn(row.raw,key));
  if(!fields.length)continue;
  if(fields.some(key=>String(row.raw[key]??'')!==String(before[key]??''))){conflicts.push(`Fila ${number}: los valores originales no coinciden`);continue;}
  for(const key of fields)if(key!=='__row'&&Object.hasOwn(values,key))row.raw[key]=values[key];
  row.status='review';row.reviewed=false;row.editCount++;applied++;
 }
 return {rows:[...map.values()],conflicts:[...new Set(conflicts)],applied};
}
