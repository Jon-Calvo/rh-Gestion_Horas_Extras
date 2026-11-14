"use client";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Badge } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";
import { decimalATexto, parseDecimal } from "@/lib/format";
import { DIAS_CORTO, DIAS_SEMANA } from "@/lib/types";

type Fila = Record<string, unknown>;
type Tipo = "text" | "number" | "date" | "time" | "bool" | "color" | "select" | "ref" | "dia";
interface Col { k: string; t: string; tipo: Tipo; req?: boolean; opciones?: string[]; ref?: string; refLabel?: string; def?: unknown; lista?: boolean; ayuda?: string }
interface Def { id: string; titulo: string; cols: Col[]; orden: string; sinActivo?: boolean }

const DEFS: Def[] = [
  { id: "areas", titulo: "Áreas", orden: "nombre", cols: [{ k: "nombre", t: "Nombre", tipo: "text", req: true, lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "sectores", titulo: "Sectores", orden: "nombre", cols: [{ k: "area_id", t: "Área", tipo: "ref", ref: "areas", refLabel: "nombre", req: true, lista: true }, { k: "nombre", t: "Nombre", tipo: "text", req: true, lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "procesos", titulo: "Procesos", orden: "nombre", cols: [{ k: "sector_id", t: "Sector", tipo: "ref", ref: "sectores", refLabel: "nombre", req: true, lista: true }, { k: "nombre", t: "Nombre", tipo: "text", req: true, lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "motivos", titulo: "Motivos", orden: "motivo", cols: [{ k: "motivo", t: "Motivo", tipo: "text", req: true, lista: true }, { k: "tipo", t: "Tipo", tipo: "select", opciones: ["PRODUCTIVO", "IMPRODUCTIVO"], def: "PRODUCTIVO", lista: true }, { k: "requiere_aprobacion", t: "Requiere aprobación", tipo: "bool", def: true, lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "categoria_tipos", titulo: "Tipos de categoría", orden: "codigo", cols: [{ k: "codigo", t: "Código", tipo: "text", req: true, lista: true }, { k: "descripcion", t: "Descripción", tipo: "text", lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "categorias", titulo: "Valor hora por categoría", orden: "vigente_desde", sinActivo: true, cols: [{ k: "categoria_tipo_id", t: "Tipo de categoría", tipo: "ref", ref: "categoria_tipos", refLabel: "codigo", req: true, lista: true }, { k: "valor_hora", t: "Valor hora", tipo: "number", req: true, lista: true }, { k: "moneda", t: "Moneda", tipo: "text", req: true, def: "ARS", lista: true }, { k: "vigente_desde", t: "Vigente desde", tipo: "date", req: true, lista: true }, { k: "vigente_hasta", t: "Vigente hasta", tipo: "date", lista: true }] },
  { id: "bandas_horarias", titulo: "Bandas horarias", orden: "hora_desde", cols: [{ k: "descripcion", t: "Descripción", tipo: "text", req: true, lista: true }, { k: "hora_desde", t: "Desde", tipo: "time", req: true, lista: true }, { k: "hora_hasta", t: "Hasta", tipo: "time", req: true, lista: true, ayuda: "Si es menor que «Desde» (ej. 22:00 a 06:00) la banda cruza la medianoche y pertenece al día en que empieza." }, { k: "dia_desde", t: "Día desde", tipo: "dia", req: true, def: 1, lista: true }, { k: "dia_hasta", t: "Día hasta", tipo: "dia", req: true, def: 5, lista: true, ayuda: "Rango inclusive. Si «Día desde» es mayor (ej. sábado a martes) el rango pasa por el domingo. Para un solo día, elegí el mismo." }, { k: "multiplicador", t: "Multiplicador", tipo: "number", req: true, def: 1, lista: true }, { k: "multiplicador_feriado", t: "Mult. feriado", tipo: "number", lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "feriados", titulo: "Feriados", orden: "fecha", sinActivo: true, cols: [{ k: "fecha", t: "Fecha", tipo: "date", req: true, lista: true }, { k: "descripcion", t: "Descripción", tipo: "text", lista: true }] },
  { id: "ib_configuracion", titulo: "Configuración IB", orden: "descripcion", cols: [{ k: "descripcion", t: "Descripción", tipo: "text", req: true, lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
  { id: "bandas_ranking", titulo: "Bandas de ranking", orden: "ranking_inferior", cols: [{ k: "descripcion", t: "Descripción", tipo: "text", req: true, lista: true }, { k: "ranking_inferior", t: "Ranking desde", tipo: "number", req: true, lista: true }, { k: "ranking_superior", t: "Ranking hasta", tipo: "number", lista: true }, { k: "color", t: "Color", tipo: "color", req: true, def: "#64748B", lista: true }, { k: "aplica_a_solicitud", t: "Aplica a solicitud", tipo: "bool", def: true, lista: true }, { k: "aplica_a_real", t: "Aplica a real", tipo: "bool", def: false, lista: true }, { k: "bloqueo_seleccion", t: "Selección", tipo: "select", opciones: ["PERMITIDO", "ADVERTENCIA", "BLOQUEADO"], def: "PERMITIDO", lista: true }, { k: "activo", t: "Activo", tipo: "bool", def: true, lista: true }] },
];

export function CatalogosAdmin({ datos }: { datos: Record<string, Fila[]> }) {
  const [tab, setTab] = useState(DEFS[0].id);
  const def = DEFS.find((d) => d.id === tab)!;
  return (
    <>
      <div className="flex gap-1 overflow-x-auto mb-4 pb-1" role="tablist">{DEFS.map((d) => (
        <button key={d.id} role="tab" aria-selected={tab === d.id} onClick={() => setTab(d.id)} className={`btn btn-sm whitespace-nowrap ${tab === d.id ? "btn-primary" : "btn-ghost"}`}>{d.titulo}</button>))}</div>
      <Tabla key={def.id} def={def} filas={datos[def.id] ?? []} datos={datos} />
    </>
  );
}

function Tabla({ def, filas, datos }: { def: Def; filas: Fila[]; datos: Record<string, Fila[]> }) {
  const [edit, setEdit] = useState<Fila | "nuevo" | null>(null);
  const ord = useMemo(() => [...filas].sort((a, b) => String(a[def.orden] ?? "").localeCompare(String(b[def.orden] ?? ""), "es", { numeric: true })), [filas, def.orden]);
  const refTxt = (c: Col, v: unknown) => { const f = (datos[c.ref!] ?? []).find((x) => x.id === v); return f ? String(f[c.refLabel!]) : "—"; };
  const mostrar = (c: Col, f: Fila) => {
    const v = f[c.k];
    if (c.tipo === "bool") return <Badge tono={v ? "verde" : "gris"}>{v ? "Sí" : "No"}</Badge>;
    if (c.tipo === "ref") return refTxt(c, v);
    if (c.tipo === "time") return v ? String(v).slice(0, 5) : "—";
    if (c.tipo === "dia") return v === undefined || v === null ? "—" : `${v} · ${DIAS_CORTO[Number(v) - 1]}`;
    if (c.tipo === "number") return v === null || v === undefined || v === "" ? "—" : decimalATexto(v as number);
    if (c.tipo === "color") return <span className="inline-flex items-center gap-2"><span style={{ width: 14, height: 14, borderRadius: 4, background: String(v), border: "1px solid var(--border)" }} />{String(v)}</span>;
    return v === null || v === undefined || v === "" ? "—" : String(v);
  };
  return (
    <>
      <div className="flex justify-end mb-3"><button className="btn btn-primary" onClick={() => setEdit("nuevo")}>+ Agregar</button></div>
      <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="tbl"><thead><tr>{def.cols.filter((c) => c.lista).map((c) => <th key={c.k}>{c.t}</th>)}<th /></tr></thead>
        <tbody>{ord.length === 0 ? <tr><td colSpan={def.cols.length + 1} className="text-center text-muted py-8">Sin registros</td></tr> : ord.map((f) => (
          <tr key={String(f.id)}>{def.cols.filter((c) => c.lista).map((c) => <td key={c.k}>{mostrar(c, f)}</td>)}<td className="text-right"><button className="btn btn-secondary btn-sm" onClick={() => setEdit(f)}>Editar</button></td></tr>))}</tbody></table></div></div>
      {edit && <Form def={def} fila={edit === "nuevo" ? null : edit} datos={datos} onCerrar={() => setEdit(null)} />}
    </>
  );
}

function Form({ def, fila, datos, onCerrar }: { def: Def; fila: Fila | null; datos: Record<string, Fila[]>; onCerrar: () => void }) {
  const toast = useToast(); const router = useRouter();
  const [v, setV] = useState<Record<string, unknown>>(() => Object.fromEntries(def.cols.map((c) => {
    const ini = fila ? (fila[c.k] ?? (c.tipo === "dia" ? (c.k === "dia_hasta" ? 7 : 1) : c.tipo === "bool" ? false : "")) : (c.def ?? (c.tipo === "bool" ? false : ""));
    return [c.k, c.tipo === "number" ? decimalATexto(ini as number) : ini];
  })));
  const [ocupado, setOcupado] = useState(false);
  const guardar = async (e: React.FormEvent) => {
    e.preventDefault(); setOcupado(true);
    const payload: Record<string, unknown> = {};
    for (const c of def.cols) {
      const x = v[c.k];
      if (c.tipo === "number") {
        const n = parseDecimal(x as string);
        if (String(x ?? "").trim() !== "" && n === null) { setOcupado(false); toast("error", `«${c.t}» debe ser un número (podés usar coma o punto).`); return; }
        payload[c.k] = n;
      } else payload[c.k] = c.tipo === "bool" ? !!x : c.tipo === "dia" ? Number(x) : x === "" ? null : x;
    }
    const sb = createClient();
    const { error } = fila ? await sb.from(def.id).update(payload).eq("id", fila.id as string) : await sb.from(def.id).insert(payload);
    setOcupado(false);
    if (error) { toast("error", mensajeError(error)); return; }
    toast("ok", "Guardado"); router.refresh(); onCerrar();
  };
  const eliminar = async () => {
    if (!fila || !confirm("¿Eliminar este registro? Si está en uso, la base lo va a rechazar.")) return;
    const { error } = await createClient().from(def.id).delete().eq("id", fila.id as string);
    if (error) { toast("error", mensajeError(error)); return; }
    toast("ok", "Eliminado"); router.refresh(); onCerrar();
  };
  return (
    <Modal abierto onCerrar={onCerrar} titulo={`${fila ? "Editar" : "Agregar"} · ${def.titulo}`}>
      <form onSubmit={guardar} className="space-y-3">
        {def.cols.map((c) => (
          <label key={c.k} className={c.tipo === "bool" ? "flex items-center gap-2 text-sm" : "block"}>
            {c.tipo === "bool" ? <><input type="checkbox" checked={!!v[c.k]} onChange={(e) => setV({ ...v, [c.k]: e.target.checked })} />{c.t}</> : <>
              <span className="label">{c.t}{c.req && " *"}</span>
              {c.tipo === "select" ? <select className="input" value={String(v[c.k])} onChange={(e) => setV({ ...v, [c.k]: e.target.value })}>{c.opciones!.map((o) => <option key={o}>{o}</option>)}</select>
              : c.tipo === "ref" ? <select className="input" required={c.req} value={String(v[c.k])} onChange={(e) => setV({ ...v, [c.k]: e.target.value })}><option value="">Elegir…</option>{(datos[c.ref!] ?? []).map((o) => <option key={String(o.id)} value={String(o.id)}>{String(o[c.refLabel!])}</option>)}</select>
              : c.tipo === "color" ? <div className="flex gap-2"><input type="color" className="h-10 w-14 rounded" value={String(v[c.k]) || "#64748B"} onChange={(e) => setV({ ...v, [c.k]: e.target.value.toUpperCase() })} /><input className="input" value={String(v[c.k])} pattern="#[0-9A-Fa-f]{6}" onChange={(e) => setV({ ...v, [c.k]: e.target.value })} /></div>
              : c.tipo === "dia" ? <select className="input" required value={String(v[c.k])} onChange={(e) => setV({ ...v, [c.k]: Number(e.target.value) })}>{DIAS_SEMANA.map((d, i) => <option key={d} value={i + 1}>{i + 1} — {d}</option>)}</select>
              : <input className="input" type={c.tipo === "number" ? "text" : c.tipo} inputMode={c.tipo === "number" ? "decimal" : undefined} placeholder={c.tipo === "number" ? "Ej.: 1,5" : undefined} required={c.req} value={String(v[c.k] ?? "")} onChange={(e) => setV({ ...v, [c.k]: e.target.value })} />}
              {c.tipo === "number" && !c.ayuda && <span className="text-xs text-muted mt-1 block">Coma o punto como decimal.</span>}
              {c.ayuda && <span className="text-xs text-muted mt-1 block">{c.ayuda}</span>}</>}
          </label>))}
        <div className="flex justify-between gap-2 pt-2">{fila ? <button type="button" className="btn btn-danger" onClick={eliminar}>Eliminar</button> : <span />}
          <div className="flex gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado}>{ocupado ? <span className="spinner" /> : "Guardar"}</button></div></div>
      </form>
    </Modal>
  );
}
