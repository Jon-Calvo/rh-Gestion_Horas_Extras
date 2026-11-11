"use client";
import type { Area, Sector, Proceso } from "@/lib/types";

export interface Scope { area_id: string; sector_id: string; proceso_id: string }

/** Selectores en cascada Área → Sector → Proceso. */
export function ScopeSelect({ value, onChange, areas, sectores, procesos, disabled, requerido = true }: {
  value: Scope; onChange: (s: Scope) => void; areas: Area[]; sectores: Sector[]; procesos: Proceso[]; disabled?: boolean; requerido?: boolean;
}) {
  const secs = sectores.filter((s) => s.area_id === value.area_id && s.activo);
  const procs = procesos.filter((p) => p.sector_id === value.sector_id && p.activo);
  return (
    <div className="grid gap-3 sm:grid-cols-3">
      <label><span className="label">Área</span>
        <select className="input" required={requerido} disabled={disabled} value={value.area_id} onChange={(e) => onChange({ area_id: e.target.value, sector_id: "", proceso_id: "" })}>
          <option value="">Seleccionar…</option>{areas.filter((a) => a.activo).map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}
        </select></label>
      <label><span className="label">Sector</span>
        <select className="input" required={requerido} disabled={disabled || !value.area_id} value={value.sector_id} onChange={(e) => onChange({ ...value, sector_id: e.target.value, proceso_id: "" })}>
          <option value="">Seleccionar…</option>{secs.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
        </select></label>
      <label><span className="label">Proceso</span>
        <select className="input" required={requerido} disabled={disabled || !value.sector_id} value={value.proceso_id} onChange={(e) => onChange({ ...value, proceso_id: e.target.value })}>
          <option value="">Seleccionar…</option>{procs.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
        </select></label>
    </div>
  );
}
