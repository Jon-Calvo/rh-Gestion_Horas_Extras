import type { BandaRanking } from "@/lib/types";

/** Banda de ranking que corresponde a un valor (solo para colorear; el bloqueo real lo decide la base). */
export function bandaPara(valor: number | null | undefined, bandas: BandaRanking[], campo: "solicitud" | "real"): BandaRanking | null {
  if (valor === null || valor === undefined) return null;
  const v = Number(valor);
  return bandas.find((b) => b.activo && (campo === "solicitud" ? b.aplica_a_solicitud : b.aplica_a_real) && v >= Number(b.ranking_inferior) && (b.ranking_superior === null || v < Number(b.ranking_superior))) ?? null;
}
