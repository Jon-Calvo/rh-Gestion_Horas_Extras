import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { fetchAll } from "@/lib/supabase/fetch-all";
import { empleadosParaKpi } from "@/lib/empleados-solicitud";
import { calcularKpis, comparativoTipos, enPeriodo, filtrarSolicitudes, filtrarSolicitudesPorTipo, inicioMes, mesDe, opcionesFiltros, periodoAnterior, SITUACIONES_KPI, sumarMeses, topEmpleados, type EmpKpi, type TipoPago } from "@/lib/kpis";
import { UUID_RE } from "@/lib/stats-url";
import type { SolicitudResumen } from "@/lib/types";
import { VistaEstadisticas } from "./vista";

export const metadata = { title: "Estadísticas" };

export default async function Estadisticas({ searchParams }: { searchParams: Promise<{ mes?: string; anio?: string; tipo?: string; area?: string; sector?: string; proceso?: string; solicitante?: string }> }) {
  const s = (await getSesion())!;
  const hoy = mesDe(new Date().toISOString(), s.zona);
  const sp = await searchParams;
  const anioHoy = Number(hoy.slice(0, 4));
  const anio = sp.anio && /^\d{4}$/.test(sp.anio) && Number(sp.anio) >= 2000 && Number(sp.anio) <= anioHoy ? Number(sp.anio) : null;
  const mes = sp.mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(sp.mes) && sp.mes <= hoy ? sp.mes : hoy;
  const periodo = anio ? String(anio) : mes;
  const verImp = s.flags.puedeVerImportes;
  const id = (v?: string) => (v && UUID_RE.test(v) ? v.toLowerCase() : null);
  const filtros = { area: id(sp.area), sector: id(sp.sector), proceso: id(sp.proceso), solicitante: id(sp.solicitante) };

  const sb = await createClient();
  // Mes: 6 meses hasta el elegido. Año: el año elegido y el anterior (para comparar).
  const desde = anio ? inicioMes(`${anio - 1}-01`, s.zona) : inicioMes(sumarMeses(mes, -5), s.zona);
  const hasta = anio ? inicioMes(`${anio + 1}-01`, s.zona) : inicioMes(sumarMeses(mes, 1), s.zona);
  const todas = await fetchAll<SolicitudResumen>((d, h) => sb.from("vista_solicitudes_resumen").select("*").gte("fecha_hora_inicio", desde).lt("fecha_hora_inicio", hasta).in("situacion", [...SITUACIONES_KPI]).order("id").range(d, h), 20000);
  const opciones = opcionesFiltros(todas);
  const filas = filtrarSolicitudes(todas, filtros);
  const tipoPedido = sp.tipo;
  const tipo: TipoPago | null = tipoPedido === "JORNAL" || tipoPedido === "MENSUAL" ? tipoPedido : null;

  // Detalle por empleado. Con filtro por tipo hace falta toda la ventana (la tendencia también se filtra); sin filtro, solo este mes y el anterior.
  const ventana = tipo ? filas : filas.filter((f) => { const m = mesDe(f.fecha_hora_inicio, s.zona); return enPeriodo(m, periodo) || enPeriodo(m, periodoAnterior(periodo)); });
  let emps: EmpKpi[] = []; let tipoDisponible = true;
  try { emps = await empleadosParaKpi(sb, ventana.map((f) => f.id)); } catch { tipoDisponible = false; }

  const base = tipo && tipoDisponible ? filtrarSolicitudesPorTipo(filas, emps, tipo, verImp) : filas;
  const k = calcularKpis(base, periodo, s.zona, verImp);
  const delMes = base.filter((f) => enPeriodo(mesDe(f.fecha_hora_inicio, s.zona), periodo) && Number(f.horas_aprobadas ?? 0) > 0);
  const delMesIds = new Set(delMes.map((f) => f.id));
  const empsMes = emps.filter((e) => delMesIds.has(e.solicitud_id) && (!tipo || e.tipo_pago === tipo));
  const te = topEmpleados(empsMes as never, verImp, k.monedaPrincipal, new Map(delMes.map((f) => [f.id, f.moneda])));
  const comp = tipoDisponible ? comparativoTipos(emps, filas, periodo, s.zona, verImp, k.monedaPrincipal) : null;

  const estado = { mes: anio ? null : mes, anio: anio ? String(anio) : null, tipo, ...filtros };
  const nombreDe = (l: { id: string; nombre: string }[], v: string | null) => (v ? l.find((x) => x.id === v)?.nombre ?? "—" : null);
  const filtrosTxt = [nombreDe(opciones.areas, filtros.area) && `Área: ${nombreDe(opciones.areas, filtros.area)}`, nombreDe(opciones.sectores, filtros.sector) && `Sector: ${nombreDe(opciones.sectores, filtros.sector)}`, nombreDe(opciones.procesos, filtros.proceso) && `Proceso: ${nombreDe(opciones.procesos, filtros.proceso)}`, nombreDe(opciones.solicitantes, filtros.solicitante) && `Solicitante: ${nombreDe(opciones.solicitantes, filtros.solicitante)}`].filter((x): x is string => !!x);
  return <VistaEstadisticas k={k} te={te} mes={periodo} hoy={hoy} verImp={verImp} hayDatos={filas.length > 0} hayVentana={todas.length > 0} tipo={tipo} comp={comp} estado={estado} opciones={opciones} filtrosTxt={filtrosTxt} />;
}
