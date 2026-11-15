"use client";
import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";

type Tipo = "ok" | "error" | "info";
interface T { id: number; tipo: Tipo; texto: string }
const Ctx = createContext<(tipo: Tipo, texto: string) => void>(() => {});
export const useToast = () => useContext(Ctx);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<T[]>([]);
  const push = useCallback((tipo: Tipo, texto: string) => {
    const id = Date.now() + Math.random();
    setItems((x) => [...x, { id, tipo, texto }]);
    setTimeout(() => setItems((x) => x.filter((i) => i.id !== id)), tipo === "error" ? 8000 : 4000);
  }, []);
  const caja = useRef<HTMLDivElement>(null);
  // Los formularios usan <dialog>.showModal(), que vive en la "capa superior" del navegador y tapa cualquier z-index.
  // Mostrar los avisos como popover los pone en esa misma capa, por encima del formulario abierto.
  useEffect(() => {
    const el = caja.current as (HTMLDivElement & { showPopover?: () => void; hidePopover?: () => void }) | null;
    if (!el?.showPopover) return;
    try {
      if (el.matches(":popover-open")) el.hidePopover?.();
      if (items.length > 0) el.showPopover();
    } catch { /* navegador sin soporte: queda el z-index normal */ }
  }, [items]);
  const color = { ok: "var(--success)", error: "var(--danger)", info: "var(--primary)" } as const;
  return (
    <Ctx.Provider value={push}>
      {children}
      <div ref={caja} {...({ popover: "manual" } as object)} className="fixed top-auto bottom-4 right-4 left-auto m-0 p-0 border-0 bg-transparent overflow-visible z-[100] flex-col gap-2 w-[calc(100%-2rem)] sm:w-96 [&:popover-open]:flex" role="status" aria-live="polite">
        {items.map((i) => (
          <div key={i.id} className="card fade-in px-4 py-3 text-sm flex gap-3 items-start" style={{ borderLeft: `4px solid ${color[i.tipo]}` }}>
            <span className="flex-1">{i.texto}</span>
            <button className="text-muted hover:text-fg" aria-label="Cerrar" onClick={() => setItems((x) => x.filter((k) => k.id !== i.id))}>✕</button>
          </div>
        ))}
      </div>
    </Ctx.Provider>
  );
}
