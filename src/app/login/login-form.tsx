"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { ThemeToggle } from "@/components/layout/app-shell";
import { COOKIE_SESION, atributosCookieSesion, valorCookieSesion } from "@/lib/sesion";

export function LoginForm({ aviso }: { aviso?: string }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [pass, setPass] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null); setCargando(true);
    const { error } = await createClient().auth.signInWithPassword({ email: email.trim(), password: pass });
    if (error) { setError(error.message === "Invalid login credentials" ? "Email o contraseña incorrectos." : error.message); setCargando(false); return; }
    // Duración de la sesión (config. general). Si todavía no está la migración 0006, queda el valor por defecto: cierra al cerrar el navegador.
    const sb = createClient();
    const { data: cfg } = await sb.from("configuracion_general").select("sesion_horas_maximas, sesion_cerrar_al_cerrar_navegador").eq("id", 1).maybeSingle();
    const horas = cfg ? (cfg.sesion_horas_maximas as number | null) : 12;
    const cerrar = cfg ? cfg.sesion_cerrar_al_cerrar_navegador !== false : true;
    document.cookie = `${COOKIE_SESION}=${valorCookieSesion(horas, cerrar)}; Path=/; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}${atributosCookieSesion(horas, cerrar)}`;
    router.replace("/"); router.refresh();
  };

  return (
    <div className="w-full max-w-sm">
      <div className="flex justify-end mb-6"><ThemeToggle /></div>
      <h1 className="text-2xl font-bold tracking-tight">Ingresar</h1>
      <p className="text-sm text-muted mt-1 mb-6">Usá tu email y contraseña.</p>
      <form onSubmit={enviar} className="space-y-4" noValidate>
        <div><label className="label" htmlFor="email">Email</label><input id="email" className="input" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></div>
        <div><label className="label" htmlFor="pass">Contraseña</label><input id="pass" className="input" type="password" autoComplete="current-password" required value={pass} onChange={(e) => setPass(e.target.value)} /></div>
        {aviso && !error && <div role="status" className="text-sm rounded-lg px-3 py-2 bg-[var(--surface-2,transparent)] border">{aviso}</div>}
        {error && <div role="alert" className="text-sm rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}>{error}</div>}
        <button className="btn btn-primary w-full" disabled={cargando || !email || !pass}>{cargando ? <span className="spinner" /> : "Ingresar"}</button>
      </form>
      <p className="text-xs text-muted mt-6">¿Olvidaste tu contraseña? Pedile a un administrador que la restablezca.</p>
    </div>
  );
}
