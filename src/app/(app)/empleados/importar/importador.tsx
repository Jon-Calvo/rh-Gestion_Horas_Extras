"use client";
import { useState } from "react";
import readXlsxFile from "read-excel-file";
import { createClient } from "@/lib/supabase/client";
import { Badge } from "@/components/ui/misc";
import { mensajeError } from "@/lib/errors";

const COLS = ["legajo", "nombre_completo", "categoria", "area", "sector", "proceso", "estado", "ib", "ranking_real"] as const;
type Fila = Record<(typeof COLS)[number], string>;
interface Res { n: number; legajo: string; ok: boolean; msg?: string }

const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
const ALIAS: Record<string, (typeof COLS)[number]> = { legajo: "legajo", nombre: "nombre_completo", nombre_completo: "nombre_completo", categoria: "categoria", area: "area", sector: "sector", proceso: "proceso", estado: "estado", ib: "ib", ranking_real: "ranking_real", ranking: "ranking_real" };

function parseCsv(txt: string): string[][] {
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

export function Importador() {
  const [filas, setFilas] = useState<Fila[]>([]);
  const [archivo, setArchivo] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [res, setRes] = useState<Res[]>([]);
  const [corriendo, setCorriendo] = useState(false);

  const leer = async (f: File) => {
    setErr(null); setRes([]); setFilas([]); setArchivo(f.name);
    try {
      let matriz: string[][];
      if (/\.xlsx$/i.test(f.name)) matriz = (await readXlsxFile(f)).map((r) => r.map((c) => (c === null || c === undefined ? "" : c instanceof Date ? c.toISOString().slice(0, 10) : String(c))));
      else if (/\.(csv|txt)$/i.test(f.name)) matriz = parseCsv(await f.text());
      else throw new Error("Formato no soportado. Usá .xlsx o .csv");
      if (matriz.length < 2) throw new Error("El archivo no tiene filas de datos.");
      const idx = matriz[0].map((h) => ALIAS[norm(h)]);
      const faltan = (["legajo", "nombre_completo", "categoria", "area", "sector", "proceso"] as const).filter((c) => !idx.includes(c));
      if (faltan.length) throw new Error(`Faltan columnas obligatorias: ${faltan.join(", ")}. Encabezados esperados: ${COLS.join(", ")}.`);
      setFilas(matriz.slice(1).map((r) => { const o = Object.fromEntries(COLS.map((c) => [c, ""])) as Fila; idx.forEach((c, i) => { if (c) o[c] = (r[i] ?? "").trim(); }); return o; }).filter((o) => o.legajo || o.nombre_completo));
    } catch (e) { setErr(mensajeError(e)); }
  };

  const importar = async () => {
    setCorriendo(true); setRes([]);
    const sb = createClient(); const out: Res[] = [];
    for (let i = 0; i < filas.length; i++) {
      const f = filas[i];
      const { error } = await sb.rpc("rpc_importar_empleado_excel", {
        p_legajo: f.legajo, p_nombre_completo: f.nombre_completo, p_categoria_codigo: f.categoria, p_area_nombre: f.area, p_sector_nombre: f.sector,
        p_proceso_nombre: f.proceso, p_estado: f.estado || "ACTIVO", p_ib_nombre: f.ib || null, p_ranking_horas_real: f.ranking_real || null,
      });
      out.push({ n: i + 2, legajo: f.legajo, ok: !error, msg: error ? mensajeError(error) : undefined });
      setRes([...out]);
    }
    setCorriendo(false);
  };

  const plantilla = () => {
    const csv = "﻿" + COLS.join(";") + "\r\n" + "1001;Ana Pérez;OP1;Producción;Línea 1;Armado;ACTIVO;;\r\n";
    const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" })); a.download = "plantilla_empleados.csv"; a.click(); URL.revokeObjectURL(a.href);
  };
  const ok = res.filter((r) => r.ok).length, mal = res.length - ok;

  return (
    <div className="space-y-5 max-w-5xl">
      <div className="card p-5 space-y-3">
        <p className="text-sm text-muted">Columnas: <code>{COLS.join(", ")}</code>. Área, sector, proceso y categoría deben existir; el IB, si se informa, también. Si el legajo ya existe se actualiza.</p>
        <div className="flex flex-wrap gap-2 items-center">
          <label className="btn btn-primary cursor-pointer">Elegir archivo<input type="file" accept=".xlsx,.csv,.txt" className="sr-only" onChange={(e) => e.target.files?.[0] && leer(e.target.files[0])} /></label>
          <button className="btn btn-secondary" onClick={plantilla}>Descargar plantilla</button>
          {archivo && <span className="text-sm text-muted">{archivo}</span>}
        </div>
        {err && <div role="alert" className="text-sm rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--danger) 12%, transparent)", color: "var(--danger)" }}>{err}</div>}
      </div>

      {filas.length > 0 && (
        <div className="card overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b">
            <div className="font-semibold">{filas.length} fila(s) para importar</div>
            <div className="flex items-center gap-3">
              {res.length > 0 && <span className="text-sm"><b style={{ color: "var(--success)" }}>{ok} OK</b> · <b style={{ color: mal ? "var(--danger)" : undefined }}>{mal} con error</b> · {res.length}/{filas.length}</span>}
              <button className="btn btn-primary" disabled={corriendo} onClick={importar}>{corriendo ? <><span className="spinner" /> Importando…</> : "Importar"}</button>
            </div>
          </div>
          <div className="overflow-auto max-h-[28rem]"><table className="tbl"><thead><tr><th>#</th>{COLS.map((c) => <th key={c}>{c}</th>)}<th>Resultado</th></tr></thead>
            <tbody>{filas.map((f, i) => { const r = res[i]; return (
              <tr key={i}><td className="text-muted">{i + 2}</td>{COLS.map((c) => <td key={c}>{f[c] || <span className="text-muted">—</span>}</td>)}
                <td>{r ? (r.ok ? <Badge tono="verde">OK</Badge> : <span className="text-xs" style={{ color: "var(--danger)" }}>{r.msg}</span>) : <span className="text-muted">—</span>}</td></tr>); })}</tbody></table></div>
        </div>
      )}
    </div>
  );
}
