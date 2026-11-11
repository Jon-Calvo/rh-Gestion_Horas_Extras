"use client";
import { createContext, useCallback, useContext, useState } from "react";

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
  const color = { ok: "var(--success)", error: "var(--danger)", info: "var(--primary)" } as const;
  return (
    <Ctx.Provider value={push}>
      {children}
      <div className="fixed bottom-4 right-4 left-4 sm:left-auto z-[100] flex flex-col gap-2 sm:w-96" role="status" aria-live="polite">
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
