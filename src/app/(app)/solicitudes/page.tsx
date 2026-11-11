import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { SolicitudesTabla } from "./solicitudes-tabla";
import type { SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Solicitudes" };

export default async function Solicitudes() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const { data } = await sb.from("vista_solicitudes_resumen").select("*").neq("situacion", "ELIMINADA").order("fecha_hora_solicitud", { ascending: false }).limit(2000);
  const puedeCrear = s.flags.esAdmin || (!!s.permisos && s.permisos.modificacion_nivel !== "NADA");
  return (
    <>
      <PageHeader titulo="Solicitudes" subtitulo="Todas las solicitudes dentro de tu alcance de visibilidad." acciones={puedeCrear ? <Link href="/solicitudes/nueva" className="btn btn-primary">+ Nueva solicitud</Link> : undefined} />
      <SolicitudesTabla filas={(data ?? []) as SolicitudResumen[]} zona={s.zona} verImportes={s.flags.puedeVerImportes} exportar={s.flags.puedeExportar} />
    </>
  );
}
