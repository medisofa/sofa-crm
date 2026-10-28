import { requireUser } from "@/lib/auth/context";

export default async function ClaimsPage() {
  const { supabase } = await requireUser();
  const { data, error } = await supabase
    .from("claims_v1")
    .select("id,folio,service_date,patient_name,amount,status,organization_id")
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw error;

  return (
    <main style={{ maxWidth: 1100, margin: "0 auto", padding: 32 }}>
      <h1>Reclamaciones</h1>
      <p>La consulta está filtrada por RLS en PostgreSQL.</p>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead><tr><th>Folio</th><th>Fecha</th><th>Paciente</th><th>Monto</th><th>Estado</th></tr></thead>
        <tbody>{(data ?? []).map(r => (
          <tr key={r.id}>
            <td>{r.folio}</td><td>{r.service_date}</td><td>{r.patient_name}</td>
            <td>RD$ {Number(r.amount).toLocaleString("es-DO", { minimumFractionDigits: 2 })}</td>
            <td>{r.status}</td>
          </tr>
        ))}</tbody>
      </table>
    </main>
  );
}
