/** PSS y contrato: permisos confirmados por servidor, sin tocar los datos de la reclamación. */
import {rpc,h,note} from '../services/iter18.js';
import {sb} from '../supabase.js';
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
   const box=h('section',{class:'note info'},h('b',{},'Identificación con la ARS'),h('p',{class:'small'},'El personal de SoFa puede hacer el primer registro. Los cambios posteriores requieren Administrador o Super Admin.'));
   function field(label,value,editable,save){
    const input=h('input',{value:value||'',maxlength:'120','aria-label':label,readOnly:!editable});
    const msg=h('div',{'aria-live':'polite'});
    const button=h('button',{type:'button',class:'btn sm'},value?'Actualizar':'Registrar por primera vez');
    button.addEventListener('click',async()=>{if(!input.value.trim()){msg.replaceChildren(note('Indique el valor antes de guardar.','error'));return;}button.disabled=true;try{await save(input.value.trim());await refresh(provider,ars,service);}catch(e){msg.replaceChildren(note(e.message,'error'));button.disabled=false;}});
    box.append(h('div',{class:'field'},h('label',{},label,input),editable?button:h('span',{class:'hint'},'Cambios: Administración'),msg));
   }
   field('Código PSS del médico',c.code,c.can_edit_pss,value=>rpc('set_ars_code_status',{p_provider:provider,p_ars:ars,p_status:'codificado',p_code:value,p_note:'Registro desde captura rápida'}));
   if(service?.tariff_id)field('Referencia de contrato',service.contract_ref||c.contract_ref,c.can_edit_contract,async value=>{await rpc('set_capture_contract_reference',{p_tariff:service.tariff_id,p_reference:value});service.contract_ref=value;});
   else box.append(h('p',{class:'small'},'Seleccione un servicio contratado para registrar su referencia de contrato.'));
   host.replaceChildren(box);
  }catch(e){if(n===seq&&host.isConnected)host.replaceChildren(note(e.message,'error'));}
 };
}
