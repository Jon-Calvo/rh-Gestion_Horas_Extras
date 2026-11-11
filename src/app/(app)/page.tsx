import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { fmtFechaHora, fmtHoras } from "@/lib/format";
import { PageHeader, SituacionBadge, Stat, Vacio } from "@/components/ui/misc";
import type { Situacion, SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Panel" };

export default async function Panel() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const cuenta = async (sit: Situacion) => (await sb.from("vista_solicitudes_resumen").select("id", { count: "exact", head: true }).eq("situacion", sit)).count ?? 0;
  const [bor, apr, ok, fin, recientes] = await Promise.all([
    cuenta("BORRADOR"), cuenta("EN_APROBACION"), cuenta("APROBADA"), cuenta("FINALIZADA"),
    sb.from("vista_solicitudes_resumen").select("*").order("fecha_hora_solicitud", { ascending: false }).limit(8),
  ]);
  const filas = (recientes.data ?? []) as SolicitudResumen[];
  const aprobables = s.flags.esAdmin || (s.permisos && s.permisos.aprobacion_nivel !== "NADA");

  return (
    <>
      <PageHeader titulo={`Hola, ${s.nombre.split(" ")[0]}`} subtitulo="Resumen de las solicitudes que podés ver." acciones={
        (s.flags.esAdmin || (s.permisos && s.permisos.modificacion_nivel !== "NADA")) ? <Link href="/solicitudes/nueva" className="btn btn-primary">+ Nueva solicitud</Link> : undefined} />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <Stat etiqueta="Borradores" valor={bor} tono="gris" detalle="Sin enviar" />
        <Stat etiqueta="En aprobación" valor={apr} tono="ambar" detalle={aprobables ? "Esperan una decisión" : "Esperan aprobación"} />
        <Stat etiqueta="Aprobadas" valor={ok} tono="azul" detalle="Pendientes de control de ingreso" />
        <Stat etiqueta="Finalizadas" valor={fin} tono="verde" detalle="Con control resuelto" />
      </div>

      {(aprobables && apr > 0) || (s.flags.puedeControlIngreso && ok > 0) ? (
        <div className="grid sm:grid-cols-2 gap-3 mb-6">
          {aprobables && apr > 0 && <Link href="/aprobaciones" className="card p-4 flex items-center justify-between hover:border-primary transition"><div><div className="font-semibold">Aprobaciones pendientes</div><div className="text-sm text-muted">{apr} solicitud(es) para revisar</div></div><span className="text-primary font-semibold">Revisar →</span></Link>}
          {s.flags.puedeControlIngreso && ok > 0 && <Link href="/control-ingreso" className="card p-4 flex items-center justify-between hover:border-primary transition"><div><div className="font-semibold">Control de ingreso</div><div className="text-sm text-muted">{ok} solicitud(es) aprobadas</div></div><span className="text-primary font-semibold">Registrar →</span></Link>}
        </div>
      ) : null}

      <div className="flex items-center justify-between mb-3"><h2 className="font-semibold">Últimas solicitudes</h2><Link href="/solicitudes" className="text-sm text-primary font-medium">Ver todas</Link></div>
      {filas.length === 0 ? <Vacio titulo="Todavía no hay solicitudes" detalle="Cuando se creen, vas a verlas acá." /> : (
        <div className="card overflow-hidden"><div className="overflow-x-auto">
          <table className="tbl"><thead><tr><th>N.º</th><th>Estado</th><th>Área / sector</th><th>Inicio</th><th className="text-right">Empleados</th><th className="text-right">Horas</th></tr></thead>
            <tbody>{filas.map((r) => (
              <tr key={r.id}>
                <td><Link className="font-semibold text-primary" href={`/solicitudes/${r.id}`}>{r.numero ?? "—"}</Link></td>
                <td><SituacionBadge situacion={r.situacion} /></td>
                <td>{r.area_nombre}<div className="text-xs text-muted">{r.sector_nombre} · {r.proceso_nombre}</div></td>
                <td>{fmtFechaHora(r.fecha_hora_inicio, s.zona)}</td>
                <td className="text-right">{r.cantidad_empleados}</td><td className="text-right">{fmtHoras(r.total_horas_solicitud)}</td>
              </tr>))}</tbody></table>
        </div></div>
      )}
    </>
  );
}
