"use client";
import Link from "next/link";
import { Fragment, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AprobacionBadge, AsistenciaBadge, Campo, PageHeader, SituacionBadge } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { PromptModal } from "@/components/ui/prompt-modal";
import { ScopeSelect, type Scope } from "@/components/ui/scope-select";
import { EmployeePicker } from "@/components/solicitudes/employee-picker";
import { IngresoModal, type RegistroIngreso } from "@/components/solicitudes/ingreso-modal";
import { IbRanking } from "@/components/solicitudes/ranking-chip";
import { useRpc } from "@/lib/use-accion";
import { fmtFechaHora, fmtHoras, fmtImporte, isoToLocal, localToIso } from "@/lib/format";
import type { Catalogos } from "@/lib/catalogos";
import type { AuditoriaNegocio, BandaRanking, DetalleCalculo, EmpleadoDetalle, EstadoAsistencia, PermisosScope, SolicitudResumen } from "@/lib/types";

type Dlg = null | "agregar" | "editar" | "cancelar" | "reabrir" | "rechazarTodos" | { tipo: "rechazar" | "reemplazar" | "rectificar"; se: EmpleadoDetalle };

export function Detalle({ sol, empleados, permisos, cat, bandas, detalle, bandasHorarias, auditoria, zona, verImportes, puedeEliminarCancelar, esAdmin, diasMax }: {
  sol: SolicitudResumen; empleados: EmpleadoDetalle[]; permisos: PermisosScope; cat: Catalogos; bandas: BandaRanking[];
  detalle: DetalleCalculo[]; bandasHorarias: Record<string, string>; auditoria: AuditoriaNegocio[]; zona: string; verImportes: boolean;
  puedeEliminarCancelar: boolean; esAdmin: boolean; diasMax: number;
}) {
  const { rpc, ocupado, router } = useRpc();
  const [dlg, setDlg] = useState<Dlg>(null);
  const [abierta, setAbierta] = useState<string | null>(null);
  const [verHistorial, setVerHistorial] = useState(false);
  const cerrar = () => setDlg(null);

  const vigentes = useMemo(() => empleados.filter((e) => e.estado_registro === "ACTIVO"), [empleados]);
  const historial = useMemo(() => empleados.filter((e) => e.estado_registro !== "ACTIVO"), [empleados]);
  const sit = sol.situacion;
  const terminal = sit === "CANCELADA" || sit === "ELIMINADA";
  const puedeEmpleados = permisos.puede_modificar && (sit === "BORRADOR" || sit === "EN_APROBACION" || sit === "APROBADA");
  const puedeReemplazar = permisos.puede_modificar && (sit === "EN_APROBACION" || sit === "APROBADA");
  const decidiendo = permisos.puede_aprobar && sit === "EN_APROBACION";
  const control = permisos.puede_control_ingreso && sit === "APROBADA";
  const hayPendientes = vigentes.some((e) => e.estado_aprobacion === "PENDIENTE_APROBACION");

  const solo = (nombre: string, args: Record<string, unknown>, ok: string) => rpc(nombre, args, ok);
  const [regIngreso, setRegIngreso] = useState<RegistroIngreso | null>(null);
  const registrar = (se: EmpleadoDetalle, r: EstadoAsistencia) => setRegIngreso({ se: se.solicitud_empleado_id, nombre: se.nombre_completo, resultado: r });
  const confirmarIngreso = async (r: RegistroIngreso, iso: string, obs: string) => {
    const res = await rpc("rpc_registrar_control_ingreso", { p_solicitud_empleado_id: r.se, p_resultado: r.resultado, p_fecha_hora: iso, p_observacion: obs || null }, "Control de ingreso registrado");
    if (res.ok) setRegIngreso(null);
  };

  return (
    <>
      <div className="mb-3"><Link href="/solicitudes" className="text-sm text-muted hover:text-fg">← Solicitudes</Link></div>
      <PageHeader titulo={`Solicitud ${sol.numero ?? ""}`} subtitulo={`${sol.area_nombre} · ${sol.sector_nombre} · ${sol.proceso_nombre}`} acciones={
        <>
          {sit === "BORRADOR" && permisos.puede_modificar && <button className="btn btn-primary" disabled={!!ocupado} onClick={() => solo("rpc_enviar_a_aprobacion", { p_solicitud_id: sol.id }, "Solicitud enviada")}>Enviar a aprobación</button>}
          {decidiendo && hayPendientes && <><button className="btn btn-success" disabled={!!ocupado} onClick={() => solo("rpc_aprobar_masivo", { p_solicitud_id: sol.id }, "Pendientes aprobados")}>Aprobar todos</button><button className="btn btn-secondary" onClick={() => setDlg("rechazarTodos")}>Rechazar todos</button></>}
          {control && <button className="btn btn-primary" disabled={!!ocupado} onClick={() => solo("rpc_finalizar_solicitud", { p_solicitud_id: sol.id }, "Solicitud finalizada")}>Finalizar control de ingreso</button>}
          {permisos.puede_modificar && !terminal && <button className="btn btn-secondary" onClick={() => setDlg("editar")}>Editar</button>}
          {permisos.puede_reabrir && (sit === "APROBADA" || sit === "RECHAZADA" || sit === "FINALIZADA") && <button className="btn btn-secondary" onClick={() => setDlg("reabrir")}>Reabrir</button>}
          {sit === "BORRADOR" && permisos.puede_modificar && puedeEliminarCancelar && <button className="btn btn-danger" disabled={!!ocupado} onClick={async () => { if (confirm("¿Eliminar este borrador? No se puede deshacer.")) { const r = await rpc("rpc_eliminar_borrador", { p_solicitud_id: sol.id }, "Borrador eliminado", { refrescar: false }); if (r.ok) router.push("/solicitudes"); } }}>Eliminar</button>}
          {!terminal && sit !== "BORRADOR" && puedeEliminarCancelar && <button className="btn btn-danger" onClick={() => setDlg("cancelar")}>Cancelar solicitud</button>}
        </>} />

      <div className="grid lg:grid-cols-3 gap-4 mb-6">
        <div className="card p-5 lg:col-span-2">
          <div className="flex items-center gap-3 mb-4"><SituacionBadge situacion={sit} /><span className="text-xs text-muted">Creada {fmtFechaHora(sol.fecha_hora_solicitud, zona)} por {sol.solicitante_nombre}</span></div>
          <dl className="grid sm:grid-cols-2 gap-x-6 gap-y-3 text-sm">
            <div><dt className="label">Inicio</dt><dd>{fmtFechaHora(sol.fecha_hora_inicio, zona)}</dd></div>
            <div><dt className="label">Fin</dt><dd>{fmtFechaHora(sol.fecha_hora_fin, zona)}</dd></div>
            <div><dt className="label">Motivo</dt><dd>{sol.motivo_nombre} <span className="text-muted">({sol.motivo_tipo === "PRODUCTIVO" ? "productivo" : "improductivo"})</span></dd></div>
            <div><dt className="label">Moneda</dt><dd>{sol.moneda ?? "—"}</dd></div>
            <div className="sm:col-span-2"><dt className="label">Observación</dt><dd className="whitespace-pre-wrap">{sol.observacion || "—"}</dd></div>
          </dl>
        </div>
        <div className="card p-5 grid grid-cols-2 gap-4 content-start">
          <div><div className="label">Empleados</div><div className="text-2xl font-bold">{sol.cantidad_empleados}</div>
            {sol.empleados_aprobados !== undefined && <div className="text-xs mt-1"><span className="text-success font-semibold">{sol.empleados_aprobados} aprob.</span> · <span className="text-danger font-semibold">{sol.empleados_rechazados} rech.</span> · <span className="text-warning font-semibold">{sol.empleados_pendientes} pend.</span></div>}</div>
          <div><div className="label">Horas</div><div className="text-2xl font-bold">{fmtHoras(sol.total_horas_solicitud)}</div>
            {sol.horas_aprobadas !== undefined && <div className="text-xs mt-1"><span className="text-success font-semibold">{fmtHoras(sol.horas_aprobadas)} aprob.</span> · <span className="text-danger font-semibold">{fmtHoras(sol.horas_rechazadas)} rech.</span> · <span className="text-warning font-semibold">{fmtHoras(sol.horas_pendientes)} pend.</span></div>}</div>
          {verImportes && <>
            <div className="col-span-2"><div className="label">Importe total</div><div className="text-xl font-bold">{fmtImporte(sol.total_importe_solicitud, sol.moneda)}</div></div>
            <div><div className="label">Aprobado</div><div className="text-sm font-semibold" style={{ color: "var(--success)" }}>{fmtImporte(sol.importe_aprobado)}</div></div>
            <div><div className="label">Pendiente</div><div className="text-sm font-semibold" style={{ color: "var(--warning)" }}>{fmtImporte(sol.importe_pendiente)}</div></div>
          </>}
        </div>
      </div>

      <div className="flex items-center justify-between mb-3">
        <h2 className="font-semibold">Empleados ({vigentes.length})</h2>
        {puedeEmpleados && <button className="btn btn-primary btn-sm" onClick={() => setDlg("agregar")}>+ Agregar empleado</button>}
      </div>
      <div className="card overflow-hidden"><div className="overflow-x-auto">
        <table className="tbl">
          <thead><tr><th>Empleado</th><th>IB / ranking</th><th>Aprobación</th><th>Ingreso</th><th className="text-right">Horas</th>{verImportes && <th className="text-right">Importe</th>}<th /></tr></thead>
          <tbody>
            {vigentes.length === 0 && <tr><td colSpan={7} className="text-center text-muted py-10">Todavía no hay empleados en esta solicitud.</td></tr>}
            {vigentes.map((e) => {
              const filas = detalle.filter((d) => d.solicitud_empleado_id === e.solicitud_empleado_id);
              return (
                <Fragment key={e.solicitud_empleado_id}>
                  <tr>
                    <td><button className="text-left" onClick={() => setAbierta(abierta === e.solicitud_empleado_id ? null : e.solicitud_empleado_id)} aria-expanded={abierta === e.solicitud_empleado_id}>
                      <div className="font-medium">{e.nombre_completo}</div>
                      <div className="text-xs text-muted">{e.legajo}{e.reemplaza_a_nombre ? ` · reemplaza a ${e.reemplaza_a_nombre}` : ""}</div></button></td>
                    <td><IbRanking ib={e.ib_descripcion} ranking={e.ranking_horas_al_momento} bandas={bandas} /></td>
                    <td><AprobacionBadge estado={e.estado_aprobacion} />{e.motivo_rechazo && <div className="text-xs text-muted mt-1 max-w-48">{e.motivo_rechazo}</div>}</td>
                    <td><AsistenciaBadge estado={e.estado_asistencia} />{e.fecha_hora_ingreso && <div className="text-xs text-muted">{fmtFechaHora(e.fecha_hora_ingreso, zona)}</div>}{e.observacion_control_ingreso && <div className="text-xs mt-0.5 max-w-48 whitespace-pre-wrap">💬 {e.observacion_control_ingreso}</div>}</td>
                    <td className="text-right">{fmtHoras(e.total_horas)}</td>
                    {verImportes && <td className="text-right">{fmtImporte(e.total_importe, sol.moneda)}</td>}
                    <td><div className="flex flex-wrap gap-1.5 justify-end">
                      {decidiendo && e.estado_aprobacion !== "APROBADO" && <button className="btn btn-success btn-sm" disabled={!!ocupado} onClick={() => solo("rpc_aprobar_empleado", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Empleado aprobado")}>Aprobar</button>}
                      {decidiendo && e.estado_aprobacion !== "RECHAZADO" && <button className="btn btn-secondary btn-sm" onClick={() => setDlg({ tipo: "rechazar", se: e })}>Rechazar</button>}
                      {control && e.estado_aprobacion === "APROBADO" && e.estado_asistencia === "PENDIENTE_INGRESO" && <>
                        <button className="btn btn-success btn-sm" disabled={!!ocupado} onClick={() => registrar(e, "INGRESO_REGISTRADO")}>Ingresó</button>
                        <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => registrar(e, "YA_ESTABA_EN_PLANTA")}>Ya estaba</button>
                        <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => registrar(e, "NO_PRESENTADO")}>No se presentó</button></>}
                      {control && ["INGRESO_REGISTRADO", "YA_ESTABA_EN_PLANTA", "NO_PRESENTADO"].includes(e.estado_asistencia) && <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => solo("rpc_quitar_control_ingreso", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Control de ingreso quitado")}>Quitar control</button>}
                      {puedeReemplazar && <button className="btn btn-ghost btn-sm" onClick={() => setDlg({ tipo: "reemplazar", se: e })}>Reemplazar</button>}
                      {puedeEmpleados && <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => { if (confirm(`¿Quitar a ${e.nombre_completo} de la solicitud?`)) solo("rpc_quitar_empleado", { p_solicitud_empleado_id: e.solicitud_empleado_id }, "Empleado quitado"); }}>Quitar</button>}
                      {esAdmin && sit === "FINALIZADA" && e.estado_aprobacion === "APROBADO" && <button className="btn btn-ghost btn-sm" onClick={() => setDlg({ tipo: "rectificar", se: e })}>Rectificar horas</button>}
                    </div></td>
                  </tr>
                  {abierta === e.solicitud_empleado_id && (
                    <tr><td colSpan={7} style={{ background: "var(--surface-2)" }}>
                      {filas.length === 0 ? <span className="text-sm text-muted">Sin desglose calculado.</span> : (
                        <table className="tbl"><thead><tr><th>Fecha</th><th>Banda</th><th className="text-right">Horas</th><th className="text-right">Mult.</th>{verImportes && <><th className="text-right">Valor/h</th><th className="text-right">Importe</th></>}<th>Feriado</th></tr></thead>
                          <tbody>{filas.map((d) => <tr key={d.id}><td>{d.fecha.split("-").reverse().join("/")}</td><td>{bandasHorarias[d.banda_horaria_id] ?? "—"}</td><td className="text-right">{fmtHoras(d.horas)}</td><td className="text-right">×{d.multiplicador}</td>{verImportes && <><td className="text-right">{fmtImporte(d.valor_hora, d.moneda)}</td><td className="text-right">{fmtImporte(d.importe, d.moneda)}</td></>}<td>{d.es_feriado ? "Sí" : "—"}</td></tr>)}</tbody></table>
                      )}
                    </td></tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div></div>

      {historial.length > 0 && (
        <div className="mt-5">
          <button className="btn btn-ghost btn-sm" onClick={() => setVerHistorial((v) => !v)}>{verHistorial ? "Ocultar" : "Ver"} historial de reemplazos y bajas ({historial.length})</button>
          {verHistorial && <div className="card mt-2 overflow-x-auto"><table className="tbl"><thead><tr><th>Empleado</th><th>Registro</th><th>Aprobación</th><th className="text-right">Horas</th></tr></thead>
            <tbody>{historial.map((e) => <tr key={e.solicitud_empleado_id}><td>{e.nombre_completo}<div className="text-xs text-muted">{e.legajo}</div></td><td>{e.estado_registro === "REEMPLAZADO" ? "Reemplazado" : "Cancelado"}</td><td><AprobacionBadge estado={e.estado_aprobacion} /></td><td className="text-right">{fmtHoras(e.total_horas)}</td></tr>)}</tbody></table></div>}
        </div>
      )}

      {esAdmin && auditoria.length > 0 && (
        <div className="mt-8">
          <h2 className="font-semibold mb-3">Historial de la solicitud</h2>
          <ol className="card divide-y">
            {auditoria.map((a) => (
              <li key={a.id} className="px-4 py-3 text-sm flex flex-wrap gap-x-4 gap-y-1">
                <span className="text-muted w-36 shrink-0">{fmtFechaHora(a.fecha_hora, zona)}</span>
                <span className="font-medium">{a.evento.replaceAll("_", " ").toLowerCase()}</span>
                {(a.estado_anterior || a.estado_nuevo) && <span className="text-muted">{a.estado_anterior ?? "—"} → {a.estado_nuevo ?? "—"}</span>}
              </li>))}
          </ol>
        </div>
      )}

      {/* Diálogos */}
      <Modal abierto={dlg === "agregar"} onCerrar={cerrar} titulo="Agregar empleado" ancho>
        <EmployeePicker bandas={bandas} excluir={vigentes.map((v) => v.empleado_id)} ocupado={!!ocupado} etiquetaBoton="Agregar"
          onElegir={async (emp) => { const r = await rpc("rpc_agregar_empleado", { p_solicitud_id: sol.id, p_empleado_id: emp.id }, `${emp.nombre_completo} agregado`); if (r.ok) cerrar(); }} />
      </Modal>
      <Modal abierto={typeof dlg === "object" && dlg !== null && dlg.tipo === "reemplazar"} onCerrar={cerrar} titulo={typeof dlg === "object" && dlg ? `Reemplazar a ${dlg.se.nombre_completo}` : ""} ancho>
        {typeof dlg === "object" && dlg && dlg.tipo === "reemplazar" && (
          <EmployeePicker bandas={bandas} excluir={vigentes.map((v) => v.empleado_id)} ocupado={!!ocupado} etiquetaBoton="Reemplazar"
            onElegir={async (emp) => { const r = await rpc("rpc_reemplazar_empleado", { p_solicitud_empleado_id: dlg.se.solicitud_empleado_id, p_empleado_nuevo_id: emp.id }, "Empleado reemplazado"); if (r.ok) cerrar(); }} />)}
      </Modal>
      <PromptModal abierto={typeof dlg === "object" && dlg !== null && dlg.tipo === "rechazar"} titulo="Rechazar empleado" etiqueta="Motivo del rechazo (obligatorio)" confirmar="Rechazar" peligro ocupado={!!ocupado} onCerrar={cerrar}
        onConfirmar={async (t) => { if (typeof dlg === "object" && dlg) { const r = await rpc("rpc_rechazar_empleado", { p_solicitud_empleado_id: dlg.se.solicitud_empleado_id, p_motivo: t }, "Empleado rechazado"); if (r.ok) cerrar(); } }} />
      <IngresoModal registro={regIngreso} zona={zona} ocupado={!!ocupado} onCerrar={() => setRegIngreso(null)} onConfirmar={confirmarIngreso} />
      <PromptModal abierto={dlg === "rechazarTodos"} titulo="Rechazar todos los pendientes" etiqueta="Motivo del rechazo (obligatorio)" confirmar="Rechazar todos" peligro ocupado={!!ocupado} onCerrar={cerrar}
        onConfirmar={async (t) => { const r = await rpc("rpc_rechazar_masivo", { p_solicitud_id: sol.id, p_motivo: t }, "Pendientes rechazados"); if (r.ok) cerrar(); }} />
      <PromptModal abierto={dlg === "cancelar"} titulo="Cancelar solicitud" etiqueta="Motivo de la cancelación (obligatorio)" confirmar="Cancelar solicitud" peligro ocupado={!!ocupado} onCerrar={cerrar}
        onConfirmar={async (t) => { const r = await rpc("rpc_cancelar_solicitud", { p_solicitud_id: sol.id, p_motivo: t }, "Solicitud cancelada"); if (r.ok) cerrar(); }} />
      <PromptModal abierto={dlg === "reabrir"} titulo="Reabrir solicitud" etiqueta="Motivo de la reapertura (obligatorio)" confirmar="Reabrir" ocupado={!!ocupado} onCerrar={cerrar}
        onConfirmar={async (t) => { const r = await rpc("rpc_reabrir_solicitud", { p_solicitud_id: sol.id, p_motivo: t }, "Solicitud reabierta"); if (r.ok) cerrar(); }} />
      <Rectificar abierto={typeof dlg === "object" && dlg !== null && dlg.tipo === "rectificar"} se={typeof dlg === "object" && dlg && dlg.tipo === "rectificar" ? dlg.se : null} ocupado={!!ocupado} onCerrar={cerrar}
        onConfirmar={async (h, m, se) => { const r = await rpc("rpc_rectificar_horas_ranking", { p_solicitud_empleado_id: se.solicitud_empleado_id, p_horas: h, p_motivo: m }, "Rectificación registrada"); if (r.ok) cerrar(); }} />
      <Editar abierto={dlg === "editar"} onCerrar={cerrar} sol={sol} cat={cat} zona={zona} diasMax={diasMax} rpc={rpc} ocupado={!!ocupado} />
    </>
  );
}

function Rectificar({ abierto, se, ocupado, onCerrar, onConfirmar }: { abierto: boolean; se: EmpleadoDetalle | null; ocupado: boolean; onCerrar: () => void; onConfirmar: (h: number, m: string, se: EmpleadoDetalle) => void }) {
  const [h, setH] = useState(""); const [m, setM] = useState("");
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo={se ? `Rectificar horas de ${se.nombre_completo}` : ""}>
      {se && <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); onConfirmar(Number(h), m.trim(), se); }}>
        <p className="text-sm text-muted">Descuenta horas del ranking de una solicitud ya finalizada. Queda registrado quién, cuándo y por qué. Horas consolidadas: <b>{fmtHoras(se.total_horas)}</b>.</p>
        <Campo etiqueta="Horas a descontar"><input className="input" type="number" step="0.01" min="0.01" max={se.total_horas} required value={h} onChange={(e) => setH(e.target.value)} /></Campo>
        <Campo etiqueta="Motivo (obligatorio)"><textarea className="input" rows={3} required value={m} onChange={(e) => setM(e.target.value)} /></Campo>
        <div className="flex justify-end gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Volver</button><button className="btn btn-primary" disabled={ocupado || !h || !m.trim()}>Registrar rectificación</button></div>
      </form>}
    </Modal>
  );
}

function Editar({ abierto, onCerrar, sol, cat, zona, diasMax, rpc, ocupado }: {
  abierto: boolean; onCerrar: () => void; sol: SolicitudResumen; cat: Catalogos; zona: string; diasMax: number; ocupado: boolean;
  rpc: (n: string, a: Record<string, unknown>, ok?: string) => Promise<{ ok: boolean }>;
}) {
  const [scope, setScope] = useState<Scope>({ area_id: sol.area_id, sector_id: sol.sector_id, proceso_id: sol.proceso_id });
  const [ini, setIni] = useState(isoToLocal(sol.fecha_hora_inicio, zona));
  const [fin, setFin] = useState(isoToLocal(sol.fecha_hora_fin, zona));
  const [mot, setMot] = useState(sol.motivo_id);
  const [obs, setObs] = useState(sol.observacion ?? "");
  const enBorrador = sol.situacion === "BORRADOR";
  const fechasOk = sol.situacion === "BORRADOR" || sol.situacion === "EN_APROBACION";
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo="Editar solicitud" ancho>
      <div className="space-y-6">
        {enBorrador && <section className="space-y-3"><h3 className="font-semibold text-sm">Área, sector y proceso</h3>
          <ScopeSelect value={scope} onChange={setScope} areas={cat.areas} sectores={cat.sectores} procesos={cat.procesos} />
          <button className="btn btn-secondary btn-sm" disabled={ocupado || !scope.proceso_id} onClick={() => rpc("rpc_modificar_scope", { p_solicitud_id: sol.id, p_area_id: scope.area_id, p_sector_id: scope.sector_id, p_proceso_id: scope.proceso_id }, "Alcance actualizado")}>Guardar alcance</button></section>}
        {fechasOk && <section className="space-y-3"><h3 className="font-semibold text-sm">Fechas</h3>
          <div className="grid sm:grid-cols-2 gap-3"><Campo etiqueta="Inicio" ayuda={`Antigüedad máxima: ${diasMax} días`}><input className="input" type="datetime-local" value={ini} onChange={(e) => setIni(e.target.value)} /></Campo><Campo etiqueta="Fin"><input className="input" type="datetime-local" min={ini} value={fin} onChange={(e) => setFin(e.target.value)} /></Campo></div>
          <p className="text-xs text-muted">Al cambiar las fechas se recalculan horas e importes, y en aprobación se vuelven a pedir las decisiones.</p>
          <button className="btn btn-secondary btn-sm" disabled={ocupado || !ini || !fin || fin <= ini} onClick={() => rpc("rpc_modificar_fechas", { p_solicitud_id: sol.id, p_fecha_hora_inicio: localToIso(ini, zona), p_fecha_hora_fin: localToIso(fin, zona) }, "Fechas actualizadas")}>Guardar fechas</button></section>}
        {fechasOk && <section className="space-y-3"><h3 className="font-semibold text-sm">Motivo</h3>
          <select className="input" value={mot} onChange={(e) => setMot(e.target.value)}>{cat.motivos.filter((m) => m.activo || m.id === sol.motivo_id).map((m) => <option key={m.id} value={m.id}>{m.motivo}{m.requiere_aprobacion ? "" : " (sin aprobación)"}</option>)}</select>
          <p className="text-xs text-muted">Pasar entre motivos que requieren aprobación conserva las aprobaciones; pasar a uno que no la requiere (o al revés) las recalcula.</p>
          <button className="btn btn-secondary btn-sm" disabled={ocupado || mot === sol.motivo_id} onClick={() => rpc("rpc_modificar_motivo", { p_solicitud_id: sol.id, p_motivo_id: mot }, "Motivo actualizado")}>Guardar motivo</button></section>}
        <section className="space-y-3"><h3 className="font-semibold text-sm">Observación</h3>
          <textarea className="input" rows={3} value={obs} onChange={(e) => setObs(e.target.value)} />
          <button className="btn btn-secondary btn-sm" disabled={ocupado || obs === (sol.observacion ?? "")} onClick={() => rpc("rpc_modificar_observacion", { p_solicitud_id: sol.id, p_observacion: obs.trim() || null }, "Observación actualizada")}>Guardar observación</button></section>
      </div>
    </Modal>
  );
}
