/** SOFA · Carga externa desde Google Sheets / Google Form.
 * La hoja NUNCA necesita publicarse. El flujo seguro es descargar la pestaña Capturas como CSV
 * e importarla aquí. Cada fila vuelve a validar médico, ARS, servicio y tarifa contra SOFA.
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, emptyView, busy, confirmDialog } from '../utils/ui.js';
import { money } from '../utils/formatters.js';
import { captureProviders, activeArs, contractedServices } from '../services/claims.js';
import { capturarConDiagnostico } from '../services/calidad-dato.js';

const TEMPLATE_URL = 'https://docs.google.com/spreadsheets/d/1VeUb9RQ_jGBN9chr6QCiV-8Gp-2b2JKaj159qo6a-ps/edit';
const REQUIRED = ['Médico / Prestador *','ARS *','Fecha del servicio *','Paciente *','NSS / No. afiliado *','Servicio / Procedimiento *'];

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

export async function render(main, ctx){
  const S={providers:[],ars:[],rows:[],validated:[],importing:false};
  paint(main,html`
    <div class="page-head"><div class="t"><h2>Carga Google Sheets / Form</h2>
      <p>Importa reclamaciones capturadas fuera de SOFA. Ninguna fila entra directo: primero se valida contra médico, ARS, servicio contractual y tarifa.</p></div>
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
          <li>El médico y la ARS deben coincidir exactamente con registros visibles en SOFA.</li>
          <li>El servicio debe existir como contratado para ese médico + ARS + fecha.</li>
          <li>Si el monto viene vacío, SOFA usa la tarifa contractual.</li>
          <li>Si el monto difiere de la tarifa, la fila se detiene para revisión manual.</li>
          <li>Autorización es obligatoria salvo modalidad <b>emergencia</b>.</li>
          <li>Los duplicados siguen siendo bloqueados por el backend de SOFA.</li>
        </ul>
      </div>
    </div>
    <div class="card" style="margin-top:14px"><div class="page-head"><div class="t"><h2>2 · Prevalidación</h2><p id="summary">Carga un CSV para comenzar.</p></div>
      <button class="btn primary" id="import" disabled>Importar filas válidas</button></div><div id="preview"></div></div>
  `);

  const file=$('#gcsv',main), validate=$('#validate',main), imp=$('#import',main), preview=$('#preview',main), summary=$('#summary',main);
  try{[S.providers,S.ars]=await Promise.all([captureProviders(),activeArs()]);}
  catch(e){paint(preview,html`<div class="note bad">${friendlyError(e)}</div>`);return;}

  file.addEventListener('change',()=>{validate.disabled=!file.files?.length;});
  $('#clear',main).addEventListener('click',()=>{file.value='';S.rows=[];S.validated=[];validate.disabled=true;imp.disabled=true;paint(preview,html``);summary.textContent='Carga un CSV para comenzar.';});

  validate.addEventListener('click',()=>busy(validate,async()=>{
    const f=file.files?.[0]; if(!f)return;
    const rows=parseCsv(await f.text()); if(rows.length<2){toast('El archivo no contiene filas para importar','bad');return;}
    const headers=rows[0].map((x)=>String(x).trim());
    const missing=REQUIRED.filter((h)=>!headers.includes(h));
    if(missing.length){paint(preview,html`<div class="note bad">Faltan columnas obligatorias: <b>${missing.join(', ')}</b>. Usa la plantilla oficial.</div>`);imp.disabled=true;return;}
    S.rows=toObjects(rows); S.validated=[];
    for(const r of S.rows){
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
          const wanted=r['Servicio / Procedimiento *'];
          const n=norm(wanted);
          const hits=services.filter((s)=>[s.name,s.cups,s.simon,s.internal_code,s.ars_service_code].some((v)=>norm(v)===n));
          if(hits.length===1){service=hits[0];tariff=Number(service.amount);}
          else if(!hits.length) errors.push('Servicio no contratado para médico + ARS + fecha');
          else errors.push('Servicio ambiguo; use nombre o código exacto');
        }catch(e){errors.push('No se pudo validar el tarifario');}
      }
      const providedAmount=num(r['Monto a reclamar']);
      if(tariff!=null && providedAmount!=null && Math.abs(providedAmount-tariff)>=0.005) errors.push(`Monto ${money(providedAmount)} difiere de tarifa ${money(tariff)}`);
      const quantity=Math.max(1,Math.trunc(num(r['Cantidad'])||1));
      S.validated.push({row:r.__row,raw:r,provider,ars,service,serviceDate,patient,member,authorization,careMode,tariff,quantity,errors,warnings,status:errors.length?'error':'ready'});
    }
    const ok=S.validated.filter((x)=>x.status==='ready').length;
    const bad=S.validated.length-ok;
    summary.textContent=`${S.validated.length} fila(s): ${ok} válida(s) · ${bad} con error(es).`;
    imp.disabled=!ok;
    paint(preview,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fila</th><th>Paciente</th><th>Médico</th><th>ARS</th><th>Servicio</th><th>Tarifa</th><th>Estado</th></tr></thead><tbody>
      ${S.validated.map((v)=>html`<tr><td>${v.row}</td><td>${v.patient||'—'}</td><td>${v.provider?.full_name||v.raw['Médico / Prestador *']||'—'}</td><td>${v.ars?.name||v.raw['ARS *']||'—'}</td><td>${v.service?.name||v.raw['Servicio / Procedimiento *']||'—'}</td><td>${v.tariff!=null?money(v.tariff):'—'}</td><td><span class="pill ${v.status==='ready'?'ok':'bad'}">${v.status==='ready'?'Lista':'Revisar'}</span>${v.errors.length?html`<div class="small muted">${v.errors.join(' · ')}</div>`:''}</td></tr>`)}
    </tbody></table></div>`);
  }));

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
          notes:[`Carga Google Sheets/Form · fila ${v.row}`,String(r['Observaciones']||'').trim()].filter(Boolean).join(' · ')
        });
        v.status='imported';v.folio=result.folio;ok++;
      }catch(e){v.status='failed';v.errors=[friendlyError(e)];fail++;}
    }
    summary.textContent=`Importación terminada: ${ok} creada(s) · ${fail} fallida(s) · ${S.validated.filter((x)=>x.status==='error').length} no importada(s) por validación.`;
    toast(fail?`Importación completada con ${fail} fila(s) fallida(s)`:`${ok} reclamación(es) importadas`,fail?'bad':'ok');
    paint(preview,html`<div class="table-wrap"><table class="t cards"><thead><tr><th>Fila</th><th>Paciente</th><th>Servicio</th><th>Resultado</th></tr></thead><tbody>
      ${S.validated.map((v)=>html`<tr><td>${v.row}</td><td>${v.patient||'—'}</td><td>${v.service?.name||v.raw['Servicio / Procedimiento *']||'—'}</td><td>${v.status==='imported'?html`<span class="pill ok">Importada</span> <span class="mono">${v.folio}</span>`:html`<span class="pill bad">${v.status==='error'?'No importada':'Falló'}</span><div class="small muted">${v.errors.join(' · ')}</div>`}</td></tr>`)}
    </tbody></table></div>`);
  }));
}
export default render;
