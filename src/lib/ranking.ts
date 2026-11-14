import type { BandaRanking } from "@/lib/types";

/** Banda de ranking de un valor, con el MISMO criterio que fn_banda_ranking de la base:
 *  inferior <= valor <= superior (superior vacío = sin tope); si dos bandas coinciden en el límite, gana la de menor inferior.
 *  Solo sirve para colorear; el bloqueo real lo decide la base. */
export function bandaPara(valor: number | null | undefined, bandas: BandaRanking[], campo: "solicitud" | "real"): BandaRanking | null {
  if (valor === null || valor === undefined) return null;
  const v = Number(valor);
  return [...bandas]
    .filter((b) => b.activo && (campo === "solicitud" ? b.aplica_a_solicitud : b.aplica_a_real) && v >= Number(b.ranking_inferior) && (b.ranking_superior === null || v <= Number(b.ranking_superior)))
    .sort((a, b) => Number(a.ranking_inferior) - Number(b.ranking_inferior))[0] ?? null;
}
