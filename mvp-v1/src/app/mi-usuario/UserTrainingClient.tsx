"use client";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

type Step = { title:string; description:string; href?:string; action?:string };

export default function UserTrainingClient({
  userId, role, label, steps
}: {
  userId:string; role:string; label:string; steps:Step[];
}) {
  const storageKey = useMemo(() => `sofa_training:${userId}:${role}`, [userId, role]);
  const [done, setDone] = useState<boolean[]>(steps.map(() => false));

  useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || "[]");
      if (Array.isArray(saved)) setDone(steps.map((_,i) => Boolean(saved[i])));
    } catch {}
  }, [storageKey, steps]);

  function toggle(i:number) {
    const next = done.map((v,idx) => idx===i ? !v : v);
    setDone(next);
    localStorage.setItem(storageKey, JSON.stringify(next));
  }

  const completed = done.filter(Boolean).length;
  const pct = Math.round((completed / Math.max(steps.length,1)) * 100);

  return (
    <section>
      <div style={{ display:"flex", justifyContent:"space-between", alignItems:"end", gap:12, flexWrap:"wrap" }}>
        <div>
          <h2>Entrenamiento para {label}</h2>
          <p>Completa estos pasos con datos de prueba antes de operar información real.</p>
        </div>
        <strong>{completed}/{steps.length} · {pct}%</strong>
      </div>
      <div style={{ height:8, background:"#e7ebf0", borderRadius:999, overflow:"hidden", marginBottom:16 }}>
        <div style={{ width:`${pct}%`, height:"100%", background:"#1A365D" }} />
      </div>
      <div style={{ display:"grid", gap:12 }}>
        {steps.map((step,i) => (
          <article key={step.title} style={{ background:"#fff", border:"1px solid #dfe4ea", borderRadius:12, padding:18 }}>
            <div style={{ display:"flex", gap:12, alignItems:"flex-start" }}>
              <input aria-label={`Completar ${step.title}`} type="checkbox" checked={done[i]} onChange={() => toggle(i)} style={{ marginTop:5 }} />
              <div style={{ flex:1 }}>
                <h3 style={{ marginTop:0 }}>{i+1}. {step.title}</h3>
                <p>{step.description}</p>
                {step.href ? <Link href={step.href}>Practicar ahora →</Link> : <span><strong>Acción:</strong> {step.action}</span>}
              </div>
            </div>
          </article>
        ))}
      </div>
      {pct === 100 && (
        <div role="status" style={{ marginTop:16, padding:16, border:"1px solid #8cc7a1", background:"#f0fff4", borderRadius:12 }}>
          Entrenamiento básico completado. Puedes repetirlo en cualquier momento desde “Cómo usar mi usuario”.
        </div>
      )}
    </section>
  );
}
