import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { fetchAll } from "@/lib/supabase/fetch-all";
import { empleadosParaKpi } from "@/lib/empleados-solicitud";
import { calcularKpis, comparativoTipos, filtrarSolicitudesPorTipo, inicioMes, mesDe, SITUACIONES_KPI, sumarMeses, topEmpleados, type EmpKpi, type TipoPago } from "@/lib/kpis";
import type { SolicitudResumen } from "@/lib/types";
import { VistaEstadisticas } from "./vista";

export const metadata = { title: "Estadísticas" };

export default async function Estadisticas({ searchParams }: { searchParams: Promise<{ mes?: string; tipo?: string }> }) {
  const s = (await getSesion())!;
  const hoy = mesDe(new Date().toISOString(), s.zona);
  const pedido = (await searchParams).mes;
  const mes = pedido && /^\d{4}-(0[1-9]|1[0-2])$/.test(pedido) && pedido <= hoy ? pedido : hoy;
  const verImp = s.flags.puedeVerImportes;

  const sb = await createClient();
  const desde = inicioMes(sumarMeses(mes, -5), s.zona), hasta = inicioMes(sumarMeses(mes, 1), s.zona);
  const filas = await fetchAll<SolicitudResumen>((d, h) => sb.from("vista_solicitudes_resumen").select("*").gte("fecha_hora_inicio", desde).lt("fecha_hora_inicio", hasta).in("situacion", [...SITUACIONES_KPI]).order("id").range(d, h), 20000);
  const tipoPedido = (await searchParams).tipo;
  const tipo: TipoPago | null = tipoPedido === "JORNAL" || tipoPedido === "MENSUAL" ? tipoPedido : null;

  // Detalle por empleado. Con filtro por tipo hace falta toda la ventana (la tendencia también se filtra); sin filtro, solo este mes y el anterior.
  const ventana = tipo ? filas : filas.filter((f) => { const m = mesDe(f.fecha_hora_inicio, s.zona); return m === mes || m === sumarMeses(mes, -1); });
  let emps: EmpKpi[] = []; let tipoDisponible = true;
  try { emps = await empleadosParaKpi(sb, ventana.map((f) => f.id)); } catch { tipoDisponible = false; }

  const base = tipo && tipoDisponible ? filtrarSolicitudesPorTipo(filas, emps, tipo, verImp) : filas;
  const k = calcularKpis(base, mes, s.zona, verImp);
  const delMes = base.filter((f) => mesDe(f.fecha_hora_inicio, s.zona) === mes && Number(f.horas_aprobadas ?? 0) > 0);
  const delMesIds = new Set(delMes.map((f) => f.id));
  const empsMes = emps.filter((e) => delMesIds.has(e.solicitud_id) && (!tipo || e.tipo_pago === tipo));
  const te = topEmpleados(empsMes as never, verImp, k.monedaPrincipal, new Map(delMes.map((f) => [f.id, f.moneda])));
  const comp = tipoDisponible ? comparativoTipos(emps, filas, mes, s.zona, verImp, k.monedaPrincipal) : null;

  return <VistaEstadisticas k={k} te={te} mes={mes} hoy={hoy} verImp={verImp} hayDatos={filas.length > 0} tipo={tipo} comp={comp} />;
}
