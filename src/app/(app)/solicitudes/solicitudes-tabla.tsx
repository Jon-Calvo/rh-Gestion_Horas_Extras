"use client";
import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/ui/data-table";
import { SituacionBadge, Vacio } from "@/components/ui/misc";
import { SITUACION_LABEL, type Situacion, type SolicitudResumen } from "@/lib/types";
import { fmtFechaHora, fmtHoras, fmtImporte } from "@/lib/format";
import { Icon } from "@/components/layout/icons";

const SITS: Situacion[] = ["BORRADOR", "EN_APROBACION", "APROBADA", "RECHAZADA", "FINALIZADA", "CANCELADA"];

export function SolicitudesTabla({ filas, zona, verImportes, exportar }: { filas: SolicitudResumen[]; zona: string; verImportes: boolean; exportar: boolean }) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [sit, setSit] = useState<"" | Situacion>("");
  const datos = useMemo(() => filas.filter((f) => !sit || f.situacion === sit), [filas, sit]);

  const columns = useMemo<ColumnDef<SolicitudResumen>[]>(() => [
    { accessorKey: "numero", header: "N.º", cell: (c) => <Link href={`/solicitudes/${c.row.original.id}`} className="font-semibold text-primary" onClick={(e) => e.stopPropagation()}>{c.getValue<string>() ?? "—"}</Link> },
    { accessorKey: "situacion", header: "Estado", cell: (c) => <SituacionBadge situacion={c.getValue<Situacion>()} /> },
    { id: "alcance", header: "Área / sector / proceso", accessorFn: (r) => `${r.area_nombre} ${r.sector_nombre} ${r.proceso_nombre}`, cell: (c) => <div>{c.row.original.area_nombre}<div className="text-xs text-muted">{c.row.original.sector_nombre} · {c.row.original.proceso_nombre}</div></div> },
    { accessorKey: "motivo_nombre", header: "Motivo" },
    { accessorKey: "fecha_hora_inicio", header: "Inicio", cell: (c) => fmtFechaHora(c.getValue<string>(), zona) },
    { accessorKey: "solicitante_nombre", header: "Solicitante" },
    { accessorKey: "cantidad_empleados", header: "Emp.", meta: undefined, cell: (c) => <div className="text-right">{c.getValue<number>()}</div> },
    { accessorKey: "total_horas_solicitud", header: "Horas", cell: (c) => <div className="text-right">{fmtHoras(c.getValue<number>())}</div> },
    ...(verImportes ? [{ accessorKey: "total_importe_solicitud", header: "Importe", cell: (c: any) => <div className="text-right">{fmtImporte(c.getValue(), c.row.original.moneda)}</div> } as ColumnDef<SolicitudResumen>] : []),
  ], [zona, verImportes]);

  const csv = () => {
    const cab = ["Numero", "Estado", "Area", "Sector", "Proceso", "Motivo", "Inicio", "Fin", "Solicitante", "Empleados", "Horas", ...(verImportes ? ["Moneda", "Importe"] : [])];
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const lineas = datos.map((r) => [r.numero, SITUACION_LABEL[r.situacion], r.area_nombre, r.sector_nombre, r.proceso_nombre, r.motivo_nombre, fmtFechaHora(r.fecha_hora_inicio, zona), fmtFechaHora(r.fecha_hora_fin, zona), r.solicitante_nombre, r.cantidad_empleados, r.total_horas_solicitud, ...(verImportes ? [r.moneda, r.total_importe_solicitud] : [])].map(esc).join(";"));
    const blob = new Blob(["﻿" + [cab.map(esc).join(";"), ...lineas].join("\r\n")], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `solicitudes_${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(a.href);
  };

  return (
    <>
      <div className="flex flex-col sm:flex-row gap-3 mb-4">
        <input className="input sm:max-w-xs" type="search" placeholder="Buscar por número, área, solicitante…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" />
        <select className="input sm:max-w-48" value={sit} onChange={(e) => setSit(e.target.value as Situacion | "")} aria-label="Filtrar por estado">
          <option value="">Todos los estados</option>{SITS.map((x) => <option key={x} value={x}>{SITUACION_LABEL[x]}</option>)}
        </select>
        <div className="flex-1" />
        {exportar && <button className="btn btn-secondary" onClick={csv} disabled={datos.length === 0}><Icon name="download" size={16} /> Exportar CSV</button>}
      </div>
      {filas.length === 0 ? <Vacio titulo="No hay solicitudes para mostrar" detalle="Si esperabas ver alguna, revisá tu alcance de visibilidad con un administrador." />
        : <DataTable data={datos} columns={columns} filtroGlobal={q} onFila={(r) => router.push(`/solicitudes/${r.id}`)} vacio="Ninguna solicitud coincide con el filtro" />}
    </>
  );
}
