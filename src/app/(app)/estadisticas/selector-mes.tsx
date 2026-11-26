"use client";
import { useRouter } from "next/navigation";
import { sumarMeses, type OpcionesStats } from "@/lib/kpis";
import { cambiarFiltro, urlStats, type EstadoStats } from "@/lib/stats-url";

/** Período (mes o año completo) y tipo de empleado. */
export function SelectorMes({ estado, actual, conTipo }: { estado: EstadoStats; actual: string; conTipo: boolean }) {
  const router = useRouter();
  const esAnio = !!estado.anio;
  const mes = estado.mes ?? actual, anioActual = Number(actual.slice(0, 4));
  const anio = Number(estado.anio ?? mes.slice(0, 4));
  const ir = (n: Partial<EstadoStats>) => router.push(urlStats({ ...estado, ...n }, actual));
  const irMes = (m: string) => { if (/^\d{4}-\d{2}$/.test(m)) ir({ mes: m, anio: null }); };
  const irAnio = (a: number) => { if (a >= 2000 && a <= anioActual) ir({ anio: String(a), mes: null }); };
  return (
    <div className="no-print flex flex-wrap items-center gap-1.5" role="group" aria-label="Período y tipo de empleado">
      {conTipo && <select className="input !w-44" value={estado.tipo ?? ""} aria-label="Tipo de empleado" onChange={(e) => ir({ tipo: e.target.value || null })}>
        <option value="">Jornal y mensual</option><option value="JORNAL">Solo jornal</option><option value="MENSUAL">Solo mensual</option>
      </select>}
      <div className="inline-flex rounded-lg overflow-hidden border" style={{ borderColor: "var(--border)" }} role="group" aria-label="Tipo de período">
        <button className={`btn btn-sm ${!esAnio ? "btn-primary" : "btn-ghost"}`} aria-pressed={!esAnio} onClick={() => ir({ anio: null, mes: mes })}>Mes</button>
        <button className={`btn btn-sm ${esAnio ? "btn-primary" : "btn-ghost"}`} aria-pressed={esAnio} onClick={() => ir({ anio: String(anio), mes: null })}>Año completo</button>
      </div>
      {esAnio ? <>
        <button className="btn btn-secondary btn-sm" aria-label="Año anterior" disabled={anio <= 2000} onClick={() => irAnio(anio - 1)}>◀</button>
        <input className="input !w-24" type="number" min={2000} max={anioActual} value={anio} onChange={(e) => irAnio(Number(e.target.value))} aria-label="Elegir año" />
        <button className="btn btn-secondary btn-sm" aria-label="Año siguiente" disabled={anio >= anioActual} onClick={() => irAnio(anio + 1)}>▶</button>
        <button className="btn btn-ghost btn-sm" disabled={anio === anioActual} onClick={() => irAnio(anioActual)}>Año actual</button>
      </> : <>
        <button className="btn btn-secondary btn-sm" aria-label="Mes anterior" onClick={() => irMes(sumarMeses(mes, -1))}>◀</button>
        <input className="input !w-40" type="month" value={mes} max={actual} onChange={(e) => irMes(e.target.value)} aria-label="Elegir mes" />
        <button className="btn btn-secondary btn-sm" aria-label="Mes siguiente" disabled={mes >= actual} onClick={() => irMes(sumarMeses(mes, 1))}>▶</button>
        <button className="btn btn-ghost btn-sm" disabled={mes === actual} onClick={() => irMes(actual)}>Mes actual</button>
      </>}
    </div>
  );
}

/** Área → Sector → Proceso (en cascada) y Solicitante. Selección única; «Todos» = sin filtro. */
export function SelectoresAlcance({ estado, actual, opciones }: { estado: EstadoStats; actual: string; opciones: OpcionesStats }) {
  const router = useRouter();
  const cambiar = (c: "area" | "sector" | "proceso" | "solicitante", v: string) => router.push(urlStats(cambiarFiltro(estado, c, v || null), actual));
  const sectores = opciones.sectores.filter((s) => !estado.area || s.area_id === estado.area);
  const procesos = opciones.procesos.filter((p) => (!estado.sector || p.sector_id === estado.sector) && (!estado.area || opciones.sectores.find((s) => s.id === p.sector_id)?.area_id === estado.area));
  const hay = !!(estado.area || estado.sector || estado.proceso || estado.solicitante);
  const sel = (rotulo: string, valor: string | null, lista: { id: string; nombre: string }[], c: "area" | "sector" | "proceso" | "solicitante", todos: string) => (
    <label className="block min-w-0"><span className="label">{rotulo}</span>
      <select className="input" value={valor ?? ""} onChange={(e) => cambiar(c, e.target.value)}>
        <option value="">{todos}</option>
        {valor && !lista.some((x) => x.id === valor) && <option value={valor}>(sin solicitudes en el período)</option>}
        {lista.map((x) => <option key={x.id} value={x.id}>{x.nombre}</option>)}
      </select></label>);
  return (
    <div className="no-print card p-3 mb-4" role="group" aria-label="Filtros por área, sector, proceso y solicitante">
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        {sel("Área", estado.area, opciones.areas, "area", "Todas las áreas")}
        {sel("Sector", estado.sector, sectores, "sector", "Todos los sectores")}
        {sel("Proceso", estado.proceso, procesos, "proceso", "Todos los procesos")}
        {sel("Solicitante", estado.solicitante, opciones.solicitantes, "solicitante", "Todos los solicitantes")}
      </div>
      {hay && <div className="mt-2 text-right"><button className="btn btn-ghost btn-sm" onClick={() => router.push(urlStats({ ...estado, area: null, sector: null, proceso: null, solicitante: null }, actual))}>Quitar filtros</button></div>}
    </div>
  );
}
