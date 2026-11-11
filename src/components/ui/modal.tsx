"use client";
import { useEffect, useRef } from "react";

export function Modal({ abierto, onCerrar, titulo, children, ancho }: { abierto: boolean; onCerrar: () => void; titulo: string; children: React.ReactNode; ancho?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current; if (!d) return;
    if (abierto && !d.open) d.showModal();
    if (!abierto && d.open) d.close();
  }, [abierto]);
  return (
    <dialog ref={ref} className={`modal ${ancho ? "wide" : ""}`} onClose={onCerrar} onClick={(e) => { if (e.target === ref.current) onCerrar(); }}>
      {abierto && (
        <div className="flex flex-col max-h-[90vh]">
          <div className="flex items-center justify-between px-5 py-4 border-b">
            <h2 className="font-semibold text-base">{titulo}</h2>
            <button className="btn btn-ghost btn-sm" onClick={onCerrar} aria-label="Cerrar">✕</button>
          </div>
          <div className="p-5 overflow-y-auto">{children}</div>
        </div>
      )}
    </dialog>
  );
}
