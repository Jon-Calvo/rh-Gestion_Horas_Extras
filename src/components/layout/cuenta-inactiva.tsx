"use client";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function CuentaInactiva({ nombre, sinPerfil }: { nombre: string; sinPerfil: boolean }) {
  const router = useRouter();
  const salir = async () => { await createClient().auth.signOut(); router.replace("/login"); router.refresh(); };
  return (
    <div className="min-h-dvh grid place-items-center p-6">
      <div className="card p-8 max-w-md text-center">
        <div className="text-4xl mb-3" aria-hidden>🔒</div>
        <h1 className="text-lg font-bold">Cuenta sin acceso</h1>
        <p className="text-sm text-muted mt-2">
          {sinPerfil ? "Tu usuario todavía no tiene un perfil habilitado en el sistema." : `Hola ${nombre}: tu cuenta está inactiva.`} Pedile a un administrador que la active.
        </p>
        <button className="btn btn-primary mt-6" onClick={salir}>Cerrar sesión</button>
      </div>
    </div>
  );
}
