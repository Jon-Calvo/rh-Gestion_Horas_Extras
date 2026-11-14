"use client";
import { useMemo, useState } from "react";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/ui/data-table";
import { Badge, Campo, Vacio } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { ScopeSelect, type Scope } from "@/components/ui/scope-select";
import { useRpc } from "@/lib/use-accion";
import { decimalATexto, fmtHoras, parseDecimal } from "@/lib/format";
import { bandaPara } from "@/lib/ranking";
import type { Catalogos } from "@/lib/catalogos";
import type { BandaRanking, CategoriaTipo, EmpleadoResumen, IbConfig } from "@/lib/types";

export function EmpleadosTabla({ filas, cat, categorias, ibs, bandas, puedeEditar }: { filas: EmpleadoResumen[]; cat: Catalogos; categorias: CategoriaTipo[]; ibs: IbConfig[]; bandas: BandaRanking[]; puedeEditar: boolean }) {
  const [q, setQ] = useState("");
  const [estado, setEstado] = useState<"" | "ACTIVO" | "INACTIVO">("ACTIVO");
  const [edit, setEdit] = useState<EmpleadoResumen | "nuevo" | null>(null);
  const datos = useMemo(() => filas.filter((f) => !estado || f.estado === estado), [filas, estado]);

  const columns = useMemo<ColumnDef<EmpleadoResumen>[]>(() => [
    { accessorKey: "legajo", header: "Legajo", cell: (c) => <span className="font-semibold">{c.getValue<string>()}</span> },
    { accessorKey: "nombre_completo", header: "Nombre" },
    { accessorKey: "categoria_codigo", header: "Categoría" },
    { id: "unidad", header: "Área / sector / proceso", accessorFn: (r) => [r.area_nombre, r.sector_nombre, r.proceso_nombre].filter(Boolean).join(" "), cell: (c) => <div>{c.row.original.area_nombre ?? "—"}<div className="text-xs text-muted">{[c.row.original.sector_nombre, c.row.original.proceso_nombre].filter(Boolean).join(" · ")}</div></div> },
    { accessorKey: "ib_descripcion", header: "IB", cell: (c) => c.getValue<string>() ?? "—" },
    { accessorKey: "ranking_horas", header: "Ranking", cell: (c) => { const b = bandaPara(c.getValue<number>(), bandas, "solicitud"); return <span className="font-medium" style={{ color: b?.color }} title={b?.descripcion}>{fmtHoras(c.getValue<number>())} h</span>; } },
    { accessorKey: "estado", header: "Estado", cell: (c) => <Badge tono={c.getValue<string>() === "ACTIVO" ? "verde" : "gris"}>{c.getValue<string>() === "ACTIVO" ? "Activo" : "Inactivo"}</Badge> },
    ...(puedeEditar ? [{ id: "acc", header: "", cell: (c: any) => <button className="btn btn-ghost btn-sm" onClick={() => setEdit(c.row.original)}>Editar</button> } as ColumnDef<EmpleadoResumen>] : []),
  ], [bandas, puedeEditar]);

  return (
    <>
      <div className="flex flex-col sm:flex-row gap-3 mb-4">
        <input className="input sm:max-w-xs" type="search" placeholder="Buscar legajo, nombre, área…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" />
        <select className="input sm:max-w-40" value={estado} onChange={(e) => setEstado(e.target.value as "" | "ACTIVO" | "INACTIVO")} aria-label="Estado">
          <option value="ACTIVO">Activos</option><option value="INACTIVO">Inactivos</option><option value="">Todos</option>
        </select>
        <div className="flex-1" />
        {puedeEditar && <button className="btn btn-primary" onClick={() => setEdit("nuevo")}>+ Nuevo empleado</button>}
      </div>
      {filas.length === 0 ? <Vacio titulo="No hay empleados para mostrar" detalle="Importá un Excel o cargalos manualmente." /> : <DataTable data={datos} columns={columns} filtroGlobal={q} vacio="Ningún empleado coincide" />}
      {puedeEditar && edit !== null && <FormEmpleado key={edit === "nuevo" ? "nuevo" : edit.id} abierto emp={edit === "nuevo" ? null : edit} cat={cat} categorias={categorias} ibs={ibs} onCerrar={() => setEdit(null)} />}
    </>
  );
}

function FormEmpleado({ abierto, emp, cat, categorias, ibs, onCerrar }: { abierto: boolean; emp: EmpleadoResumen | null; cat: Catalogos; categorias: CategoriaTipo[]; ibs: IbConfig[]; onCerrar: () => void }) {
  const { rpc, ocupado, toast } = useRpc();
  const [legajo, setLegajo] = useState(emp?.legajo ?? "");
  const [nombre, setNombre] = useState(emp?.nombre_completo ?? "");
  const [categoria, setCategoria] = useState(emp?.categoria_codigo ?? "");
  const [scope, setScope] = useState<Scope>({ area_id: emp?.area_id ?? "", sector_id: emp?.sector_id ?? "", proceso_id: emp?.proceso_id ?? "" });
  const [estado, setEstado] = useState<"ACTIVO" | "INACTIVO">(emp?.estado ?? "ACTIVO");
  const [ib, setIb] = useState(emp?.ib_id ?? "");
  const [real, setReal] = useState(decimalATexto(emp?.ranking_horas_real));

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault();
    const realNum = parseDecimal(real);
    if (real.trim() !== "" && realNum === null) { toast("error", "El ranking real debe ser un número (podés usar coma o punto)."); return; }
    const r = await rpc("rpc_upsert_empleado", {
      p_legajo: legajo.trim(), p_nombre_completo: nombre.trim(), p_categoria_codigo: categoria,
      p_area_id: scope.area_id || null, p_sector_id: scope.sector_id || null, p_proceso_id: scope.proceso_id || null,
      p_estado: estado, p_ib_id: ib || null, p_ranking_horas_real: realNum,
      p_borrar_ib: !!emp?.ib_id && !ib, p_borrar_ranking_real: emp?.ranking_horas_real != null && real.trim() === "",
    }, emp ? "Empleado actualizado" : "Empleado creado");
    if (r.ok) onCerrar();
  };
  // Se remonta el formulario al cambiar de empleado para reiniciar el estado.
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo={emp ? `Editar ${emp.nombre_completo}` : "Nuevo empleado"} ancho>
      {abierto && <form key={emp?.id ?? "nuevo"} onSubmit={guardar} className="space-y-4">
        <div className="grid sm:grid-cols-2 gap-3">
          <Campo etiqueta="Legajo"><input className="input" required value={legajo} onChange={(e) => setLegajo(e.target.value)} /></Campo>
          <Campo etiqueta="Nombre completo"><input className="input" required value={nombre} onChange={(e) => setNombre(e.target.value)} /></Campo>
          <Campo etiqueta="Categoría"><select className="input" required value={categoria} onChange={(e) => setCategoria(e.target.value)}><option value="">Seleccionar…</option>{categorias.map((c) => <option key={c.id} value={c.codigo}>{c.codigo}{c.descripcion ? ` — ${c.descripcion}` : ""}</option>)}</select></Campo>
          <Campo etiqueta="Estado"><select className="input" value={estado} onChange={(e) => setEstado(e.target.value as "ACTIVO" | "INACTIVO")}><option value="ACTIVO">Activo</option><option value="INACTIVO">Inactivo</option></select></Campo>
        </div>
        <ScopeSelect value={scope} onChange={setScope} areas={cat.areas} sectores={cat.sectores} procesos={cat.procesos} />
        <div className="grid sm:grid-cols-2 gap-3">
          <Campo etiqueta="IB (opcional)"><select className="input" value={ib} onChange={(e) => setIb(e.target.value)}><option value="">Sin IB</option>{ibs.map((i) => <option key={i.id} value={i.id}>{i.descripcion}</option>)}</select></Campo>
          <Campo etiqueta="Ranking real (opcional)" ayuda="Coma o punto como decimal. El ranking según solicitud lo calcula el sistema."><input className="input" inputMode="decimal" placeholder="Ej.: 12,5" value={real} onChange={(e) => setReal(e.target.value)} /></Campo>
        </div>
        <div className="flex justify-end gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={!!ocupado}>{ocupado ? <span className="spinner" /> : "Guardar"}</button></div>
      </form>}
    </Modal>
  );
}
