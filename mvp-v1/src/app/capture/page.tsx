import { requireUser } from "@/lib/auth/context";

export default async function CapturePage() {
  const { memberships } = await requireUser();
  const clients = memberships.filter(m => m.kind === "client");
  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: 32 }}>
      <h1>Captura rápida</h1>
      <p>Esta pantalla mínima se conecta al endpoint <code>/api/v1/claims</code>. La selección final de médico, ARS, procedimiento y tarifa debe cargarse desde catálogos autorizados por organización.</p>
      <p>Organizaciones habilitadas: {clients.length}</p>
      <p>La versión funcional completa requiere el componente de formulario y catálogos descritos en la arquitectura.</p>
    </main>
  );
}
