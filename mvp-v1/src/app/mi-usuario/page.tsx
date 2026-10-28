import Link from "next/link";
import { requireUser } from "@/lib/auth/context";
import { trainingForRole } from "@/lib/training/roles";
import UserTrainingClient from "./UserTrainingClient";

export default async function MyUserPage() {
  const { user, memberships } = await requireUser();
  const primary = memberships[0];
  const role = primary?.role_code ?? "client";
  const training = trainingForRole(role);

  return (
    <main style={{ maxWidth: 980, margin: "0 auto", padding: 32 }}>
      <div style={{ display:"flex", justifyContent:"space-between", gap:16, alignItems:"center", flexWrap:"wrap" }}>
        <div>
          <p style={{ margin:0, color:"#8B0000", fontWeight:700 }}>SOFA · Autoentrenamiento</p>
          <h1 style={{ marginTop:6 }}>Cómo usar mi usuario</h1>
          <p>Sesión: <strong>{user.email}</strong> · Rol principal: <strong>{training.label}</strong></p>
        </div>
        <Link href="/">Ir al sistema</Link>
      </div>

      <section style={{ background:"#fff", border:"1px solid #dfe4ea", borderRadius:14, padding:22, margin:"20px 0" }}>
        <h2>Tu misión</h2>
        <p>{training.mission}</p>
      </section>

      <UserTrainingClient
        userId={user.id}
        role={role}
        label={training.label}
        steps={training.firstActions}
      />

      <section style={{ display:"grid", gridTemplateColumns:"repeat(auto-fit,minmax(260px,1fr))", gap:16, marginTop:22 }}>
        <article style={{ background:"#fff", border:"1px solid #dfe4ea", borderRadius:14, padding:20 }}>
          <h2>Reglas de seguridad</h2>
          <ul>{training.guardrails.map(x => <li key={x}>{x}</li>)}</ul>
        </article>
        <article style={{ background:"#fff", border:"1px solid #dfe4ea", borderRadius:14, padding:20 }}>
          <h2>Qué significa hacerlo bien</h2>
          <ul>{training.success.map(x => <li key={x}>{x}</li>)}</ul>
        </article>
      </section>

      <section style={{ background:"#1A365D", color:"#fff", borderRadius:14, padding:22, marginTop:22 }}>
        <h2>Ruta del MVP</h2>
        <p>Captura → Recepción → Validación → Radicación → Glosa/Pago → Cierre.</p>
        <p style={{ marginBottom:0 }}>Si una pantalla o dato no corresponde a tu trabajo, no intentes forzar el acceso: SOFA aplica permisos por rol y organización.</p>
      </section>
    </main>
  );
}
