/** SOFA · SeNaSa · Certificado de pago y conciliación por autorización.
 * Replica la estructura del Certificado de Pago Prestador de Servicios de Salud:
 * cabecera, detalle de facturas y detalle de autorizaciones.
 */
import { supabase, rpc, providerOptions, h, money, fmtDate, note, guarded, table } from '../services/iter18.js';

const PDFJS_URL='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs';
const PDFJS_WORKER='https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs';
const num=(v)=>Number(String(v??'').replace(/,/g,'').replace(/[^0-9.-]/g,'')||0);
const isoDate=(v)=>{const m=String(v??'').trim().match(/^(\d{1,2})[\\/-](\d{1,2})[\\/-](\d{4})$/);return m?`${m[3]}-${String(m[2]).padStart(2,'0')}-${String(m[1]).padStart(2,'0')}`:'';};
function rowsFromItems(items){const rows=[];for(const it of items.filter(x=>String(x.str||'').trim())){const y=Number(it.transform?.[5]||0),x=Number(it.transform?.[4]||0),s=String(it.str).trim();let r=rows.find(z=>Math.abs(z.y-y)<=2.5);if(!r){r={y,items:[]};rows.push(r);}r.items.push({x,s});}return rows.sort((a,b)=>b.y-a.y).map(r=>({y:r.y,items:r.items.sort((a,b)=>a.x-b.x),text:r.items.sort((a,b)=>a.x-b.x).map(x=>x.s).join(' ').replace(/\s+/g,' ').trim()}));}
function cellsByFractions(row,width,f){const out=Array.from({length:f.length-1},()=>[]);for(const it of row.items){const p=it.x/Math.max(width,1);let k=f.length-2;for(let i=0;i<f.length-1;i++){if(p>=f[i]&&p<f[i+1]){k=i;break;}}out[k].push(it.s);}return out.map(a=>a.join(' ').replace(/\s+/g,' ').trim());}
async function parseSenasaPdf(file){
  const pdfjs=await import(PDFJS_URL); pdfjs.GlobalWorkerOptions.workerSrc=PDFJS_WORKER;
  const pdf=await pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
  const pages=[];
  for(let i=1;i<=pdf.numPages;i++){const p=await pdf.getPage(i),tc=await p.getTextContent();pages.push({width:Number(p.view?.[2]||1),rows:rowsFromItems(tc.items)});}
  const all=pages.flatMap(p=>p.rows.map(r=>r.text)).join('\\n');
  const one=(re)=>all.match(re)?.[1]?.trim()||'';
  const invoices=[],authorizations=[];
  for(const p of pages){for(const row of p.rows){
    const a=cellsByFractions(row,p.width,[0,.105,.235,.37,.485,.61,.75,.88,1]);
    if(/^\d{5,}/.test(a[0]||'')&&isoDate(a[2])&&isoDate(a[3])&&a.slice(4).filter(x=>/[0-9].*\\.\d{2}/.test(x)).length>=4){
      const x={internal_number:a[0],ncf:a[1],receipt_date:isoDate(a[2]),invoice_date:isoDate(a[3]),invoice_amount:num(a[4]),invoice_objection_amount:num(a[5]),authorization_objection_amount:num(a[6]),amount_payable:num(a[7])};
      if(!invoices.some(z=>z.internal_number===x.internal_number&&z.ncf===x.ncf))invoices.push(x);
    }
    const b=cellsByFractions(row,p.width,[0,.075,.19,.275,.525,.65,.77,.89,1]);
    if(/^\d+/.test(b[0]||'')&&/^\d{7,}/.test(b[1]||'')){
      const x={invoice_number:b[0],authorization_number:b[1],authorization_date:isoDate(b[2]),affiliate_name:b[3],service_name:b[4],claimed_amount:num(b[5]),objected_amount:num(b[6]),paid_amount:num(b[7])};
      if(!authorizations.some(z=>z.authorization_number===x.authorization_number))authorizations.push(x);
    }
  }}
  const amounts=(label)=>{const l=pages.flatMap(p=>p.rows).find(r=>new RegExp(label,'i').test(r.text));const m=l?.text.match(/-?[0-9][0-9,]*\\.\d{2}/g)||[];return m.length?num(m.at(-1)):0;};
  return {
    providerCode:one(/C[ÓO]DIGO\s+DEL\s+PRESTADOR\s*:\s*([^\\n]+)/i).split(/\s+/)[0]||'',
    providerName:one(/NOMBRE\s+DEL\s+PRESTADOR\s*:\s*([^\\n]+)/i).replace(/\s+RNC\s*:.*$/i,'').trim(),
    rnc:one(/RNC\s*:\s*([^\\n]*)/i).replace(/CERTIFICADO.*$/i,'').trim(),
    ovp:one(/CERTIFICADO\s+OVP\s+NO\\.?\s*:\s*([0-9A-Za-z-]+)/i),
    subtotal:amounts('SUB-?TOTAL'),invoiceObj:amounts('Objeciones\s+en\s+Facturas'),authObj:amounts('Objeciones\s+en\s+Autorizaciones'),total:amounts('TOTAL\s+A\s+PAGAR'),
    invoices,authorizations,pages:pdf.numPages
  };
}
const fld=(label,type='text',value='')=>h('label',{},label,h('input',{type,value,style:'width:100%'}));

export async function render(root,ctx){
  root.replaceChildren();
  const msg=h('div',{'aria-live':'polite'});
  const list=h('div',{'aria-live':'polite'});
  const form=h('section',{class:'i18-card'});
  root.append(
    h('div',{class:'page-head'},
      h('div',{class:'t'},h('h2',{},'SeNaSa · Certificados de pago'),h('p',{},'Conciliación por OVP, factura y autorización. Los valores objetados generan diferencias para revisión de glosas.'))),
    msg,form,list
  );

  const providers=await guarded(msg,providerOptions); if(!providers)return;
  const {data:arsRows,error:arsErr}=await supabase.from('ars').select('id,name,code').like('code','senasa_%').order('name');
  if(arsErr){msg.replaceChildren(note(arsErr.message,'error'));return;}
  const ars=arsRows||[];

  const provider=h('select',{},h('option',{value:''},'Seleccione prestador…'),providers.map(p=>h('option',{value:p.id,'data-org':p.organization_id},p.full_name)));
  const arsSel=h('select',{},h('option',{value:''},'Seleccione régimen SeNaSa…'),ars.map(a=>h('option',{value:a.id},a.name)));
  const pcode=h('input',{placeholder:'Código del prestador'});
  const pname=h('input',{placeholder:'Nombre del prestador'});
  const rnc=h('input',{placeholder:'RNC'});
  const ovp=h('input',{placeholder:'Certificado OVP No.'});
  const subtotal=h('input',{type:'number',step:'0.01',value:'0'});
  const invObj=h('input',{type:'number',step:'0.01',value:'0'});
  const authObj=h('input',{type:'number',step:'0.01',value:'0'});
  const total=h('input',{type:'number',step:'0.01',value:'0'});
  const source=h('input',{placeholder:'Nombre del PDF / archivo de origen'});
  const pdfFile=h('input',{type:'file',accept:'application/pdf,.pdf'});
  const parseBtn=h('button',{class:'i18-btn i18-sec',type:'button'},'Leer PDF SeNaSa');
  const invBox=h('div'); const authBox=h('div');
  const previewBox=h('div',{'aria-live':'polite'}); const preview=h('div',{'aria-live':'polite'}); const reconcile=h('div',{'aria-live':'polite'});
  const invoices=[]; const auths=[];

  function addInvoice(x={}){
    const row={
      internal:h('input',{value:x.internal_number||'',placeholder:'Num. interno'}),
      ncf:h('input',{value:x.ncf||'',placeholder:'NCF'}),
      receipt:h('input',{type:'date',value:x.receipt_date||''}),
      invoiceDate:h('input',{type:'date',value:x.invoice_date||''}),
      invoiceAmount:h('input',{type:'number',step:'0.01',value:x.invoice_amount||''}),
      invoiceObj:h('input',{type:'number',step:'0.01',value:x.invoice_objection_amount||'0'}),
      authObj:h('input',{type:'number',step:'0.01',value:x.authorization_objection_amount||'0'}),
      payable:h('input',{type:'number',step:'0.01',value:x.amount_payable||''})
    };
    invoices.push(row); drawInvoices();
  }
  function drawInvoices(){
    invBox.replaceChildren(table(['Num. interno','NCF','Recepción','Fecha factura','Monto factura','Obj. factura','Obj. autorización','Monto a pagar'].map(label=>({label,get:()=>''})),[]));
    const wrap=h('div',{class:'table-wrap'}); const t=h('table',{class:'t cards'});
    t.append(h('thead',{},h('tr',{},['Num. interno','NCF','Recepción','Fecha factura','Monto factura','Obj. factura','Obj. autorización','Monto a pagar'].map(x=>h('th',{},x)))));
    t.append(h('tbody',{},invoices.map(r=>h('tr',{},[r.internal,r.ncf,r.receipt,r.invoiceDate,r.invoiceAmount,r.invoiceObj,r.authObj,r.payable].map(x=>h('td',{},x))))));
    wrap.append(t); invBox.replaceChildren(wrap);
  }
  function addAuth(x={}){
    const row={
      invoice:h('input',{value:x.invoice_number||'',placeholder:'Factura'}),
      authorization:h('input',{value:x.authorization_number||'',placeholder:'Autorización'}),
      date:h('input',{type:'date',value:x.authorization_date||''}),
      affiliate:h('input',{value:x.affiliate_name||'',placeholder:'Afiliado'}),
      service:h('input',{value:x.service_name||'',placeholder:'Servicio'}),
      claimed:h('input',{type:'number',step:'0.01',value:x.claimed_amount||''}),
      objected:h('input',{type:'number',step:'0.01',value:x.objected_amount||'0'}),
      paid:h('input',{type:'number',step:'0.01',value:x.paid_amount||''})
    };
    auths.push(row); drawAuths();
  }
  function drawPreview(meta={}){
    const inv=invoices.filter(r=>r.ncf.value||r.internal.value).map(r=>({
      ncf:r.ncf.value,invoice_amount:num(r.invoiceAmount.value),invoice_objection_amount:num(r.invoiceObj.value),
      authorization_objection_amount:num(r.authObj.value),amount_payable:num(r.payable.value)
    }));
    const au=auths.filter(r=>r.authorization.value).map(r=>({
      authorization:r.authorization.value,affiliate:r.affiliate.value,service:r.service.value,
      claimed:num(r.claimed.value),objected:num(r.objected.value),paid:num(r.paid.value),date:r.date.value
    }));
    const claimed=au.reduce((s,x)=>s+x.claimed,0), objected=au.reduce((s,x)=>s+x.objected,0), paid=au.reduce((s,x)=>s+x.paid,0);
    const suspicious=au.filter(x=>String(x.date||'').startsWith('1969-')).length;
    const expected=num(total.value||subtotal.value), delta=Math.abs(expected-paid);
    previewBox.replaceChildren(h('section',{class:'i18-card'},
      h('h3',{},'Previsualización antes de conciliar'),
      h('div',{class:'grid kpis'},
        h('div',{class:'kpi'},h('div',{class:'l'},'OVP'),h('div',{class:'v'},ovp.value||'—')),
        h('div',{class:'kpi'},h('div',{class:'l'},'Facturas'),h('div',{class:'v'},String(inv.length))),
        h('div',{class:'kpi'},h('div',{class:'l'},'Autorizaciones'),h('div',{class:'v'},String(au.length))),
        h('div',{class:'kpi'},h('div',{class:'l'},'Pagado extraído'),h('div',{class:'v'},money(paid)))
      ),
      h('div',{class:'note '+(delta<0.01?'ok':'warn')},
        `Reclamado por autorizaciones: ${money(claimed)} · Objetado: ${money(objected)} · Pagado: ${money(paid)} · Total certificado: ${money(expected)}${delta>=0.01?` · Diferencia: ${money(delta)}`:''}`
      ),
      suspicious?h('div',{class:'note warn'},`${suspicious} fecha(s) de autorización parecen atípicas (1969). Revísalas antes de conciliar.`):null,
      meta.pages?h('p',{class:'small muted'},`Extracción desde PDF: ${meta.pages} página(s). Todos los campos permanecen editables antes de Guardar y conciliar.`):null
    ));
  }

  function drawAuths(){
    const wrap=h('div',{class:'table-wrap'}); const t=h('table',{class:'t cards'});
    t.append(h('thead',{},h('tr',{},['Factura','Autorización','Fecha auth.','Afiliado','Servicio','Valor reclamado','Valor objetado','Valor pagado'].map(x=>h('th',{},x)))));
    t.append(h('tbody',{},auths.map(r=>h('tr',{},[r.invoice,r.authorization,r.date,r.affiliate,r.service,r.claimed,r.objected,r.paid].map(x=>h('td',{},x))))));
    wrap.append(t); authBox.replaceChildren(wrap);
  }

  addInvoice(); addAuth();
  parseBtn.addEventListener('click',async()=>{
    const file=pdfFile.files?.[0];
    if(!file){msg.replaceChildren(note('Seleccione un PDF de SeNaSa.','error'));return;}
    parseBtn.disabled=true; msg.replaceChildren(note('Leyendo certificado SeNaSa…'));
    try{
      const x=await parseSenasaPdf(file);
      pcode.value=x.providerCode||''; pname.value=x.providerName||''; rnc.value=x.rnc||''; ovp.value=x.ovp||'';
      subtotal.value=String(x.subtotal||0); invObj.value=String(x.invoiceObj||0); authObj.value=String(x.authObj||0); total.value=String(x.total||x.subtotal||0); source.value=file.name;
      invoices.length=0;auths.length=0; x.invoices.forEach(addInvoice);x.authorizations.forEach(addAuth); if(!invoices.length)addInvoice();if(!auths.length)addAuth();
      const suspicious=x.authorizations.filter(a=>String(a.authorization_date||'').startsWith('1969-')).length;
      const invTotal=x.invoices.reduce((s,r)=>s+num(r.invoice_amount),0), authClaimed=x.authorizations.reduce((s,r)=>s+num(r.claimed_amount),0), authPaid=x.authorizations.reduce((s,r)=>s+num(r.paid_amount),0), authObjected=x.authorizations.reduce((s,r)=>s+num(r.objected_amount),0);
      preview.replaceChildren(h('section',{class:'i18-card'},
        h('h3',{},'Previsualización extraída del PDF'),
        h('div',{class:'grid kpis'},
          h('div',{class:'kpi'},h('div',{class:'l'},'OVP'),h('div',{class:'v'},x.ovp||'—')),
          h('div',{class:'kpi'},h('div',{class:'l'},'Facturas'),h('div',{class:'v'},String(x.invoices.length)),h('div',{class:'h'},money(invTotal))),
          h('div',{class:'kpi'},h('div',{class:'l'},'Autorizaciones'),h('div',{class:'v'},String(x.authorizations.length)),h('div',{class:'h'},money(authClaimed))),
          h('div',{class:'kpi'},h('div',{class:'l'},'Pagado / Objetado'),h('div',{class:'v'},money(authPaid)),h('div',{class:'h'},`Objetado ${money(authObjected)}`))
        ),
        suspicious ? note(`${suspicious} fecha(s) de autorización parecen atípicas (1969). Corríjalas antes de conciliar.`,'warn') : note('Revise los datos extraídos. Puede editar cualquier campo antes de guardar y conciliar.','ok')
      ));
      msg.replaceChildren(note(`PDF leído: ${x.pages} página(s), ${x.invoices.length} factura(s), ${x.authorizations.length} autorización(es). Revise la previsualización antes de conciliar.`,suspicious?'warn':'ok'));
    }catch(e){msg.replaceChildren(note('No se pudo leer automáticamente el PDF. Puede completar el formulario manualmente. '+e.message,'error'));}
    finally{parseBtn.disabled=false;}
  });

  const save=h('button',{class:'i18-btn',type:'button'},'Guardar y conciliar todo');
  save.addEventListener('click',async()=>{
    if(!provider.value||!arsSel.value||!pcode.value.trim()||!pname.value.trim()||!ovp.value.trim()){msg.replaceChildren(note('Complete prestador, régimen SeNaSa, código, nombre y OVP.','error'));return;}
    const org=provider.selectedOptions[0]?.dataset.org;
    const inv=invoices.filter(r=>r.ncf.value||r.internal.value).map(r=>({
      internal_number:r.internal.value,ncf:r.ncf.value,receipt_date:r.receipt.value,invoice_date:r.invoiceDate.value,
      invoice_amount:num(r.invoiceAmount.value),invoice_objection_amount:num(r.invoiceObj.value),
      authorization_objection_amount:num(r.authObj.value),amount_payable:num(r.payable.value)
    }));
    const au=auths.filter(r=>r.authorization.value).map(r=>({
      invoice_number:r.invoice.value,authorization_number:r.authorization.value,authorization_date:r.date.value,
      affiliate_name:r.affiliate.value,service_name:r.service.value,claimed_amount:num(r.claimed.value),
      objected_amount:num(r.objected.value),paid_amount:num(r.paid.value)
    }));
    save.disabled=true;
    try{
      const certId=await rpc('save_senasa_payment_certificate',{
        p_org:org,p_provider:provider.value,p_ars:arsSel.value,p_provider_code:pcode.value,p_provider_name:pname.value,
        p_rnc:rnc.value||null,p_ovp:ovp.value,p_subtotal:num(subtotal.value),p_invoice_obj:num(invObj.value),
        p_auth_obj:num(authObj.value),p_total:num(total.value),p_source_file:source.value||null,p_invoices:inv,p_authorizations:au
      });
      const rr=await rpc('senasa_certificate_reconciliation',{p_certificate:certId});
      reconcile.replaceChildren(h('section',{class:'i18-card'},
        h('h3',{},`Resultado de conciliación · OVP ${rr?.ovp||ovp.value}`),
        h('div',{class:'grid kpis'},
          h('div',{class:'kpi'},h('div',{class:'l'},'Coincidencias'),h('div',{class:'v'},String(rr?.matched||0))),
          h('div',{class:'kpi'},h('div',{class:'l'},'Diferencias'),h('div',{class:'v'},String(rr?.differences||0))),
          h('div',{class:'kpi'},h('div',{class:'l'},'No encontradas'),h('div',{class:'v'},String(rr?.not_found||0))),
          h('div',{class:'kpi'},h('div',{class:'l'},'Objetado'),h('div',{class:'v'},money(rr?.objected_total||0)),h('div',{class:'h'},`Pagado ${money(rr?.paid_total||0)}`))
        ),
        rr?.ready_to_apply
          ? note('Conciliación completa: todas las autorizaciones fueron encontradas y sus montos coinciden. El pago queda listo para el flujo de aplicación.','ok')
          : note('Conciliación con diferencias: revise autorizaciones no encontradas o montos distintos antes de aplicar el pago o registrar glosa.','warn')
      ));
      msg.replaceChildren(note('Certificado SeNaSa guardado y conciliado contra las reclamaciones de SOFA.','ok'));
      await loadList();
    }catch(e){msg.replaceChildren(note(e.message,'error'));}finally{save.disabled=false;}
  });

  form.replaceChildren(
    h('h3',{},'Certificado de Pago Prestador de Servicios de Salud'),
    h('div',{class:'i18-form'},
      h('label',{},'Prestador SOFA',provider),h('label',{},'Régimen SeNaSa',arsSel),
      h('label',{},'Código del prestador',pcode),h('label',{},'Nombre del prestador',pname),
      h('label',{},'RNC',rnc),h('label',{},'Certificado OVP No.',ovp),
      h('label',{},'PDF SeNaSa',pdfFile),h('div',{class:'i18-actions'},parseBtn),
      h('label',{},'Archivo de origen',source)),
    preview,
    previewBox,
    h('h4',{},'Detalle de las facturas'),invBox,
    h('div',{class:'i18-actions'},h('button',{class:'i18-btn i18-sec',type:'button',onclick:()=>addInvoice()},'+ Agregar factura')),
    h('div',{class:'i18-form'},
      h('label',{},'Sub-total',subtotal),h('label',{},'Objeciones en facturas',invObj),
      h('label',{},'Objeciones en autorizaciones',authObj),h('label',{},'Total a pagar',total)),
    h('h4',{},'Detalle de autorizaciones por factura'),authBox,
    h('div',{class:'i18-actions'},h('button',{class:'i18-btn i18-sec',type:'button',onclick:()=>addAuth()},'+ Agregar autorización')),
    h('div',{class:'i18-actions'},save),
    reconcile
  );

  provider.addEventListener('change',()=>{const p=providers.find(x=>x.id===provider.value); if(p)pname.value=p.full_name||'';});
  [ovp,subtotal,invObj,authObj,total].forEach(x=>x.addEventListener('change',()=>drawPreview()));

  async function loadList(){
    const org=provider.selectedOptions[0]?.dataset.org;
    let q=supabase.from('senasa_payment_certificates').select('id,ovp_number,provider_name_snapshot,total_payable,invoice_objection_amount,authorization_objection_amount,status,created_at,ars(name)').order('created_at',{ascending:false}).limit(50);
    if(org)q=q.eq('organization_id',org);
    const {data,error}=await q;
    if(error){list.replaceChildren(note(error.message,'error'));return;}
    list.replaceChildren(h('section',{class:'i18-card'},h('h3',{},'Certificados registrados'),
      table([
        {label:'OVP',get:r=>r.ovp_number},
        {label:'Prestador',get:r=>r.provider_name_snapshot},
        {label:'ARS',get:r=>r.ars?.name||'SeNaSa'},
        {label:'Total pagar',right:true,get:r=>money(r.total_payable)},
        {label:'Obj. factura',right:true,get:r=>money(r.invoice_objection_amount)},
        {label:'Obj. autorización',right:true,get:r=>money(r.authorization_objection_amount)},
        {label:'Estado',get:r=>r.status}
      ],data||[])));
  }
  provider.addEventListener('change',loadList); loadList();
}
