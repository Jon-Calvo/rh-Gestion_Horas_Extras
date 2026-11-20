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

/** true si los minutos del valor "YYYY-MM-DDTHH:mm" no son múltiplo del paso configurado. */
export function minutosFueraDePaso(valor: string, paso: number): boolean {
  return paso > 1 && valor !== "" && Number(valor.slice(14, 16)) % paso !== 0;
}
