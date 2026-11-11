import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { permisosPorSolicitud } from "@/lib/permisos";
import { PageHeader, Vacio } from "@/components/ui/misc";
import { ListaControl } from "./lista";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Control de ingreso" };

export default async function ControlIngreso() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const { data } = await sb.from("vista_solicitudes_resumen").select("*").eq("situacion", "APROBADA").order("fecha_hora_inicio").limit(200);
  const todas = (data ?? []) as SolicitudResumen[];
  const permisos = await permisosPorSolicitud(sb, todas);
  const mias = todas.filter((x) => permisos.get(x.id)?.puede_control_ingreso);
  const ids = mias.map((m) => m.id);
  const emps = ids.length ? ((await sb.from("vista_solicitud_empleados_detalle").select("*").in("solicitud_id", ids).eq("estado_registro", "ACTIVO").eq("estado_aprobacion", "APROBADO")).data ?? []) as EmpleadoDetalle[] : [];
  return (
    <>
      <PageHeader titulo="Control de ingreso" subtitulo="Solicitudes aprobadas dentro de tu alcance de visibilidad. Registrá el resultado de cada empleado y finalizá." />
      {mias.length === 0 ? <Vacio titulo="No hay solicitudes aprobadas para controlar" detalle="Aparecen cuando una solicitud queda aprobada." />
        : <ListaControl solicitudes={mias} empleados={emps} zona={s.zona} />}
    </>
  );
}
