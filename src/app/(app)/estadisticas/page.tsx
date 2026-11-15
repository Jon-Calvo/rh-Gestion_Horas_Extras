import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { fetchAll } from "@/lib/supabase/fetch-all";
import { empleadosDeSolicitudes } from "@/lib/empleados-solicitud";
import { calcularKpis, inicioMes, mesDe, SITUACIONES_KPI, sumarMeses, topEmpleados } from "@/lib/kpis";
import type { SolicitudResumen } from "@/lib/types";
import { VistaEstadisticas } from "./vista";

export const metadata = { title: "Estadísticas" };

export default async function Estadisticas({ searchParams }: { searchParams: Promise<{ mes?: string }> }) {
  const s = (await getSesion())!;
  const hoy = mesDe(new Date().toISOString(), s.zona);
  const pedido = (await searchParams).mes;
  const mes = pedido && /^\d{4}-(0[1-9]|1[0-2])$/.test(pedido) && pedido <= hoy ? pedido : hoy;
  const verImp = s.flags.puedeVerImportes;

  const sb = await createClient();
  const desde = inicioMes(sumarMeses(mes, -5), s.zona), hasta = inicioMes(sumarMeses(mes, 1), s.zona);
  const filas = await fetchAll<SolicitudResumen>((d, h) => sb.from("vista_solicitudes_resumen").select("*").gte("fecha_hora_inicio", desde).lt("fecha_hora_inicio", hasta).in("situacion", [...SITUACIONES_KPI]).order("id").range(d, h), 20000);
  const k = calcularKpis(filas, mes, s.zona, verImp);

  // Detalle por empleado, solo de las solicitudes del mes elegido con horas aprobadas.
  const delMes = filas.filter((f) => mesDe(f.fecha_hora_inicio, s.zona) === mes && Number(f.horas_aprobadas ?? 0) > 0);
  const emps = await empleadosDeSolicitudes(sb, delMes.map((f) => f.id), true);
  const te = topEmpleados(emps, verImp, k.monedaPrincipal, new Map(delMes.map((f) => [f.id, f.moneda])));

  return <VistaEstadisticas k={k} te={te} mes={mes} hoy={hoy} verImp={verImp} hayDatos={filas.length > 0} />;
}
