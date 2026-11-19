import { localToIso } from "@/lib/format";

export interface EventoFichada { legajo: string; fecha_hora: string; tipo: "ENTRADA" | "SALIDA" }
export interface FichadasLeidas {
  periodoDesde: string; periodoHasta: string; // yyyy-mm-dd
  eventos: EventoFichada[]; legajos: number; entradas: number; salidas: number; avisos: string[];
}

const sinAcentos = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const FECHA = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/;
const HORA = /^(\d{1,2}):(\d{2})(?::\d{2})?$/;
const PERIODO = /(\d{1,2})\/(\d{1,2})\/(\d{4})\s*-\s*(\d{1,2})\/(\d{1,2})\/(\d{4})/;
const pad = (n: number | string) => String(n).padStart(2, "0");
const ymd = (d: string, m: string, y: string) => `${y}-${pad(m)}-${pad(d)}`;

/** Lee el Excel (.xls, .xlsx) o CSV del reloj a una matriz de texto. La librería se carga solo cuando se usa. */
export async function leerMatrizFichadas(file: Blob): Promise<string[][]> {
  const X = await import("@e965/xlsx");
  const wb = X.read(new Uint8Array(await file.arrayBuffer()), { type: "array", cellDates: false, raw: false });
  const ws = wb.Sheets[wb.SheetNames[0]];
  if (!ws) throw new Error("El archivo no tiene hojas.");
  return (X.utils.sheet_to_json(ws, { header: 1, raw: false, defval: "" }) as unknown[][]).map((f) => f.map((c) => String(c ?? "").trim()));
}

/**
 * Interpreta el listado del reloj: bloques por empleado ("N. Legajo" + número) seguidos de filas
 * (día, fecha dd/mm/aaaa, hora hh:mm, "Entrada"/"Salida"). Busca por contenido, no por posición fija.
 * `zona`: zona horaria de la empresa (las horas del reloj son locales).
 */
export function parsearFichadas(matriz: string[][], zona: string): FichadasLeidas {
  const avisos: string[] = [];
  const eventos: EventoFichada[] = [];
  const legajos = new Set<string>();
  let legajo: string | null = null;
  let desde: string | null = null, hasta: string | null = null;
  let sinLegajo = 0, horaMala = 0;

  for (let r = 0; r < matriz.length; r++) {
    const fila = matriz[r] ?? [];
    if (!desde) {
      for (const c of fila) { const m = PERIODO.exec(c ?? ""); if (m) { desde = ymd(m[1], m[2], m[3]); hasta = ymd(m[4], m[5], m[6]); break; } }
    }
    const iLeg = fila.findIndex((c) => { const t = sinAcentos(c ?? ""); return /^n[.°º]?\s*legajo$/.test(t) || t === "legajo"; });
    if (iLeg >= 0) {
      const v = fila.slice(iLeg + 1).find((c) => (c ?? "").trim() !== "");
      legajo = v ? v.trim() : null;
      if (legajo) legajos.add(legajo);
      continue;
    }
    const iF = fila.findIndex((c) => FECHA.test((c ?? "").trim()));
    if (iF < 0) continue;
    const resto = fila.slice(iF + 1).map((c) => (c ?? "").trim());
    const h = resto.find((c) => HORA.test(c));
    const tipoTxt = resto.map(sinAcentos).find((c) => c === "entrada" || c === "salida");
    if (!h || !tipoTxt) continue;
    if (!legajo) { sinLegajo++; continue; }
    const f = FECHA.exec(fila[iF].trim())!; const hm = HORA.exec(h)!;
    const dia = Number(f[1]), mes = Number(f[2]), hh = Number(hm[1]), mi = Number(hm[2]);
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31 || hh > 23 || mi > 59) { horaMala++; continue; }
    eventos.push({ legajo, fecha_hora: localToIso(`${ymd(f[1], f[2], f[3])}T${pad(hh)}:${pad(mi)}`, zona), tipo: tipoTxt === "entrada" ? "ENTRADA" : "SALIDA" });
  }

  if (eventos.length === 0) throw new Error("No encontré fichadas en el archivo. Esperaba el listado del reloj con «N. Legajo» y filas de fecha, hora y tipo de evento (Entrada/Salida).");
  if (sinLegajo) avisos.push(`${sinLegajo} fichada(s) aparecían antes de un «N. Legajo» y se ignoraron.`);
  if (horaMala) avisos.push(`${horaMala} fichada(s) con fecha u hora inválida se ignoraron.`);

  // Período: el del encabezado. Si falta, se deduce de las propias fechas (día local de cada evento).
  const diaLocal = (iso: string) => new Intl.DateTimeFormat("en-CA", { timeZone: zona, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
  const dias = eventos.map((e) => diaLocal(e.fecha_hora)).sort();
  if (!desde || !hasta) {
    desde = dias[0]; hasta = dias[dias.length - 1];
    avisos.push("El archivo no indica el período de evaluación: se tomó del primer al último día con fichadas. Si el reloj no registró nada el primer o el último día, esos días no figurarán como cubiertos.");
  } else if (dias[0] < desde || dias[dias.length - 1] > hasta) {
    throw new Error(`Hay fichadas fuera del período indicado en el encabezado (${desde} a ${hasta}). Revisá el archivo.`);
  }
  return { periodoDesde: desde, periodoHasta: hasta, eventos, legajos: legajos.size, entradas: eventos.filter((e) => e.tipo === "ENTRADA").length, salidas: eventos.filter((e) => e.tipo === "SALIDA").length, avisos };
}
