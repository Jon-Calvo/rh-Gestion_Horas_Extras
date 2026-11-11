"use client";
import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";

/** Llama a una RPC de Supabase, muestra el resultado y refresca la pantalla. La lógica de negocio vive en la base. */
export function useRpc() {
  const router = useRouter();
  const toast = useToast();
  const [ocupado, setOcupado] = useState<string | null>(null);

  const rpc = useCallback(async <T = unknown>(nombre: string, args: Record<string, unknown>, ok?: string, opts?: { refrescar?: boolean }): Promise<{ ok: boolean; data?: T }> => {
    setOcupado(nombre);
    try {
      const { data, error } = await createClient().rpc(nombre, args);
      if (error) { toast("error", mensajeError(error)); return { ok: false }; }
      if (ok) toast("ok", ok);
      if (opts?.refrescar !== false) router.refresh();
      return { ok: true, data: data as T };
    } catch (e) {
      toast("error", mensajeError(e));
      return { ok: false };
    } finally { setOcupado(null); }
  }, [router, toast]);

  return { rpc, ocupado, router, toast };
}
