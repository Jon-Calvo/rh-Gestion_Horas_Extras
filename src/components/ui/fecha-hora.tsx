"use client";

import { minutosFueraDePaso } from "@/lib/limites";
export { SIN_LIMITES, limitesDe, avisoLimite, minutosFueraDePaso, type LimitesSolicitud } from "@/lib/limites";

const pad = (n: number) => String(n).padStart(2, "0");

/** Selector nativo de fecha y hora (datetime-local). Con paso > 1 se usa `step`: el navegador limita la lista de minutos
 *  del selector (p. ej. 00 y 30) y valida el valor. Valor: "YYYY-MM-DDTHH:mm" (hora local de la zona configurada) o "". */
export function CampoFechaHora({ value, onChange, paso, min, required, id }: { value: string; onChange: (v: string) => void; paso: number; min?: string; required?: boolean; id?: string }) {
  const fuera = minutosFueraDePaso(value, paso);
  // Con paso > 1 no se pasa `min`: el navegador lo usa como base de los pasos y un mínimo con minutos sueltos desalinearía la lista.
  return (
    <>
      <input id={id} className="input" type="datetime-local" required={required} min={paso > 1 ? undefined : min} step={paso > 1 ? paso * 60 : undefined}
        value={value} onChange={(e) => onChange(e.target.value)} aria-invalid={fuera || undefined} />
      {fuera && <p role="alert" className="text-xs mt-1" style={{ color: "var(--danger)" }}>Los minutos deben ser múltiplos de {paso} (00, {pad(paso)}…).</p>}
    </>
  );
}
