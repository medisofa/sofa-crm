/** Acuse compartible: datos agregados del lote, sin datos de pacientes. */
import { money, date } from './formatters.js';
export function receptionTotals(r) {
  return r.office_reception_lines.reduce((a,l)=>({count:a.count+Number(l.declared_count),amount:a.amount+Number(l.declared_amount)}),{count:0,amount:0});
}
export function receiptText(r) {
  const t=receptionTotals(r);
  return [`SOFA · Acuse de recepción ${r.status==='anulada'?'ANULADO':''}`,r.folio,r.organizations?.legal_name || '',
    `Recibido: ${date(r.received_on)}`,r.service_period?`Período de servicios: ${date(r.service_period).slice(3)}`:'',
    r.providers?.full_name?`Médico: ${r.providers.full_name}`:'',`Entregó: ${r.delivered_by}`,`Recibió: ${r.received_by_label}`,
    ...r.office_reception_lines.map(l=>`${l.ars?.name || 'ARS'} · ${l.service_label}: ${l.declared_count} reclamaciones · ${money(l.declared_amount)}`),
    `Total recibido: ${t.count} reclamaciones · Monto declarado: ${money(t.amount)}`,r.notes?`Observaciones: ${r.notes}`:'',
    r.cancelled_reason?`Anulación: ${r.cancelled_reason}`:'','La recepción acredita la entrega del lote. Pendiente de captura, conciliación y validación.'].filter(Boolean).join('\n');
}
export async function receiptImage(r) {
  const canvas=document.createElement('canvas'); canvas.width=1000;
  const c=canvas.getContext('2d'); c.font='22px sans-serif'; const lines=[];
  for(const text of receiptText(r).split('\n')) {
    let line='';
    // Wrap by character as well as spaces, including long observations/identifiers.
    for(const char of text) {if(c.measureText(line+char).width>900){lines.push(line);line='';} line+=char;}
    lines.push(line,'');
  }
  canvas.height=100+lines.length*30;
  c.fillStyle='#ffffff'; c.fillRect(0,0,canvas.width,canvas.height);
  c.fillStyle='#17263c'; c.font='22px sans-serif';
  lines.forEach((line,i)=>c.fillText(line,50,60+i*30));
  const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
  if(!blob) throw new Error('No se pudo generar el acuse. Intente otra vez.');
  return new File([blob],`${r.folio}.png`,{type:'image/png'});
}
export function downloadReceipt(file) {
  const url=URL.createObjectURL(file);const a=document.createElement('a');a.href=url;a.download=file.name;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
}
