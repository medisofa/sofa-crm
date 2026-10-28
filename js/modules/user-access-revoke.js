/** Candidato: requiere las RPC de revocación instaladas y validadas. */
import {html} from '../utils/dom.js';
import {formDialog, fieldError, toast} from '../utils/ui.js';
import {supabase} from '../services/iter18.js';

async function request(name, args) {
  const {data,error}=await supabase.rpc(name,args);
  if(error) {
    if(error.code==='PGRST202'||error.code==='42883') throw new Error('La gestión por selección aún no está habilitada. No se modificó ningún acceso.');
    throw new Error(error.message||'No se pudo verificar la operación.');
  }
  return data;
}
export async function revokeSelectedAccesses(account, ctx, reload) {
  if(ctx.role!=='super_admin'||!ctx.session?.user?.id||ctx.session.user.id===account.user_id||account.protectedAdmin) throw new Error('Esta cuenta requiere otro procedimiento de administración.');
  const memberships=account.memberships;
  if(!memberships.length||memberships.some(m=>m.conflict||!m.organization_id)||new Set(memberships.map(m=>m.organization_id)).size!==memberships.length) throw new Error('Primero revisa las inconsistencias de los accesos.');
  const review=await formDialog({title:'Seleccionar accesos para revocar',submitLabel:'Revisar selección',wide:true,
    body:html`<p><b>${account.full_name||account.email}</b> · ${account.email}</p><p>Marca solo las organizaciones a las que esta cuenta debe dejar de acceder. Se conservan la cuenta y su historial.</p>
      <fieldset><legend>Accesos de la cuenta</legend>${memberships.map((m,i)=>html`<label class="user-membership check"><input type="checkbox" name="access_${i}"> ${m.role_name||m.role_code} · ${m.organization||m.organization_id}</label>`)}</fieldset><p role="alert" id="selection-error"></p>`,
    onSubmit:async(d,form)=>{
      const selected=memberships.filter((m,i)=>d[`access_${i}`]===true);
      if(!selected.length){form.querySelector('#selection-error').textContent='Selecciona al menos un acceso.';return false;}
      const orgs=selected.map(m=>m.organization_id);
      const preview=await request('admin_access_revoke_preview',{p_user:account.user_id,p_orgs:orgs});
      if(preview?.user_id!==account.user_id||!Array.isArray(preview.accesses)||!Array.isArray(preview.blockers)||!preview.expected||preview.accesses.length!==orgs.length||new Set(preview.accesses.map(a=>a.organization_id)).size!==orgs.length||preview.accesses.some(a=>!orgs.includes(a.organization_id)))throw new Error('La vista previa no coincide con la selección.');
      if(preview.accesses.some(a=>selected.find(m=>m.organization_id===a.organization_id)?.role_code!==a.role_code))throw new Error('Un rol cambió desde que abriste la cuenta. Actualiza el listado.');
      if(preview.can_revoke!==true||preview.blockers.length)throw new Error(preview.blockers.join(' ')||'Esta selección no se puede revocar.');
      return {preview,orgs,selected};
    }});
  if(!review)return;
  let saved=false;
  await formDialog({title:'Confirmar revocación de accesos',submitLabel:'Revocar accesos seleccionados',wide:true,
    body:html`<p><b>${account.full_name||account.email}</b></p><ul>${review.selected.map(m=>html`<li>${m.role_name||m.role_code} · ${m.organization||m.organization_id}</li>`)}</ul>
      <p>Los demás accesos se conservan. Si seleccionaste todos, la cuenta quedará sin acceso operativo. Esta acción no activa el perfil ni asigna otro rol.</p>
      <div class="field"><label for="revoke-reason">Motivo obligatorio</label><textarea id="revoke-reason" name="reason" maxlength="1000" rows="3"></textarea></div>
      <div class="field"><label class="check"><input id="revoke-confirm" name="confirmed" type="checkbox"> Confirmo la cuenta y las organizaciones seleccionadas.</label></div>`,
    onOpen:(form)=>{for(const name of ['reason','confirmed'])form.elements[name].addEventListener('input',()=>fieldError(form.elements[name],null));},
    onSubmit:async(d,form)=>{
      if((d.reason||'').trim().length<12){fieldError(form.elements.reason,'Describe el motivo con al menos 12 caracteres.');form.elements.reason.focus();return false;}
      if(d.confirmed!==true){fieldError(form.elements.confirmed,'Confirma los accesos seleccionados.');form.elements.confirmed.focus();return false;}
      const result=await request('admin_access_revoke_apply',{p_user:account.user_id,p_orgs:review.orgs,p_reason:d.reason.trim(),p_expected:review.preview.expected});
      if(result?.ok!==true||!result.audit_id||result.user_id!==account.user_id)throw new Error('No se confirmó el resultado. Revisa la cuenta antes de repetir.');
      saved=true;toast('Accesos revocados y registrados en auditoría.','ok');return true;
    }});
  if(saved)await reload();
}
