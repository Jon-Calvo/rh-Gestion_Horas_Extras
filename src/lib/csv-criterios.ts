import type { BandaHoraria, ConceptoHorario, DetalleCalculo } from "@/lib/types";

/** Una columna de horas del Excel: un criterio horario (o, para franjas anteriores a la migración 0007 sin criterio, la franja misma). */
export interface ColCriterio { clave: string; etiqueta: string; mult: number }

/**
 * Agrupa los tramos calculados por criterio horario. Varias franjas del mismo criterio (ej. lunes a viernes y sábado de
 * «Extras al 50%») suman en UNA columna. El encabezado lleva el N° identificador del criterio, que no cambia aunque se
 * renombre: «[1] Extras (al 50%)». Las franjas sin criterio (datos anteriores a la 0007) quedan en una columna propia «[-] …».
 */
export function criteriosUsados(det: DetalleCalculo[], bandas: BandaHoraria[], conceptos: ConceptoHorario[]): { cols: ColCriterio[]; claveDe: (bandaId: string) => string | null } {
  const bPorId = new Map(bandas.map((b) => [b.id, b]));
  const cPorId = new Map(conceptos.map((c) => [c.id, c]));
  const claveDe = (bandaId: string): string | null => {
    const b = bPorId.get(bandaId);
    if (!b) return null;
    return b.concepto_id && cPorId.has(b.concepto_id) ? `c:${b.concepto_id}` : `b:${b.id}`;
  };
  const cols = new Map<string, ColCriterio>();
  for (const d of det) {
    const k = claveDe(d.banda_horaria_id);
    if (!k || cols.has(k)) continue;
    const b = bPorId.get(d.banda_horaria_id)!;
    const c = b.concepto_id ? cPorId.get(b.concepto_id) : undefined;
    cols.set(k, c ? { clave: k, etiqueta: `[${c.numero}] ${c.descripcion}`, mult: Number(c.multiplicador) } : { clave: k, etiqueta: `[-] ${b.descripcion}`, mult: Number(b.multiplicador) });
  }
  return { cols: [...cols.values()].sort((a, b) => a.mult - b.mult || a.etiqueta.localeCompare(b.etiqueta, "es", { numeric: true })), claveDe };
}

/** Horas y total de un empleado dentro de un criterio. */
export function sumaCriterio(det: DetalleCalculo[], clave: string, claveDe: (bandaId: string) => string | null): { n: number; horas: number; total: number } {
  const d = det.filter((x) => claveDe(x.banda_horaria_id) === clave);
  return { n: d.length, horas: d.reduce((a, x) => a + Number(x.horas), 0), total: d.reduce((a, x) => a + Number(x.importe), 0) };
}
