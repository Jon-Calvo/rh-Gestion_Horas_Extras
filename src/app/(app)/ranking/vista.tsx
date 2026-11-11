"use client";
import { useMemo, useState } from "react";
import { Badge, Vacio } from "@/components/ui/misc";
import { fmtFechaHora, fmtHoras } from "@/lib/format";
import { bandaPara } from "@/lib/ranking";
import type { BandaRanking, EmpleadoResumen } from "@/lib/types";
import type { Historico, Rectificacion } from "./page";

export function RankingVista({ empleados, bandas, historico, rectificaciones, nombres, usuarios, esAdmin, zona, ultimoReseteo }: {
  empleados: EmpleadoResumen[]; bandas: BandaRanking[]; historico: Historico[]; rectificaciones: Rectificacion[]; nombres: Record<string, string>; usuarios: Record<string, string>; esAdmin: boolean; zona: string; ultimoReseteo: string | null;
}) {
  const [tab, setTab] = useState<"vigente" | "historico" | "rect">("vigente");
  const [q, setQ] = useState("");
  const filas = useMemo(() => empleados.filter((e) => !q || `${e.nombre_completo} ${e.legajo} ${e.area_nombre ?? ""}`.toLowerCase().includes(q.toLowerCase())), [empleados, q]);
  const max = Math.max(1, ...empleados.map((e) => Number(e.ranking_horas)));
  const tabs = [{ k: "vigente" as const, t: "Ranking vigente" }, ...(esAdmin ? [{ k: "historico" as const, t: "Histórico de períodos" }, { k: "rect" as const, t: "Rectificaciones" }] : [])];

  return (
    <>
      <div className="flex flex-wrap gap-2 mb-4" role="tablist">
        {tabs.map((x) => <button key={x.k} role="tab" aria-selected={tab === x.k} onClick={() => setTab(x.k)} className={`btn btn-sm ${tab === x.k ? "btn-primary" : "btn-secondary"}`}>{x.t}</button>)}
      </div>
      {tab === "vigente" && <>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mb-4 text-xs">
          {bandas.filter((b) => b.aplica_a_solicitud).map((b) => <span key={b.id} className="inline-flex items-center gap-1.5"><span style={{ width: 10, height: 10, borderRadius: 3, background: b.color }} />{b.descripcion} ({fmtHoras(b.ranking_inferior)}{b.ranking_superior === null ? "+" : `–${fmtHoras(b.ranking_superior)}`}){b.bloqueo_seleccion === "BLOQUEADO" ? " · bloqueada" : b.bloqueo_seleccion === "ADVERTENCIA" ? " · advertencia" : ""}</span>)}
          {ultimoReseteo && <span className="text-muted ml-auto">Último reseteo: {fmtFechaHora(ultimoReseteo, zona)}</span>}
        </div>
        <input className="input sm:max-w-xs mb-4" type="search" placeholder="Buscar empleado…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" />
        {filas.length === 0 ? <Vacio titulo="Sin empleados" /> : (
          <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="tbl"><thead><tr><th>#</th><th>Empleado</th><th>Área</th><th style={{ minWidth: 220 }}>Horas (según solicitud)</th><th className="text-right">Ranking real</th></tr></thead>
            <tbody>{filas.slice(0, 500).map((e, i) => { const b = bandaPara(e.ranking_horas, bandas, "solicitud"); const br = bandaPara(e.ranking_horas_real, bandas, "real");
              return (<tr key={e.id}><td className="text-muted">{i + 1}</td><td>{e.nombre_completo}<div className="text-xs text-muted">{e.legajo}</div></td><td>{e.area_nombre ?? "—"}</td>
                <td><div className="flex items-center gap-2"><div className="h-2 rounded-full flex-1" style={{ background: "var(--surface-2)" }}><div className="h-2 rounded-full" style={{ width: `${(Number(e.ranking_horas) / max) * 100}%`, background: b?.color ?? "var(--primary)" }} /></div><span className="w-16 text-right font-medium">{fmtHoras(e.ranking_horas)}</span></div></td>
                <td className="text-right">{e.ranking_horas_real === null ? "—" : <span style={{ color: br?.color }}>{fmtHoras(e.ranking_horas_real)}</span>}</td></tr>); })}</tbody></table></div></div>)}
      </>}
      {tab === "historico" && (historico.length === 0 ? <Vacio titulo="Todavía no hay períodos cerrados" detalle="Al resetear el ranking, las horas finales de cada empleado quedan guardadas acá." /> :
        <div className="card overflow-x-auto"><table className="tbl"><thead><tr><th>Cierre</th><th>Empleado</th><th className="text-right">Horas finales</th></tr></thead><tbody>{historico.map((h) => <tr key={h.id}><td>{fmtFechaHora(h.fecha_reseteo, zona)}</td><td>{nombres[h.empleado_id] ?? h.empleado_id.slice(0, 8)}</td><td className="text-right">{fmtHoras(h.ranking_horas_final)}</td></tr>)}</tbody></table></div>)}
      {tab === "rect" && (rectificaciones.length === 0 ? <Vacio titulo="Sin rectificaciones" detalle="Las correcciones de horas de solicitudes finalizadas se registran desde el detalle de cada solicitud." /> :
        <div className="card overflow-x-auto"><table className="tbl"><thead><tr><th>Fecha</th><th>Empleado</th><th className="text-right">Descontadas</th><th className="text-right">Antes → después</th><th>Motivo</th><th>Por</th></tr></thead>
          <tbody>{rectificaciones.map((r) => <tr key={r.id}><td>{fmtFechaHora(r.created_at, zona)}</td><td>{nombres[r.empleado_id] ?? r.empleado_id.slice(0, 8)}</td><td className="text-right"><Badge tono="rojo">−{fmtHoras(r.horas_descontadas)}</Badge></td><td className="text-right">{fmtHoras(r.ranking_antes)} → {fmtHoras(r.ranking_despues)}</td><td className="max-w-xs">{r.motivo}</td><td>{usuarios[r.usuario_id] ?? "—"}</td></tr>)}</tbody></table></div>)}
    </>
  );
}
