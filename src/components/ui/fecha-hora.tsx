"use client";
import { useEffect, useState } from "react";
import { localToIso } from "@/lib/format";

export { SIN_LIMITES, limitesDe, avisoLimite, type LimitesSolicitud } from "@/lib/limites";
import type { LimitesSolicitud } from "@/lib/limites";

const pad = (n: number) => String(n).padStart(2, "0");

/** Fecha + hora + minutos. Con paso 1 usa el selector nativo; con otro paso (5, 10, 15, 20, 30, 60) el minuto se elige de una lista.
 *  Valor: "YYYY-MM-DDTHH:mm" (hora local de la zona configurada) o "" si falta algún dato. */
export function CampoFechaHora({ value, onChange, paso, min, required, id }: { value: string; onChange: (v: string) => void; paso: number; min?: string; required?: boolean; id?: string }) {
  const [f0, h0] = value ? value.split("T") : ["", ""];
  const [fecha, setFecha] = useState(f0 ?? "");
  const [hh, setHh] = useState(h0 ? h0.slice(0, 2) : "");
  const [mm, setMm] = useState(h0 ? h0.slice(3, 5) : "");
  // Si el valor cambia desde afuera (ej.: se limpia el formulario), se sincroniza.
  useEffect(() => {
    if (!value) return;
    const [f, h] = value.split("T");
    setFecha(f); setHh(h.slice(0, 2)); setMm(h.slice(3, 5));
  }, [value]);

  if (paso <= 1) return <input id={id} className="input" type="datetime-local" required={required} min={min} value={value} onChange={(e) => onChange(e.target.value)} />;

  const emitir = (f: string, h: string, m: string) => onChange(f && h !== "" && m !== "" ? `${f}T${h}:${m}` : "");
  const minutos: string[] = [];
  for (let m = 0; m < 60; m += paso) minutos.push(pad(m));
  // Un horario viejo con un minuto fuera del paso no se pierde: se muestra como opción adicional (la base lo rechazará si se guarda).
  if (mm !== "" && !minutos.includes(mm)) minutos.push(mm);
  return (
    <div className="flex gap-2">
      <input id={id} className="input flex-1 min-w-0" type="date" required={required} min={min ? min.slice(0, 10) : undefined} value={fecha}
        onChange={(e) => { setFecha(e.target.value); emitir(e.target.value, hh, mm); }} />
      <select aria-label="Hora" className="input w-[4.5rem] px-2" required={required} value={hh} onChange={(e) => { setHh(e.target.value); emitir(fecha, e.target.value, mm); }}>
        <option value="">hh</option>{Array.from({ length: 24 }, (_, i) => pad(i)).map((h) => <option key={h} value={h}>{h}</option>)}
      </select>
      <select aria-label="Minutos" className="input w-[4.5rem] px-2" required={required} value={mm} onChange={(e) => { setMm(e.target.value); emitir(fecha, hh, e.target.value); }}>
        <option value="">mm</option>{minutos.map((m) => <option key={m} value={m}>{m}</option>)}
      </select>
    </div>
  );
}
