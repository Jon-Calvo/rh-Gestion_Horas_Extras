import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAll } from "@/lib/supabase/fetch-all";
import { fmtFecha, fmtFechaHora } from "@/lib/format";
import { resumenFeriadosFactores } from "@/lib/feriados-csv";
import { criteriosUsados, sumaCriterio } from "@/lib/csv-criterios";
import { APROBACION_LABEL, ASISTENCIA_LABEL, SITUACION_LABEL, type BandaHoraria, type ConceptoHorario, type DetalleCalculo, type EmpleadoDetalle, type EmpleadoResumen, type SolicitudResumen } from "@/lib/types";

const lotes = <T,>(a: T[], n: number) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const hora = (iso: string, tz: string) => new Intl.DateTimeFormat("es-AR", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso));
const dec = (n: number) => n.toFixed(2).replace(".", ",");
const hhmm = (h: number) => { const m = Math.round(h * 60); return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`; };
// Evita que Excel interprete texto cargado por usuarios como fórmula (=, +, -, @).
const texto = (v: unknown) => { const t = String(v ?? "").replace(/\r?\n/g, " ").trim(); return /^[=+\-@]/.test(t) ? `'${t}` : t; };
const TIPO_TXT: Record<string, string> = { JORNAL: "Jornal", MENSUAL: "Mensual" };
const celda = (v: string) => `"${v.replace(/"/g, '""')}"`;

/** Una fila por empleado de cada solicitud, con una columna de horas (y de valor/total, si corresponde) por cada banda horaria usada. */
export async function armarCsvSolicitudes(sb: SupabaseClient, filas: SolicitudResumen[], opts: { zona: string; verImportes: boolean }): Promise<string> {
  const { zona, verImportes } = opts;
  const ids = filas.map((f) => f.id);

  const emps: EmpleadoDetalle[] = [];
  for (const l of lotes(ids, 50)) emps.push(...(await fetchAll<EmpleadoDetalle>((d, h) => sb.from("vista_solicitud_empleados_detalle").select("*").in("solicitud_id", l).eq("estado_registro", "ACTIVO").order("solicitud_empleado_id").range(d, h))));

  const detalle: DetalleCalculo[] = [];
  for (const l of lotes(emps.map((e) => e.solicitud_empleado_id), 80)) detalle.push(...(await fetchAll<DetalleCalculo>((d, h) => sb.from("solicitud_empleado_detalle").select("*").in("solicitud_empleado_id", l).order("id").range(d, h))));

  const feriados = new Map((await fetchAll<{ fecha: string; descripcion: string | null }>((d, h) => sb.from("feriados").select("fecha, descripcion").order("fecha").range(d, h))).map((f) => [f.fecha, f.descripcion]));
  const bandas = (await fetchAll<BandaHoraria>((d, h) => sb.from("bandas_horarias").select("*").range(d, h)));
  // N° identificadores (migración 0007). Si todavía no se aplicó, las columnas Id salen vacías.
  const nums = async (tabla: string, key: string): Promise<Map<string, number>> => {
    try { return new Map((await fetchAll<Record<string, unknown>>((d, h) => sb.from(tabla).select("*").order("id").range(d, h))).map((r) => [String(r[key]).toLowerCase(), Number(r.numero)])); } catch { return new Map(); }
  };
  const [nArea, nSector, nProceso, nMotivo, nIb, nIbDesc, nCat] = await Promise.all([nums("areas", "id"), nums("sectores", "id"), nums("procesos", "id"), nums("motivos", "id"), nums("ib_configuracion", "id"), nums("ib_configuracion", "descripcion"), nums("categoria_tipos", "codigo")]);
  let conceptos: ConceptoHorario[] = [];
  try { conceptos = await fetchAll<ConceptoHorario>((d, h) => sb.from("conceptos_horarios").select("*").order("numero").range(d, h)); } catch { conceptos = []; }
  const resEmp = new Map<string, EmpleadoResumen>();
  for (const l of lotes([...new Set(emps.map((e) => e.empleado_id))], 100)) for (const r of await fetchAll<EmpleadoResumen>((d, h) => sb.from("vista_empleados_resumen").select("*").in("id", l).order("id").range(d, h))) resEmp.set(r.id, r);
  const usuarios = new Map<string, string>(), nUsuario = new Map<string, number>();
  const idsUsuarios = new Set<string>([...filas.map((f) => f.solicitante_id), ...emps.flatMap((e) => [e.usuario_aprobacion_id, e.usuario_control_ingreso_id])].filter((x): x is string => !!x));
  for (const l of lotes([...idsUsuarios], 100)) for (const u of await fetchAll<{ id: string; nombre_completo: string; numero?: number }>((d, h) => sb.from("usuarios").select("*").in("id", l).order("id").range(d, h))) { usuarios.set(u.id, u.nombre_completo); if (u.numero != null) nUsuario.set(u.id, Number(u.numero)); }
  const idN = (m: Map<string, number>, k: string | null | undefined) => { const v = k ? m.get(String(k).toLowerCase()) : undefined; return v === undefined ? "" : String(v); };

  const porSe = new Map<string, DetalleCalculo[]>();
  for (const d of detalle) { const a = porSe.get(d.solicitud_empleado_id) ?? []; a.push(d); porSe.set(d.solicitud_empleado_id, a); }
  const { cols: usadas, claveDe } = criteriosUsados(detalle, bandas, conceptos);

  const cab = ["N°Solicitud", "FechaSolicitud", "IdSolicitante", "Solicitante", "FechaInicioExtra", "HoraInicioExtra", "FechaFinExtra", "HoraFinExtra", "IdMotivo", "MotivoExtra", "TipoMotivo", "IdArea", "AreaExtra", "IdSector", "SectorExtra", "IdProceso", "ProcesoExtra", "StatusSolicitud", "ObservacionExtra",
    "Legajo", "Colaborador", "IdCategoria", "Categoria", "TipoEmpleado", "StatusColaborador", "IdIB", "IB", "RankingHoras", "EstadoAprobacion", "MotivoRechazo", "IdUsuarioAprobacion", "UsuarioAprobacion", "FechaAprobacion", "EstadoIngreso", "IdUsuarioControlIngreso", "FechaIngreso", "ObservacionIngreso", "CantidadHoras", "HorasReales", "InicioReal", "FinReal", "OrigenTiempoReal", "ObservacionTiempoReal", "FeriadosEnExtra", "HsFeriado", "FactoresAplicados",
    ...usadas.flatMap((b) => [`Hs ${b.etiqueta}`, ...(verImportes ? [`ValorHs ${b.etiqueta}`, `Total ${b.etiqueta}`] : [])]),
    ...(verImportes ? ["Moneda", "TotalImporte", "ImporteReal"] : [])];

  const lineas: string[] = [];
  const NBASE = 19;
  const base = (s: SolicitudResumen) => [s.numero ?? "", fmtFecha(s.fecha_hora_solicitud, zona), idN(nUsuario, s.solicitante_id), s.solicitante_nombre, fmtFecha(s.fecha_hora_inicio, zona), hora(s.fecha_hora_inicio, zona), fmtFecha(s.fecha_hora_fin, zona), hora(s.fecha_hora_fin, zona),
    idN(nMotivo, s.motivo_id), s.motivo_nombre, s.motivo_tipo === "PRODUCTIVO" ? "PRODUCTIVO" : "IMPRODUCTIVO", idN(nArea, s.area_id), s.area_nombre, idN(nSector, s.sector_id), s.sector_nombre, idN(nProceso, s.proceso_id), s.proceso_nombre, SITUACION_LABEL[s.situacion], s.observacion ?? ""];
  for (const s of filas) {
    const es = emps.filter((e) => e.solicitud_id === s.id);
    if (es.length === 0) { lineas.push([...base(s).map((x) => texto(x)), ...Array(cab.length - NBASE).fill("")].map(celda).join(";")); continue; }
    for (const e of es) {
      const det = porSe.get(e.solicitud_empleado_id) ?? [];
      const r = resEmp.get(e.empleado_id);
      const ff = resumenFeriadosFactores(det, bandas, feriados);
      const porBanda = usadas.flatMap((b) => {
        const t = sumaCriterio(det, b.clave, claveDe);
        return [t.n ? dec(t.horas) : "", ...(verImportes ? [t.n && t.horas > 0 ? dec(t.total / t.horas) : "", t.n ? dec(t.total) : ""] : [])];
      });
      const ibN = e.ib_descripcion ? idN(nIbDesc, e.ib_descripcion) || idN(nIb, r?.ib_id) : idN(nIb, r?.ib_id);
      lineas.push([
        ...base(s).map((x) => texto(x)),
        e.legajo, e.nombre_completo, idN(nCat, r?.categoria_codigo), r?.categoria_codigo ?? "", TIPO_TXT[(e.tipo_pago ?? r?.tipo_pago ?? "") as string] ?? "", r ? (r.estado === "ACTIVO" ? "Activo" : "Inactivo") : "", ibN, e.ib_descripcion ?? "", e.ranking_horas_al_momento != null ? dec(Number(e.ranking_horas_al_momento)) : "",
        APROBACION_LABEL[e.estado_aprobacion], e.motivo_rechazo ?? "", idN(nUsuario, e.usuario_aprobacion_id), e.usuario_aprobacion_id ? usuarios.get(e.usuario_aprobacion_id) ?? "" : "", e.fecha_hora_aprobacion ? fmtFecha(e.fecha_hora_aprobacion, zona) : "",
        e.estado_asistencia === "NO_APLICA" ? "" : ASISTENCIA_LABEL[e.estado_asistencia], idN(nUsuario, e.usuario_control_ingreso_id), e.fecha_hora_ingreso ? fmtFechaHora(e.fecha_hora_ingreso, zona).replace(", ", " ") : "", e.observacion_control_ingreso ?? "", hhmm(Number(e.total_horas)),
        e.horas_reales != null ? hhmm(Number(e.horas_reales)) : "", e.real_inicio ? fmtFechaHora(e.real_inicio, zona).replace(", ", " ") : "", e.real_fin ? fmtFechaHora(e.real_fin, zona).replace(", ", " ") : "",
        e.real_origen === "FICHADA" ? "Fichada" : e.real_origen === "MANUAL" ? "Manual" : "", e.observacion_real ?? "",
        ff.feriados, ff.horasFeriado, ff.factores,
      ].map((x, i) => (i < NBASE ? x : texto(x))).concat(porBanda, verImportes ? [s.moneda ?? "", e.total_importe != null ? dec(Number(e.total_importe)) : "", e.importe_real != null ? dec(Number(e.importe_real)) : ""] : []).map((x) => celda(String(x))).join(";"));
    }
  }
  return "﻿" + [cab.map(celda).join(";"), ...lineas].join("\r\n");
}
