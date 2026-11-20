"use client";
import { useRouter } from "next/navigation";
import { sumarMeses } from "@/lib/kpis";

export function SelectorMes({ mes, actual, tipo, conTipo }: { mes: string; actual: string; tipo: string | null; conTipo: boolean }) {
  const router = useRouter();
  const url = (m: string, t: string | null) => { const p = new URLSearchParams(); if (m !== actual) p.set("mes", m); if (t) p.set("tipo", t); const q = p.toString(); return q ? `/estadisticas?${q}` : "/estadisticas"; };
  const ir = (m: string) => { if (/^\d{4}-\d{2}$/.test(m)) router.push(url(m, tipo)); };
  return (
    <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Filtros de estadísticas">
      {conTipo && <select className="input !w-44" value={tipo ?? ""} aria-label="Tipo de empleado" onChange={(e) => router.push(url(mes, e.target.value || null))}>
        <option value="">Jornal y mensual</option><option value="JORNAL">Solo jornal</option><option value="MENSUAL">Solo mensual</option>
      </select>}
      <button className="btn btn-secondary btn-sm" aria-label="Mes anterior" onClick={() => ir(sumarMeses(mes, -1))}>◀</button>
      <input className="input !w-40" type="month" value={mes} max={actual} onChange={(e) => ir(e.target.value)} aria-label="Elegir mes" />
      <button className="btn btn-secondary btn-sm" aria-label="Mes siguiente" disabled={mes >= actual} onClick={() => ir(sumarMeses(mes, 1))}>▶</button>
      <button className="btn btn-ghost btn-sm" disabled={mes === actual} onClick={() => ir(actual)}>Mes actual</button>
    </div>
  );
}
