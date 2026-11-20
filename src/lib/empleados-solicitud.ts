import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAll } from "@/lib/supabase/fetch-all";
import type { EmpleadoDetalle } from "@/lib/types";
import type { EmpKpi } from "@/lib/kpis";

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

/** Versión liviana para estadísticas: solo las columnas necesarias, empleados activos. Lanza error si falta la migración 0005 (tipo_pago). */
export async function empleadosParaKpi(sb: SupabaseClient, ids: string[]): Promise<EmpKpi[]> {
  const salida: EmpKpi[] = [];
  for (let i = 0; i < ids.length; i += 50) {
    const lote = ids.slice(i, i + 50);
    salida.push(...(await fetchAll<EmpKpi>((d, h) => sb.from("vista_solicitud_empleados_detalle")
      .select("solicitud_empleado_id, solicitud_id, empleado_id, legajo, nombre_completo, estado_aprobacion, estado_registro, total_horas, total_importe, tipo_pago")
      .in("solicitud_id", lote).eq("estado_registro", "ACTIVO").order("solicitud_empleado_id").range(d, h), 100000)));
  }
  return salida;
}
