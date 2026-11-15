"use client";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Badge } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";
import { leerMatriz, norm, parseFechaFlexible } from "@/lib/tabular";

interface Fila { n: number; fecha: string | null; crudo: string; descripcion: string; error?: string; estado?: "nuevo" | "actualiza" }
const dmy = (iso: string) => iso.split("-").reverse().join("/");
const MODELO = "﻿Fecha;Descripción\r\n01/01/2027;Año Nuevo\r\n24/03/2027;Día de la Memoria\r\n";

export function ImportarFeriados({ existentes, onCerrar }: { existentes: Record<string, unknown>[]; onCerrar: () => void }) {
  const toast = useToast(); const router = useRouter();
  const [filas, setFilas] = useState<Fila[]>([]);
  const [archivo, setArchivo] = useState(""); const [err, setErr] = useState<string | null>(null); const [ocupado, setOcupado] = useState(false);
  const ya = useMemo(() => new Set(existentes.map((e) => String(e.fecha))), [existentes]);

  const leer = async (f: File) => {
    setErr(null); setFilas([]); setArchivo(f.name);
    try {
      const m = await leerMatriz(f);
      if (m.length < 2) throw new Error("El archivo no tiene filas de datos.");
      const h = m[0].map(norm);
      const iF = h.findIndex((x) => x === "fecha"), iD = h.findIndex((x) => x === "descripcion" || x === "detalle" || x === "nombre");
      if (iF < 0) throw new Error("Falta la columna «Fecha». Encabezados esperados: Fecha, Descripción.");
      const vistas = new Map<string, number>();
      const out: Fila[] = m.slice(1).map((r, i) => {
        const crudo = (r[iF] ?? "").trim(); const fecha = parseFechaFlexible(crudo);
        const f: Fila = { n: i + 2, fecha, crudo, descripcion: iD >= 0 ? (r[iD] ?? "").trim() : "" };
        if (!fecha) f.error = crudo ? `Fecha no válida: «${crudo}» (usá dd/mm/aaaa o aaaa-mm-dd)` : "Fecha vacía";
        else if (f.descripcion.length > 200) f.error = "Descripción de más de 200 caracteres";
        else { if (vistas.has(fecha)) f.error = `Fecha repetida en el archivo (también en la fila ${vistas.get(fecha)})`; else vistas.set(fecha, f.n); f.estado = ya.has(fecha) ? "actualiza" : "nuevo"; }
        return f;
      }).filter((f) => f.crudo || f.descripcion);
      setFilas(out);
    } catch (e) { setErr(mensajeError(e)); }
  };

  const validas = filas.filter((f) => !f.error);
  const importar = async () => {
    setOcupado(true);
    const sb = createClient();
    for (let i = 0; i < validas.length; i += 200) {
      const { error } = await sb.from("feriados").upsert(validas.slice(i, i + 200).map((f) => ({ fecha: f.fecha, descripcion: f.descripcion || null })), { onConflict: "fecha" });
      if (error) { setOcupado(false); toast("error", `${mensajeError(error)} (se importaron ${i} de ${validas.length}; podés volver a intentar: no se duplican)`); router.refresh(); return; }
    }
    setOcupado(false); toast("ok", `${validas.length} feriado(s) importado(s)`); router.refresh(); onCerrar();
  };

  return (
    <Modal abierto onCerrar={onCerrar} titulo="Importar feriados" ancho>
      <div className="space-y-4">
        <p className="text-sm text-muted">Archivo <b>.xlsx</b> o <b>.csv</b> con las columnas <b>Fecha</b> y <b>Descripción</b>. Si la fecha ya existe, se actualiza su descripción; no se generan duplicados.{" "}
          <a className="underline text-primary" href={`data:text/csv;charset=utf-8,${encodeURIComponent(MODELO)}`} download="modelo_feriados.csv">Descargar modelo</a></p>
        <input className="input" type="file" accept=".xlsx,.csv,.txt" onChange={(e) => { const f = e.target.files?.[0]; if (f) leer(f); }} aria-label="Archivo de feriados" />
        {err && <div className="text-sm rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--danger) 14%, transparent)", color: "var(--danger)" }}>{err}</div>}
        {filas.length > 0 && <>
          <div className="text-sm"><b>{archivo}</b>: {filas.length} fila(s) · <span className="text-success font-medium">{validas.length} válidas</span>{filas.length - validas.length > 0 && <> · <span className="text-danger font-medium">{filas.length - validas.length} con error (no se importan)</span></>}</div>
          <div className="card overflow-hidden max-h-80 overflow-y-auto"><table className="tbl"><thead><tr><th>Fila</th><th>Fecha</th><th>Descripción</th><th>Resultado</th></tr></thead>
            <tbody>{filas.map((f) => (
              <tr key={f.n}><td className="text-muted">{f.n}</td><td className="whitespace-nowrap">{f.fecha ? dmy(f.fecha) : f.crudo || "—"}</td><td>{f.descripcion || "—"}</td>
                <td>{f.error ? <span className="text-danger text-xs">{f.error}</span> : <Badge tono={f.estado === "nuevo" ? "verde" : "ambar"}>{f.estado === "nuevo" ? "Nuevo" : "Actualiza"}</Badge>}</td></tr>))}</tbody></table></div>
        </>}
        <div className="flex justify-end gap-2"><button className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado || validas.length === 0} onClick={importar}>{ocupado ? <span className="spinner" /> : `Importar ${validas.length || ""} feriado(s)`}</button></div>
      </div>
    </Modal>
  );
}
