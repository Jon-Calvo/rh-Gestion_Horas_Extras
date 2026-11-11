import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { RankingVista } from "./vista";
import type { BandaRanking, EmpleadoResumen } from "@/lib/types";

export const metadata = { title: "Ranking" };

export interface Historico { id: string; empleado_id: string; ranking_horas_final: number; fecha_reseteo: string }
export interface Rectificacion { id: string; solicitud_empleado_id: string; solicitud_id: string; empleado_id: string; horas_descontadas: number; ranking_antes: number; ranking_despues: number; motivo: string; usuario_id: string; created_at: string }

export default async function Ranking() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const [emp, bandas] = await Promise.all([
    sb.from("vista_empleados_resumen").select("*").eq("estado", "ACTIVO").order("ranking_horas", { ascending: false }).limit(5000),
    sb.from("bandas_ranking").select("*").eq("activo", true).order("ranking_inferior"),
  ]);
  let historico: Historico[] = []; let rectificaciones: Rectificacion[] = []; let usuarios: Record<string, string> = {};
  if (s.flags.esAdmin) {
    const [h, r, u] = await Promise.all([
      sb.from("ranking_horas_historico").select("*").order("fecha_reseteo", { ascending: false }).limit(1000),
      sb.from("ranking_rectificaciones").select("*").order("created_at", { ascending: false }).limit(300),
      sb.from("usuarios").select("id, nombre_completo"),
    ]);
    historico = (h.data ?? []) as Historico[]; rectificaciones = (r.data ?? []) as Rectificacion[];
    usuarios = Object.fromEntries(((u.data ?? []) as { id: string; nombre_completo: string }[]).map((x) => [x.id, x.nombre_completo]));
  }
  const nombres = Object.fromEntries(((emp.data ?? []) as EmpleadoResumen[]).map((e) => [e.id, `${e.nombre_completo} (${e.legajo})`]));
  return (
    <>
      <PageHeader titulo="Ranking de horas" subtitulo={`Horas aprobadas acumuladas en el período (${s.config?.ranking_periodo?.toLowerCase() ?? "mensual"}).`} />
      <RankingVista empleados={(emp.data ?? []) as EmpleadoResumen[]} bandas={(bandas.data ?? []) as BandaRanking[]} historico={historico} rectificaciones={rectificaciones} nombres={nombres} usuarios={usuarios} esAdmin={s.flags.esAdmin} zona={s.zona} ultimoReseteo={s.config?.ultimo_reseteo_ranking ?? null} />
    </>
  );
}
