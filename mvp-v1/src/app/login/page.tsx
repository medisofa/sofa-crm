"use client";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/browser";

export default function LoginPage() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true); setError("");
    const fd = new FormData(e.currentTarget);
    const email = String(fd.get("email") || "").trim();
    const password = String(fd.get("password") || "");
    const { error } = await supabaseBrowser().auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) { setError("No se pudo iniciar sesión."); return; }
    router.replace("/");
    router.refresh();
  }

  return (
    <main style={{ maxWidth: 420, margin: "10vh auto", padding: 24 }}>
      <h1>SOFA</h1>
      <p>Acceso seguro</p>
      <form onSubmit={submit}>
        <label>Correo<input name="email" type="email" autoComplete="username" required style={{ display:"block",width:"100%",marginBottom:12 }} /></label>
        <label>Contraseña<input name="password" type="password" autoComplete="current-password" required style={{ display:"block",width:"100%",marginBottom:12 }} /></label>
        <button disabled={busy} type="submit">{busy ? "Entrando…" : "Entrar"}</button>
        {error && <p role="alert">{error}</p>}
      </form>
    </main>
  );
}
