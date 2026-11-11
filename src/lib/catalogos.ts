import { createClient } from "@/lib/supabase/server";
import type { Area, Sector, Proceso, Motivo } from "@/lib/types";

export interface Catalogos { areas: Area[]; sectores: Sector[]; procesos: Proceso[]; motivos: Motivo[] }

export async function getCatalogos(): Promise<Catalogos> {
  const sb = await createClient();
  const [a, s, p, m] = await Promise.all([
    sb.from("areas").select("*").order("nombre"),
    sb.from("sectores").select("*").order("nombre"),
    sb.from("procesos").select("*").order("nombre"),
    sb.from("motivos").select("*").order("motivo"),
  ]);
  return { areas: (a.data ?? []) as Area[], sectores: (s.data ?? []) as Sector[], procesos: (p.data ?? []) as Proceso[], motivos: (m.data ?? []) as Motivo[] };
}
