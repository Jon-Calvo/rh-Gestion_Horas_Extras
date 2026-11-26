/** Estado de los filtros de Estadísticas que viaja en la URL (compartible). */
export interface EstadoStats { mes: string | null; anio: string | null; tipo: string | null; area: string | null; sector: string | null; proceso: string | null; solicitante: string | null }

/** Arma /estadisticas?… omitiendo lo que está en su valor por defecto. Si hay año, no se manda mes. */
export function urlStats(e: EstadoStats, mesActual: string): string {
  const p = new URLSearchParams();
  if (e.anio) p.set("anio", e.anio); else if (e.mes && e.mes !== mesActual) p.set("mes", e.mes);
  if (e.tipo) p.set("tipo", e.tipo);
  if (e.area) p.set("area", e.area);
  if (e.sector) p.set("sector", e.sector);
  if (e.proceso) p.set("proceso", e.proceso);
  if (e.solicitante) p.set("solicitante", e.solicitante);
  const q = p.toString();
  return q ? `/estadisticas?${q}` : "/estadisticas";
}

/** Al cambiar un nivel se limpian los de abajo (Área → Sector → Proceso); Solicitante es independiente. */
export function cambiarFiltro(e: EstadoStats, campo: "area" | "sector" | "proceso" | "solicitante", valor: string | null): EstadoStats {
  const n = { ...e, [campo]: valor || null };
  if (campo === "area") { n.sector = null; n.proceso = null; }
  if (campo === "sector") n.proceso = null;
  return n;
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
