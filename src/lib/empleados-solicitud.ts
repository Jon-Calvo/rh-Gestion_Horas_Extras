import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAll } from "@/lib/supabase/fetch-all";
import type { EmpleadoDetalle } from "@/lib/types";

/** Empleados (ACTIVO) de varias solicitudes, sin chocar con el tope de 1000 filas por consulta. */
export async function empleadosDeSolicitudes(sb: SupabaseClient, ids: string[], soloAprobados = false): Promise<EmpleadoDetalle[]> {
  const salida: EmpleadoDetalle[] = [];
  for (let i = 0; i < ids.length; i += 50) {
    const lote = ids.slice(i, i + 50);
    salida.push(...(await fetchAll<EmpleadoDetalle>((d, h) => {
      let q = sb.from("vista_solicitud_empleados_detalle").select("*").in("solicitud_id", lote).eq("estado_registro", "ACTIVO");
      if (soloAprobados) q = q.eq("estado_aprobacion", "APROBADO");
      return q.order("solicitud_empleado_id").range(d, h);
    })));
  }
  return salida;
}
