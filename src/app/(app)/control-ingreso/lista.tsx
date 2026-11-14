"use client";
import Link from "next/link";
import { useMemo, useState } from "react";
import { AsistenciaBadge } from "@/components/ui/misc";
import { IngresoModal, type RegistroIngreso } from "@/components/solicitudes/ingreso-modal";
import { ObservacionBtn, ResumenEstados } from "@/components/solicitudes/observacion-btn";
import { useRpc } from "@/lib/use-accion";
import { fmtFechaHora, fmtHoras, isoToLocal } from "@/lib/format";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

export function ListaControl({ solicitudes, empleados, zona }: { solicitudes: SolicitudResumen[]; empleados: EmpleadoDetalle[]; zona: string }) {
  const { rpc, ocupado } = useRpc();
  const [reg, setReg] = useState<RegistroIngreso | null>(null);
  const [f, setF] = useState({ desde: "", hasta: "", nombre: "", sector: "", proceso: "", solo: "" });

  const sectores = useMemo(() => [...new Set(solicitudes.map((s) => s.sector_nombre))].sort((a, b) => a.localeCompare(b, "es")), [solicitudes]);
  const procesos = useMemo(() => [...new Set(solicitudes.filter((s) => !f.sector || s.sector_nombre === f.sector).map((s) => s.proceso_nombre))].sort((a, b) => a.localeCompare(b, "es")), [solicitudes, f.sector]);

  const visibles = useMemo(() => {
    const q = f.nombre.trim().toLowerCase();
    return solicitudes.map((s) => {
      const dia = isoToLocal(s.fecha_hora_inicio, zona).slice(0, 10);
      if (f.desde && dia < f.desde) return null;
      if (f.hasta && dia > f.hasta) return null;
      if (f.sector && s.sector_nombre !== f.sector) return null;
      if (f.proceso && s.proceso_nombre !== f.proceso) return null;
      let es = empleados.filter((e) => e.solicitud_id === s.id);
      if (q) es = es.filter((e) => e.nombre_completo.toLowerCase().includes(q) || e.legajo.toLowerCase().includes(q));
      if (f.solo === "pendientes") es = es.filter((e) => e.estado_asistencia === "PENDIENTE_INGRESO");
      if ((q || f.solo) && es.length === 0) return null;
      return { s, es };
    }).filter((x): x is { s: SolicitudResumen; es: EmpleadoDetalle[] } => x !== null);
  }, [solicitudes, empleados, f, zona]);

  const hayFiltros = Object.values(f).some(Boolean);
  const confirmar = async (r: RegistroIngreso, iso: string, obs: string) => {
    const res = await rpc("rpc_registrar_control_ingreso", { p_solicitud_empleado_id: r.se, p_resultado: r.resultado, p_fecha_hora: iso, p_observacion: obs || null }, "Control registrado");
    if (res.ok) setReg(null);
  };
  const abrir = (e: EmpleadoDetalle, resultado: RegistroIngreso["resultado"]) => setReg({ se: e.solicitud_empleado_id, nombre: e.nombre_completo, resultado });

  return (
    <div className="space-y-4">
      <div className="card p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-6 items-end">
        <label className="block"><span className="label">Desde</span><input className="input" type="date" value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></label>
        <label className="block"><span className="label">Hasta</span><input className="input" type="date" value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></label>
        <label className="block lg:col-span-2"><span className="label">Empleado (nombre o legajo)</span><input className="input" type="search" placeholder="Buscar…" value={f.nombre} onChange={(e) => setF({ ...f, nombre: e.target.value })} /></label>
        <label className="block"><span className="label">Sector</span><select className="input" value={f.sector} onChange={(e) => setF({ ...f, sector: e.target.value, proceso: "" })}><option value="">Todos</option>{sectores.map((x) => <option key={x}>{x}</option>)}</select></label>
        <label className="block"><span className="label">Proceso</span><select className="input" value={f.proceso} onChange={(e) => setF({ ...f, proceso: e.target.value })}><option value="">Todos</option>{procesos.map((x) => <option key={x}>{x}</option>)}</select></label>
        <label className="block"><span className="label">Mostrar</span><select className="input" value={f.solo} onChange={(e) => setF({ ...f, solo: e.target.value })}><option value="">Todos los empleados</option><option value="pendientes">Solo pendientes de ingreso</option></select></label>
        <div className="sm:col-span-2 lg:col-span-5 text-xs text-muted">La fecha filtra por el día de inicio de la extra. {visibles.length} de {solicitudes.length} solicitud(es).</div>
        <div className="lg:col-span-1 flex lg:justify-end"><button className="btn btn-ghost btn-sm" disabled={!hayFiltros} onClick={() => setF({ desde: "", hasta: "", nombre: "", sector: "", proceso: "", solo: "" })}>Limpiar filtros</button></div>
      </div>

      {visibles.length === 0 && <div className="card p-8 text-center text-muted">Ninguna solicitud coincide con los filtros.</div>}
      {visibles.map(({ s, es }) => {
        const pend = empleados.filter((e) => e.solicitud_id === s.id && e.estado_asistencia === "PENDIENTE_INGRESO").length;
        return (
          <section key={s.id} className="card overflow-hidden">
            <header className="flex flex-wrap items-center gap-3 p-4 border-b">
              <div className="min-w-0 flex-1">
                <Link href={`/solicitudes/${s.id}`} className="font-semibold text-primary">Solicitud {s.numero}</Link>
                <div className="text-sm text-muted">{s.area_nombre} · {s.sector_nombre} · {s.proceso_nombre}</div>
                <div className="text-xs text-muted">{fmtFechaHora(s.fecha_hora_inicio, zona)} → {fmtFechaHora(s.fecha_hora_fin, zona)}</div>
                <div className="text-xs text-muted"><ResumenEstados s={s} /></div>
              </div>
              <ObservacionBtn texto={s.observacion} titulo={`Observación · Solicitud ${s.numero}`} />
              <span className="text-sm text-muted">{pend} sin resolver</span>
              <button className="btn btn-primary btn-sm" disabled={!!ocupado || pend > 0} title={pend > 0 ? "Resolvé el ingreso de todos los empleados" : undefined} onClick={() => rpc("rpc_finalizar_solicitud", { p_solicitud_id: s.id }, "Solicitud finalizada")}>Finalizar</button>
            </header>
            <div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Empleado</th><th>Ingreso</th><th className="text-right">Horas</th><th /></tr></thead>
              <tbody>{es.map((e) => (
                <tr key={e.solicitud_empleado_id}>
                  <td>{e.nombre_completo}<div className="text-xs text-muted">{e.legajo}</div></td>
                  <td><AsistenciaBadge estado={e.estado_asistencia} />{e.fecha_hora_ingreso && <div className="text-xs text-muted">{fmtFechaHora(e.fecha_hora_ingreso, zona)}</div>}
                    {e.observacion_control_ingreso && <div className="text-xs mt-0.5 max-w-xs whitespace-pre-wrap">💬 {e.observacion_control_ingreso}</div>}</td>
                  <td className="text-right">{fmtHoras(e.total_horas)}</td>
                  <td><div className="flex flex-wrap gap-1.5 justify-end">
                    {e.estado_asistencia === "PENDIENTE_INGRESO" ? <>
                      <button className="btn btn-success btn-sm" disabled={!!ocupado} onClick={() => abrir(e, "INGRESO_REGISTRADO")}>Ingresó</button>
                      <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => abrir(e, "YA_ESTABA_EN_PLANTA")}>Ya estaba</button>
                      <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => abrir(e, "NO_PRESENTADO")}>No se presentó</button></>
                      : ["INGRESO_REGISTRADO", "YA_ESTABA_EN_PLANTA", "NO_PRESENTADO"].includes(e.estado_asistencia) ? <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => rpc("rpc_quitar_control_ingreso", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Control quitado")}>Quitar control</button> : null}
                  </div></td>
                </tr>))}</tbody></table></div>
          </section>
        );
      })}
      <IngresoModal registro={reg} zona={zona} ocupado={!!ocupado} onCerrar={() => setReg(null)} onConfirmar={confirmar} />
    </div>
  );
}
