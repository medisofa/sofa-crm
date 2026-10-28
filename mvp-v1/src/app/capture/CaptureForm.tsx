"use client";
import { FormEvent, useEffect, useState } from "react";

type Org={organization_id:string;organization_name:string};
type Provider={id:string;full_name:string};
type Ars={id:string;name:string};
type Tariff={id:string;amount:number;procedure:{id:string;name:string;internal_code:string;simon_code?:string|null;cups_code?:string|null}};

export default function CaptureForm({ organizations }:{ organizations:Org[] }) {
  const [org,setOrg]=useState(organizations[0]?.organization_id ?? "");
  const [providers,setProviders]=useState<Provider[]>([]);
  const [ars,setArs]=useState<Ars[]>([]);
  const [provider,setProvider]=useState("");
  const [payer,setPayer]=useState("");
  const [serviceDate,setServiceDate]=useState(new Date().toISOString().slice(0,10));
  const [tariffs,setTariffs]=useState<Tariff[]>([]);
  const [proc,setProc]=useState("");
  const [status,setStatus]=useState("");

  useEffect(()=>{ if(!org)return; fetch(`/api/v1/catalogs?organization_id=${org}`).then(r=>r.json()).then(j=>{setProviders(j.data?.providers??[]);setArs(j.data?.ars??[]);}); },[org]);
  useEffect(()=>{ if(!org||!provider||!payer||!serviceDate){setTariffs([]);return;} fetch(`/api/v1/catalogs?organization_id=${org}&provider_id=${provider}&ars_id=${payer}&service_date=${serviceDate}`).then(r=>r.json()).then(j=>setTariffs(j.data?.tariffs??[])); },[org,provider,payer,serviceDate]);

  async function submit(e:FormEvent<HTMLFormElement>){
    e.preventDefault(); setStatus("Guardando…");
    const fd=new FormData(e.currentTarget);
    const t=tariffs.find(x=>x.procedure.id===proc);
    if(!t){setStatus("Seleccione un servicio vigente.");return;}
    const body={
      organization_id:org,provider_id:provider,ars_id:payer,service_date:serviceDate,
      patient_name:String(fd.get("patient_name")||""),member_number:String(fd.get("member_number")||""),
      authorization_number:String(fd.get("authorization_number")||"")||null,procedure_id:proc,
      quantity:Number(fd.get("quantity")||1),unit_amount:Number(t.amount),notes:String(fd.get("notes")||"")||null
    };
    const r=await fetch("/api/v1/claims",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(body)});
    const j=await r.json();
    if(!r.ok){setStatus("No se pudo guardar. Revise los datos.");return;}
    setStatus(`Guardada ${j.data.folio}`);
    e.currentTarget.reset();
    setProc("");
  }

  return <form onSubmit={submit}>
    <label>Consultorio<select value={org} onChange={e=>setOrg(e.target.value)} required>{organizations.map(o=><option key={o.organization_id} value={o.organization_id}>{o.organization_name}</option>)}</select></label>
    <label>Médico<select value={provider} onChange={e=>setProvider(e.target.value)} required><option value="">Seleccione</option>{providers.map(p=><option key={p.id} value={p.id}>{p.full_name}</option>)}</select></label>
    <label>ARS<select value={payer} onChange={e=>setPayer(e.target.value)} required><option value="">Seleccione</option>{ars.map(a=><option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
    <label>Fecha<input value={serviceDate} onChange={e=>setServiceDate(e.target.value)} type="date" required /></label>
    <label>Paciente<input name="patient_name" maxLength={150} required /></label>
    <label>NSS / afiliado<input name="member_number" maxLength={60} required /></label>
    <label>Autorización<input name="authorization_number" maxLength={80} /></label>
    <label>Servicio<select value={proc} onChange={e=>setProc(e.target.value)} required><option value="">Seleccione</option>{tariffs.map(t=><option key={t.id} value={t.procedure.id}>{t.procedure.name} · RD$ {Number(t.amount).toFixed(2)}</option>)}</select></label>
    <label>Cantidad<input name="quantity" type="number" min={1} max={99} defaultValue={1} required /></label>
    <label>Notas<textarea name="notes" maxLength={500} /></label>
    <button type="submit">Guardar reclamación</button>
    <p aria-live="polite">{status}</p>
  </form>;
}
