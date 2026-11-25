"use client";
import { useMemo, useState } from "react";

export type DirOrden = "asc" | "desc";
export interface EstadoOrden { clave: string | null; dir: DirOrden }

/** Orden por encabezado: clic = ascendente, otro clic = descendente, otro = vuelve al orden original. */
export function useOrden<T>(filas: T[], valor: (fila: T, clave: string) => string | number | null | undefined, inicial?: EstadoOrden) {
  const [o, setO] = useState<EstadoOrden>(inicial ?? { clave: null, dir: "asc" });
  const alternar = (clave: string) => setO((x) => x.clave !== clave ? { clave, dir: "asc" } : x.dir === "asc" ? { clave, dir: "desc" } : { clave: null, dir: "asc" });
  const ordenadas = useMemo(() => {
    if (!o.clave) return filas;
    const k = o.clave, sgn = o.dir === "asc" ? 1 : -1;
    return [...filas].sort((a, b) => {
      const va = valor(a, k), vb = valor(b, k);
      const na = va === null || va === undefined || va === "", nb = vb === null || vb === undefined || vb === "";
      if (na || nb) return na && nb ? 0 : na ? 1 : -1; // vacíos siempre al final
      if (typeof va === "number" && typeof vb === "number") return (va - vb) * sgn;
      return String(va).localeCompare(String(vb), "es", { numeric: true, sensitivity: "base" }) * sgn;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filas, o]);
  return { ordenadas, orden: o, alternar };
}

/** Encabezado de columna ordenable (accesible por teclado). */
export function ThOrden({ clave, orden, alternar, children, className }: { clave: string; orden: EstadoOrden; alternar: (k: string) => void; children: React.ReactNode; className?: string }) {
  const dir = orden.clave === clave ? orden.dir : null;
  return (
    <th aria-sort={dir === "asc" ? "ascending" : dir === "desc" ? "descending" : "none"} className={className}>
      <button type="button" className="inline-flex items-center gap-1 font-inherit cursor-pointer select-none hover:underline" onClick={() => alternar(clave)} title="Ordenar">
        {children}<span aria-hidden className="text-xs opacity-70 w-3 inline-block">{dir === "asc" ? "↑" : dir === "desc" ? "↓" : ""}</span>
      </button>
    </th>
  );
}
