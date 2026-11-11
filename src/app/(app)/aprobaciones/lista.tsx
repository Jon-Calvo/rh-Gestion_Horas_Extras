"use client";
import Link from "next/link";
import { useState } from "react";
import { AprobacionBadge } from "@/components/ui/misc";
import { PromptModal } from "@/components/ui/prompt-modal";
import { useRpc } from "@/lib/use-accion";
import { fmtFechaHora, fmtHoras, fmtImporte } from "@/lib/format";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

export function ListaAprobaciones({ solicitudes, empleados, zona, verImportes }: { solicitudes: SolicitudResumen[]; empleados: EmpleadoDetalle[]; zona: string; verImportes: boolean }) {
  const { rpc, ocupado } = useRpc();
  const [rech, setRech] = useState<{ tipo: "uno" | "todos"; id: string } | null>(null);
  return (
    <div className="space-y-4">
      {solicitudes.map((s) => {
        const es = empleados.filter((e) => e.solicitud_id === s.id);
        const pend = es.filter((e) => e.estado_aprobacion === "PENDIENTE_APROBACION");
        return (
          <section key={s.id} className="card overflow-hidden">
            <header className="flex flex-wrap items-center gap-3 p-4 border-b">
              <div className="min-w-0 flex-1">
                <Link href={`/solicitudes/${s.id}`} className="font-semibold text-primary">Solicitud {s.numero}</Link>
                <div className="text-sm text-muted">{s.area_nombre} · {s.sector_nombre} · {s.proceso_nombre} · {s.motivo_nombre}</div>
                <div className="text-xs text-muted">{fmtFechaHora(s.fecha_hora_inicio, zona)} → {fmtFechaHora(s.fecha_hora_fin, zona)} · {s.solicitante_nombre}</div>
              </div>
              <div className="flex gap-2">
                <button className="btn btn-success btn-sm" disabled={!!ocupado || pend.length === 0} onClick={() => rpc("rpc_aprobar_masivo", { p_solicitud_id: s.id }, "Pendientes aprobados")}>Aprobar {pend.length || ""} pendiente(s)</button>
                <button className="btn btn-secondary btn-sm" disabled={!!ocupado || pend.length === 0} onClick={() => setRech({ tipo: "todos", id: s.id })}>Rechazar pendientes</button>
              </div>
            </header>
            <div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Empleado</th><th>Estado</th><th className="text-right">Horas</th>{verImportes && <th className="text-right">Importe</th>}<th /></tr></thead>
              <tbody>{es.map((e) => (
                <tr key={e.solicitud_empleado_id}>
                  <td>{e.nombre_completo}<div className="text-xs text-muted">{e.legajo}</div></td>
                  <td><AprobacionBadge estado={e.estado_aprobacion} /></td>
                  <td className="text-right">{fmtHoras(e.total_horas)}</td>{verImportes && <td className="text-right">{fmtImporte(e.total_importe, s.moneda)}</td>}
                  <td className="text-right"><div className="flex gap-1.5 justify-end">
                    {e.estado_aprobacion !== "APROBADO" && <button className="btn btn-success btn-sm" disabled={!!ocupado} onClick={() => rpc("rpc_aprobar_empleado", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Empleado aprobado")}>Aprobar</button>}
                    {e.estado_aprobacion !== "RECHAZADO" && <button className="btn btn-secondary btn-sm" onClick={() => setRech({ tipo: "uno", id: e.solicitud_empleado_id })}>Rechazar</button>}
                  </div></td>
                </tr>))}</tbody></table></div>
          </section>
        );
      })}
      <PromptModal abierto={!!rech} titulo="Rechazar" etiqueta="Motivo del rechazo (obligatorio)" confirmar="Rechazar" peligro ocupado={!!ocupado} onCerrar={() => setRech(null)}
        onConfirmar={async (t) => { if (!rech) return; const r = rech.tipo === "uno" ? await rpc("rpc_rechazar_empleado", { p_solicitud_empleado_id: rech.id, p_motivo: t }, "Rechazado") : await rpc("rpc_rechazar_masivo", { p_solicitud_id: rech.id, p_motivo: t }, "Pendientes rechazados"); if (r.ok) setRech(null); }} />
    </div>
  );
}
