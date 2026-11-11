"use client";
import { useState } from "react";
import Link from "next/link";
import { fmtFechaHora } from "@/lib/format";
import { Badge } from "@/components/ui/misc";

interface F { id: string; fecha_hora: string; usuario_id: string | null; origen: string; modulo: string; entidad_tipo: string; entidad_id: string | null; evento: string; estado_anterior: string | null; estado_nuevo: string | null; datos: unknown }

export function AuditoriaTabla({ filas, nombres, zona }: { filas: F[]; nombres: Record<string, string>; zona: string }) {
  const [q, setQ] = useState(""); const [abierta, setAbierta] = useState<string | null>(null);
  const v = filas.filter((f) => !q || `${f.evento} ${f.modulo} ${f.entidad_tipo} ${nombres[f.usuario_id ?? ""] ?? ""}`.toLowerCase().includes(q.toLowerCase()));
  return (
    <>
      <input className="input sm:max-w-xs mb-4" type="search" placeholder="Filtrar por evento, módulo o usuario…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Filtrar" />
      <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Fecha</th><th>Usuario</th><th>Evento</th><th>Entidad</th><th>Cambio de estado</th></tr></thead>
        <tbody>{v.length === 0 ? <tr><td colSpan={5} className="text-center text-muted py-8">Sin eventos</td></tr> : v.map((f) => (
          <><tr key={f.id} className="cursor-pointer" onClick={() => setAbierta(abierta === f.id ? null : f.id)}>
            <td className="whitespace-nowrap">{fmtFechaHora(f.fecha_hora, zona)}</td>
            <td>{f.usuario_id ? nombres[f.usuario_id] ?? "—" : <Badge>Sistema</Badge>}</td>
            <td className="font-medium">{f.evento}</td>
            <td>{f.entidad_tipo}{f.entidad_tipo === "solicitud" && f.entidad_id && <> · <Link className="underline" href={`/solicitudes/${f.entidad_id}`} onClick={(e) => e.stopPropagation()}>ver</Link></>}</td>
            <td>{f.estado_anterior || f.estado_nuevo ? `${f.estado_anterior ?? "—"} → ${f.estado_nuevo ?? "—"}` : "—"}</td></tr>
          {abierta === f.id && <tr key={f.id + "d"}><td colSpan={5}><pre className="text-xs overflow-x-auto p-2 rounded" style={{ background: "var(--surface-2)" }}>{JSON.stringify(f.datos, null, 2)}</pre></td></tr>}</>))}</tbody></table></div></div>
    </>
  );
}
