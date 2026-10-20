/** SOFA · SeNaSa · Certificado de pago y conciliación por autorización.
 * Replica la estructura del Certificado de Pago Prestador de Servicios de Salud:
 * cabecera, detalle de facturas y detalle de autorizaciones.
 */
import { supabase, rpc, providerOptions, h, money, fmtDate, note, guarded, table } from '../services/iter18.js';

const num=(v)=>Number(String(v??'').replace(/,/g,'')||0);
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
  const invBox=h('div'); const authBox=h('div');
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
  function drawAuths(){
    const wrap=h('div',{class:'table-wrap'}); const t=h('table',{class:'t cards'});
    t.append(h('thead',{},h('tr',{},['Factura','Autorización','Fecha auth.','Afiliado','Servicio','Valor reclamado','Valor objetado','Valor pagado'].map(x=>h('th',{},x)))));
    t.append(h('tbody',{},auths.map(r=>h('tr',{},[r.invoice,r.authorization,r.date,r.affiliate,r.service,r.claimed,r.objected,r.paid].map(x=>h('td',{},x))))));
    wrap.append(t); authBox.replaceChildren(wrap);
  }

  addInvoice(); addAuth();

  const save=h('button',{class:'i18-btn',type:'button'},'Guardar y conciliar');
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
      await rpc('save_senasa_payment_certificate',{
        p_org:org,p_provider:provider.value,p_ars:arsSel.value,p_provider_code:pcode.value,p_provider_name:pname.value,
        p_rnc:rnc.value||null,p_ovp:ovp.value,p_subtotal:num(subtotal.value),p_invoice_obj:num(invObj.value),
        p_auth_obj:num(authObj.value),p_total:num(total.value),p_source_file:source.value||null,p_invoices:inv,p_authorizations:au
      });
      msg.replaceChildren(note('Certificado SeNaSa guardado. SOFA comparó autorizaciones y montos con las reclamaciones existentes.','ok'));
      await loadList();
    }catch(e){msg.replaceChildren(note(e.message,'error'));}finally{save.disabled=false;}
  });

  form.replaceChildren(
    h('h3',{},'Certificado de Pago Prestador de Servicios de Salud'),
    h('div',{class:'i18-form'},
      h('label',{},'Prestador SOFA',provider),h('label',{},'Régimen SeNaSa',arsSel),
      h('label',{},'Código del prestador',pcode),h('label',{},'Nombre del prestador',pname),
      h('label',{},'RNC',rnc),h('label',{},'Certificado OVP No.',ovp),
      h('label',{},'Archivo de origen',source)),
    h('h4',{},'Detalle de las facturas'),invBox,
    h('div',{class:'i18-actions'},h('button',{class:'i18-btn i18-sec',type:'button',onclick:()=>addInvoice()},'+ Agregar factura')),
    h('div',{class:'i18-form'},
      h('label',{},'Sub-total',subtotal),h('label',{},'Objeciones en facturas',invObj),
      h('label',{},'Objeciones en autorizaciones',authObj),h('label',{},'Total a pagar',total)),
    h('h4',{},'Detalle de autorizaciones por factura'),authBox,
    h('div',{class:'i18-actions'},h('button',{class:'i18-btn i18-sec',type:'button',onclick:()=>addAuth()},'+ Agregar autorización')),
    h('div',{class:'i18-actions'},save)
  );

  provider.addEventListener('change',()=>{const p=providers.find(x=>x.id===provider.value); if(p)pname.value=p.full_name||'';});

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
