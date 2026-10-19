import type { ReactNode } from "react";

export const metadata = {
  title: "SOFA · Soluciones de Facturación Médica",
  description: "Gestión segura de reclamaciones médicas"
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="es">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#f7f8fb", color: "#17202e" }}>
        {children}
      </body>
    </html>
  );
}
