import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { permisosPorSolicitud } from "@/lib/permisos";
import type { SolicitudResumen } from "@/lib/types";

// Contadores del menú. Mismo criterio que las pantallas Aprobaciones y Control de ingreso
// (solicitudes dentro del alcance del usuario, según fn_permisos_para_scope); la base filtra por RLS.
export const dynamic = "force-dynamic";

export async function GET() {
  const sb = await createClient();
  const { data: u } = await sb.auth.getUser();
  if (!u.user) return NextResponse.json({ error: "No autenticado" }, { status: 401 });
  const contar = async (situacion: string, clave: "puede_aprobar" | "puede_control_ingreso") => {
    const { data } = await sb.from("vista_solicitudes_resumen").select("id, area_id, sector_id, proceso_id").eq("situacion", situacion).limit(200);
    const filas = (data ?? []) as unknown as SolicitudResumen[];
    if (filas.length === 0) return 0;
    const p = await permisosPorSolicitud(sb, filas);
    return filas.filter((f) => p.get(f.id)?.[clave]).length;
  };
  const [aprobaciones, control] = await Promise.all([contar("EN_APROBACION", "puede_aprobar"), contar("APROBADA", "puede_control_ingreso")]);
  return NextResponse.json({ aprobaciones, control });
}
