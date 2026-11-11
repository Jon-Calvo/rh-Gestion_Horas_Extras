"use client";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { fmtHoras } from "@/lib/format";
import { bandaPara } from "@/lib/ranking";
import type { BandaRanking, EmpleadoResumen } from "@/lib/types";

export function EmployeePicker({ bandas, excluir, onElegir, ocupado, etiquetaBoton = "Elegir" }: { bandas: BandaRanking[]; excluir: string[]; onElegir: (e: EmpleadoResumen) => void; ocupado?: boolean; etiquetaBoton?: string }) {
  const [q, setQ] = useState("");
  const [filas, setFilas] = useState<EmpleadoResumen[]>([]);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(async () => {
      setCargando(true); setError(null);
      let qb = createClient().from("vista_empleados_resumen").select("*").eq("estado", "ACTIVO").order("nombre_completo").limit(25);
      const txt = q.trim().replace(/[%,()]/g, " ");
      if (txt) qb = qb.or(`legajo.ilike.%${txt}%,nombre_completo.ilike.%${txt}%`);
      const { data, error } = await qb;
      if (error) setError(error.message);
      setFilas(((data ?? []) as EmpleadoResumen[]).filter((e) => !excluir.includes(e.id)));
      setCargando(false);
    }, 250);
    return () => clearTimeout(t);
  }, [q, excluir]);

  return (
    <div>
      <input className="input" autoFocus type="search" placeholder="Buscar por legajo o nombre…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar empleado" />
      <div className="mt-3 border rounded-xl divide-y max-h-80 overflow-y-auto">
        {cargando && <div className="p-4 text-sm text-muted flex gap-2"><span className="spinner" /> Buscando…</div>}
        {!cargando && error && <div className="p-4 text-sm" style={{ color: "var(--danger)" }}>{error}</div>}
        {!cargando && !error && filas.length === 0 && <div className="p-4 text-sm text-muted">Sin resultados.</div>}
        {filas.map((e) => {
          const b = bandaPara(e.ranking_horas, bandas, "solicitud");
          return (
            <div key={e.id} className="flex items-center gap-3 p-3">
              <div className="min-w-0 flex-1">
                <div className="font-medium text-sm truncate">{e.nombre_completo} <span className="text-muted font-normal">· {e.legajo}</span></div>
                <div className="text-xs text-muted truncate">{[e.area_nombre, e.sector_nombre, e.proceso_nombre].filter(Boolean).join(" · ") || "Sin área"} · {e.categoria_codigo}</div>
              </div>
              <div className="text-right text-xs">
                <div className="font-semibold">{fmtHoras(e.ranking_horas)} h</div>
                {b && <div style={{ color: b.color }}>{b.descripcion}{b.bloqueo_seleccion === "BLOQUEADO" ? " (bloqueado)" : ""}</div>}
              </div>
              <button className="btn btn-primary btn-sm" disabled={ocupado || b?.bloqueo_seleccion === "BLOQUEADO"} onClick={() => onElegir(e)}>{etiquetaBoton}</button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
