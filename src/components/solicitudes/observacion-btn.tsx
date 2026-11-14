"use client";
import { useState } from "react";
import { Modal } from "@/components/ui/modal";

/** Botón compacto que abre la observación completa en una ventana (no ocupa espacio en la tabla). */
export function ObservacionBtn({ texto, titulo = "Observación" }: { texto: string | null | undefined; titulo?: string }) {
  const [abierto, setAbierto] = useState(false);
  if (!texto || !texto.trim()) return <span className="text-muted" aria-label="Sin observación">—</span>;
  return (
    <>
      <button type="button" className="btn btn-ghost btn-sm" title="Ver observación" onClick={(e) => { e.stopPropagation(); setAbierto(true); }}>💬 Ver</button>
      <div onClick={(e) => e.stopPropagation()}><Modal abierto={abierto} onCerrar={() => setAbierto(false)} titulo={titulo}><p className="whitespace-pre-wrap text-sm">{texto}</p></Modal></div>
    </>
  );
}

/** "3 empleados · 2 aprobados · 1 rechazado" con las horas, para encabezados de tarjetas. */
export function ResumenEstados({ s }: { s: { cantidad_empleados: number; empleados_aprobados?: number; empleados_rechazados?: number; empleados_pendientes?: number } }) {
  const a = s.empleados_aprobados, r = s.empleados_rechazados, p = s.empleados_pendientes;
  if (a === undefined) return <>{s.cantidad_empleados} empleado(s)</>;
  return <>{s.cantidad_empleados} empleado(s): <b className="text-success">{a} aprob.</b>{" · "}<b className="text-danger">{r} rech.</b>{" · "}<b className="text-warning">{p} pend.</b></>;
}
