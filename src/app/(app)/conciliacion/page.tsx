import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { permisosPorSolicitud } from "@/lib/permisos";
import { PageHeader } from "@/components/ui/misc";
import { Conciliacion } from "./conciliacion";
import type { SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Conciliación de fichadas" };

export default async function Page() {
  const s = (await getSesion())!;
  if (!s.flags.puedeControlIngreso) redirect("/");
  const sb = await createClient();
  const [sol, imp] = await Promise.all([
    sb.from("vista_solicitudes_resumen").select("*").in("situacion", ["APROBADA", "FINALIZADA"]).order("fecha_hora_inicio", { ascending: false }).limit(300),
    sb.from("fichadas_importaciones").select("id, archivo, periodo_desde, periodo_hasta, created_at").order("created_at", { ascending: false }).limit(10),
  ]);
  const todas = (sol.data ?? []) as SolicitudResumen[];
  const permisos = await permisosPorSolicitud(sb, todas);
  const mias = todas.filter((x) => permisos.get(x.id)?.puede_control_ingreso);
  const preparada = s.config && "fichadas_redondeo_minutos" in s.config;
  return (
    <>
      <PageHeader titulo="Conciliación de fichadas" subtitulo="Compará el horario solicitado con las fichadas reales del reloj y confirmá el tiempo realmente trabajado. El horario de la solicitud no se modifica." />
      {!preparada && imp.error ? <div role="alert" className="card p-4 text-sm">Falta aplicar la migración 0005 en Supabase para usar esta pantalla.</div>
        : <Conciliacion solicitudes={mias} zona={s.zona} verImportes={s.flags.puedeVerImportes} esAdmin={s.flags.esAdmin} importaciones={(imp.data ?? []) as Imp[]} />}
    </>
  );
}
export interface Imp { id: string; archivo: string; periodo_desde: string; periodo_hasta: string; created_at: string }
