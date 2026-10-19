import Link from "next/link";
import { requireUser } from "@/lib/auth/context";

export default async function Home() {
  const { memberships } = await requireUser();
  return (
    <main style={{ maxWidth: 960, margin: "0 auto", padding: 32 }}>
      <h1>SOFA</h1>
      <p>MVP operativo: captura, seguimiento y cierre de reclamaciones por organización.</p>
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
        <Link href="/capture">Capturar reclamación</Link>
        <Link href="/claims">Ver reclamaciones</Link>
      </div>
      <h2>Organizaciones visibles</h2>
      <ul>{memberships.map(m => <li key={m.organization_id}>{m.organization_name} · {m.role_code}</li>)}</ul>
    </main>
  );
}
