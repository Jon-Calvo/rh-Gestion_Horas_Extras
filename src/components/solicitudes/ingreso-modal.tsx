"use client";
import { useState } from "react";
import { Modal } from "@/components/ui/modal";
import { Campo } from "@/components/ui/misc";
import { localToIso, nowLocal } from "@/lib/format";
import type { EstadoAsistencia } from "@/lib/types";

const TITULO: Record<string, string> = { INGRESO_REGISTRADO: "Registrar ingreso", YA_ESTABA_EN_PLANTA: "Ya estaba en planta", NO_PRESENTADO: "No se presentó" };

export interface RegistroIngreso { se: string; nombre: string; resultado: EstadoAsistencia }

/** Ventana para registrar el control de ingreso: fecha y hora (solo cuando ingresó) y observación opcional. */
export function IngresoModal({ registro, zona, ocupado, onCerrar, onConfirmar }: {
  registro: RegistroIngreso | null; zona: string; ocupado: boolean; onCerrar: () => void;
  onConfirmar: (r: RegistroIngreso, fechaHoraIso: string, observacion: string) => void;
}) {
  return (
    <Modal abierto={!!registro} onCerrar={onCerrar} titulo={registro ? `${TITULO[registro.resultado] ?? "Control de ingreso"} · ${registro.nombre}` : ""}>
      {registro && <Form registro={registro} zona={zona} ocupado={ocupado} onCerrar={onCerrar} onConfirmar={onConfirmar} />}
    </Modal>
  );
}

function Form({ registro, zona, ocupado, onCerrar, onConfirmar }: { registro: RegistroIngreso; zona: string; ocupado: boolean; onCerrar: () => void; onConfirmar: (r: RegistroIngreso, iso: string, obs: string) => void }) {
  const [fecha, setFecha] = useState(() => nowLocal(zona));
  const [obs, setObs] = useState("");
  const conFecha = registro.resultado === "INGRESO_REGISTRADO";
  return (
    <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); onConfirmar(registro, conFecha ? localToIso(fecha, zona) : new Date().toISOString(), obs.trim()); }}>
      {conFecha && <Campo etiqueta="Fecha y hora de ingreso" ayuda={`Hora de ${zona}. Por defecto, el momento actual.`}><input className="input" type="datetime-local" required value={fecha} onChange={(e) => setFecha(e.target.value)} /></Campo>}
      <Campo etiqueta="Observación (opcional)" ayuda={`${obs.length}/1000`}><textarea className="input" rows={3} maxLength={1000} value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Ej.: ingresó por portería sur, llegó con retraso…" /></Campo>
      <div className="flex justify-end gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado}>{ocupado ? <span className="spinner" /> : "Confirmar"}</button></div>
    </form>
  );
}
