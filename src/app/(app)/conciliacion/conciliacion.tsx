"use client";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Badge, Campo, Vacio, SituacionBadge } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { useRpc } from "@/lib/use-accion";
import { mensajeError } from "@/lib/errors";
import { fmtFechaHora, fmtHoras, fmtImporte, isoToLocal, localToIso } from "@/lib/format";
import { leerMatrizFichadas, parsearFichadas, type FichadasLeidas } from "@/lib/fichadas";
import type { SolicitudResumen } from "@/lib/types";
import type { Imp } from "./page";

interface Fila {
  solicitud_empleado_id: string; legajo: string; nombre_completo: string; tipo_pago: string | null; estado_asistencia: string;
  total_horas: number; total_importe: number | null; real_inicio: string | null; real_fin: string | null; horas_reales: number | null;
  importe_real: number | null; real_origen: "FICHADA" | "MANUAL" | null; observacion_real: string | null; fecha_hora_real: string | null;
  prop_estado: "COMPLETA" | "INCOMPLETA" | "REVISAR" | "SIN_FICHADAS" | "SIN_COBERTURA"; prop_inicio: string | null; prop_fin: string | null;
  prop_horas: number | null; prop_importe: number | null; prop_nota: string | null; fichadas: { fecha_hora: string; tipo: "ENTRADA" | "SALIDA" }[];
}
const ESTADO: Record<Fila["prop_estado"], { t: string; tono: "verde" | "ambar" | "rojo" | "gris" | "azul" }> = {
  COMPLETA: { t: "Completa", tono: "verde" }, INCOMPLETA: { t: "Incompleta", tono: "ambar" }, REVISAR: { t: "Revisar", tono: "ambar" },
  SIN_FICHADAS: { t: "Sin fichadas", tono: "rojo" }, SIN_COBERTURA: { t: "Sin datos del reloj", tono: "gris" },
};
const LOTE = 4000;

export function Conciliacion({ solicitudes, zona, verImportes, importaciones }: { solicitudes: SolicitudResumen[]; zona: string; verImportes: boolean; esAdmin: boolean; importaciones: Imp[] }) {
  const router = useRouter();
  const [abierta, setAbierta] = useState<SolicitudResumen | null>(null);
  const [f, setF] = useState({ desde: "", hasta: "", texto: "", solo: "" });
  const visibles = useMemo(() => solicitudes.filter((s) => {
    const dia = isoToLocal(s.fecha_hora_inicio, zona).slice(0, 10);
    if (f.desde && dia < f.desde) return false; if (f.hasta && dia > f.hasta) return false;
    if (f.texto && !`${s.numero ?? ""} ${s.sector_nombre} ${s.proceso_nombre} ${s.solicitante_nombre}`.toLowerCase().includes(f.texto.toLowerCase())) return false;
    const aprob = s.empleados_aprobados ?? 0, conc = s.empleados_conciliados ?? 0;
    if (f.solo === "pendientes" && !(aprob > conc)) return false;
    return true;
  }), [solicitudes, f, zona]);

  return (
    <div className="space-y-5">
      <ImportarFichadas zona={zona} importaciones={importaciones} onListo={() => router.refresh()} />
      <div className="card p-4 grid sm:grid-cols-4 gap-3">
        <Campo etiqueta="Desde"><input type="date" className="input" value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></Campo>
        <Campo etiqueta="Hasta"><input type="date" className="input" value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></Campo>
        <Campo etiqueta="Buscar"><input type="search" className="input" placeholder="N°, sector, proceso, solicitante" value={f.texto} onChange={(e) => setF({ ...f, texto: e.target.value })} /></Campo>
        <Campo etiqueta="Mostrar"><select className="input" value={f.solo} onChange={(e) => setF({ ...f, solo: e.target.value })}><option value="">Todas</option><option value="pendientes">Con empleados sin conciliar</option></select></Campo>
      </div>
      {visibles.length === 0 ? <Vacio titulo="No hay solicitudes para conciliar" detalle="Aparecen las solicitudes aprobadas o finalizadas dentro de tu alcance." /> : (
        <div className="card overflow-auto"><table className="tbl"><thead><tr><th>N°</th><th>Fecha</th><th>Sector / proceso</th><th>Situación</th><th className="text-right">Aprobados</th><th className="text-right">Conciliados</th><th></th></tr></thead>
          <tbody>{visibles.map((s) => { const a = s.empleados_aprobados ?? 0, c = s.empleados_conciliados ?? 0; return (
            <tr key={s.id}><td className="font-semibold">{s.numero ?? "—"}</td><td>{fmtFechaHora(s.fecha_hora_inicio, zona)}<div className="text-xs text-muted">a {fmtFechaHora(s.fecha_hora_fin, zona)}</div></td>
              <td>{s.sector_nombre}<div className="text-xs text-muted">{s.proceso_nombre}</div></td><td><SituacionBadge situacion={s.situacion} /></td>
              <td className="text-right">{a}</td><td className="text-right"><Badge tono={a > 0 && c >= a ? "verde" : c > 0 ? "ambar" : "gris"}>{c}/{a}</Badge></td>
              <td className="text-right"><button className="btn btn-secondary btn-sm" onClick={() => setAbierta(s)}>Conciliar</button></td></tr>); })}</tbody></table></div>
      )}
      {abierta && <DetalleConciliacion key={abierta.id} sol={abierta} zona={zona} verImportes={verImportes} onCerrar={() => setAbierta(null)} />}
      <p className="text-xs text-muted">Detalle completo de cada solicitud en <Link className="underline" href="/solicitudes">Solicitudes</Link>.</p>
    </div>
  );
}

function ImportarFichadas({ zona, importaciones, onListo }: { zona: string; importaciones: Imp[]; onListo: () => void }) {
  const [leidas, setLeidas] = useState<FichadasLeidas | null>(null);
  const [archivo, setArchivo] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [corriendo, setCorriendo] = useState(false);

  const leer = async (file: File) => {
    setErr(null); setMsg(null); setLeidas(null); setArchivo(file.name);
    try { setLeidas(parsearFichadas(await leerMatrizFichadas(file), zona)); } catch (e) { setErr(mensajeError(e)); }
  };
  const importar = async () => {
    if (!leidas) return;
    setCorriendo(true); setErr(null); setMsg(null);
    try {
      const sb = createClient(); let id: string | null = null; let nuevos = 0, repetidos = 0;
      for (let i = 0; i < leidas.eventos.length; i += LOTE) {
        const { data, error } = await sb.rpc("rpc_importar_fichadas", { p_importacion_id: id, p_archivo: archivo, p_periodo_desde: leidas.periodoDesde, p_periodo_hasta: leidas.periodoHasta, p_eventos: leidas.eventos.slice(i, i + LOTE) });
        if (error) throw error;
        const d = data as { importacion_id: string; nuevos: number; repetidos: number }; id = d.importacion_id; nuevos += d.nuevos; repetidos += d.repetidos;
      }
      setMsg(`Importación lista: ${nuevos} fichada(s) nueva(s), ${repetidos} ya existían.`); setLeidas(null); onListo();
    } catch (e) { setErr(mensajeError(e)); } finally { setCorriendo(false); }
  };
  return (
    <div className="card p-5 space-y-3">
      <div className="font-semibold">Importar fichadas del reloj</div>
      <p className="text-sm text-muted">Subí el Excel del reloj (.xls o .xlsx) con «N. Legajo» y las filas de fecha, hora y Entrada/Salida. Importar el mismo período dos veces no duplica fichadas.</p>
      <div className="flex flex-wrap gap-2 items-center">
        <label className="btn btn-primary cursor-pointer">Elegir archivo<input type="file" accept=".xls,.xlsx,.csv" className="sr-only" onChange={(e) => e.target.files?.[0] && leer(e.target.files[0])} /></label>
        {archivo && <span className="text-sm text-muted">{archivo}</span>}
      </div>
      {err && <div role="alert" className="text-sm rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}>{err}</div>}
      {msg && <div role="status" className="text-sm" style={{ color: "var(--success)" }}>{msg}</div>}
      {leidas && <div className="space-y-2">
        <div className="text-sm">{leidas.legajos} legajo(s), {leidas.eventos.length} fichada(s) ({leidas.entradas} entradas, {leidas.salidas} salidas). Período: <b>{leidas.periodoDesde}</b> a <b>{leidas.periodoHasta}</b>.</div>
        {leidas.avisos.map((a, i) => <div key={i} className="text-xs text-muted">⚠ {a}</div>)}
        <button className="btn btn-primary" disabled={corriendo} onClick={importar}>{corriendo ? <><span className="spinner" /> Importando…</> : "Importar fichadas"}</button>
      </div>}
      {importaciones.length > 0 && <div className="text-xs text-muted">Últimas importaciones: {importaciones.slice(0, 3).map((i) => `${i.archivo} (${i.periodo_desde} a ${i.periodo_hasta})`).join(" · ")}</div>}
    </div>
  );
}

function DetalleConciliacion({ sol, zona, verImportes, onCerrar }: { sol: SolicitudResumen; zona: string; verImportes: boolean; onCerrar: () => void }) {
  const { rpc, ocupado, toast } = useRpc();
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [edit, setEdit] = useState<Fila | null>(null);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const { data, error } = await createClient().rpc("rpc_conciliacion_solicitud", { p_solicitud_id: sol.id });
    if (error) setError(mensajeError(error)); else { setError(null); setFilas((data ?? []) as Fila[]); }
  }, [sol.id]);
  useEffect(() => { cargar(); }, [cargar]);

  const accion = async (nombre: string, args: Record<string, unknown>, ok: string) => { const r = await rpc(nombre, args, ok); if (r.ok) await cargar(); return r; };
  const completas = (filas ?? []).filter((x) => x.prop_estado === "COMPLETA" && !x.real_origen).length;

  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Conciliación ${sol.numero ?? ""}`} ancho>
      <div className="space-y-4">
        <div className="text-sm text-muted">Solicitado: {fmtFechaHora(sol.fecha_hora_inicio, zona)} a {fmtFechaHora(sol.fecha_hora_fin, zona)} · {sol.sector_nombre} / {sol.proceso_nombre}</div>
        {error && <div role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{error}</div>}
        {!filas && !error && <span className="spinner" />}
        {filas && filas.length === 0 && <Vacio titulo="No hay empleados aprobados activos" />}
        {filas && filas.length > 0 && <>
          <div className="flex justify-end"><button className="btn btn-primary btn-sm" disabled={!!ocupado || completas === 0} onClick={() => accion("rpc_confirmar_propuestas", { p_solicitud_id: sol.id }, "Propuestas confirmadas")}>Confirmar propuestas completas ({completas})</button></div>
          <div className="space-y-3">{filas.map((x) => { const e = ESTADO[x.prop_estado]; return (
            <div key={x.solicitud_empleado_id} className="card p-3 space-y-2">
              <div className="flex flex-wrap items-center gap-2 justify-between">
                <div><b>{x.nombre_completo}</b> <span className="text-muted text-sm">· legajo {x.legajo}{x.tipo_pago ? ` · ${x.tipo_pago === "JORNAL" ? "Jornal" : "Mensual"}` : ""}</span></div>
                <Badge tono={e.tono}>{e.t}</Badge>
              </div>
              <div className="grid sm:grid-cols-3 gap-2 text-sm">
                <div><div className="text-xs text-muted">Solicitado</div><b>{fmtHoras(x.total_horas)} h</b>{verImportes && x.total_importe != null && <span className="text-muted"> · {fmtImporte(x.total_importe, sol.moneda)}</span>}</div>
                <div><div className="text-xs text-muted">Propuesta de fichadas</div>{x.prop_horas != null ? <><b>{fmtHoras(x.prop_horas)} h</b> <span className="text-muted">{x.prop_inicio && x.prop_fin ? `${fmtFechaHora(x.prop_inicio, zona)} → ${fmtFechaHora(x.prop_fin, zona)}` : ""}</span></> : <span className="text-muted">—</span>}</div>
                <div><div className="text-xs text-muted">Tiempo real confirmado</div>{x.real_origen ? <><b>{fmtHoras(x.horas_reales)} h</b> <Badge tono={x.real_origen === "MANUAL" ? "azul" : "verde"}>{x.real_origen === "MANUAL" ? "Manual" : "Fichada"}</Badge>{x.real_inicio && x.real_fin && <div className="text-xs text-muted">{fmtFechaHora(x.real_inicio, zona)} → {fmtFechaHora(x.real_fin, zona)}</div>}{verImportes && x.importe_real != null && <div className="text-xs text-muted">{fmtImporte(x.importe_real, sol.moneda)}</div>}{x.observacion_real && <div className="text-xs text-muted">“{x.observacion_real}”</div>}</> : <span className="text-muted">Sin confirmar</span>}</div>
              </div>
              {x.prop_nota && <div className="text-xs text-muted">{x.prop_nota}</div>}
              {x.fichadas.length > 0 && <div className="text-xs text-muted">Fichadas: {x.fichadas.map((p) => `${p.tipo === "ENTRADA" ? "E" : "S"} ${fmtFechaHora(p.fecha_hora, zona)}`).join(" · ")}</div>}
              <div className="flex flex-wrap gap-2">
                {x.prop_estado === "COMPLETA" && <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => accion("rpc_confirmar_real", { p_se_id: x.solicitud_empleado_id, p_inicio: x.prop_inicio, p_fin: x.prop_fin, p_observacion: null, p_desde_propuesta: true }, "Tiempo real confirmado")}>Confirmar propuesta</button>}
                {x.prop_estado === "SIN_FICHADAS" && <button className="btn btn-secondary btn-sm" disabled={!!ocupado} onClick={() => setEdit({ ...x, prop_inicio: null, prop_fin: null })}>Confirmar 0 h…</button>}
                <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => setEdit(x)}>Indicar horario…</button>
                {x.real_origen && <button className="btn btn-ghost btn-sm" disabled={!!ocupado} onClick={() => accion("rpc_quitar_real", { p_se_id: x.solicitud_empleado_id }, "Tiempo real quitado")}>Quitar</button>}
              </div>
            </div>); })}</div>
        </>}
        {edit && <EditarReal key={edit.solicitud_empleado_id} fila={edit} sol={sol} zona={zona} ocupado={!!ocupado}
          onCerrar={() => setEdit(null)}
          onGuardar={async (ini, fin, obs) => { const r = await accion("rpc_confirmar_real", { p_se_id: edit.solicitud_empleado_id, p_inicio: ini, p_fin: fin, p_observacion: obs, p_desde_propuesta: false }, "Tiempo real guardado"); if (r.ok) setEdit(null); else toast("error", "No se pudo guardar el tiempo real."); }} />}
      </div>
    </Modal>
  );
}

function EditarReal({ fila, sol, zona, ocupado, onCerrar, onGuardar }: { fila: Fila; sol: SolicitudResumen; zona: string; ocupado: boolean; onCerrar: () => void; onGuardar: (ini: string | null, fin: string | null, obs: string) => void }) {
  const base = fila.real_inicio ?? fila.prop_inicio; const baseF = fila.real_fin ?? fila.prop_fin;
  const [ini, setIni] = useState(base ? isoToLocal(base, zona) : "");
  const [fin, setFin] = useState(baseF ? isoToLocal(baseF, zona) : "");
  const [obs, setObs] = useState(fila.observacion_real ?? "");
  const cero = !ini && !fin;
  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Tiempo real · ${fila.nombre_completo}`}>
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); onGuardar(cero ? null : localToIso(ini, zona), cero ? null : localToIso(fin, zona), obs.trim()); }}>
        <p className="text-sm text-muted">Debe estar dentro del horario solicitado ({fmtFechaHora(sol.fecha_hora_inicio, zona)} a {fmtFechaHora(sol.fecha_hora_fin, zona)}). Dejá ambos vacíos para registrar 0 h trabajadas.</p>
        <div className="grid sm:grid-cols-2 gap-3">
          <Campo etiqueta="Inicio real"><input type="datetime-local" className="input" value={ini} required={!cero && !!fin} onChange={(e) => setIni(e.target.value)} /></Campo>
          <Campo etiqueta="Fin real"><input type="datetime-local" className="input" value={fin} required={!cero && !!ini} onChange={(e) => setFin(e.target.value)} /></Campo>
        </div>
        <Campo etiqueta="Observación (obligatoria)" ayuda="Explicá el criterio usado, por ejemplo: fichó tarde pero cumplió el turno completo."><textarea className="input" required rows={3} value={obs} onChange={(e) => setObs(e.target.value)} /></Campo>
        <div className="flex justify-end gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado || ((!!ini) !== (!!fin))}>{ocupado ? <span className="spinner" /> : "Guardar"}</button></div>
      </form>
    </Modal>
  );
}
