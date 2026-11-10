/** Resumen diario: preparación interna y WhatsApp manual explícito, sin simular envíos. */
import {h,note,num} from '../services/iter18.js';
import {viewAsState} from '../utils/view-as-state.js';
import {waLink} from '../utils/whatsapp.js';
import {DIGEST_TYPES,dailyDigestText,getDailyDigestSettings,saveDailyDigestSettings,getDailyDigestPreview} from '../services/pending-digest.js';
const STAFF=['super_admin','admin','operations','billing'];
export async function mountPendingDigest(box,ctx={}){
 if(!STAFF.includes(ctx.role))return;
 if(ctx.viewAs||viewAsState.active){box.append(note('Resumen personal no disponible en modo soporte. No se consultaron preferencias ni mensajes.'));return;}
 let settings=null,preview=null,busy=false;
 const feedback=h('div',{role:'status','aria-live':'polite'});
 const status=h('p',{class:'small muted'});
 const totals=h('div',{'aria-live':'polite'});
 const text=h('pre',{class:'i18-pre','aria-label':'Texto del resumen'});
 const phone=h('input',{id:'pd-phone',type:'tel',autocomplete:'tel',inputmode:'tel',maxlength:'20','aria-describedby':'pd-phone-help'});
 const time=h('input',{id:'pd-time',type:'time',required:true,value:'07:00','aria-describedby':'pd-time-help'});
 const save=h('button',{type:'submit',class:'btn'},'Guardar preferencias');
 const refresh=h('button',{type:'button',class:'btn'},'Actualizar vista previa');
 const manual=h('a',{class:'btn primary',target:'_blank',rel:'noopener noreferrer','aria-disabled':'true',tabindex:'-1'},'Abrir WhatsApp (envío manual)');
 const form=h('form',{class:'i18-form'},h('div',{class:'form-grid'},
  h('div',{class:'field'},h('label',{for:'pd-phone'},'Tu número de WhatsApp',phone),h('span',{id:'pd-phone-help',class:'hint'},'Solo su usuario puede consultar o modificar este destinatario.')),
  h('div',{class:'field'},h('label',{for:'pd-time'},'Hora diaria de preparación',time),h('span',{id:'pd-time-help',class:'hint'},'Todos los días · America/Santo_Domingo.'))),save);
 const section=h('section',{class:'card pending-digest',style:'margin-top:16px','aria-labelledby':'pd-title'},
  h('h3',{id:'pd-title'},'Resumen diario de pendientes'),
  note('Pendiente de conectar WhatsApp Business. La preparación del resumen no envía mensajes automáticamente.','info'),status,
  form,feedback,h('h4',{},'Vista previa actual'),totals,text,
  h('div',{class:'i18-actions'},refresh,h('a',{class:'btn',href:'#/mi-bandeja'},'Ver Mi bandeja'),manual),
  h('p',{class:'small muted'},'WhatsApp se abre únicamente al pulsar el botón. Revise y envíe el mensaje desde allí; SOFA no lo marca como enviado ni confirma entrega.'));
 box.append(section);
 const alive=()=>section.isConnected;
 function busyForm(value){busy=value;[phone,time,save,refresh].forEach(el=>{el.disabled=value;});}
 function link(){
  const url=settings&&preview?waLink(settings.phone,dailyDigestText(preview)):'';
  if(url){manual.href=url;manual.removeAttribute('aria-disabled');manual.removeAttribute('tabindex');}
  else{manual.removeAttribute('href');manual.setAttribute('aria-disabled','true');manual.setAttribute('tabindex','-1');}
 }
 manual.addEventListener('click',event=>{if(!manual.hasAttribute('href')||ctx.viewAs||viewAsState.active)event.preventDefault();});
 function showSettings(){
  phone.value=settings.phone||'';time.value=settings.local_time||'07:00';
  status.textContent=settings.preparation_enabled
   ?`El resumen se prepara todos los días a las ${time.value}, hora de Santo Domingo. Envío automático pendiente de WhatsApp Business.`
   :'Preferencias guardadas para preparación. La programación diaria aún no está activada; el envío automático está pendiente de WhatsApp Business.';
  if(settings.prepared_at){const stamp=new Intl.DateTimeFormat('es-DO',{timeZone:'America/Santo_Domingo',dateStyle:'short',timeStyle:'short'}).format(new Date(settings.prepared_at));status.textContent+=` Última preparación de hoy: ${stamp}.`;}
  link();
 }
 function showPreview(){
  const byType=new Map((preview.counts||[]).map(c=>[c.type,c]));
  const t=preview.totals||{};
  totals.replaceChildren(h('p',{},`${num(t.total??0)} pendientes · ${num(t.overdue??0)} vencidos · ${num(t.high??0)} de prioridad alta · ${num(t.unassigned??0)} sin responsable`),
   h('p',{class:'small muted'},preview.scope==='equipo_visible'?'Equipo y clientes dentro de su acceso.':'Solo tareas asignadas a su usuario, incluidas las suplencias vigentes.'),
   h('ul',{},...DIGEST_TYPES.map(([type,label])=>h('li',{},`${label}: ${num(byType.get(type)?.total??0)}`))));
  text.textContent=dailyDigestText(preview);link();
 }
 async function load(){
  busyForm(true);feedback.replaceChildren();
  const results=await Promise.allSettled([getDailyDigestSettings(),getDailyDigestPreview()]);
  if(!alive())return;
  if(results[0].status==='fulfilled'){settings=results[0].value;showSettings();}
  else{settings=null;feedback.append(note('No se pudieron consultar las preferencias. Intente actualizar.','error'));}
  if(results[1].status==='fulfilled'){preview=results[1].value;showPreview();}
  else{preview=null;totals.replaceChildren(note('No se pudo consultar la bandeja. No se muestran ceros ni un mensaje para enviar.','error'));text.textContent='';}
  link();busyForm(false);save.disabled=!settings;
 }
 refresh.addEventListener('click',async()=>{
  if(busy)return;
  if(!settings){await load();return;}
  busyForm(true);feedback.replaceChildren();
  try{const data=await getDailyDigestPreview();if(!alive())return;preview=data;showPreview();feedback.append(note('Vista previa actualizada.','ok'));}
  catch(_){if(!alive())return;preview=null;text.textContent='';totals.replaceChildren(note('No se pudo actualizar el resumen. Vuelva a intentarlo.','error'));link();}
  finally{if(alive()){busyForm(false);refresh.focus();}}
 });
 form.addEventListener('submit',async event=>{
  event.preventDefault();if(busy||ctx.viewAs||viewAsState.active)return;
  busyForm(true);feedback.replaceChildren();
  try{const data=await saveDailyDigestSettings(phone.value,time.value);if(!alive())return;settings=data;showSettings();feedback.append(note('Preferencias guardadas. No se envió ningún mensaje.','ok'));}
  catch(e){if(alive())feedback.append(note(e.message||'No se pudieron guardar las preferencias.','error'));}
  finally{if(alive())busyForm(false);}
 });
 await load();
}
