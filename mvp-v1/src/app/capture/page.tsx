import { requireUser } from "@/lib/auth/context";
import CaptureForm from "./CaptureForm";

export default async function CapturePage() {
  const { memberships } = await requireUser();
  const organizations = memberships
    .filter(m => m.kind === "client")
    .map(m => ({ organization_id:m.organization_id, organization_name:m.organization_name }));
  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 32 }}>
      <h1>Captura rápida</h1>
      <p>La tarifa se obtiene del contrato vigente; el servidor vuelve a validarla antes de guardar.</p>
      {organizations.length ? <CaptureForm organizations={organizations} /> : <p>No hay consultorios disponibles para esta cuenta.</p>}
    </main>
  );
}
