/** Recepción en oficina y conciliación de lotes contra reclamaciones reales. */
import { html, render as paint, $, $$ } from '../utils/dom.js';
import { loadInto, busy, toast, friendlyError, opt, formDialog, fieldError } from '../utils/ui.js';
import { money, date } from '../utils/formatters.js';
import { activeArs, captureProviders } from '../services/claims.js';
import { officeReceptionRoles, receptionClients, listOfficeReceptions, getOfficeReception, createOfficeReception,
  assignOfficeClaim, cancelOfficeReception, receptionCandidates, uploadReceptionFile, receptionFiles, receptionFileUrl } from '../services/office-receptions.js';
import { receptionTotals, receiptText, receiptImage, downloadReceipt } from '../utils/reception-receipt.js';
const BASE = '#/retiros/oficina';
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone:'America/Santo_Domingo',year:'numeric',month:'2-digit',day:'2-digit' }).format(new Date());
const serviceOptions = ['Consulta ambulatoria','Consulta especializada','Laboratorio','Imagenología','Procedimientos','Cirugía','Emergencia','Odontología','Terapia física','Otro'];
const error = (box,e) => paint(box,html`<div class="note bad" role="alert">${friendlyError(e)}</div>`);
export async function render(main,ctx) {
  const manage=officeReceptionRoles.includes(ctx.role);
  const id=(ctx.arg || '').split('/')[1];
  paint(main,html`<div class="page-head"><div class="t"><p><a href="#/retiros">← Retiros y recepción</a></p><h2>Recepción en oficina</h2><p>Registra lo entregado, emite el acuse y concilia con las reclamaciones capturadas.</p></div>
    ${manage && !id?html`<a class="btn primary" href="${BASE}/nueva">+ Registrar recepción</a>`:''}</div><div id="office-body"></div>`);
  const body=$('#office-body',main);
  if(id==='nueva') {
    if(!manage) {error(body,new Error('Su perfil solo puede consultar recepciones.'));return;}
    return showForm();
  }
  if(id) return detail();
  let page=0,org='';
  paint(body,html`<div class="toolbar"><label for="office-client-filter">Cliente</label><select id="office-client-filter" class="input"><option value="">Todos los clientes visibles</option></select></div><div id="office-history"></div>`);
  receptionClients().then(rows=>{if($('#office-client-filter',main))paint($('#office-client-filter',main),html`<option value="">Todos los clientes visibles</option>${rows.map(c=>opt(c.id,c.legal_name))}`);}).catch(e=>toast(friendlyError(e),'bad'));
  const history=$('#office-history',body);
  const load=()=>loadInto(history,()=>listOfficeReceptions({org,page}),r=>html`
    <div class="table-wrap"><table class="t cards"><thead><tr><th>Folio / fecha</th><th>Cliente</th><th>Entregó / recibió</th><th>Recibidas</th><th>Monto declarado</th><th>Estado</th></tr></thead><tbody>
    ${r.data.map(x=>{const t=receptionTotals(x);return html`<tr><td data-l="Folio"><a href="${BASE}/${x.id}">${x.folio}</a><div class="small muted">${date(x.received_on)}</div></td><td data-l="Cliente">${x.organizations?.legal_name}<div class="small muted">${x.providers?.full_name || 'Cliente completo'}</div></td><td data-l="Entregó / recibió">${x.delivered_by}<div class="small muted">${x.received_by_label}</div></td><td data-l="Recibidas">${t.count}</td><td data-l="Monto declarado">${money(t.amount)}</td><td data-l="Estado">${x.status==='anulada'?'Anulada':'Recibida · consultar conciliación'}</td></tr>`;})}
    </tbody></table></div><div class="toolbar"><button class="btn" data-history-page="${page-1}" ${page===0?'disabled':''}>Anterior</button><span>Página ${page+1} · ${r.count} recepciones</span><button class="btn" data-history-page="${page+1}" ${(page+1)*25>=r.count?'disabled':''}>Siguiente</button></div>`,{isEmpty:r=>!r.data.length,empty:()=>html`<div class="note">No hay recepciones para este cliente.${manage?html` <a href="${BASE}/nueva">Registrar la primera</a>`:''}</div>`});
  $('#office-client-filter',body).addEventListener('change',e=>{org=e.target.value;page=0;load();});
  history.addEventListener('click',e=>{const b=e.target.closest('[data-history-page]');if(b){page=Number(b.dataset.historyPage);load();}});
  return load();

  async function showForm() {
    let clients,ars,providers;
    try {[clients,ars,providers]=await Promise.all([receptionClients(),activeArs(),captureProviders({realOnly:true})]);}
    catch(e){error(body,e);body.insertAdjacentHTML('beforeend','<button class="btn" id="retry-office-form">Reintentar</button>');$('#retry-office-form',body).onclick=showForm;return;}
    if(!body.isConnected)return;
    const requestId=crypto.randomUUID();let frozenPayload=null;
    paint(body,html`<section class="card"><h3>Registrar entrega de reclamaciones</h3><p class="small muted">Una línea por ARS y tipo de servicio. Los montos son declarados y no generan cuentas por cobrar.</p>
      <form id="office-form"><div class="form-grid">
      <div class="field"><label for="of-org">Cliente que entrega *</label><select id="of-org" name="organization_id" required><option value="">Seleccionar cliente</option>${clients.map(c=>opt(c.id,c.legal_name))}</select></div>
      <div class="field"><label for="of-provider">Médico (opcional)</label><select id="of-provider" name="provider_id"><option value="">Todo el cliente</option></select></div>
      <div class="field"><label for="of-day">Fecha de recepción *</label><input id="of-day" name="received_on" type="date" value="${today()}" max="${today()}" required></div>
      <div class="field"><label for="of-period">Período de servicios</label><input id="of-period" name="service_period" type="month"></div>
      <div class="field"><label for="of-delivered">Entregado por *</label><input id="of-delivered" name="delivered_by" maxlength="160" required placeholder="Secretaria, mensajero o médico"></div>
      <div class="field"><label for="of-received">Recibido por *</label><input id="of-received" name="received_by_label" maxlength="160" value="${ctx.profile?.full_name || ''}" required></div></div>
      <h3>Detalle de lo recibido</h3><div id="office-lines"></div><button type="button" class="btn" id="of-add">+ Agregar línea</button>
      <p class="note" id="of-totals" role="status"></p>
      <div class="field"><label for="of-notes">Observaciones</label><textarea id="of-notes" name="notes" rows="3" maxlength="2000" placeholder="Faltantes, entregas pendientes o estado de los documentos"></textarea></div>
      <p class="small muted">Podrás adjuntar fotos o PDF al guardar. El acuse acredita la entrega; no confirma validación ni cobertura.</p>
      <div id="of-message" aria-live="polite"></div><div class="toolbar"><button type="submit" class="btn primary">Guardar y abrir acuse</button><a class="btn" href="${BASE}">Cancelar</a></div></form></section>`);
    const form=$('#office-form',body),lines=$('#office-lines',form);let lineNo=0;
    const totals=()=>{let count=0,amount=0;$$('[data-office-line]',lines).forEach(r=>{count+=Number($('[data-count]',r).value)||0;amount+=Number($('[data-amount]',r).value)||0;});$('#of-totals',form).textContent=`Total recibido: ${count} reclamaciones · Monto declarado: ${money(amount)}`;};
    function addLine(){if(lines.children.length>=100)return;const n=++lineNo,box=document.createElement('fieldset');box.dataset.officeLine='';box.className='office-line';paint(box,html`<legend>Línea ${n}</legend><div class="office-line-fields">
      <div class="field"><label for="of-ars-${n}">ARS *</label><select id="of-ars-${n}" data-ars required><option value="">Seleccionar ARS</option>${ars.map(a=>opt(a.id,a.name))}</select></div>
      <div class="field"><label for="of-service-${n}">Tipo de servicio *</label><input id="of-service-${n}" data-service list="office-service-options" minlength="2" maxlength="160" required></div>
      <div class="field"><label for="of-count-${n}">Reclamaciones *</label><input id="of-count-${n}" data-count type="number" min="1" max="100000" step="1" required></div>
      <div class="field"><label for="of-amount-${n}">Monto declarado (RD$) *</label><input id="of-amount-${n}" data-amount type="number" min="0" max="999999999999.99" step="0.01" required></div>
      <button type="button" class="btn" data-remove-line aria-label="Eliminar línea ${n}">Quitar</button></div>`);lines.append(box);totals();}
    const dl=document.createElement('datalist');dl.id='office-service-options';paint(dl,html`${serviceOptions.map(s=>html`<option value="${s}"></option>`)}`);form.append(dl);addLine();
    $('#of-org',form).addEventListener('change',e=>paint($('#of-provider',form),html`<option value="">Todo el cliente</option>${providers.filter(p=>p.organization_id===e.target.value).map(p=>opt(p.id,p.full_name))}`));
    $('#of-add',form).onclick=addLine;lines.addEventListener('input',totals);lines.addEventListener('click',e=>{const b=e.target.closest('[data-remove-line]');if(b){if(lines.children.length===1){toast('Conserve al menos una línea.','warn');return;}b.closest('fieldset').remove();totals();}});
    form.addEventListener('submit',e=>{e.preventDefault();if(!form.reportValidity())return;busy(e.submitter,async()=>{
      try {
        const v=Object.fromEntries(new FormData(form));v.service_period=v.service_period?`${v.service_period}-01`:null;
        v.lines=$$('[data-office-line]',lines).map(r=>({ars_id:$('[data-ars]',r).value,service_label:$('[data-service]',r).value.trim(),declared_count:Number($('[data-count]',r).value),declared_amount:Number($('[data-amount]',r).value)}));
        if(!frozenPayload)frozenPayload=v;
        $$('input,select,textarea,button[type="button"]',form).forEach(el=>el.disabled=true);
        // A timeout may occur after commit. Keep the same id and payload on retry.
        const saved=await createOfficeReception(requestId,frozenPayload);location.hash=`${BASE}/${saved}`;
      }catch(err){
        error($('#of-message',form),err);
        if (/^(22|23|42)/.test(String(err.code || ''))) {
          frozenPayload=null;
          $$('input,select,textarea,button[type="button"]',form).forEach(el=>el.disabled=false);
        } else {
          $('#of-message',form).append(document.createTextNode('La respuesta no se confirmó. Reintenta guardar: se verificará la misma recepción sin duplicarla.'));
        }
      }
    });});
  }

  async function detail() {
    return loadInto(body,()=>getOfficeReception(id),r=>{
      const t=receptionTotals(r);const linkedCount=r.links.length;
      const linkedAmount=r.links.reduce((s,x)=>s+Number(x.service_lines?.amount || 0),0);
      const reconciled=linkedCount===t.count && Math.abs(linkedAmount-t.amount)<0.005;
      return html`<section class="card"><div class="page-head"><div class="t"><h3>${r.folio} · ${r.organizations?.legal_name}</h3><p>${date(r.received_on)} · Entregó: ${r.delivered_by} · Recibió: ${r.received_by_label}</p></div><span class="pill ${r.status==='anulada'?'bad':reconciled?'ok':'warn'}">${r.status==='anulada'?'Anulada':reconciled?'Conciliada':'Pendiente de conciliación'}</span></div>
      ${r.notes?html`<p>${r.notes}</p>`:''}${r.cancelled_reason?html`<div class="note bad">Anulada: ${r.cancelled_reason}</div>`:''}
      <div class="toolbar"><button class="btn primary" data-receipt>Descargar acuse en imagen</button><button class="btn" data-share>Compartir acuse</button><a class="btn" href="#/captura">Ir a captura</a><a class="btn" href="${BASE}">Ver recepciones</a></div>
      <div class="office-summary"><div><b>${t.count}</b><span>Reclamaciones recibidas</span></div><div><b>${linkedCount}</b><span>Capturadas vinculadas</span></div><div><b>${money(t.amount)}</b><span>Monto declarado</span></div><div><b>${money(linkedAmount)}</b><span>Monto capturado vinculado</span></div></div>
      <p class="small muted">Vincula reclamaciones existentes del mismo cliente y ARS. Verifica el servicio antes de vincular. No se crean reclamaciones ni se cambian sus estados.</p>
      ${r.office_reception_lines.map(l=>{const linked=r.links.filter(x=>x.reception_line_id===l.id),sum=linked.reduce((s,x)=>s+Number(x.service_lines?.amount||0),0);const ok=linked.length===Number(l.declared_count)&&Math.abs(sum-Number(l.declared_amount))<0.005;return html`<section class="office-item"><div class="page-head"><div class="t"><h3>${l.ars?.name} · ${l.service_label}</h3><p>Recibidas: ${l.declared_count} · ${money(l.declared_amount)}<br>Vinculadas: ${linked.length} · ${money(sum)}</p></div><span class="pill ${ok?'ok':'warn'}">${ok?'Conciliada':`Diferencia: ${Number(l.declared_count)-linked.length} reclamaciones · ${money(Number(l.declared_amount)-sum)}`}</span></div>
        ${linked.map(x=>html`<div class="office-linked"><a href="#/reclamaciones/${x.service_line_id}">${x.service_lines?.claim_folio || x.service_line_id}</a><span>${x.service_lines?.patient_name} · ${x.service_lines?.service_name_snapshot || ''} · ${money(x.service_lines?.amount)}</span>${manage&&r.status!=='anulada'?html`<button class="btn sm" data-unlink="${x.service_line_id}" data-item="${l.id}">Desvincular</button>`:''}</div>`)}
        ${manage&&r.status!=='anulada'?html`<button class="btn" data-link="${l.id}">Vincular reclamaciones capturadas</button>`:''}</section>`;})}
      <section class="office-item"><h3>Evidencia de lo recibido</h3><p class="small muted">Fotos y PDF privados, hasta 10 MB por archivo. Los enlaces de lectura vencen en 5 minutos.</p>
      ${manage&&r.status!=='anulada'?html`<label for="office-files" class="etiqueta">Adjuntar fotos o PDF</label><input id="office-files" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" multiple>`:''}<div id="office-files-msg" aria-live="polite"></div><div id="office-file-list"></div></section>
      ${manage&&r.status!=='anulada'?html`<button class="btn" data-cancel-reception>Anular recepción</button>`:''}<div id="office-detail-msg" aria-live="polite"></div></section>`;
    }).then(async r=>{if(!r||!body.isConnected)return;
      const run=(button,fn)=>busy(button,async()=>{try{await fn();}catch(e){error($('#office-detail-msg',body),e);}});
      $('[data-receipt]',body).onclick=e=>run(e.currentTarget,async()=>downloadReceipt(await receiptImage(r)));
      $('[data-share]',body).onclick=e=>run(e.currentTarget,async()=>{const file=await receiptImage(r);if(navigator.canShare?.({files:[file]})){try{await navigator.share({files:[file],title:r.folio,text:receiptText(r)});}catch(e){if(e.name!=='AbortError')throw e;}}else{downloadReceipt(file);toast('Acuse descargado. Adjunta la imagen en WhatsApp o correo.','ok');}});
      $$('[data-link]',body).forEach(b=>b.onclick=()=>linkDialog(r,r.office_reception_lines.find(l=>l.id===b.dataset.link)).catch(e=>error($('#office-detail-msg',body),e)));
      $$('[data-unlink]',body).forEach(b=>b.onclick=()=>run(b,async()=>{await assignOfficeClaim(b.dataset.item,b.dataset.unlink,true);await detail();}));
      $('[data-cancel-reception]',body)?.addEventListener('click',async()=>{const result=await formDialog({title:`Anular ${r.folio}`,submitLabel:'Anular recepción',body:html`<p>Se conserva el acuse y la evidencia. Se liberan sus vinculaciones; las reclamaciones no se eliminan.</p><div class="field"><label for="office-cancel-reason">Motivo *</label><textarea id="office-cancel-reason" name="reason" maxlength="1000"></textarea></div>`,onSubmit:async(v,f)=>{if(v.reason.trim().length<5){fieldError(f.elements.reason,'Indique al menos 5 caracteres.');return false;}await cancelOfficeReception(r.id,v.reason.trim());return true;}});if(result)detail();});
      async function files(){const box=$('#office-file-list',body);await loadInto(box,()=>receptionFiles(r),rows=>html`${rows.map(f=>html`<p><button class="btn" data-file="${f.name}">${f.name.slice(37)}</button></p>`)}`,{empty:()=>html`<p class="small muted">Sin archivos adjuntos.</p>`});$$('[data-file]',box).forEach(b=>b.onclick=()=>run(b,async()=>{const win=window.open('','_blank');try{const url=await receptionFileUrl(r,b.dataset.file);if(win){win.opener=null;win.location.href=url;}else paint($('#office-files-msg',body),html`<a href="${url}" target="_blank" rel="noopener">Abrir archivo (enlace temporal)</a>`);}catch(e){win?.close();throw e;}}));}
      $('#office-files',body)?.addEventListener('change',async e=>{const input=e.target,filesToUpload=[...input.files];input.disabled=true;try{for(const file of filesToUpload)await uploadReceptionFile(r,file);input.value='';paint($('#office-files-msg',body),html`<p class="note ok">Archivos guardados.</p>`);}catch(err){error($('#office-files-msg',body),err);}finally{input.disabled=false;await files();}});
      await files();
    });
  }

  async function linkDialog(header,item) {
    let page=0,query='';
    await formDialog({title:`Vincular · ${item.ars?.name} · ${item.service_label}`,submitLabel:'Cerrar',wide:true,
      body:html`<p>Busca por folio, paciente o NSS. Comprueba servicio, fecha y monto antes de vincular.</p><div class="toolbar"><label for="office-search">Buscar reclamación</label><input id="office-search" type="search" class="input"><button type="button" class="btn" data-find>Buscar</button></div><div id="office-candidates"></div>`,onSubmit:async()=>true,
      onOpen:(form,dialog)=>{
        const box=$('#office-candidates',form);
        const load=()=>loadInto(box,()=>receptionCandidates(header,item,query,page),r=>html`${r.data.map(c=>html`<div class="office-linked"><span><b>${c.folio}</b> · ${c.patient_name}<br>${c.service_name} · ${date(c.service_date)} · ${money(c.claimed)}</span><button type="button" class="btn" data-assign="${c.id}" ${header.links.some(x=>x.service_line_id===c.id)?'disabled':''}>${header.links.some(x=>x.service_line_id===c.id)?'Vinculada':'Vincular'}</button></div>`)}<div class="toolbar"><button type="button" class="btn" data-candidate-page="${page-1}" ${page===0?'disabled':''}>Anterior</button><span>Página ${page+1} · ${r.count} resultados</span><button type="button" class="btn" data-candidate-page="${page+1}" ${(page+1)*25>=r.count?'disabled':''}>Siguiente</button></div>`,{isEmpty:r=>!r.data.length,empty:()=>html`<p class="note">No se encontraron reclamaciones de este cliente y ARS. Captúralas primero y vuelve a vincularlas aquí.</p>`});
        $('[data-find]',form).onclick=()=>{query=$('#office-search',form).value;page=0;load();};
        $('#office-search',form).onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();$('[data-find]',form).click();}};
        box.addEventListener('click',e=>{const p=e.target.closest('[data-candidate-page]');if(p){page=Number(p.dataset.candidatePage);load();return;}const b=e.target.closest('[data-assign]');if(b)busy(b,async()=>{try{await assignOfficeClaim(item.id,b.dataset.assign);header.links.push({service_line_id:b.dataset.assign});await load();await detail();}catch(err){toast(friendlyError(err),'bad');}});});
        // Refresh also after Escape/Cancelar, since links are saved individually.
        dialog.addEventListener('close',()=>detail());load();
      }});
  }
}
