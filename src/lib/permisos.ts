import type { SupabaseClient } from "@supabase/supabase-js";
import type { PermisosScope, SolicitudResumen } from "@/lib/types";

/** Permisos efectivos (fn_permisos_para_scope) para cada solicitud, consultando una vez por alcance distinto. */
export async function permisosPorSolicitud(sb: SupabaseClient, filas: SolicitudResumen[]): Promise<Map<string, PermisosScope>> {
  const claves = new Map<string, { a: string; s: string; p: string }>();
  filas.forEach((f) => claves.set(`${f.area_id}|${f.sector_id}|${f.proceso_id}`, { a: f.area_id, s: f.sector_id, p: f.proceso_id }));
  const porClave = new Map<string, PermisosScope>();
  await Promise.all([...claves.entries()].map(async ([k, v]) => {
    const { data } = await sb.rpc("fn_permisos_para_scope", { p_area_id: v.a, p_sector_id: v.s, p_proceso_id: v.p });
    const r = (Array.isArray(data) ? data[0] : data) as PermisosScope | null;
    porClave.set(k, r ?? { puede_ver: true, puede_modificar: false, puede_aprobar: false, puede_reabrir: false, puede_control_ingreso: false });
  }));
  const out = new Map<string, PermisosScope>();
  filas.forEach((f) => out.set(f.id, porClave.get(`${f.area_id}|${f.sector_id}|${f.proceso_id}`)!));
  return out;
}
