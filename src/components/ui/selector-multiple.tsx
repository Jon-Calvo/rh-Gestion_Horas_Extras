"use client";
import { useMemo, useState } from "react";

export interface OpcionMultiple { id: string; label: string; grupo?: string }

/** Selección múltiple con etiquetas, buscador y casillas agrupadas. */
export function SelectorMultiple({ opciones, seleccion, onChange, etiqueta, singular }: {
  opciones: OpcionMultiple[]; seleccion: string[]; onChange: (ids: string[]) => void; etiqueta: string; singular: string;
}) {
  const [q, setQ] = useState("");
  const sel = useMemo(() => new Set(seleccion), [seleccion]);
  const porId = useMemo(() => new Map(opciones.map((o) => [o.id, o])), [opciones]);
  const visibles = useMemo(() => {
    const n = q.trim().toLowerCase();
    return opciones.filter((o) => !n || `${o.grupo ?? ""} ${o.label}`.toLowerCase().includes(n));
  }, [opciones, q]);
  const grupos = useMemo(() => {
    const m = new Map<string, OpcionMultiple[]>();
    for (const o of visibles) { const g = o.grupo ?? ""; const l = m.get(g); if (l) l.push(o); else m.set(g, [o]); }
    return [...m.entries()].sort(([a], [b]) => a.localeCompare(b, "es"));
  }, [visibles]);
  const alternar = (id: string) => onChange(sel.has(id) ? seleccion.filter((x) => x !== id) : [...seleccion, id]);
  const todosVisibles = () => onChange([...new Set([...seleccion, ...visibles.map((o) => o.id)])]);

  return (
    <div className="space-y-2 min-w-0">
      <div className="flex flex-wrap gap-1.5" aria-live="polite">
        {seleccion.length === 0 && <span className="text-xs text-muted">Ningún {singular} elegido todavía.</span>}
        {seleccion.map((id) => (
          <span key={id} className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary)" }}>
            {porId.get(id)?.label ?? "(ya no existe)"}
            <button type="button" className="opacity-70 hover:opacity-100 leading-none" aria-label={`Quitar ${porId.get(id)?.label ?? singular}`} onClick={() => alternar(id)}>×</button>
          </span>
        ))}
      </div>
      <div className="rounded-lg border overflow-hidden">
        <div className="flex flex-wrap gap-2 p-2 border-b">
          <input className="input flex-1 min-w-32" type="search" placeholder={`Buscar ${singular}…`} aria-label={`Buscar ${etiqueta}`} value={q} onChange={(e) => setQ(e.target.value)} />
          <button type="button" className="btn btn-secondary btn-sm" onClick={todosVisibles} disabled={visibles.length === 0}>{q ? "Elegir los encontrados" : "Elegir todos"}</button>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange([])} disabled={seleccion.length === 0}>Limpiar</button>
        </div>
        <div className="max-h-56 overflow-auto py-1">
          {grupos.length === 0 && <div className="text-xs text-muted px-3 py-3">Sin resultados</div>}
          {grupos.map(([g, ops]) => (
            <div key={g}>
              {g && <div className="px-3 pt-2 pb-1 text-[11px] uppercase tracking-wide text-muted">{g}</div>}
              {ops.map((o) => (
                <label key={o.id} className="flex items-center gap-2 px-3 py-1.5 text-sm cursor-pointer hover:bg-black/5 dark:hover:bg-white/5">
                  <input type="checkbox" checked={sel.has(o.id)} onChange={() => alternar(o.id)} /> {o.label}
                </label>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
