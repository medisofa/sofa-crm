/** PSS y contrato: permisos confirmados por servidor, sin tocar los datos de la reclamación. */
import {rpc,h,note} from '../services/iter18.js';
import {sb} from '../supabase.js';
import {viewAsState} from '../utils/view-as-state.js';

/** Origen de la gestión, separado de quién registra (el servidor audita auth.uid()). */
export function pssRegistrationControls(existingCode, id, channel){
 const source=h('select',{id:`${id}-source`,'aria-label':'Origen de la gestión del código PSS'},
  h('option',{value:''},'Seleccione el origen…'),h('option',{value:'medico'},'Gestión directa del médico'),h('option',{value:'sofa'},'Gestión SoFa'));
 const reason=h('textarea',{id:`${id}-reason`,rows:'2',maxlength:'300','aria-label':'Motivo u observación del código PSS',placeholder:existingCode?'Motivo obligatorio si cambia el código (mínimo 5 caracteres)':'Ej.: código recibido por el médico; tarifario pendiente'});
 const element=h('div',{},h('label',{for:source.id},'Origen de la gestión',source),h('label',{for:reason.id},'Motivo / observación',reason));
 return {element,source,reason,getNote(value){
  const changed=String(value||'').trim()!==String(existingCode||'').trim();
  if(changed&&!source.value)throw new Error('Seleccione si el código fue gestionado directamente por el médico o por SoFa.');
  if(changed&&existingCode&&reason.value.trim().length<5)throw new Error('Indique el motivo del cambio de código (mínimo 5 caracteres).');
  if(!changed&&!source.value&&!reason.value.trim())return null;
  const origin=source.value==='medico'?'Gestión directa del médico':source.value==='sofa'?'Gestión SoFa':null;
  return [origin&&`Origen: ${origin}.`,channel,reason.value.trim()&&`Motivo / observación: ${reason.value.trim()}`].filter(Boolean).join(' ');
 }};
}

export function captureIdentifiers(host){
 let seq=0;
 return async function refresh(provider,ars,service){
  const n=++seq;host.replaceChildren();if(!provider||!ars)return;
  host.replaceChildren(note('Consultando código PSS y contrato…'));
  try{
   let plan=null;
   if(service?.tariff_id){const {data,error}=await sb().from('tariffs').select('plan_id').eq('id',service.tariff_id).single();if(error)throw error;plan=data.plan_id;}
   const c=await rpc('ars_identifier_context',{p_provider:provider,p_ars:ars,p_plan:plan});
   if(n!==seq||!host.isConnected)return;
   const support=viewAsState.active;
   const box=h('section',{class:'note info'},h('b',{},'Identificación con la ARS'),h('p',{class:'small'},'Puede registrar un código PSS ya asignado, aunque el tarifario esté pendiente. El médico y el personal autorizado de SoFa pueden hacer el primer registro. Los cambios posteriores requieren Administrador o Super Admin.'));
   if(support)box.append(note('Modo soporte, solo lectura. Salga del modo soporte para registrar o actualizar datos.','info'));
   function field(label,value,editable,save,registration=null){
    editable=editable&&!support;
    const input=h('input',{value:value||'',maxlength:'120','aria-label':label,readOnly:!editable});
    const msg=h('div',{'aria-live':'polite'});
    const button=h('button',{type:'button',class:'btn sm'},value?'Actualizar':'Registrar por primera vez');
    button.addEventListener('click',async()=>{
     if(viewAsState.active){msg.replaceChildren(note('Salga del modo soporte para registrar o actualizar datos.','info'));return;}
     if(!input.value.trim()){msg.replaceChildren(note('Indique el valor antes de guardar.','error'));return;}
     button.disabled=true;
     try{await save(input.value.trim(),registration?.getNote(input.value.trim()));if(n===seq&&host.isConnected)await refresh(provider,ars,service);}
     catch(e){msg.replaceChildren(note(e.message,'error'));button.disabled=false;}
    });
    box.append(h('div',{class:'field'},h('label',{},label,input),editable&&registration?registration.element:null,editable?button:h('span',{class:'hint'},support?'Solo lectura en modo soporte':'Cambios: Administración'),msg));
   }
   const registration=pssRegistrationControls(c.code,'capture-pss','Registro desde captura rápida.');
   field('Código PSS del médico',c.code,c.can_edit_pss,(value,p_note)=>rpc('set_ars_code_status',{p_provider:provider,p_ars:ars,p_status:'codificado',p_code:value,p_note}),registration);
   if(service?.tariff_id)field('Referencia de contrato',service.contract_ref||c.contract_ref,c.can_edit_contract,async value=>{await rpc('set_capture_contract_reference',{p_tariff:service.tariff_id,p_reference:value});service.contract_ref=value;});
   else box.append(h('p',{class:'small'},'El código PSS no requiere una tarifa cargada. Para registrar la referencia de contrato debe seleccionar un servicio contratado.'));
   host.replaceChildren(box);
  }catch(e){if(n===seq&&host.isConnected)host.replaceChildren(note(e.message,'error'));}
 };
}
