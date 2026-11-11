"use client";
import { useEffect, useState } from "react";
import { Modal } from "@/components/ui/modal";

/** Modal que pide un motivo obligatorio (rechazar, cancelar, reabrir). */
export function PromptModal({ abierto, titulo, etiqueta, confirmar, peligro, ocupado, onCerrar, onConfirmar }: {
  abierto: boolean; titulo: string; etiqueta: string; confirmar: string; peligro?: boolean; ocupado?: boolean; onCerrar: () => void; onConfirmar: (texto: string) => void;
}) {
  const [t, setT] = useState("");
  useEffect(() => { if (abierto) setT(""); }, [abierto]);
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo={titulo}>
      <form onSubmit={(e) => { e.preventDefault(); if (t.trim()) onConfirmar(t.trim()); }} className="space-y-4">
        <label className="block"><span className="label">{etiqueta}</span><textarea className="input" rows={3} required autoFocus value={t} onChange={(e) => setT(e.target.value)} /></label>
        <div className="flex justify-end gap-2">
          <button type="button" className="btn btn-secondary" onClick={onCerrar}>Volver</button>
          <button className={`btn ${peligro ? "btn-danger" : "btn-primary"}`} disabled={!t.trim() || ocupado}>{ocupado ? <span className="spinner" /> : confirmar}</button>
        </div>
      </form>
    </Modal>
  );
}
