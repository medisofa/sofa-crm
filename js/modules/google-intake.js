/** SOFA · Carga externa desde Google Sheets / Google Form.
 * Permite completar/corregir datos dentro de SOFA antes de importar.
 * Cada corrección queda en audit_log con usuario, fecha, campos y valores antes/después.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, busy, confirmDialog, formDialog, opt, requireFields } from '../utils/ui.js';
import { money, todayISO } from '../utils/formatters.js';
import { captureProviders, activeArs, contractedServices } from '../services/claims.js';
import { cie10Suggestions } from '../services/calidad-dato.js';
import { createIntakeAutosave } from '../utils/intake-autosave.js';
import { intakeSnapshot, replayIntakeAudit } from '../utils/intake-draft.js';
import { registerProgressGuard } from '../utils/progress-guard.js';
import { rpc } from '../services/iter18.js';
import { can } from '../utils/permissions.js';
import { contractDialog } from './contracts.js?v=5.30.0';

const TEMPLATE_URL = 'https://docs.google.com/spreadsheets/d/1VeUb9RQ_jGBN9chr6QCiV-8Gp-2b2JKaj159qo6a-ps/edit';
const REQUIRED = ['Médico / Prestador *','ARS *','Fecha del servicio *','Paciente *','NSS / No. afiliado *','Servicio / Procedimiento *'];
const EDITABLE = [
  'Médico / Prestador *','ARS *','Fecha del servicio *','Modalidad','Paciente *','NSS / No. afiliado *',
  'No. autorización','Fecha autorización','Cédula paciente','Diagnóstico CIE-10','Centro / clínica',
  'Servicio / Procedimiento *','Cantidad','Monto a reclamar','Motivo ajuste','Observaciones'
];

const norm = (v) => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const num = (v) => {
  if(String(v??'').trim()==='')return null;
  let s=String(v??'').replace(/[^0-9,.-]/g,'');
  if(s.includes(',')&&s.includes('.')) s=s.lastIndexOf(',')>s.lastIndexOf('.')?s.replace(/\./g,'').replace(',','.'):s.replace(/,/g,'');
  else if(s.includes(','))s=/^-?\d{1,3}(,\d{3})+$/.test(s)?s.replace(/,/g,''):s.replace(',','.');
  const n=Number(s); return Number.isFinite(n)?n:null;
};
const parseDate = (v) => {
  const s=String(v??'').trim();const m=s.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  const value=/^\d{4}-\d{2}-\d{2}$/.test(s)?s:m?`${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')}`:'';
  if(!value)return '';const d=new Date(`${value}T00:00:00Z`);
  return Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==value?'':value;
};

function parseCsv(text){
  const rows=[]; let row=[]; let cell=''; let q=false;let line=1,start=1;
  for(let i=0;i<text.length;i++){
    const ch=text[i], nx=text[i+1];
    if(ch==='\r'||(ch==='\n'&&text[i-1]!=='\r'))line++;
    if(ch==='"' && q && nx==='"'){cell+='"';i++;continue;}
    if(ch==='"'){q=!q;continue;}
    if(ch===',' && !q){row.push(cell);cell='';continue;}
    if((ch==='\n'||ch==='\r')&&!q){
      if(ch==='\r'&&nx==='\n') i++;
      row.push(cell);cell='';
      if(row.some((x)=>String(x).trim()!=='')){row.sourceRow=start;rows.push(row);}
      row=[];start=line;continue;
    }
    cell+=ch;
  }
  row.push(cell); if(row.some((x)=>String(x).trim()!=='')){row.sourceRow=start;rows.push(row);}
  return rows;
}
function toObjects(rows){
  if(!rows.length) return [];
  const headers=rows[0].map((h)=>String(h).trim());
  return rows.slice(1).map((r,i)=>({...Object.fromEntries(headers.map((h,j)=>[h,r[j]??''])),__row:r.sourceRow||i+2}));
}
function exact(items, value, fields){
  const n=norm(value); if(!n) return null;
  const hits=items.filter((x)=>fields.some((f)=>norm(x?.[f])===n));
  return hits.length===1?hits[0]:null;
}
function changedValues(before, after){
  const fields=EDITABLE.filter((k)=>String(before?.[k]??'')!==String(after?.[k]??''));
  const oldValues=Object.fromEntries(fields.map((k)=>[k,before?.[k]??'']));
  const newValues=Object.fromEntries(fields.map((k)=>[k,after?.[k]??'']));
  return {fields,oldValues,newValues};
}

export async function render(main, ctx){
  const S={draftId:null,providers:[],ars:[],rows:[],validated:[],busy:false,initializing:true,sourceName:'',editor:null,auditCursor:0,reviewFilter:'all',batchId:crypto.randomUUID?.()||String(Date.now())};
  paint(main,html`
    <div class="page-head"><div class="t"><h2>Carga Google Sheets / Form</h2>
      <p>Importa reclamaciones capturadas fuera de SOFA. Si faltan datos, el mismo usuario puede completarlos aquí antes de importar; cada cambio queda en bitácora.</p></div>
      <div class="toolbar" style="margin:0"><a class="btn" href="${TEMPLATE_URL}" target="_blank" rel="noopener">Abrir plantilla Google Sheets</a></div>
    </div>
    <section id="gi-draft-panel" class="card" style="margin-bottom:14px">
      <h3>Progreso de la carga</h3><p id="gi-draft-status" role="status" aria-live="polite">Comprobando cargas guardadas…</p>
      <p id="gi-source-name" class="small muted"></p>
      <div class="toolbar"><button type="button" class="btn" id="gi-save-progress">Guardar progreso ahora</button><button type="button" class="btn" id="gi-fork-progress" hidden>Conservar cambios como copia</button><select id="gi-draft-list" aria-label="Cargas guardadas"></select><button type="button" class="btn" id="gi-resume-progress">Reanudar carga</button><button type="button" class="btn" id="gi-resume-editor" hidden>Reanudar edición pendiente</button><button type="button" class="btn" id="gi-discard-editor" hidden>Descartar edición pendiente</button></div>
      <details><summary>Recuperar una revisión anterior al autoguardado</summary><p>Conserve abierta la pestaña anterior. Seleccione abajo el mismo CSV original y elija su revisión de bitácora. Compare el resultado antes de cerrar la pestaña anterior.</p><select id="gi-legacy-list" aria-label="Revisiones anteriores"></select><button type="button" class="btn" id="gi-legacy-progress">Recuperar revisión anterior</button></details>
    </section>
    <div class="grid two" style="align-items:start">
      <div class="card">
        <h2>1 · Obtener las respuestas</h2>
        <ol class="small">
          <li>La secretaria completa el Google Form vinculado a la hoja.</li>
          <li>En Google Sheets abre la pestaña <b>Capturas</b>.</li>
          <li>Archivo → Descargar → <b>Valores separados por comas (.csv)</b>.</li>
          <li>Selecciona ese CSV aquí.</li>
        </ol>
        <div class="note warn"><b>Privacidad:</b> no publiques la hoja en Internet. El archivo puede contener datos de pacientes.</div>
        <div class="field" style="margin-top:12px"><label for="gcsv">Archivo CSV de Google Sheets</label><input id="gcsv" type="file" accept=".csv,text/csv"></div>
        <div class="toolbar"><button class="btn primary" id="validate" disabled>Validar archivo</button><button class="btn" id="clear">Limpiar</button></div>
      </div>
      <div class="card"><h2>Reglas de importación</h2>
        <ul class="small">
          <li>Todas las filas quedan <b>En revisión</b>. Puede editarlas, excluirlas con motivo o aprobarlas.</li>
          <li>Cada corrección se registra en la bitácora con el usuario autenticado.</li>
          <li>El médico y la ARS deben coincidir con registros visibles en SOFA.</li>
          <li>El servicio debe estar contratado para médico + ARS + fecha.</li>
          <li>Si el monto viene vacío, SOFA usa la tarifa contractual.</li>
          <li>El monto puede ajustarse para esta reclamación con motivo. Cambiar el tarifario requiere una nueva vigencia autorizada.</li>
          <li>Los duplicados siguen siendo bloqueados por el backend de SOFA.</li>
        </ul>
      </div>
    </div>
    <div class="card" style="margin-top:14px"><div class="page-head"><div class="t"><h2>2 · Revisar, corregir y confirmar</h2><p id="summary">Carga un CSV para comenzar.</p></div>
      <div class="toolbar"><button class="btn" id="duplicates" disabled>Verificar duplicadas</button><button class="btn" id="approve" disabled>Aprobar filas sin observaciones</button><button class="btn primary" id="import" disabled>Confirmar e importar aprobadas</button></div></div><div id="gi-action-status" class="gi-action-status" role="status" aria-live="polite" hidden></div><div id="gi-review-help" role="status" aria-live="polite"></div><div id="gi-review-filters" class="toolbar gi-review-filters" role="group" aria-label="Filtrar filas por observación"></div><div id="preview"></div></div>
  `);

  const file=$('#gcsv',main), validate=$('#validate',main), imp=$('#import',main), preview=$('#preview',main), summary=$('#summary',main);
  try{[S.providers,S.ars]=await Promise.all([captureProviders(),activeArs()]);}
  catch(e){paint(preview,html`<div class="note bad">${friendlyError(e)}</div>`);return;}

  async function validateRow(r, previous={}){
    const errors=[]; const warnings=[];
    const provider=exact(S.providers,r['Médico / Prestador *'],['full_name']);
    if(!provider) errors.push('Médico no encontrado o nombre ambiguo');
    const ars=exact(S.ars,r['ARS *'],['name','code']);
    if(!ars) errors.push('ARS no encontrada');
    const serviceDate=parseDate(r['Fecha del servicio *']); if(!serviceDate) errors.push('Fecha del servicio inválida');else if(serviceDate>todayISO())errors.push('La fecha del servicio no puede ser futura');
    const patient=String(r['Paciente *']||'').trim(); if(patient.length<3) errors.push('Paciente inválido');
    const member=String(r['NSS / No. afiliado *']||'').trim(); if(member.length<3) errors.push('NSS / afiliado inválido');
    const careMode=norm(r['Modalidad'])||'ambulatorio';
    const authorization=String(r['No. autorización']||'').trim();
    if(careMode!=='emergencia' && authorization.length<2) errors.push('Falta autorización');
    let service=null, tariff=null;
    if(provider&&ars&&serviceDate){
      try{
        const services=await contractedServices(provider.id,ars.id,serviceDate);
        const wanted=r['Servicio / Procedimiento *']; const n=norm(wanted);
        const hits=services.filter((s)=>[s.name,s.cups,s.simon,s.internal_code,s.ars_service_code].some((v)=>norm(v)===n));
        if(hits.length===1){service=hits[0];tariff=Number(service.amount);}
        else if(!hits.length) errors.push('Servicio no contratado para médico + ARS + fecha');
        else errors.push('Servicio ambiguo; use nombre o código exacto');
      }catch(e){errors.push('No se pudo validar el tarifario');}
    }
    const providedAmount=num(r['Monto a reclamar']);
    if(providedAmount!=null && !(providedAmount>0))errors.push('El monto debe ser mayor que cero');
    if(providedAmount!=null&&Math.abs(Math.round(providedAmount*100)/100-providedAmount)>0.0000001)errors.push('El monto debe tener como máximo dos decimales');
    if(tariff!=null && providedAmount!=null && Math.abs(providedAmount-tariff)>=0.005 && String(r['Motivo ajuste']||'').trim().length<10) errors.push(`Monto ${money(providedAmount)} difiere de tarifa ${money(tariff)}; indique el motivo del ajuste (mínimo 10 caracteres)`);
    if(tariff!=null&&providedAmount!=null&&Math.abs(providedAmount-tariff)>=0.005&&!can('claims.discrepancy',ctx.role))errors.push('El ajuste de monto requiere autorización de Administración o Facturación');
    const quantity=num(r['Cantidad'])??1;
    if(!Number.isInteger(quantity)||quantity<1||quantity>999)errors.push('Cantidad: indique un entero entre 1 y 999');
    const keepApproval=previous.reviewed && !errors.length && previous.tariff===tariff && EDITABLE.every(key=>String(previous.raw?.[key]??'')===String(r[key]??''));
    return {
      ...previous,row:r.__row,raw:r,provider,ars,service,serviceDate,patient,member,authorization,careMode,tariff,quantity,
      original:previous.original||{...r},amount:providedAmount,validationErrors:[...errors],errors,warnings,reviewed:!!keepApproval,status:errors.length?'error':keepApproval?'ready':'review',editCount:previous.editCount||0
    };
  }

  const activeReview = v => !['excluded','imported','removed'].includes(v.status);
  const needsAuthorization = v => activeReview(v) && (v.validationErrors||[]).includes('Falta autorización');
  const needsAmount = v => activeReview(v) && (v.validationErrors||[]).some(e=>e.startsWith('Monto ')||e.startsWith('El monto')||e.startsWith('El ajuste de monto'));
  const hasDuplicates = v => activeReview(v) && (v.duplicateMessages||[]).some(e=>e.startsWith('Posible duplicada')||e.startsWith('Ya existe en SoFa'));
  const reviewFilters = [
    ['all','Todas',()=>true],
    ['authorization','Autorización pendiente',needsAuthorization],
    ['amount','Monto por revisar',needsAmount],
    ['duplicates','Posibles duplicadas',hasDuplicates],
    ['clean','Sin observaciones',v=>activeReview(v)&&!v.errors.length],
    ['ready','Aprobadas',v=>v.status==='ready']
  ];

  function draw(){
    const ok=S.validated.filter((x)=>x.status==='ready').length;
    const bad=S.validated.filter((x)=>['error','failed','review'].includes(x.status)).length;
    const excluded=S.validated.filter(x=>x.status==='excluded').length;
    const imported=S.validated.filter((x)=>x.status==='imported').length;
    summary.textContent=`${S.busy?'Procesando revisión… ':''}${S.validated.length} fila(s): ${ok} aprobada(s) · ${bad} por revisar · ${excluded} excluida(s)${imported?` · ${imported} importada(s)`:''}.`;
    const clean=S.validated.filter(v=>v.status==='review'&&!v.errors.length).length;
    const active=S.validated.filter(activeReview);
    const issues=S.validated.filter(v=>activeReview(v)&&v.errors.length).length;
    const auth=S.validated.filter(needsAuthorization).length,amount=S.validated.filter(needsAmount).length,duplicates=S.validated.filter(hasDuplicates).length;
    paint($('#gi-review-help',main),S.validated.length?html`<div class="note ${issues?'warn':'ok'}">
      <b>${!ok&&!clean&&active.length?'No hay filas listas para aprobar.':`${clean} fila(s) sin observaciones para aprobar · ${ok} aprobada(s).`}</b>
      ${issues?html`<p>Bloqueos: ${auth} con autorización pendiente · ${amount} con monto por revisar · ${duplicates} con posibles duplicados. Una fila puede aparecer en más de un grupo.</p>
      <p>Completa la autorización documentada; si el monto difiere de la tarifa, corrígelo o registra el motivo real del ajuste. Compara las duplicadas antes de excluirlas. Las demás filas pueden aprobarse por separado.</p>`:''}
      <span class="small">Las correcciones guardadas se conservan. No necesitas limpiar ni volver a cargar el archivo.</span></div>`:html``);
    paint($('#gi-review-filters',main),S.validated.length?html`${reviewFilters.map(([key,label,match])=>html`<button type="button" class="btn sm" data-review-filter="${key}" aria-pressed="${S.reviewFilter===key}">${label} · ${S.validated.filter(match).length}</button>`)}`:html``);
    const visible=S.validated.filter(reviewFilters.find(([key])=>key===S.reviewFilter)?.[2]||(()=>true));
    imp.disabled=S.busy||!ok;
    imp.title=ok?'Importar solo las filas aprobadas':'Primero aprueba al menos una fila sin observaciones.';
    $('#approve',main).title=clean?'Aprobar las filas sin errores; las demás se conservan para corregir.':'No hay filas sin observaciones. Revisa los bloqueos indicados debajo.';
    $('#duplicates',main).disabled=S.busy||!S.validated.length;$('#approve',main).disabled=S.busy||!S.validated.some(v=>v.status==='review'&&!v.errors.length);
    validate.disabled=S.busy||S.initializing||!(file.files?.length||S.rows.length||S.validated.length);file.disabled=S.busy||S.initializing||!owner;$('#clear',main).disabled=S.busy||S.initializing;
    $('#gi-resume-editor',main).hidden=!S.editor;$('#gi-discard-editor',main).hidden=!S.editor;
    progressPanel?.querySelectorAll('button,select').forEach(button=>{button.disabled=S.busy||S.initializing||!owner;});
    paint(preview,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fila</th><th>Paciente</th><th>Médico</th><th>ARS</th><th>Servicio</th><th>Tarifa / monto unitario</th><th>Estado</th><th>Acción</th></tr></thead><tbody>
      ${visible.map((v)=>html`<tr>
        <td data-l="Fila">${v.row}</td>
        <td data-l="Paciente">${v.patient||'—'}</td>
        <td data-l="Médico">${v.provider?.full_name||v.raw['Médico / Prestador *']||'—'}</td>
        <td data-l="ARS">${v.ars?.name||v.raw['ARS *']||'—'}</td>
        <td data-l="Servicio">${v.service?.name||v.raw['Servicio / Procedimiento *']||'—'}</td>
        <td data-l="Tarifa / monto">Tarifa: ${v.tariff!=null?money(v.tariff):'—'}<div class="small">A reclamar: ${v.amount!=null?money(v.amount):v.tariff!=null?money(v.tariff):'—'}</div><div class="small">Cantidad: ${v.quantity} · Total: ${money((v.amount??v.tariff??0)*v.quantity)}</div>${v.raw['Motivo ajuste']?html`<div class="small">Motivo: ${v.raw['Motivo ajuste']}</div>`:''}${can('contracts.edit',ctx.role)&&v.service&&!['imported','removed','excluded'].includes(v.status)?html`<button class="btn sm" data-tariff-row="${v.row}">Nueva vigencia tarifario</button>`:''}</td>
        <td data-l="Estado">
          ${v.status==='imported'
            ? html`<span class="pill ok">Importada</span> <span class="mono">${v.folio||''}</span>`
            : html`<span class="pill ${v.status==='ready'?'ok':'bad'}">${v.status==='ready'?'Aprobada':v.status==='excluded'?'Excluida':v.status==='removed'?'Eliminada':'En revisión'}</span>`}
          ${v.editCount?html` <span class="pill">Corregida ${v.editCount}×</span>`:''}
          ${v.errors?.length?html`<div class="small muted">${v.errors.join(' · ')}</div>`:''}
          ${v.auditWarning?html`<div class="small" style="color:var(--warn)">${v.auditWarning}</div>`:''}
        </td>
        <td data-l="Acción">${v.status==='imported'?html`<a class="btn sm" href="#/reclamaciones">Ver reclamaciones</a>${['super_admin','admin','billing'].includes(ctx.role)?html`<button class="btn sm" data-remove-row="${v.row}">Eliminar reclamación</button>`:''}`:v.status==='removed'?html`<span class="small">Eliminación registrada en bitácora</span>`:v.status==='excluded'?html`<button class="btn sm" data-restore-row="${v.row}">Restaurar fila</button>`:html`<button class="btn sm" data-edit-row="${v.row}">Completar / editar</button><button class="btn sm" data-exclude-row="${v.row}">Excluir / eliminar del lote</button>${v.status==='review'&&!v.errors.length?html`<button class="btn sm" data-review-row="${v.row}">Aprobar fila</button>`:''}`}</td>
      </tr>`)}
    ${S.validated.length&&!visible.length?html`<tr><td colspan="8" class="small muted">No hay filas con este filtro. Seleccione «Todas» para volver al lote completo.</td></tr>`:''}</tbody></table></div>`);
    paintActionFeedback();
    $('#gi-review-filters',main).querySelectorAll('button').forEach(button=>{button.disabled=S.busy;});
    preview.setAttribute('aria-busy',String(S.busy));
    preview.querySelectorAll('button').forEach(button=>{button.disabled=S.busy;});
  }

  async function editRow(v){
    if(S.editor&&Number(S.editor.row)!==Number(v.row)){toast(`Reanude o descarte primero la edición pendiente de la fila ${S.editor.row}.`,'bad');return false;}
    if(['excluded','imported','removed'].includes(v.status)){toast('Restaure la fila o revise la reclamación confirmada antes de editarla.','bad');return false;}
    const pendingEditor=S.editor?.values||null;
    const r=v.raw;
    const currentProvider=v.provider||exact(S.providers,r['Médico / Prestador *'],['full_name']);
    const currentArs=v.ars||exact(S.ars,r['ARS *'],['name','code']);
    const result=await formDialog({
      title:`Completar / editar fila ${v.row}`,submitLabel:'Guardar corrección',wide:true,
      body:html`
        <details><summary>Ver valores originales del archivo</summary><dl>${EDITABLE.map(key=>html`<dt>${key}</dt><dd>${v.original?.[key]||'(vacío)'}</dd>`)}</dl></details><div class="note warn"><b>Bitácora:</b> se registrarán los campos modificados, los valores anteriores y nuevos, tu usuario y la fecha.</div>
        <div class="form-grid">
          <div class="field"><label>Médico / Prestador *</label><select name="provider" required><option value="">Seleccione…</option>${S.providers.map((p)=>opt(p.id,p.full_name,currentProvider?.id))}</select></div>
          <div class="field"><label>ARS *</label><select name="ars" required><option value="">Seleccione…</option>${S.ars.map((a)=>opt(a.id,a.name,currentArs?.id))}</select></div>
          <div class="field"><label>Fecha del servicio *</label><input name="service_date" type="date" required value="${parseDate(r['Fecha del servicio *'])}"></div>
          <div class="field"><label>Modalidad</label><select name="care_mode">${['ambulatorio','emergencia','internamiento'].map((x)=>opt(x,x,norm(r['Modalidad'])||'ambulatorio'))}</select></div>
          <div class="field" style="grid-column:1/-1"><label>Paciente *</label><input name="patient" required value="${r['Paciente *']||''}"></div>
          <div class="field"><label>NSS / No. afiliado *</label><input name="member" required value="${r['NSS / No. afiliado *']||''}"></div>
          <div class="field"><label>No. autorización</label><input name="authorization" value="${r['No. autorización']||''}"></div>
          <div class="field"><label>Fecha autorización</label><input name="auth_date" type="date" value="${parseDate(r['Fecha autorización'])}"></div>
          <div class="field"><label>Cédula paciente</label><input name="patient_doc" value="${r['Cédula paciente']||''}"></div><div id="gie_global" style="grid-column:1/-1"></div>
          <div class="field"><label>Diagnóstico CIE-10</label><input name="diagnosis" value="${r['Diagnóstico CIE-10']||''}" placeholder="Escribe o selecciona una sugerencia"><div class="hint">SOFA sugiere según servicio, SIMON y CUPS; puedes cambiarlo.</div><div id="gie_dx_sugs" class="small" style="margin-top:6px"></div></div>
          <div class="field"><label>Centro / clínica</label><input name="clinic" value="${r['Centro / clínica']||''}"></div>
          <div class="field" style="grid-column:1/-1"><label>Servicio / Procedimiento *</label><select name="service" required><option value="">Seleccione médico, ARS y fecha</option></select><div class="hint">Solo se muestran servicios contratados para la combinación seleccionada.</div></div>
          <div class="field"><label>Cantidad</label><input name="quantity" type="number" min="1" step="1" value="${num(r['Cantidad'])||1}"></div>
          <div class="field"><label>Monto unitario a reclamar</label><input name="amount" type="number" min="0" step="0.01" value="${num(r['Monto a reclamar'])??''}"><div class="hint">Déjalo vacío para usar la tarifa contractual.</div></div>
          <div class="field" style="grid-column:1/-1"><button type="button" class="btn" data-editor-copy hidden>Conservar esta edición como copia</button></div>
          <div class="field" style="grid-column:1/-1"><label for="gie_reason">Motivo del ajuste de monto</label><textarea id="gie_reason" name="discrepancy_reason" minlength="10">${r['Motivo ajuste']||''}</textarea><div class="hint">Obligatorio si el monto unitario difiere de la tarifa. Solo afecta esta reclamación.</div><button type="button" class="btn sm" data-use-tariff>Usar tarifa contractual</button></div><div class="field" style="grid-column:1/-1"><label>Observaciones</label><textarea name="notes" rows="2">${r['Observaciones']||''}</textarea></div>
        </div>`,
      onOpen:(form)=>{
        S.editorForm=form;
        form.querySelector('[data-editor-copy]').addEventListener('click',event=>busy(event.currentTarget,async()=>{try{await forkCurrentDraft();}catch(error){paint(form.querySelector('.fd-msg'),html`<div class="note bad" role="alert">${error.message}</div>`);}}));
        let captureEnabled=false;
        const captureEditor=()=>{if(!captureEnabled)return;S.editor={row:v.row,values:Object.fromEntries(new FormData(form).entries())};snapshotChanged();};
        form.addEventListener('input',captureEditor);form.addEventListener('change',captureEditor);
        if(pendingEditor)for(const [name,value] of Object.entries(pendingEditor)){if(name!=='service'&&form.elements[name])form.elements[name].value=value;}

        form.querySelector('[data-use-tariff]').addEventListener('click',()=>{form.elements.amount.value='';form.elements.discrepancy_reason.value='';captureEditor();});
        const globalBox=form.querySelector('#gie_global');
        let gseq=0;
        const checkGlobal=async()=>{
          const ced=form.elements.patient_doc.value.trim(), nss=form.elements.member.value.trim();
          if(!ced&&!nss){paint(globalBox,html``);return;}
          const my=++gseq;
          try{
            const r0=await rpc('global_patient_lookup',{p_cedula:ced||null,p_nss:nss||null,p_name:form.elements.patient.value.trim()||null,p_birth:null,p_phone:null});
            if(my!==gseq)return;
            if(r0?.match==='exact'&&r0.patient){
              paint(globalBox,html`<div class="note info"><b>Paciente universal encontrado:</b> ${r0.patient.full_name}. Solo se reutilizarán datos administrativos.
                <div class="toolbar" style="margin-top:6px"><button type="button" class="btn sm" data-use-gp>Usar datos</button></div></div>`);
              globalBox.querySelector('[data-use-gp]')?.addEventListener('click',async()=>{
                form.elements.patient.value=r0.patient.full_name||form.elements.patient.value;
                form.elements.patient_doc.value=r0.patient.cedula||form.elements.patient_doc.value;
                form.elements.member.value=r0.patient.nss||r0.patient.member_number||form.elements.member.value;
                if(r0.patient.ars_id&&S.ars.some((a)=>a.id===r0.patient.ars_id)){form.elements.ars.value=r0.patient.ars_id;}
                paint(globalBox,html`<div class="note ok">Datos administrativos cargados. No se copiaron consultas ni diagnósticos previos.</div>`);
                await loadServices();
              });
            }else if(r0?.match==='conflict') paint(globalBox,html`<div class="note bad">La cédula y el NSS pertenecen a registros distintos. Revise antes de continuar.</div>`);
            else paint(globalBox,html``);
          }catch(_){paint(globalBox,html``);}
        };
        form.elements.patient_doc.addEventListener('change',checkGlobal);
        form.elements.member.addEventListener('change',checkGlobal);

        const loadDx=async()=>{
          const box=form.querySelector('#gie_dx_sugs'); if(!box)return;
          const procedure=form.elements.service.value;
          if(!procedure){paint(box,html``);return;}
          try{
            const rows=await cie10Suggestions(procedure,null,8);
            if(!rows.length){paint(box,html`<span class="muted">Sin sugerencia automática. Escribe el código documentado.</span>`);return;}
            paint(box,html`<div class="toolbar" style="gap:6px;flex-wrap:wrap">${rows.map((x)=>html`<button class="btn sm" type="button" data-gdx="${x.code}" title="${x.rationale||''}">${x.code} · ${x.title_es}</button>`)}</div><div class="small muted">Sugerencias administrativas; confirma el diagnóstico documentado.</div>`);
            box.querySelectorAll('[data-gdx]').forEach((b)=>b.addEventListener('click',()=>{form.elements.diagnosis.value=b.dataset.gdx;captureEditor();}));
          }catch(_){paint(box,html`<span class="muted">Puedes escribir el CIE-10 manualmente.</span>`);}
        };
        const loadServices=async()=>{
          const p=form.elements.provider.value,a=form.elements.ars.value,d=form.elements.service_date.value,s=form.elements.service;
          paint(s,html`<option value="">Cargando…</option>`);
          if(!p||!a||!d){paint(s,html`<option value="">Seleccione médico, ARS y fecha</option>`);return;}
          try{
            const rows=await contractedServices(p,a,d);
            const current=norm(r['Servicio / Procedimiento *']);
            paint(s,html`<option value="">Seleccione…</option>${rows.map((x)=>html`<option value="${x.procedure_id}" data-name="${x.name}" ${[x.name,x.cups,x.simon,x.internal_code,x.ars_service_code].some((y)=>norm(y)===current)?'selected':''}>${x.name}${x.cups?` · CUPS ${x.cups}`:''}${x.simon?` · SIMON ${x.simon}`:''} · ${money(x.amount)}</option>`) }`);
          }catch(e){paint(s,html`<option value="">No se pudieron cargar los servicios</option>`);}
          await loadDx();captureEditor();
        };
        ['provider','ars','service_date'].forEach((n)=>form.elements[n].addEventListener('change',loadServices));
        form.elements.service.addEventListener('change',loadDx);
        loadServices().then(()=>{if(pendingEditor?.service&&[...form.elements.service.options].some(option=>option.value===pendingEditor.service))form.elements.service.value=pendingEditor.service;captureEnabled=true;captureEditor();});
      },
      onSubmit:async(d,form)=>{
        if(!requireFields(form,['provider','ars','service_date','patient','member','service']))return false;
        const provider=S.providers.find((p)=>p.id===d.provider);
        const ars=S.ars.find((a)=>a.id===d.ars);
        const serviceName=form.elements.service.selectedOptions[0]?.dataset.name||'';
        const after={...r,
          'Médico / Prestador *':provider?.full_name||'',
          'ARS *':ars?.name||'',
          'Fecha del servicio *':d.service_date,
          'Modalidad':d.care_mode,
          'Paciente *':String(d.patient||'').trim(),
          'NSS / No. afiliado *':String(d.member||'').trim(),
          'No. autorización':String(d.authorization||'').trim(),
          'Fecha autorización':d.auth_date||'',
          'Cédula paciente':String(d.patient_doc||'').trim(),
          'Diagnóstico CIE-10':String(d.diagnosis||'').trim(),
          'Centro / clínica':String(d.clinic||'').trim(),
          'Servicio / Procedimiento *':serviceName,
          'Cantidad':d.quantity||'1',
          'Monto a reclamar':d.amount||'',
          'Motivo ajuste':String(d.discrepancy_reason||'').trim(),
          'Observaciones':String(d.notes||'').trim()
        };
        const diff=changedValues(r,after);
        if(!diff.fields.length){toast('No hay cambios para guardar.');return true;}
        snapshotChanged();await autosave.flush();
        const recordId=`${S.batchId}:row:${v.row}`;
        const auditId=await rpc('log_google_intake_edit',{
          p_record_id:recordId,
          p_org:provider?.organization_id||v.provider?.organization_id||null,
          p_before:diff.oldValues,
          p_after:diff.newValues,
          p_fields:diff.fields
        });
        S.auditCursor=Math.max(S.auditCursor,Number(auditId)||0);S.editor=null;
        const updated=await validateRow(after,{...v,editCount:(v.editCount||0)+1});
        const ix=S.validated.findIndex((x)=>x.row===v.row);
        S.validated[ix]=updated;
        await checkDuplicates();
        toast(`Fila ${v.row} corregida y registrada en bitácora`,'ok');
        return true;
      }
    });
    if(result!==null) draw();
    S.editor=null;S.editorForm=null;snapshotChanged();
    return result;
  }

  function dataFor(v){
    const r=v.raw;
    return {provider:v.provider?.id,ars:v.ars?.id,procedure:v.service?.procedure_id,service_date:v.serviceDate,
      patient:v.patient,member:v.member,authorization:v.authorization,patient_doc:String(r['Cédula paciente']||'').trim(),
      diagnosis:String(r['Diagnóstico CIE-10']||'').trim(),quantity:v.quantity,care_mode:v.careMode,clinic:String(r['Centro / clínica']||'').trim(),
      amount:v.amount,expected_tariff:v.tariff,discrepancy_reason:String(r['Motivo ajuste']||'').trim()||null,review_confirmed:!!v.reviewed,
      notes:[`Carga Google Sheets/Form · fila ${v.row}`,String(r['Observaciones']||'').trim()].filter(Boolean).join(' · '),source_original:Object.fromEntries(EDITABLE.map(key=>[key,v.original?.[key]??''])),source_final:Object.fromEntries(EDITABLE.map(key=>[key,r[key]??'']))};
  }
  const recordId=v=>`${S.batchId}:row:${v.row}`;
  async function auditDecision(v,action,reason){
    const auditId=await rpc('log_google_intake_edit',{p_record_id:recordId(v),p_org:v.provider?.organization_id||null,
      p_before:{estado:v.status},p_after:{accion:action,motivo:reason,valores:Object.fromEntries(EDITABLE.map(key=>[key,v.raw[key]??'']))},p_fields:['estado','accion','motivo']});
    S.auditCursor=Math.max(S.auditCursor,Number(auditId)||0);
  }
  async function checkDuplicates(){
    const active=S.validated.filter(v=>!['excluded','imported','removed'].includes(v.status));
    const seen=new Map();let checked=0,failed=0,skipped=0;
    for(const v of active){v.errors=[...(v.validationErrors||[])];v.duplicateMessages=[];}
    for(const v of active){
      if(!v.provider||!v.ars||!v.service||!v.serviceDate||v.member.length<3){skipped++;continue;}
      const scope=`${v.provider.organization_id}:${v.ars.id}:`;
      const keys=[scope+`member:${v.member}:${v.serviceDate}:${v.service.procedure_id}`];
      if(v.authorization)keys.push(scope+`auth:${v.authorization}`);
      for(const key of keys){
        const other=seen.get(key);
        if(other&&other.row!==v.row){v.duplicateMessages.push(`Posible duplicada con fila ${other.row} del archivo`);other.duplicateMessages.push(`Posible duplicada con fila ${v.row} del archivo`);}else seen.set(key,v);
      }
      try{
        const result=await rpc('google_intake_review_v1',{p_record_id:recordId(v),p_action:'duplicates',p_data:dataFor(v)});
        checked++;
        if(result.already_imported){v.status=result.removed?'removed':'imported';v.folio=result.result?.folio;v.claimId=result.result?.id;continue;}
        if(result.duplicate)v.duplicateMessages.push(`Ya existe en SoFa: ${(result.folios||[]).join(', ')}`);
      }catch(error){failed++;v.duplicateMessages.push('No se pudo verificar duplicadas. Vuelva a intentarlo.');}
    }
    for(const v of active){if(['imported','removed'].includes(v.status))continue;v.errors.push(...new Set(v.duplicateMessages));if(v.errors.length){v.status='error';v.reviewed=false;}else v.status=v.reviewed?'ready':'review';}
    S.duplicateStats={checked,failed,skipped,duplicates:active.filter(v=>v.duplicateMessages.some(m=>!m.startsWith('No se pudo'))).length};
  }
  async function refreshReview(){
    for(let i=0;i<S.validated.length;i++){
      const v=S.validated[i];if(['excluded','imported','removed'].includes(v.status))continue;
      S.validated[i]=await validateRow(v.raw,v);
    }
    await checkDuplicates();
  }
  const actionFeedback=new Map();let lastAction=null;
  const actionClock=()=>new Date().toLocaleTimeString('es-DO',{hour:'2-digit',minute:'2-digit',second:'2-digit',timeZone:'America/Santo_Domingo'});
  function paintActionFeedback(){
    for(const action of actionFeedback.values()){
      const button=action.find();if(!button)continue;
      button.dataset.actionState=action.state;
      button.setAttribute('aria-busy',String(action.state==='running'));
      button.title=action.state==='running'?action.message:`${action.message} · ${action.at}${button.disabled?'':'. Puede volver a ejecutar la acción.'}`;
    }
    const box=$('#gi-action-status',main);if(!box)return;
    box.hidden=!lastAction;
    if(lastAction){const available=lastAction.find();const repeat=available&&!available.disabled?'. Puede volver a ejecutar la acción.':'';box.dataset.state=lastAction.state;box.textContent=lastAction.state==='running'?lastAction.message:`${lastAction.message} · ${lastAction.at}${repeat}`;}
  }
  function clearActionFeedback(){
    actionFeedback.clear();lastAction=null;validate.textContent='Validar archivo';
    main.querySelectorAll('[data-action-state]').forEach(button=>{delete button.dataset.actionState;button.removeAttribute('aria-busy');button.removeAttribute('title');});
  }
  const topAction=(id,label)=>({id,label,find:()=>$('#'+id,main)});
  function duplicateOutcome(){
    const d=S.duplicateStats||{checked:0,failed:0,skipped:0,duplicates:0};
    return {state:d.failed&&d.checked===0?'error':d.failed||d.skipped||d.duplicates?'warning':'success',
      message:`Verificación de duplicadas finalizada: ${d.checked} fila(s) comprobadas, ${d.duplicates} con posibles coincidencias, ${d.skipped} sin comprobar por datos incompletos${d.failed?`, ${d.failed} con fallo de consulta`:''}`};
  }
  async function run(fn,descriptor=topAction('validate','Revisión')){
    if(S.busy||S.initializing||!owner)return;
    try{await autosave.flush();}catch(error){toast('No se continuará hasta guardar el progreso. '+error.message,'bad');return;}
    const action={...descriptor,state:'running',message:`${descriptor.label}: en proceso…`,at:null};
    actionFeedback.set(action.id,action);lastAction=action;S.busy=true;draw();
    try{
      snapshotChanged();await autosave.flush();
      const result=await fn();
      const outcome=result===null||result===false?{state:'cancelled',message:`${action.label}: cancelada; no se confirmó la acción`}
        :result&&typeof result==='object'&&result.state?result:{state:'success',message:`${action.label}: proceso finalizado`};
      Object.assign(action,outcome);
    }catch(error){action.state='error';action.message=`${action.label}: ${friendlyError(error)}`;toast(friendlyError(error),'bad');}
    finally{action.at=actionClock();actionFeedback.set(action.id,action);lastAction=action;snapshotChanged();try{await autosave.flush();await refreshDraftOptions();}catch(error){toast(error.message,'bad');}S.busy=false;draw();}
  }
  async function approveRows(rows){
    await checkDuplicates();
    for(const v of rows){
      if(v.errors.length||v.status!=='review')continue;
      await auditDecision(v,'APROBACION_FILA','Fila revisada y aprobada por el usuario');v.reviewed=true;v.status='ready';
    }
  }
  async function askReason(v,action){
    return formDialog({title:`${action} · fila ${v.row}`,submitLabel:'Confirmar y registrar',
      body:html`<p>${v.patient||'Fila sin paciente identificado'}</p><div class="field"><label for="gi-action-reason">Motivo (mínimo 10 caracteres)</label><textarea id="gi-action-reason" name="reason" minlength="10" required></textarea></div>`,
      onSubmit:async(d)=>{
        const reason=String(d.reason||'').trim();if(reason.length<10){toast('Indique un motivo de al menos 10 caracteres','bad');return false;}
        snapshotChanged();await autosave.flush();
        if(action==='Eliminar reclamación'){
          await rpc('google_intake_review_v1',{p_record_id:recordId(v),p_action:'remove',p_data:{reason}});v.status='removed';
        }else{
          await auditDecision(v,action==='Restaurar fila'?'RESTAURACION_FILA':'EXCLUSION_FILA',reason);
          v.reviewed=false;v.status=action==='Restaurar fila'?'review':'excluded';
        }
        await checkDuplicates();return true;
      }});
  }
  const owner=ctx.session?.user?.id;
  const progressPanel=$('#gi-draft-panel',main),progressStatus=$('#gi-draft-status',main);
  const draftSelect=$('#gi-draft-list',main),legacySelect=$('#gi-legacy-list',main);
  const draftCall=(action,id=null,extra={})=>rpc('google_intake_drafts_v1',{p_action:action,p_id:id,p_owner:owner,...extra});
  const serializeFeedback=()=>({actions:[...actionFeedback.values()].map(({id,label,state,message,at})=>({id,label,state,message,at})),last:lastAction?.id||null});
  const autosave=createIntakeAutosave({rpc,owner,id:()=>S.draftId||S.batchId,serialize:()=>intakeSnapshot(S,EDITABLE,serializeFeedback()),
    onStatus:(state,text)=>{progressStatus.dataset.state=state;progressStatus.textContent=text;const conflict=state==='error'&&/otra pestaña|otra ventana|sobrescrib/i.test(text);progressPanel.querySelector('#gi-fork-progress').hidden=!conflict;if(S.editorForm?.isConnected)S.editorForm.querySelector('[data-editor-copy]').hidden=!conflict;}});
  const snapshotChanged=()=>{if(owner&&(S.rows.length||S.validated.length||S.editor))autosave.mark();};
  registerProgressGuard(progressPanel,{pending:()=>autosave.pending()||S.busy,
    flush:async()=>{if(S.busy)throw Error('Hay una acción de la carga en proceso. Termine o cancele la acción antes de actualizar.');await autosave.flush();}});
  const onlineSave=()=>{if(autosave.pending())autosave.flush().catch(()=>{});};
  window.addEventListener('online',onlineSave);
  window.addEventListener('hashchange',()=>{if(autosave.pending())autosave.flush().catch(()=>{});},{once:true});
  function restoreFeedback(saved){
    clearActionFeedback();
    for(const item of saved?.actions||[]){
      if(!['success','warning','error','cancelled','running'].includes(item.state))continue;
      const [key,row]=String(item.id).split(':');
      const find=['validate','duplicates','approve','import'].includes(key)?()=>$('#'+key,main)
        :()=>[...preview.querySelectorAll('button')].find(button=>button.dataset[key]===String(row));
      const action={...item,find};
      if(action.state==='running'){action.state='warning';action.message='La acción anterior quedó interrumpida. Revise el resultado antes de repetirla.';}
      actionFeedback.set(action.id,action);
    }
    lastAction=actionFeedback.get(saved?.last)||null;
  }
  let legacyOptions=null;
  async function refreshDraftOptions(){
    const drafts=await draftCall('list');
    const legacy=legacyOptions||await draftCall('legacy_list');legacyOptions=legacy;
    paint(draftSelect,html`<option value="">Seleccione una carga guardada…</option>${(drafts.items||[]).map(item=>html`<option value="${item.id}" ${item.id===(S.draftId||S.batchId)?'selected':''}>${item.source_name} · ${item.rows} fila(s)</option>`)}`);
    paint(legacySelect,html`<option value="">Seleccione una revisión anterior…</option>${(legacy.items||[]).map(item=>html`<option value="${item.id}">${new Date(item.updated_at).toLocaleString('es-DO',{timeZone:'America/Santo_Domingo'})} · ${item.rows} fila(s) con bitácora</option>`)}`);
  }
  async function hydrate(saved,{legacy=false,commits=[]}={}){
    const payload=saved.payload;
    if(payload.schema!==1||!Array.isArray(payload.rows))throw Error('La versión de este borrador no es compatible. No se reemplazó su revisión.');
    S.draftId=saved.id;S.batchId=payload.origin_id||saved.id;S.sourceName=payload.source_name;
    let recoveredRows=payload.rows,recoveryCursor=payload.audit_cursor||0,recoveredEditor=payload.editor||null;
    if(!legacy){
      const audit=await draftCall('events',S.batchId);
      const newer=(audit.events||[]).filter(event=>Number(event.id)>recoveryCursor);
      if(newer.length){
        const replay=replayIntakeAudit(payload.rows.map(row=>row.raw),newer,{trustSavedSource:true,baseRows:payload.rows});
        if(!replay.conflicts.length){recoveredRows=replay.rows;recoveryCursor=Math.max(recoveryCursor,...newer.map(event=>Number(event.id)));

        }
        else toast('Se conserva su copia. Hay cambios de otra pestaña en la bitácora que requieren comparación.','bad');
      }
      commits=audit.commits||commits;
    }
    S.rows=recoveredRows.map(row=>({...row.raw}));S.validated=[];
    S.editor=recoveredEditor;S.auditCursor=recoveryCursor;
    for(const row of recoveredRows){
      const current=await validateRow(row.raw,{original:row.original||row.raw,editCount:row.editCount||0});
      if(row.status==='excluded')current.status='excluded';
      else if(!legacy&&row.reviewed&&!current.errors.length&&current.tariff===row.tariff){current.reviewed=true;current.status='ready';}
      S.validated.push(current);
    }
    await checkDuplicates();
    for(const stored of commits){
      const row=S.validated.find(candidate=>candidate.row===Number(stored.row));if(!row)continue;
      row.status=stored.removed?'removed':'imported';row.folio=stored.result?.folio;row.claimId=stored.result?.id;row.errors=[];
    }
    autosave.adopt(S.draftId,saved.version||0);restoreFeedback(payload.feedback);file.value='';
    $('#gi-resume-editor',main).hidden=!S.editor;$('#gi-discard-editor',main).hidden=!S.editor;
    $('#gi-source-name',main).textContent=`Carga recuperada: ${S.sourceName}. Puede continuar sin volver a seleccionar el archivo.`;
    snapshotChanged();await autosave.flush();
  }
  async function resumeDraft(id){
    if(S.busy)return;await autosave.flush();S.busy=true;draw();
    try{const result=await draftCall('get',id);await hydrate(result.draft,{commits:result.commits||[]});await refreshDraftOptions();}
    catch(error){progressStatus.dataset.state='error';progressStatus.textContent=error.message;}
    finally{S.busy=false;draw();}
  }
  function parsedFile(table){
    if(table.length<2)throw Error('El archivo no contiene filas para importar.');
    const headers=table[0].map(value=>String(value).trim());const missing=REQUIRED.filter(key=>!headers.includes(key));
    if(missing.length)throw Error(`Faltan columnas obligatorias: ${missing.join(', ')}`);
    const rows=toObjects(table);if(rows.length>1000)throw Error('El máximo por carga es de 1,000 filas.');return rows;
  }
  $('#gi-save-progress',main).addEventListener('click',async()=>{try{snapshotChanged();await autosave.flush();await refreshDraftOptions();}catch(error){toast(error.message,'bad');}});
  $('#gi-resume-progress',main).addEventListener('click',()=>{if(draftSelect.value)resumeDraft(draftSelect.value).catch(error=>toast(error.message,'bad'));});
  $('#gi-resume-editor',main).addEventListener('click',()=>{
    const row=S.validated.find(item=>item.row===Number(S.editor?.row));if(!row)return;
    if(['imported','removed'].includes(row.status))run(()=>formDialog({title:'Edición pendiente conservada',submitLabel:'Cerrar',body:html`<p>Esta fila ya tiene una reclamación confirmada o eliminada. Su texto pendiente se conserva aquí; no modifica la reclamación.</p><dl>${Object.entries(S.editor.values||{}).map(([key,value])=>html`<dt>${key}</dt><dd>${value||'(vacío)'}</dd>`)}</dl>`,onSubmit:()=>true}),topAction('gi-resume-editor','Consultar edición conservada'));
    else run(()=>editRow(row),topAction('validate',`Reanudar edición · fila ${row.row}`));
  });
  $('#gi-legacy-progress',main).addEventListener('click',()=>run(async()=>{
    const chosen=file.files?.[0];if(!chosen||!legacySelect.value)throw Error('Seleccione el mismo CSV original y una revisión de la bitácora.');
    if(!await confirmDialog('Recuperar revisión anterior','Confirme que seleccionó el mismo CSV original. Se recuperarán correcciones y exclusiones; las filas se volverán a validar y deberá aprobarlas antes de importar. No se crean reclamaciones al recuperar.','Recuperar revisión'))return false;
    const rows=parsedFile(parseCsv(await chosen.text()));const result=await draftCall('legacy_get',legacySelect.value);
    const replay=replayIntakeAudit(rows,result.events||[]);
    if(replay.conflicts.length)throw Error(`No se aplicó la recuperación: ${replay.conflicts.slice(0,3).join(' · ')}. Compare el archivo con la pestaña anterior.`);
    if(!replay.applied)throw Error('No se encontraron correcciones o revisiones compatibles con ese archivo.');
    await autosave.flush();
    await hydrate({id:legacySelect.value,version:0,payload:{schema:1,source_name:chosen.name,rows:replay.rows,audit_cursor:Math.max(0,...(result.events||[]).map(event=>Number(event.id)))}}, {legacy:true,commits:result.commits||[]});
    legacyOptions=null;await refreshDraftOptions();return {state:'success',message:`Recuperadas ${replay.applied} acciones de la bitácora. Compare las filas antes de cerrar la pestaña anterior`};
  },topAction('gi-legacy-progress','Recuperar revisión anterior')));
  $('#gi-discard-editor',main).addEventListener('click',()=>run(async()=>{if(!await confirmDialog('Descartar edición pendiente','Se descartará únicamente el texto de esa edición sin confirmar. La fila y sus correcciones ya guardadas se conservan.','Descartar edición'))return false;S.editor=null;snapshotChanged();},topAction('gi-discard-editor','Descartar edición pendiente')));
  async function forkCurrentDraft(){
    S.draftId=crypto.randomUUID();S.sourceName=(S.sourceName+' · copia').slice(0,255);autosave.adopt(S.draftId,0);snapshotChanged();await autosave.flush();await refreshDraftOptions();$('#gi-source-name',main).textContent=`Copia conservada: ${S.sourceName}. La versión de la otra pestaña no se modificó.`;
  }
  $('#gi-fork-progress',main).addEventListener('click',async()=>{
    if(S.busy)return;S.busy=true;draw();
    try{await forkCurrentDraft();}catch(error){toast(error.message,'bad');}finally{S.busy=false;draw();}
  });
  async function initializeDraft(){
    if(!owner)throw Error('No se pudo identificar su sesión para proteger el progreso. Vuelva a entrar.');
    const result=await draftCall('latest');
    if(result.draft)await hydrate(result.draft,{commits:result.commits||[]});
    else{progressStatus.dataset.state='saved';progressStatus.textContent='El progreso se guardará en SoFa al revisar un archivo.';}
    await refreshDraftOptions();
  }
  file.addEventListener('change',async()=>{
    if(S.busy||S.initializing||!owner)return;
    const selected=file.files?.[0];
    try{await autosave.flush();}catch(error){toast('La carga anterior no se ha guardado. '+error.message,'bad');file.value='';return;}
    clearActionFeedback();S.rows=[];S.validated=[];S.editor=null;S.auditCursor=0;S.sourceName=selected?.name||'';S.batchId=crypto.randomUUID();S.draftId=S.batchId;autosave.adopt(S.draftId,0);
    $('#gi-source-name',main).textContent=selected?`Archivo seleccionado: ${selected.name}`:'';draw();
  });
  $('#clear',main).textContent='Descartar esta revisión';
  $('#clear',main).addEventListener('click',async()=>{
    if(S.busy||S.initializing||!owner)return;
    if(!await confirmDialog('Descartar revisión','Se archivará este borrador. No se eliminan reclamaciones confirmadas ni registros de bitácora.','Descartar revisión'))return;
    try{await autosave.flush();await draftCall('archive',S.draftId||S.batchId,{p_version:autosave.version(S.draftId||S.batchId)});}
    catch(error){toast(error.message,'bad');return;}
    clearActionFeedback();file.value='';S.rows=[];S.validated=[];S.editor=null;S.auditCursor=0;S.sourceName='';S.batchId=crypto.randomUUID();S.draftId=S.batchId;autosave.adopt(S.draftId,0);
    $('#gi-source-name',main).textContent='';progressStatus.textContent='Revisión descartada. Puede seleccionar otro archivo.';draw();await refreshDraftOptions();
  });
  validate.addEventListener('click',()=>run(async()=>{
    const f=file.files?.[0];if(!f&&!S.rows.length&&!S.validated.length)return;
    if(!S.validated.length){
      const rows=f?parseCsv(await f.text()):null;if(f)S.sourceName=f.name;if(rows&&rows.length<2){throw Error('El archivo no contiene filas para importar');}
      const headers=rows?rows[0].map(x=>String(x).trim()):REQUIRED;const missing=REQUIRED.filter(h=>!headers.includes(h));
      if(missing.length)throw Error(`Faltan columnas obligatorias: ${missing.join(', ')}. Use la plantilla oficial.`);
      if(rows)S.rows=toObjects(rows);if(S.rows.length>1000)throw Error('El máximo por carga es de 1,000 filas. Divida el archivo.');
      snapshotChanged();await autosave.flush();
      S.validated=[];for(const r of S.rows)S.validated.push(await validateRow(r));
    }
    await refreshReview();validate.textContent='Volver a validar correcciones';
    const issues=S.validated.filter(v=>v.errors.length).length;return {state:issues?'warning':'success',message:`Archivo revisado: ${S.validated.length} fila(s), ${issues} con observaciones`};
  },topAction('validate','Revisar archivo')));
  $('#gi-review-filters',main).addEventListener('click',e=>{const button=e.target.closest('[data-review-filter]');if(!button||S.busy)return;S.reviewFilter=button.dataset.reviewFilter;draw();});
  $('#duplicates',main).addEventListener('click',()=>run(async()=>{await checkDuplicates();return duplicateOutcome();},topAction('duplicates','Verificar duplicadas')));
  $('#approve',main).addEventListener('click',()=>run(async()=>{
    const rows=S.validated.filter(v=>v.status==='review'&&!v.errors.length);
    if(!await confirmDialog('Aprobar filas revisadas',`Se aprobarán ${rows.length} fila(s) sin observaciones. La decisión quedará en bitácora; todavía no se crean reclamaciones.`,'Aprobar'))return false;
    await approveRows(rows);const approved=rows.filter(v=>v.status==='ready').length;return {state:approved===rows.length?'success':'warning',message:`Aprobación finalizada: ${approved} de ${rows.length} fila(s) aprobadas`};
  },topAction('approve','Aprobar filas')));
  preview.addEventListener('click',e=>{
    const button=e.target.closest('[data-edit-row],[data-exclude-row],[data-restore-row],[data-review-row],[data-tariff-row],[data-remove-row]');if(!button||S.busy)return;
    const key=Object.keys(button.dataset).find(k=>k.endsWith('Row'));const v=S.validated.find(x=>String(x.row)===button.dataset[key]);if(!v)return;
    run(async()=>{
      if(key==='editRow')return await editRow(v);
      else if(key==='reviewRow'){await approveRows([v]);return {state:v.status==='ready'?'success':'warning',message:v.status==='ready'?`Fila ${v.row} aprobada`:`Fila ${v.row} sin aprobar; revise las observaciones`};}
      else if(key==='excludeRow')return await askReason(v,'Excluir fila');
      else if(key==='restoreRow')return await askReason(v,'Restaurar fila');
      else if(key==='removeRow')return await askReason(v,'Eliminar reclamación');
      else if(key==='tariffRow'&&can('contracts.edit',ctx.role)){
        const changed=await contractDialog(S.providers,S.ars,{provider:v.provider.id,ars:v.ars.id,procedure:v.service.procedure_id,
          service:v.service.name,requireReason:true,onSave:async data=>{snapshotChanged();await autosave.flush();return rpc('google_intake_tariff_v1',{p_record_id:recordId(v),p_data:data});}});
        if(changed){await refreshReview();toast('Nueva vigencia registrada. Revise y apruebe nuevamente las filas afectadas.','ok');}
        return changed;
      }
    },{id:`${key}:${v.row}`,label:`${button.textContent} · fila ${v.row}`,find:()=>[...preview.querySelectorAll('button')].find(b=>b.dataset[key]===String(v.row))});
  });
  imp.addEventListener('click',()=>run(async()=>{
    await checkDuplicates();const ready=S.validated.filter(v=>v.status==='ready'&&v.reviewed);if(!ready.length)return {state:'warning',message:'No hay filas aprobadas disponibles para importar'};
    if(!await confirmDialog('Confirmación definitiva',`Se crearán ${ready.length} reclamación(es) aprobadas. Las demás filas no se importarán. El guardado y su bitácora se confirman juntos.`,'Confirmar e importar'))return false;
    let ok=0,fail=0;
    for(const v of ready){
      try{
        const result=await rpc('google_intake_review_v1',{p_record_id:recordId(v),p_action:'commit',p_data:dataFor(v)});
        v.status=result.removed?'removed':'imported';v.folio=result.folio;v.claimId=result.id;ok++;snapshotChanged();
      }catch(error){v.status='failed';v.reviewed=false;v.errors=[friendlyError(error)];fail++;}
    }
    toast(`Resultado: ${ok} confirmada(s) · ${fail} por corregir`,fail?'bad':'ok');
    return {state:fail?'warning':'success',message:`Importación finalizada: ${ok} confirmada(s), ${fail} por corregir`};
  },topAction('import','Confirmar importación')));
  try{await initializeDraft();}catch(error){progressStatus.dataset.state='error';progressStatus.textContent=error.message;toast(error.message,'bad');}
  finally{S.initializing=false;draw();}
}
export default render;
