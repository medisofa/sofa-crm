import Link from "next/link";
import { requireUser } from "@/lib/auth/context";

export default async function Home() {
  const { memberships } = await requireUser();
  return (
    <main style={{ maxWidth: 960, margin: "0 auto", padding: 32 }}>
      <p style={{ color:"#8B0000", fontWeight:700, marginBottom:4 }}>SOFA · Soluciones de Facturación Médica</p>
      <h1 style={{ marginTop:0 }}>Panel MVP</h1>
      <p>Captura, seguimiento y cierre de reclamaciones por organización.</p>
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom:24 }}>
        <Link href="/capture">Capturar reclamación</Link>
        <Link href="/claims">Ver reclamaciones</Link>
        <Link href="/mi-usuario">Cómo usar mi usuario</Link>
      </div>
      <section style={{ background:"#fff", border:"1px solid #dfe4ea", borderRadius:12, padding:18 }}>
        <h2>Autoentrenamiento</h2>
        <p>¿Es tu primera vez o quieres repasar tu flujo? SOFA adapta la guía al rol de tu sesión.</p>
        <Link href="/mi-usuario">Iniciar entrenamiento →</Link>
      </section>
      <h2>Organizaciones visibles</h2>
      <ul>{memberships.map(m => <li key={m.organization_id}>{m.organization_name} · {m.role_code}</li>)}</ul>
    </main>
  );
}
