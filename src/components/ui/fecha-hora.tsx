"use client";
import { useEffect, useState } from "react";
import { localToIso } from "@/lib/format";

export interface LimitesSolicitud { paso: number; horasMax: number | null }
export const SIN_LIMITES: LimitesSolicitud = { paso: 1, horasMax: null };

/** Límites configurables de las solicitudes a partir de la configuración general (tolerante si la migración 0005 no está aplicada). */
export function limitesDe(cfg: { minutos_intervalo?: number | null; horas_maximas_solicitud?: number | string | null } | null | undefined): LimitesSolicitud {
  const paso = Number(cfg?.minutos_intervalo ?? 1);
  const hm = cfg?.horas_maximas_solicitud;
  return { paso: [1, 5, 10, 15, 20, 30, 60].includes(paso) ? paso : 1, horasMax: hm == null || hm === "" || Number(hm) <= 0 ? null : Number(hm) };
}

/** Aviso (no bloquea: la base valida igual) si el rango pedido supera el máximo de horas seguidas. */
export function avisoLimite(ini: string, fin: string, zona: string, horasMax: number | null): string | null {
  if (!horasMax || !ini || !fin) return null;
  const h = (new Date(localToIso(fin, zona)).getTime() - new Date(localToIso(ini, zona)).getTime()) / 3600000;
  if (h > horasMax + 1e-9) return `La solicitud dura ${String(Math.round(h * 100) / 100).replace(".", ",")} h y el máximo permitido es ${String(horasMax).replace(".", ",")} h seguidas.`;
  return null;
}

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
