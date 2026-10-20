/** SOFA · Carga externa desde Google Sheets / Google Form.
 * Permite completar/corregir datos dentro de SOFA antes de importar.
 * Cada corrección queda en audit_log con usuario, fecha, campos y valores antes/después.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, busy, confirmDialog, formDialog, opt, requireFields } from '../utils/ui.js';
import { money } from '../utils/formatters.js';
import { captureProviders, activeArs, contractedServices } from '../services/claims.js';
import { capturarConDiagnostico, cie10Suggestions } from '../services/calidad-dato.js';
import { rpc } from '../services/iter18.js';

const TEMPLATE_URL = 'https://docs.google.com/spreadsheets/d/1VeUb9RQ_jGBN9chr6QCiV-8Gp-2b2JKaj159qo6a-ps/edit';
const REQUIRED = ['Médico / Prestador *','ARS *','Fecha del servicio *','Paciente *','NSS / No. afiliado *','Servicio / Procedimiento *'];
const EDITABLE = [
  'Médico / Prestador *','ARS *','Fecha del servicio *','Modalidad','Paciente *','NSS / No. afiliado *',
  'No. autorización','Fecha autorización','Cédula paciente','Diagnóstico CIE-10','Centro / clínica',
  'Servicio / Procedimiento *','Cantidad','Monto a reclamar','Observaciones'
];

const norm = (v) => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const num = (v) => {
  const s=String(v??'').replace(/[^0-9,.-]/g,'').replace(',','.');
  const n=Number(s); return Number.isFinite(n)?n:null;
};
const parseDate = (v) => {
  const s=String(v??'').trim();
  if(/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const m=s.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/);
  if(m) return `${m[3]}-${String(m[2]).padStart(2,'0')}-${String(m[1]).padStart(2,'0')}`;
  const d=new Date(s); return Number.isNaN(d.getTime())?'':d.toISOString().slice(0,10);
};
function parseCsv(text){
  const rows=[]; let row=[]; let cell=''; let q=false;
  for(let i=0;i<text.length;i++){
    const ch=text[i], nx=text[i+1];
    if(ch==='"' && q && nx==='"'){cell+='"';i++;continue;}
    if(ch==='"'){q=!q;continue;}
    if(ch===',' && !q){row.push(cell);cell='';continue;}
    if((ch==='\n'||ch==='\r')&&!q){
      if(ch==='\r'&&nx==='\n') i++;
      row.push(cell);cell='';
      if(row.some((x)=>String(x).trim()!=='')) rows.push(row);
      row=[];continue;
    }
    cell+=ch;
  }
  row.push(cell); if(row.some((x)=>String(x).trim()!=='')) rows.push(row);
  return rows;
}
function toObjects(rows){
  if(!rows.length) return [];
  const headers=rows[0].map((h)=>String(h).trim());
  return rows.slice(1).map((r,i)=>({__row:i+2,...Object.fromEntries(headers.map((h,j)=>[h,r[j]??'']))}));
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
  const S={providers:[],ars:[],rows:[],validated:[],batchId:crypto.randomUUID?.()||String(Date.now())};
  paint(main,html`
    <div class="page-head"><div class="t"><h2>Carga Google Sheets / Form</h2>
      <p>Importa reclamaciones capturadas fuera de SOFA. Si faltan datos, el mismo usuario puede completarlos aquí antes de importar; cada cambio queda en bitácora.</p></div>
      <div class="toolbar" style="margin:0"><a class="btn" href="${TEMPLATE_URL}" target="_blank" rel="noopener">Abrir plantilla Google Sheets</a></div>
    </div>
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
          <li>Una fila incompleta puede corregirse con <b>Completar / editar</b>.</li>
          <li>Cada corrección se registra en la bitácora con el usuario autenticado.</li>
          <li>El médico y la ARS deben coincidir con registros visibles en SOFA.</li>
          <li>El servicio debe estar contratado para médico + ARS + fecha.</li>
          <li>Si el monto viene vacío, SOFA usa la tarifa contractual.</li>
          <li>Si el monto difiere de la tarifa, se exige revisión antes de importar.</li>
          <li>Los duplicados siguen siendo bloqueados por el backend de SOFA.</li>
        </ul>
      </div>
    </div>
    <div class="card" style="margin-top:14px"><div class="page-head"><div class="t"><h2>2 · Prevalidación y corrección</h2><p id="summary">Carga un CSV para comenzar.</p></div>
      <button class="btn primary" id="import" disabled>Importar filas válidas</button></div><div id="preview"></div></div>
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
    const serviceDate=parseDate(r['Fecha del servicio *']); if(!serviceDate) errors.push('Fecha del servicio inválida');
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
    if(tariff!=null && providedAmount!=null && Math.abs(providedAmount-tariff)>=0.005) errors.push(`Monto ${money(providedAmount)} difiere de tarifa ${money(tariff)}`);
    const quantity=Math.max(1,Math.trunc(num(r['Cantidad'])||1));
    return {
      ...previous,row:r.__row,raw:r,provider,ars,service,serviceDate,patient,member,authorization,careMode,tariff,quantity,
      errors,warnings,status:errors.length?'error':'ready',editCount:previous.editCount||0
    };
  }

  function draw(){
    const ok=S.validated.filter((x)=>x.status==='ready').length;
    const bad=S.validated.filter((x)=>x.status==='error'||x.status==='failed').length;
    const imported=S.validated.filter((x)=>x.status==='imported').length;
    summary.textContent=`${S.validated.length} fila(s): ${ok} lista(s) · ${bad} por revisar${imported?` · ${imported} importada(s)`:''}.`;
    imp.disabled=!ok;
    paint(preview,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fila</th><th>Paciente</th><th>Médico</th><th>ARS</th><th>Servicio</th><th>Tarifa</th><th>Estado</th><th>Acción</th></tr></thead><tbody>
      ${S.validated.map((v)=>html`<tr>
        <td data-l="Fila">${v.row}</td>
        <td data-l="Paciente">${v.patient||'—'}</td>
        <td data-l="Médico">${v.provider?.full_name||v.raw['Médico / Prestador *']||'—'}</td>
        <td data-l="ARS">${v.ars?.name||v.raw['ARS *']||'—'}</td>
        <td data-l="Servicio">${v.service?.name||v.raw['Servicio / Procedimiento *']||'—'}</td>
        <td data-l="Tarifa">${v.tariff!=null?money(v.tariff):'—'}</td>
        <td data-l="Estado">
          ${v.status==='imported'
            ? html`<span class="pill ok">Importada</span> <span class="mono">${v.folio||''}</span>`
            : html`<span class="pill ${v.status==='ready'?'ok':'bad'}">${v.status==='ready'?'Lista':'Revisar'}</span>`}
          ${v.editCount?html` <span class="pill">Corregida ${v.editCount}×</span>`:''}
          ${v.errors?.length?html`<div class="small muted">${v.errors.join(' · ')}</div>`:''}
          ${v.auditWarning?html`<div class="small" style="color:var(--warn)">${v.auditWarning}</div>`:''}
        </td>
        <td data-l="Acción">${v.status==='imported'?html`<a class="btn sm" href="#/reclamaciones">Ver reclamaciones</a>`:html`<button class="btn sm" data-edit-row="${v.row}">Completar / editar</button>`}</td>
      </tr>`)}
    </tbody></table></div>`);
  }

  async function editRow(v){
    const r=v.raw;
    const currentProvider=v.provider||exact(S.providers,r['Médico / Prestador *'],['full_name']);
    const currentArs=v.ars||exact(S.ars,r['ARS *'],['name','code']);
    const result=await formDialog({
      title:`Completar / editar fila ${v.row}`,submitLabel:'Guardar corrección',wide:true,
      body:html`
        <div class="note warn"><b>Bitácora:</b> se registrarán los campos modificados, los valores anteriores y nuevos, tu usuario y la fecha.</div>
        <div class="form-grid">
          <div class="field"><label>Médico / Prestador *</label><select name="provider" required><option value="">Seleccione…</option>${S.providers.map((p)=>opt(p.id,p.full_name,currentProvider?.id))}</select></div>
          <div class="field"><label>ARS *</label><select name="ars" required><option value="">Seleccione…</option>${S.ars.map((a)=>opt(a.id,a.name,currentArs?.id))}</select></div>
          <div class="field"><label>Fecha del servicio *</label><input name="service_date" type="date" required value="${parseDate(r['Fecha del servicio *'])}"></div>
          <div class="field"><label>Modalidad</label><select name="care_mode">${['ambulatorio','emergencia','internamiento'].map((x)=>opt(x,x,norm(r['Modalidad'])||'ambulatorio'))}</select></div>
          <div class="field" style="grid-column:1/-1"><label>Paciente *</label><input name="patient" required value="${r['Paciente *']||''}"></div>
          <div class="field"><label>NSS / No. afiliado *</label><input name="member" required value="${r['NSS / No. afiliado *']||''}"></div>
          <div class="field"><label>No. autorización</label><input name="authorization" value="${r['No. autorización']||''}"></div>
          <div class="field"><label>Fecha autorización</label><input name="auth_date" type="date" value="${parseDate(r['Fecha autorización'])}"></div>
          <div class="field"><label>Cédula paciente</label><input name="patient_doc" value="${r['Cédula paciente']||''}"></div>
          <div class="field"><label>Diagnóstico CIE-10</label><input name="diagnosis" value="${r['Diagnóstico CIE-10']||''}" placeholder="Escribe o selecciona una sugerencia"><div class="hint">SOFA sugiere según servicio, SIMON y CUPS; puedes cambiarlo.</div><div id="gie_dx_sugs" class="small" style="margin-top:6px"></div></div>
          <div class="field"><label>Centro / clínica</label><input name="clinic" value="${r['Centro / clínica']||''}"></div>
          <div class="field" style="grid-column:1/-1"><label>Servicio / Procedimiento *</label><select name="service" required><option value="">Seleccione médico, ARS y fecha</option></select><div class="hint">Solo se muestran servicios contratados para la combinación seleccionada.</div></div>
          <div class="field"><label>Cantidad</label><input name="quantity" type="number" min="1" step="1" value="${num(r['Cantidad'])||1}"></div>
          <div class="field"><label>Monto a reclamar</label><input name="amount" type="number" min="0" step="0.01" value="${num(r['Monto a reclamar'])??''}"><div class="hint">Déjalo vacío para usar la tarifa contractual.</div></div>
          <div class="field" style="grid-column:1/-1"><label>Observaciones</label><textarea name="notes" rows="2">${r['Observaciones']||''}</textarea></div>
        </div>`,
      onOpen:(form)=>{
        const loadDx=async()=>{
          const box=form.querySelector('#gie_dx_sugs'); if(!box)return;
          const procedure=form.elements.service.value;
          if(!procedure){paint(box,html``);return;}
          try{
            const rows=await cie10Suggestions(procedure,null,8);
            if(!rows.length){paint(box,html`<span class="muted">Sin sugerencia automática. Escribe el código documentado.</span>`);return;}
            paint(box,html`<div class="toolbar" style="gap:6px;flex-wrap:wrap">${rows.map((x)=>html`<button class="btn sm" type="button" data-gdx="${x.code}" title="${x.rationale||''}">${x.code} · ${x.title_es}</button>`)}</div><div class="small muted">Sugerencias administrativas; confirma el diagnóstico documentado.</div>`);
            box.querySelectorAll('[data-gdx]').forEach((b)=>b.addEventListener('click',()=>{form.elements.diagnosis.value=b.dataset.gdx;}));
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
          await loadDx();
        };
        ['provider','ars','service_date'].forEach((n)=>form.elements[n].addEventListener('change',loadServices));
        form.elements.service.addEventListener('change',loadDx);
        loadServices();
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
          'Observaciones':String(d.notes||'').trim()
        };
        const diff=changedValues(r,after);
        if(!diff.fields.length){toast('No hay cambios para guardar.');return true;}
        const recordId=`${S.batchId}:row:${v.row}`;
        await rpc('log_google_intake_edit',{
          p_record_id:recordId,
          p_org:provider?.organization_id||v.provider?.organization_id||null,
          p_before:diff.oldValues,
          p_after:diff.newValues,
          p_fields:diff.fields
        });
        const updated=await validateRow(after,{...v,editCount:(v.editCount||0)+1});
        const ix=S.validated.findIndex((x)=>x.row===v.row);
        S.validated[ix]=updated;
        toast(`Fila ${v.row} corregida y registrada en bitácora`,'ok');
        return true;
      }
    });
    if(result!==null) draw();
  }

  file.addEventListener('change',()=>{validate.disabled=!file.files?.length;});
  $('#clear',main).addEventListener('click',()=>{file.value='';S.rows=[];S.validated=[];S.batchId=crypto.randomUUID?.()||String(Date.now());validate.disabled=true;imp.disabled=true;paint(preview,html``);summary.textContent='Carga un CSV para comenzar.';});

  validate.addEventListener('click',()=>busy(validate,async()=>{
    const f=file.files?.[0]; if(!f)return;
    const rows=parseCsv(await f.text()); if(rows.length<2){toast('El archivo no contiene filas para importar','bad');return;}
    const headers=rows[0].map((x)=>String(x).trim());
    const missing=REQUIRED.filter((h)=>!headers.includes(h));
    if(missing.length){paint(preview,html`<div class="note bad">Faltan columnas obligatorias: <b>${missing.join(', ')}</b>. Usa la plantilla oficial.</div>`);imp.disabled=true;return;}
    S.rows=toObjects(rows); S.validated=[]; S.batchId=crypto.randomUUID?.()||String(Date.now());
    for(const r of S.rows) S.validated.push(await validateRow(r));
    draw();
  }));

  preview.addEventListener('click',(e)=>{
    const b=e.target.closest('[data-edit-row]'); if(!b)return;
    const v=S.validated.find((x)=>String(x.row)===String(b.dataset.editRow)); if(v) editRow(v).catch((err)=>toast(friendlyError(err),'bad'));
  });

  imp.addEventListener('click',()=>busy(imp,async()=>{
    const ready=S.validated.filter((x)=>x.status==='ready');
    if(!ready.length)return;
    if(!(await confirmDialog('Importar reclamaciones',`Se crearán ${ready.length} reclamación(es) en SOFA. Las filas con errores no se importarán.`,'Importar')))return;
    imp.disabled=true; let ok=0,fail=0;
    for(const v of ready){
      try{
        const r=v.raw;
        const result=await capturarConDiagnostico({
          provider:v.provider.id,ars:v.ars.id,procedure:v.service.procedure_id,serviceDate:v.serviceDate,
          patientName:v.patient,member:v.member,authorization:v.authorization,
          patientDoc:String(r['Cédula paciente']||'').trim(),diagnosis:String(r['Diagnóstico CIE-10']||'').trim(),
          quantity:v.quantity,careMode:v.careMode,clinic:String(r['Centro / clínica']||'').trim(),
          notes:[`Carga Google Sheets/Form · fila ${v.row}`,v.editCount?`Corregida en SOFA ${v.editCount} vez/veces`:'',String(r['Observaciones']||'').trim()].filter(Boolean).join(' · ')
        });
        v.status='imported';v.folio=result.folio;ok++;
        try{
          await rpc('log_google_intake_import',{
            p_record_id:`${S.batchId}:row:${v.row}`,
            p_org:v.provider.organization_id,
            p_claim:result.id,
            p_folio:result.folio
          });
        }catch(auditErr){v.auditWarning='La reclamación se creó, pero no se pudo registrar el evento de importación en la bitácora de carga.';}
      }catch(e){v.status='failed';v.errors=[friendlyError(e)];fail++;}
    }
    draw();
    summary.textContent=`Importación terminada: ${ok} creada(s) · ${fail} fallida(s) · ${S.validated.filter((x)=>x.status==='error').length} por revisar.`;
    toast(fail?`Importación completada con ${fail} fila(s) fallida(s)`:`${ok} reclamación(es) importadas`,fail?'bad':'ok');
  }));
}
export default render;
