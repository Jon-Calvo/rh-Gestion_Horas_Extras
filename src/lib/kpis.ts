import { localToIso } from "@/lib/format";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

/** Situaciones que cuentan para los indicadores: se excluyen borradores, canceladas y eliminadas
 *  (las horas de una cancelada ya no se van a trabajar y el ranking se revirtió). */
export const SITUACIONES_KPI = ["EN_APROBACION", "APROBADA", "RECHAZADA", "FINALIZADA"] as const;

export interface MesKpi { mes: string; solicitudes: number; horasAprob: number; horasRech: number; horasPend: number; horasFinalizadas: number; importeAprob: Record<string, number> }
export interface ItemTop { clave: string; nombre: string; detalle?: string; horas: number; importe: number; solicitudes: number }
export interface Kpis {
  mes: string; anterior: string; actual: MesKpi; previo: MesKpi; serie: MesKpi[];
  monedaPrincipal: string | null; otrasMonedas: string[];
  topProcesoHoras: ItemTop[]; topProcesoImporte: ItemTop[]; topMotivoHoras: ItemTop[]; topMotivoImporte: ItemTop[]; topSectorHoras: ItemTop[];
  mix: { productivo: number; improductivo: number };
  porSituacion: Record<string, number>;
}

/** "YYYY-MM" de un instante, en la zona horaria dada. */
export function mesDe(iso: string, zona: string): string {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: zona, year: "numeric", month: "2-digit" }).formatToParts(new Date(iso));
  return `${p.find((x) => x.type === "year")!.value}-${p.find((x) => x.type === "month")!.value}`;
}
export function sumarMeses(mes: string, n: number): string {
  const [y, m] = mes.split("-").map(Number);
  const t = y * 12 + (m - 1) + n;
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, "0")}`;
}
/** Instante UTC (ISO) en que empieza el mes local. */
export function inicioMes(mes: string, zona: string): string { return localToIso(`${mes}-01T00:00`, zona); }
/** Variación porcentual; null si no hay base para comparar. */
export function pct(actual: number, anterior: number): number | null { return anterior === 0 ? null : ((actual - anterior) / anterior) * 100; }

const num = (v: unknown) => Number(v ?? 0) || 0;
const vacio = (mes: string): MesKpi => ({ mes, solicitudes: 0, horasAprob: 0, horasRech: 0, horasPend: 0, horasFinalizadas: 0, importeAprob: {} });

export function calcularKpis(filas: SolicitudResumen[], mes: string, zona: string, verImportes: boolean): Kpis {
  const validas = filas.filter((f) => (SITUACIONES_KPI as readonly string[]).includes(f.situacion));
  const meses = Array.from({ length: 6 }, (_, i) => sumarMeses(mes, i - 5));
  const serie = new Map<string, MesKpi>(meses.map((m) => [m, vacio(m)]));
  const delMes: SolicitudResumen[] = [];
  for (const f of validas) {
    const m = mesDe(f.fecha_hora_inicio, zona);
    const k = serie.get(m); if (!k) continue;
    k.solicitudes++;
    k.horasAprob += num(f.horas_aprobadas); k.horasRech += num(f.horas_rechazadas); k.horasPend += num(f.horas_pendientes);
    if (f.situacion === "FINALIZADA") k.horasFinalizadas += num(f.horas_aprobadas);
    if (verImportes && f.importe_aprobado != null) { const mo = f.moneda ?? "—"; k.importeAprob[mo] = (k.importeAprob[mo] ?? 0) + num(f.importe_aprobado); }
    if (m === mes) delMes.push(f);
  }
  // Los importes de distintas monedas no se suman: se muestra la moneda principal (ARS si existe, si no la de mayor monto) y se avisa del resto.
  const tot: Record<string, number> = {};
  for (const k of serie.values()) for (const [mo, v] of Object.entries(k.importeAprob)) tot[mo] = (tot[mo] ?? 0) + v;
  const monedas = Object.keys(tot).sort((a, b) => (a === "ARS" ? -1 : b === "ARS" ? 1 : tot[b] - tot[a]));
  const principal = verImportes ? (monedas[0] ?? null) : null;

  const agrupar = (clave: (f: SolicitudResumen) => { k: string; n: string; d?: string }): ItemTop[] => {
    const m = new Map<string, ItemTop>();
    for (const f of delMes) {
      const horas = num(f.horas_aprobadas); if (horas <= 0) continue;
      const { k, n, d } = clave(f);
      const it = m.get(k) ?? { clave: k, nombre: n, detalle: d, horas: 0, importe: 0, solicitudes: 0 };
      it.horas += horas; it.solicitudes++;
      if (verImportes && f.moneda === principal) it.importe += num(f.importe_aprobado);
      m.set(k, it);
    }
    return [...m.values()];
  };
  const top = (a: ItemTop[], por: "horas" | "importe") => [...a].filter((x) => x[por] > 0).sort((x, y) => y[por] - x[por] || x.nombre.localeCompare(y.nombre, "es")).slice(0, 5);
  const procesos = agrupar((f) => ({ k: `${f.sector_nombre}|${f.proceso_nombre}`, n: f.proceso_nombre, d: f.sector_nombre }));
  const motivos = agrupar((f) => ({ k: f.motivo_nombre, n: f.motivo_nombre }));
  const sectores = agrupar((f) => ({ k: `${f.area_nombre}|${f.sector_nombre}`, n: f.sector_nombre, d: f.area_nombre }));

  const mix = { productivo: 0, improductivo: 0 };
  for (const f of delMes) { if (f.motivo_tipo === "PRODUCTIVO") mix.productivo += num(f.horas_aprobadas); else mix.improductivo += num(f.horas_aprobadas); }
  const porSituacion: Record<string, number> = {};
  for (const f of delMes) porSituacion[f.situacion] = (porSituacion[f.situacion] ?? 0) + 1;

  const lista = [...serie.values()];
  return {
    mes, anterior: sumarMeses(mes, -1), actual: lista[5], previo: lista[4], serie: lista,
    monedaPrincipal: principal, otrasMonedas: verImportes ? monedas.filter((m) => m !== principal) : [],
    topProcesoHoras: top(procesos, "horas"), topProcesoImporte: verImportes ? top(procesos, "importe") : [],
    topMotivoHoras: top(motivos, "horas"), topMotivoImporte: verImportes ? top(motivos, "importe") : [], topSectorHoras: top(sectores, "horas"), mix, porSituacion,
  };
}

/** Top de empleados por horas aprobadas del mes (a partir del detalle por empleado de las solicitudes del mes). */
export function topEmpleados(emps: EmpleadoDetalle[], verImportes: boolean, moneda: string | null, monedaPorSolicitud: Map<string, string | null>) {
  const m = new Map<string, { nombre: string; legajo: string; horas: number; importe: number; solicitudes: Set<string> }>();
  for (const e of emps) {
    if (e.estado_aprobacion !== "APROBADO" || e.estado_registro !== "ACTIVO") continue;
    const it = m.get(e.empleado_id) ?? { nombre: e.nombre_completo, legajo: e.legajo, horas: 0, importe: 0, solicitudes: new Set<string>() };
    it.horas += num(e.total_horas); it.solicitudes.add(e.solicitud_id);
    if (verImportes && monedaPorSolicitud.get(e.solicitud_id) === moneda) it.importe += num(e.total_importe);
    m.set(e.empleado_id, it);
  }
  const todos = [...m.values()].filter((x) => x.horas > 0);
  return { distintos: todos.length, top: todos.sort((a, b) => b.horas - a.horas || a.nombre.localeCompare(b.nombre, "es")).slice(0, 5).map((x) => ({ ...x, solicitudes: x.solicitudes.size })) };
}
