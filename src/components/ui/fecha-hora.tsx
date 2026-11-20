"use client";

import { minutosFueraDePaso } from "@/lib/limites";
export { SIN_LIMITES, limitesDe, avisoLimite, minutosFueraDePaso, type LimitesSolicitud } from "@/lib/limites";

const BASE_PASOS = "2000-01-01T00:00";
const pad = (n: number) => String(n).padStart(2, "0");

/** Selector nativo de fecha y hora (datetime-local). Con paso > 1 se usa `step`: el navegador limita la lista de minutos
 *  del selector (p. ej. 00 y 30) y valida el valor. Valor: "YYYY-MM-DDTHH:mm" (hora local de la zona configurada) o "". */
export function CampoFechaHora({ value, onChange, paso, min, required, id }: { value: string; onChange: (v: string) => void; paso: number; min?: string; required?: boolean; id?: string }) {
  const fuera = minutosFueraDePaso(value, paso);
  // El navegador calcula los pasos a partir de `min` (o, si falta, del valor actual: por eso salían 27 y 57). Con paso > 1 se fija una base en minuto 00 para que la lista sea 00, 30 / 00, 20, 40, etc.
  return (
    <>
      <input id={id} className="input" type="datetime-local" required={required} min={paso > 1 ? BASE_PASOS : min} step={paso > 1 ? paso * 60 : undefined}
        value={value} onChange={(e) => onChange(e.target.value)} aria-invalid={fuera || undefined} />
      {fuera && <p role="alert" className="text-xs mt-1" style={{ color: "var(--danger)" }}>Los minutos deben ser múltiplos de {paso} (00, {pad(paso)}…).</p>}
    </>
  );
}
