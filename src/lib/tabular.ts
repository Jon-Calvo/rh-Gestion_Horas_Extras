import readXlsxFile from "read-excel-file";

export const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");

export function parseCsv(txt: string): string[][] {
  txt = txt.replace(/^﻿/, "");
  const sep = (txt.split("\n")[0].match(/;/g)?.length ?? 0) >= (txt.split("\n")[0].match(/,/g)?.length ?? 0) ? ";" : ",";
  const out: string[][] = []; let fila: string[] = []; let cel = ""; let q = false;
  for (let i = 0; i < txt.length; i++) {
    const c = txt[i];
    if (q) { if (c === '"') { if (txt[i + 1] === '"') { cel += '"'; i++; } else q = false; } else cel += c; }
    else if (c === '"') q = true;
    else if (c === sep) { fila.push(cel); cel = ""; }
    else if (c === "\n") { fila.push(cel.replace(/\r$/, "")); out.push(fila); fila = []; cel = ""; }
    else cel += c;
  }
  if (cel || fila.length) { fila.push(cel.replace(/\r$/, "")); out.push(fila); }
  return out.filter((r) => r.some((x) => x.trim() !== ""));
}

/** Lee un .xlsx o .csv y devuelve la matriz de texto (las fechas de Excel salen como yyyy-mm-dd). */
export async function leerMatriz(f: File): Promise<string[][]> {
  if (/\.xlsx$/i.test(f.name)) return (await readXlsxFile(f)).map((r) => r.map((c) => (c === null || c === undefined ? "" : c instanceof Date ? c.toISOString().slice(0, 10) : String(c))));
  if (/\.(csv|txt)$/i.test(f.name)) return parseCsv(await f.text());
  throw new Error("Formato no soportado. Usá .xlsx o .csv");
}

/** Fecha en texto → "yyyy-mm-dd" válida, o null. Acepta yyyy-mm-dd, dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy (año de 2 dígitos = 20xx) y número de serie de Excel. */
export function parseFechaFlexible(texto: string): string | null {
  const t = texto.trim();
  let y: number, m: number, d: number, r: RegExpMatchArray | null;
  if ((r = t.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T\s].*)?$/))) { y = +r[1]; m = +r[2]; d = +r[3]; }
  else if ((r = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$/))) { d = +r[1]; m = +r[2]; y = r[3].length === 2 ? 2000 + +r[3] : +r[3]; }
  else if (/^\d{5}$/.test(t)) { const dt = new Date(Math.round((Number(t) - 25569) * 86400000)); y = dt.getUTCFullYear(); m = dt.getUTCMonth() + 1; d = dt.getUTCDate(); }
  else return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d || y < 2000 || y > 2100) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}
