import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { permisosPorSolicitud } from "@/lib/permisos";
import { PageHeader, Vacio } from "@/components/ui/misc";
import { ListaAprobaciones } from "./lista";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Aprobaciones" };

export default async function Aprobaciones() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const { data } = await sb.from("vista_solicitudes_resumen").select("*").eq("situacion", "EN_APROBACION").order("fecha_hora_inicio").limit(200);
  const todas = (data ?? []) as SolicitudResumen[];
  const permisos = await permisosPorSolicitud(sb, todas);
  const mias = todas.filter((x) => permisos.get(x.id)?.puede_aprobar);
  const ids = mias.map((m) => m.id);
  const emps = ids.length ? ((await sb.from("vista_solicitud_empleados_detalle").select("*").in("solicitud_id", ids).eq("estado_registro", "ACTIVO")).data ?? []) as EmpleadoDetalle[] : [];
  return (
    <>
      <PageHeader titulo="Aprobaciones" subtitulo="Solicitudes en aprobación dentro de tu alcance de aprobación." />
      {mias.length === 0 ? <Vacio titulo="No tenés solicitudes para aprobar" detalle="Cuando alguien envíe una solicitud dentro de tu alcance, aparece acá." />
        : <ListaAprobaciones solicitudes={mias} empleados={emps} zona={s.zona} verImportes={s.flags.puedeVerImportes} />}
    </>
  );
}
