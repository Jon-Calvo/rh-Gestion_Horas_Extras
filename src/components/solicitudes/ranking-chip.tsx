import { fmtHoras } from "@/lib/format";
import { bandaPara } from "@/lib/ranking";
import type { BandaRanking } from "@/lib/types";

/** IB del empleado y su ranking con el color de la banda en la que está. */
export function IbRanking({ ib, ranking, bandas }: { ib: string | null | undefined; ranking: number | null | undefined; bandas: BandaRanking[] }) {
  const b = bandaPara(ranking, bandas, "solicitud");
  const color = b?.color ?? "var(--muted)";
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {ib && <span className="badge" style={{ background: "color-mix(in srgb, var(--muted) 16%, transparent)", color: "var(--text)" }}>{ib}</span>}
      {ranking !== null && ranking !== undefined && (
        <span className="badge" style={{ background: `color-mix(in srgb, ${color} 18%, transparent)`, color: "var(--text)", border: `1px solid color-mix(in srgb, ${color} 55%, transparent)` }} title={b ? `Banda de ranking: ${b.descripcion}` : "Sin banda de ranking"}>
          <span style={{ width: 8, height: 8, borderRadius: 99, background: color, flex: "none" }} />
          {fmtHoras(ranking)} h{b ? ` · ${b.descripcion}` : ""}
        </span>
      )}
      {!ib && (ranking === null || ranking === undefined) && <span className="text-muted">—</span>}
    </div>
  );
}
