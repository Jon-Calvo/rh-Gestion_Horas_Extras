"use client";
import Link from "next/link";
import { AsistenciaBadge } from "@/components/ui/misc";
import { useRpc } from "@/lib/use-accion";
import { fmtFechaHora, fmtHoras } from "@/lib/format";
import type { EmpleadoDetalle, EstadoAsistencia, SolicitudResumen } from "@/lib/types";

export function ListaControl({ solicitudes, empleados, zona }: { solicitudes: SolicitudResumen[]; empleados: EmpleadoDetalle[]; zona: string }) {
  const { rpc, ocupado } = useRpc();
  const reg = (e: EmpleadoDetalle, r: EstadoAsistencia) => rpc("rpc_registrar_control_ingreso", { p_solicitud_empleado_id: e.solicitud_empleado_id, p_resultado: r }, "Control registrado");
  return (
    <div className="space-y-4">
      {solicitudes.map((s) => {
        const es = empleados.filter((e) => e.solicitud_id === s.id);
        const pend = es.filter((e) => e.estado_asistencia === "PENDIENTE_INGRESO").length;
        return (
          <section key={s.id} className="card overflow-hidden">
            <header className="flex flex-wrap items-center gap-3 p-4 border-b">
              <div className="min-w-0 flex-1">
                <Link href={`/solicitudes/${s.id}`} className="font-semibold text-primary">Solicitud {s.numero}</Link>
                <div className="text-sm text-muted">{s.area_nombre} · {s.sector_nombre} · {s.proceso_nombre}</div>
                <div className="text-xs text-muted">{fmtFechaHora(s.fecha_hora_inicio, zona)} → {fmtFechaHora(s.fecha_hora_fin, zona)}</div>
              </div>
              <span className="text-sm text-muted">{pend} sin resolver</span>
              <button className="btn btn-primary btn-sm" disabled={!!ocupado || pend > 0} title={pend > 0 ? "Resolvé el ingreso de todos los empleados" : undefined} onClick={() => rpc("rpc_finalizar_solicitud", { p_solicitud_id: s.id }, "Solicitud finalizada")}>Finalizar</button>
            </header>
            <div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Empleado</th><th>Ingreso</th><th className="text-right">Horas</th><th /></tr></thead>
              <tbody>{es.map((e) => (
                <tr key={e.solicitud_empleado_id}>
                  <td>{e.nombre_completo}<div className="text-xs text-muted">{e.legajo}</div></td>
                  <td><AsistenciaBadge estado={e.estado_asistencia} />{e.fecha_hora_ingreso && <div className="text-xs text-muted">{fmtFechaHora(e.fecha_hora_ingreso, zona)}</div>}</td>
                  <td className="text-right">{fmtHoras(e.total_horas)}</td>
                  <td><div className="flex flex-wrap gap-1.5 justify-end">
                    {e.estado_asistencia === "PENDIENTE_INGRESO" ? <>
                      <button className="btn btn-success btn-sm" disabled={!!ocupado} onClick={() => reg(e, "INGRESO_REGISTRADO")}>Ingresó</button>
                      <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => reg(e, "YA_ESTABA_EN_PLANTA")}>Ya estaba</button>
                      <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => reg(e, "NO_PRESENTADO")}>No se presentó</button></>
                      : <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => rpc("rpc_quitar_control_ingreso", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Control quitado")}>Quitar control</button>}
                  </div></td>
                </tr>))}</tbody></table></div>
          </section>
        );
      })}
    </div>
  );
}
