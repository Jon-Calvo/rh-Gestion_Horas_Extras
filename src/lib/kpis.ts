import { localToIso } from "@/lib/format";
import type { EmpleadoDetalle, SolicitudResumen } from "@/lib/types";

/** Situaciones que cuentan para los indicadores: se excluyen borradores, canceladas y eliminadas
 *  (las horas de una cancelada ya no se van a trabajar y el ranking se revirtió). */
export const SITUACIONES_KPI = ["EN_APROBACION", "APROBADA", "RECHAZADA", "FINALIZADA"] as const;

export interface MesKpi { mes: string; solicitudes: number; horasAprob: number; horasRech: number; horasPend: number; horasFinalizadas: number; importeAprob: Record<string, number> }
export interface ItemTop { clave: string; nombre: string; detalle?: string; horas: number; importe: number; solicitudes: number }
export interface Kpis {
  /** Período elegido: "YYYY-MM" (un mes) o "YYYY" (año completo, con esAnio = true). */
  esAnio: boolean;
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

/** Período "YYYY" (año completo) o "YYYY-MM" (un mes). */
export const esPeriodoAnio = (p: string) => /^\d{4}$/.test(p);
/** Período inmediatamente anterior (mes anterior o año anterior). */
export const periodoAnterior = (p: string) => (esPeriodoAnio(p) ? String(Number(p) - 1) : sumarMeses(p, -1));
/** ¿El mes "YYYY-MM" cae dentro del período? */
export const enPeriodo = (mes: string, p: string) => (esPeriodoAnio(p) ? mes.startsWith(`${p}-`) : mes === p);
const mesesDelAnio = (anio: number) => Array.from({ length: 12 }, (_, i) => `${anio}-${String(i + 1).padStart(2, "0")}`);
const sumarMesKpi = (clave: string, l: MesKpi[]): MesKpi => {
  const r = vacio(clave);
  for (const k of l) {
    r.solicitudes += k.solicitudes; r.horasAprob += k.horasAprob; r.horasRech += k.horasRech; r.horasPend += k.horasPend; r.horasFinalizadas += k.horasFinalizadas;
    for (const [mo, v] of Object.entries(k.importeAprob)) r.importeAprob[mo] = (r.importeAprob[mo] ?? 0) + v;
  }
  return r;
};

/**
 * Indicadores de un período: un mes ("2026-11": serie de 6 meses, contra el mes anterior) o el año completo ("2026": serie de
 * 12 meses, contra el año anterior). Las solicitudes se ubican por el mes de inicio de la extra.
 */
export function calcularKpis(filas: SolicitudResumen[], mes: string, zona: string, verImportes: boolean): Kpis {
  const esAnio = esPeriodoAnio(mes);
  const validas = filas.filter((f) => (SITUACIONES_KPI as readonly string[]).includes(f.situacion));
  const meses = esAnio ? mesesDelAnio(Number(mes)) : Array.from({ length: 6 }, (_, i) => sumarMeses(mes, i - 5));
  const mesesPrev = esAnio ? mesesDelAnio(Number(mes) - 1) : [];
  const serie = new Map<string, MesKpi>([...meses, ...mesesPrev].map((m) => [m, vacio(m)]));
  const delMes: SolicitudResumen[] = [];
  for (const f of validas) {
    const m = mesDe(f.fecha_hora_inicio, zona);
    const k = serie.get(m); if (!k) continue;
    k.solicitudes++;
    k.horasAprob += num(f.horas_aprobadas); k.horasRech += num(f.horas_rechazadas); k.horasPend += num(f.horas_pendientes);
    if (f.situacion === "FINALIZADA") k.horasFinalizadas += num(f.horas_aprobadas);
    if (verImportes && f.importe_aprobado != null) { const mo = f.moneda ?? "—"; k.importeAprob[mo] = (k.importeAprob[mo] ?? 0) + num(f.importe_aprobado); }
    if (enPeriodo(m, mes)) delMes.push(f);
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

  const lista = meses.map((m) => serie.get(m)!);
  const actual = esAnio ? sumarMesKpi(mes, lista) : lista[5];
  const previo = esAnio ? sumarMesKpi(periodoAnterior(mes), mesesPrev.map((m) => serie.get(m)!)) : lista[4];
  return {
    esAnio, mes, anterior: periodoAnterior(mes), actual, previo, serie: lista,
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

// ---------------------------------------------------------------------------------------------
// Tipo de empleado (Jornal / Mensual)
// ---------------------------------------------------------------------------------------------
export type TipoPago = "JORNAL" | "MENSUAL";
export const TIPOS_PAGO: readonly TipoPago[] = ["JORNAL", "MENSUAL"];
export const TIPO_LABEL: Record<TipoPago | "SIN", string> = { JORNAL: "Jornal", MENSUAL: "Mensual", SIN: "Sin tipo definido" };

/** Fila mínima por empleado de una solicitud (vista_solicitud_empleados_detalle). */
export type EmpKpi = Pick<EmpleadoDetalle, "solicitud_id" | "empleado_id" | "legajo" | "nombre_completo" | "estado_aprobacion" | "estado_registro" | "total_horas" | "total_importe" | "tipo_pago">;

/** Recalcula las solicitudes contando solo a los empleados del tipo elegido; descarta las que no tienen ninguno. */
export function filtrarSolicitudesPorTipo(filas: SolicitudResumen[], emps: EmpKpi[], tipo: TipoPago, verImportes: boolean): SolicitudResumen[] {
  const por = new Map<string, EmpKpi[]>();
  for (const e of emps) { if (e.estado_registro !== "ACTIVO" || e.tipo_pago !== tipo) continue; const l = por.get(e.solicitud_id); if (l) l.push(e); else por.set(e.solicitud_id, [e]); }
  const salida: SolicitudResumen[] = [];
  for (const f of filas) {
    const es = por.get(f.id); if (!es?.length) continue;
    const suma = (est: string, campo: "total_horas" | "total_importe") => es.filter((e) => e.estado_aprobacion === est).reduce((a, e) => a + num(e[campo]), 0);
    salida.push({
      ...f, cantidad_empleados: es.length,
      horas_aprobadas: suma("APROBADO", "total_horas"), horas_rechazadas: suma("RECHAZADO", "total_horas"), horas_pendientes: suma("PENDIENTE_APROBACION", "total_horas"),
      importe_aprobado: verImportes ? suma("APROBADO", "total_importe") : null,
    });
  }
  return salida;
}

export interface FilaTipo { tipo: TipoPago | "SIN"; empleados: number; solicitudes: number; horas: number; horasPrevio: number; importe: number; importePrevio: number }
export interface ComparativoTipos { filas: FilaTipo[]; moneda: string | null; hayTipos: boolean }

/** Jornal vs Mensual del mes elegido (y del anterior): solo empleados aprobados. Importe solo de la moneda principal. */
export function comparativoTipos(emps: EmpKpi[], solicitudes: SolicitudResumen[], mes: string, zona: string, verImportes: boolean, moneda: string | null): ComparativoTipos {
  const sol = new Map(solicitudes.map((s) => [s.id, s]));
  const ant = periodoAnterior(mes);
  const acc = new Map<string, FilaTipo & { _e: Set<string>; _s: Set<string> }>();
  const get = (t: TipoPago | "SIN") => { let x = acc.get(t); if (!x) { x = { tipo: t, empleados: 0, solicitudes: 0, horas: 0, horasPrevio: 0, importe: 0, importePrevio: 0, _e: new Set(), _s: new Set() }; acc.set(t, x); } return x; };
  for (const t of [...TIPOS_PAGO, "SIN" as const]) get(t);
  for (const e of emps) {
    if (e.estado_registro !== "ACTIVO" || e.estado_aprobacion !== "APROBADO") continue;
    const s = sol.get(e.solicitud_id); if (!s) continue;
    const m = mesDe(s.fecha_hora_inicio, zona); const enAct = enPeriodo(m, mes); if (!enAct && !enPeriodo(m, ant)) continue;
    const x = get(e.tipo_pago ?? "SIN");
    const imp = verImportes && s.moneda === moneda ? num(e.total_importe) : 0;
    if (enAct) { x.horas += num(e.total_horas); x.importe += imp; x._e.add(e.empleado_id); x._s.add(e.solicitud_id); }
    else { x.horasPrevio += num(e.total_horas); x.importePrevio += imp; }
  }
  const filas = [...acc.values()].map(({ _e, _s, ...r }) => ({ ...r, empleados: _e.size, solicitudes: _s.size }));
  return { filas: filas.filter((f) => f.tipo !== "SIN" || f.horas > 0 || f.horasPrevio > 0), moneda, hayTipos: emps.some((e) => !!e.tipo_pago) };
}

// ---------------------------------------------------------------------------------------------
// Filtros por área / sector / proceso / solicitante (selección única)
// ---------------------------------------------------------------------------------------------
export interface FiltrosStats { area: string | null; sector: string | null; proceso: string | null; solicitante: string | null }
export const SIN_FILTROS: FiltrosStats = { area: null, sector: null, proceso: null, solicitante: null };
export interface OpcionesStats {
  areas: { id: string; nombre: string }[]; sectores: { id: string; nombre: string; area_id: string }[];
  procesos: { id: string; nombre: string; sector_id: string }[]; solicitantes: { id: string; nombre: string }[];
}

/** Se filtra por el área / sector / proceso / solicitante de la SOLICITUD (no por los de cada empleado). */
export function filtrarSolicitudes(filas: SolicitudResumen[], f: FiltrosStats): SolicitudResumen[] {
  return filas.filter((s) => (!f.area || s.area_id === f.area) && (!f.sector || s.sector_id === f.sector) && (!f.proceso || s.proceso_id === f.proceso) && (!f.solicitante || s.solicitante_id === f.solicitante));
}

/** Opciones de cada filtro: solo lo que tiene solicitudes en la ventana (y dentro de tu alcance), ordenadas por nombre. */
export function opcionesFiltros(filas: SolicitudResumen[]): OpcionesStats {
  const areas = new Map<string, { id: string; nombre: string }>(), sectores = new Map<string, { id: string; nombre: string; area_id: string }>();
  const procesos = new Map<string, { id: string; nombre: string; sector_id: string }>(), solicitantes = new Map<string, { id: string; nombre: string }>();
  for (const s of filas) {
    areas.set(s.area_id, { id: s.area_id, nombre: s.area_nombre }); sectores.set(s.sector_id, { id: s.sector_id, nombre: s.sector_nombre, area_id: s.area_id });
    procesos.set(s.proceso_id, { id: s.proceso_id, nombre: s.proceso_nombre, sector_id: s.sector_id }); solicitantes.set(s.solicitante_id, { id: s.solicitante_id, nombre: s.solicitante_nombre });
  }
  const o = <T extends { nombre: string }>(m: Map<string, T>) => [...m.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
  return { areas: o(areas), sectores: o(sectores), procesos: o(procesos), solicitantes: o(solicitantes) };
}
