import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAll } from "@/lib/supabase/fetch-all";
import { fmtFecha, fmtFechaHora } from "@/lib/format";
import { APROBACION_LABEL, ASISTENCIA_LABEL, SITUACION_LABEL, type BandaHoraria, type DetalleCalculo, type EmpleadoDetalle, type EmpleadoResumen, type SolicitudResumen } from "@/lib/types";

const lotes = <T,>(a: T[], n: number) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const hora = (iso: string, tz: string) => new Intl.DateTimeFormat("es-AR", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso));
const dec = (n: number) => n.toFixed(2).replace(".", ",");
const hhmm = (h: number) => { const m = Math.round(h * 60); return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`; };
// Evita que Excel interprete texto cargado por usuarios como fórmula (=, +, -, @).
const texto = (v: unknown) => { const t = String(v ?? "").replace(/\r?\n/g, " ").trim(); return /^[=+\-@]/.test(t) ? `'${t}` : t; };
const celda = (v: string) => `"${v.replace(/"/g, '""')}"`;

/** Una fila por empleado de cada solicitud, con una columna de horas (y de valor/total, si corresponde) por cada banda horaria usada. */
export async function armarCsvSolicitudes(sb: SupabaseClient, filas: SolicitudResumen[], opts: { zona: string; verImportes: boolean }): Promise<string> {
  const { zona, verImportes } = opts;
  const ids = filas.map((f) => f.id);

  const emps: EmpleadoDetalle[] = [];
  for (const l of lotes(ids, 50)) emps.push(...(await fetchAll<EmpleadoDetalle>((d, h) => sb.from("vista_solicitud_empleados_detalle").select("*").in("solicitud_id", l).eq("estado_registro", "ACTIVO").order("solicitud_empleado_id").range(d, h))));

  const detalle: DetalleCalculo[] = [];
  for (const l of lotes(emps.map((e) => e.solicitud_empleado_id), 80)) detalle.push(...(await fetchAll<DetalleCalculo>((d, h) => sb.from("solicitud_empleado_detalle").select("*").in("solicitud_empleado_id", l).order("id").range(d, h))));

  const bandas = (await fetchAll<BandaHoraria>((d, h) => sb.from("bandas_horarias").select("*").range(d, h)));
  const resEmp = new Map<string, EmpleadoResumen>();
  for (const l of lotes([...new Set(emps.map((e) => e.empleado_id))], 100)) for (const r of await fetchAll<EmpleadoResumen>((d, h) => sb.from("vista_empleados_resumen").select("*").in("id", l).order("id").range(d, h))) resEmp.set(r.id, r);
  const usuarios = new Map<string, string>();
  for (const l of lotes([...new Set(emps.map((e) => e.usuario_aprobacion_id).filter((x): x is string => !!x))], 100)) for (const u of await fetchAll<{ id: string; nombre_completo: string }>((d, h) => sb.from("usuarios").select("id, nombre_completo").in("id", l).order("id").range(d, h))) usuarios.set(u.id, u.nombre_completo);

  const porSe = new Map<string, DetalleCalculo[]>();
  for (const d of detalle) { const a = porSe.get(d.solicitud_empleado_id) ?? []; a.push(d); porSe.set(d.solicitud_empleado_id, a); }
  const usadas = [...new Set(detalle.map((d) => d.banda_horaria_id))].map((id) => bandas.find((b) => b.id === id)).filter((b): b is BandaHoraria => !!b)
    .sort((a, b) => Number(a.multiplicador) - Number(b.multiplicador) || a.descripcion.localeCompare(b.descripcion, "es"));

  const cab = ["N°Solicitud", "FechaSolicitud", "Solicitante", "FechaInicioExtra", "HoraInicioExtra", "FechaFinExtra", "HoraFinExtra", "MotivoExtra", "TipoMotivo", "AreaExtra", "SectorExtra", "ProcesoExtra", "StatusSolicitud", "ObservacionExtra",
    "Legajo", "Colaborador", "Categoria", "StatusColaborador", "IB", "RankingHoras", "EstadoAprobacion", "MotivoRechazo", "UsuarioAprobacion", "FechaAprobacion", "EstadoIngreso", "FechaIngreso", "ObservacionIngreso", "CantidadHoras",
    ...usadas.flatMap((b) => [`Hs ${b.descripcion}`, ...(verImportes ? [`ValorHs ${b.descripcion}`, `Total ${b.descripcion}`] : [])]),
    ...(verImportes ? ["Moneda", "TotalImporte"] : [])];

  const lineas: string[] = [];
  const base = (s: SolicitudResumen) => [s.numero ?? "", fmtFecha(s.fecha_hora_solicitud, zona), s.solicitante_nombre, fmtFecha(s.fecha_hora_inicio, zona), hora(s.fecha_hora_inicio, zona), fmtFecha(s.fecha_hora_fin, zona), hora(s.fecha_hora_fin, zona),
    s.motivo_nombre, s.motivo_tipo === "PRODUCTIVO" ? "PRODUCTIVO" : "IMPRODUCTIVO", s.area_nombre, s.sector_nombre, s.proceso_nombre, SITUACION_LABEL[s.situacion], s.observacion ?? ""];
  for (const s of filas) {
    const es = emps.filter((e) => e.solicitud_id === s.id);
    if (es.length === 0) { lineas.push([...base(s).map((x) => texto(x)), ...Array(cab.length - 14).fill("")].map(celda).join(";")); continue; }
    for (const e of es) {
      const det = porSe.get(e.solicitud_empleado_id) ?? [];
      const r = resEmp.get(e.empleado_id);
      const porBanda = usadas.flatMap((b) => {
        const d = det.filter((x) => x.banda_horaria_id === b.id);
        const hs = d.reduce((a, x) => a + Number(x.horas), 0), tot = d.reduce((a, x) => a + Number(x.importe), 0);
        return [d.length ? dec(hs) : "", ...(verImportes ? [d.length && hs > 0 ? dec(tot / hs) : "", d.length ? dec(tot) : ""] : [])];
      });
      lineas.push([
        ...base(s).map((x) => texto(x)),
        e.legajo, e.nombre_completo, r?.categoria_codigo ?? "", r ? (r.estado === "ACTIVO" ? "Activo" : "Inactivo") : "", e.ib_descripcion ?? "", e.ranking_horas_al_momento != null ? dec(Number(e.ranking_horas_al_momento)) : "",
        APROBACION_LABEL[e.estado_aprobacion], e.motivo_rechazo ?? "", e.usuario_aprobacion_id ? usuarios.get(e.usuario_aprobacion_id) ?? "" : "", e.fecha_hora_aprobacion ? fmtFecha(e.fecha_hora_aprobacion, zona) : "",
        e.estado_asistencia === "NO_APLICA" ? "" : ASISTENCIA_LABEL[e.estado_asistencia], e.fecha_hora_ingreso ? fmtFechaHora(e.fecha_hora_ingreso, zona).replace(", ", " ") : "", e.observacion_control_ingreso ?? "", hhmm(Number(e.total_horas)),
      ].map((x, i) => (i < 14 ? x : texto(x))).concat(porBanda, verImportes ? [s.moneda ?? "", e.total_importe != null ? dec(Number(e.total_importe)) : ""] : []).map((x) => celda(String(x))).join(";"));
    }
  }
  return "﻿" + [cab.map(celda).join(";"), ...lineas].join("\r\n");
}
