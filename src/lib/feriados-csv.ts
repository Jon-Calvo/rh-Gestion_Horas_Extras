import type { BandaHoraria, DetalleCalculo } from "@/lib/types";

const dec = (n: number) => n.toFixed(2).replace(".", ",");
const ddmmyyyy = (iso: string) => iso.split("-").reverse().join("/");

export interface FeriadoRef { fecha: string; descripcion: string | null }
export interface ResumenFeriadoFactores { feriados: string; horasFeriado: string; factores: string }

/**
 * Para una fila de empleado de una solicitud, a partir de los tramos ya calculados por la base:
 *  - feriados: fechas de feriado alcanzadas por la extra ("21/11/2026 (Día de la Soberanía) | …"), vacío si no hay.
 *  - horasFeriado: horas que cayeron en feriado (vacío si no hay).
 *  - factores: un renglón por día, banda y factor usado ("21/11/2026 Extras ×2,00 (feriado): 2,00 h | …").
 */
export function resumenFeriadosFactores(det: DetalleCalculo[], bandas: BandaHoraria[], feriados: Map<string, string | null>): ResumenFeriadoFactores {
  if (det.length === 0) return { feriados: "", horasFeriado: "", factores: "" };
  const banda = new Map(bandas.map((b) => [b.id, b.descripcion]));
  const fer = [...new Set(det.filter((d) => d.es_feriado).map((d) => d.fecha))].sort();
  const hsFer = det.filter((d) => d.es_feriado).reduce((a, d) => a + Number(d.horas), 0);
  const grupos = new Map<string, { fecha: string; banda: string; mult: number; feriado: boolean; horas: number }>();
  for (const d of det) {
    const k = `${d.fecha}|${d.banda_horaria_id}|${Number(d.multiplicador)}|${d.es_feriado}`;
    const g = grupos.get(k) ?? { fecha: d.fecha, banda: banda.get(d.banda_horaria_id) ?? "Banda", mult: Number(d.multiplicador), feriado: d.es_feriado, horas: 0 };
    g.horas += Number(d.horas); grupos.set(k, g);
  }
  const orden = [...grupos.values()].sort((a, b) => a.fecha.localeCompare(b.fecha) || a.mult - b.mult || a.banda.localeCompare(b.banda, "es"));
  return {
    feriados: fer.map((f) => { const t = feriados.get(f); return t ? `${ddmmyyyy(f)} (${t})` : ddmmyyyy(f); }).join(" | "),
    horasFeriado: fer.length ? dec(hsFer) : "",
    factores: orden.map((g) => `${ddmmyyyy(g.fecha)} ${g.banda} ×${dec(g.mult)}${g.feriado ? " (feriado)" : ""}: ${dec(g.horas)} h`).join(" | "),
  };
}
