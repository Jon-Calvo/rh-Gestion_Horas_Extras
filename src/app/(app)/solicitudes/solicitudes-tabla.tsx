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
import { ObservacionBtn } from "@/components/solicitudes/observacion-btn";
import { createClient } from "@/lib/supabase/client";
import { armarCsvSolicitudes } from "@/lib/csv-solicitudes";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";

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
    { accessorKey: "cantidad_empleados", header: "Emp.", cell: (c) => <div className="text-right">{c.getValue<number>()}</div> },
    { accessorKey: "empleados_aprobados", header: "Aprob.", cell: (c) => <div className="text-right text-success font-medium">{c.getValue<number | undefined>() ?? "—"}</div> },
    { accessorKey: "empleados_rechazados", header: "Rech.", cell: (c) => { const v = c.getValue<number | undefined>(); return <div className={`text-right font-medium ${v ? "text-danger" : "text-muted"}`}>{v ?? "—"}</div>; } },
    { accessorKey: "total_horas_solicitud", header: "Horas", cell: (c) => <div className="text-right">{fmtHoras(c.getValue<number>())}</div> },
    { accessorKey: "horas_aprobadas", header: "Hs aprob.", cell: (c) => <div className="text-right text-success">{c.getValue<number | undefined>() === undefined ? "—" : fmtHoras(c.getValue<number>())}</div> },
    { accessorKey: "horas_rechazadas", header: "Hs rech.", cell: (c) => { const v = c.getValue<number | undefined>(); return <div className={`text-right ${v ? "text-danger" : "text-muted"}`}>{v === undefined ? "—" : fmtHoras(v)}</div>; } },
    { id: "obs", header: "Obs.", enableSorting: false, accessorFn: (r) => r.observacion ?? "", cell: (c) => <ObservacionBtn texto={c.row.original.observacion} titulo={`Observación · Solicitud ${c.row.original.numero ?? ""}`} /> },
    ...(verImportes ? [{ accessorKey: "total_importe_solicitud", header: "Importe", cell: (c: any) => <div className="text-right">{fmtImporte(c.getValue(), c.row.original.moneda)}</div> } as ColumnDef<SolicitudResumen>] : []),
  ], [zona, verImportes]);

  const toast = useToast();
  const [exportando, setExportando] = useState(false);
  const csv = async () => {
    setExportando(true);
    try {
      const contenido = await armarCsvSolicitudes(createClient(), datos, { zona, verImportes });
      const blob = new Blob([contenido], { type: "text/csv;charset=utf-8" });
      const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `solicitudes_detalle_${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(a.href);
    } catch (e) { toast("error", mensajeError(e)); } finally { setExportando(false); }
  };

  return (
    <>
      <div className="flex flex-col sm:flex-row gap-3 mb-4">
        <input className="input sm:max-w-xs" type="search" placeholder="Buscar por número, área, solicitante…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" />
        <select className="input sm:max-w-48" value={sit} onChange={(e) => setSit(e.target.value as Situacion | "")} aria-label="Filtrar por estado">
          <option value="">Todos los estados</option>{SITS.map((x) => <option key={x} value={x}>{SITUACION_LABEL[x]}</option>)}
        </select>
        <div className="flex-1" />
        {exportar && <button className="btn btn-secondary" onClick={csv} disabled={datos.length === 0 || exportando} title="Una fila por empleado, con horas e importes por banda horaria">{exportando ? <span className="spinner" /> : <Icon name="download" size={16} />} Exportar CSV (detalle)</button>}
      </div>
      {filas.length === 0 ? <Vacio titulo="No hay solicitudes para mostrar" detalle="Si esperabas ver alguna, revisá tu alcance de visibilidad con un administrador." />
        : <DataTable data={datos} columns={columns} filtroGlobal={q} onFila={(r) => router.push(`/solicitudes/${r.id}`)} vacio="Ninguna solicitud coincide con el filtro" />}
    </>
  );
}
