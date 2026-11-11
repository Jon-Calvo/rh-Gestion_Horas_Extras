"use client";
import { useMemo, useState } from "react";
import { flexRender, getCoreRowModel, getFilteredRowModel, getPaginationRowModel, getSortedRowModel, useReactTable, type ColumnDef, type SortingState } from "@tanstack/react-table";

export function DataTable<T>({ data, columns, filtroGlobal, tamPagina = 15, vacio, onFila, rowClass }: {
  data: T[]; columns: ColumnDef<T, any>[]; filtroGlobal?: string; tamPagina?: number; vacio?: string; onFila?: (r: T) => void; rowClass?: (r: T) => string;
}) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const cols = useMemo(() => columns, [columns]);
  const t = useReactTable({
    data, columns: cols, state: { sorting, globalFilter: filtroGlobal ?? "" },
    onSortingChange: setSorting, getCoreRowModel: getCoreRowModel(), getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(), getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: tamPagina } }, globalFilterFn: "includesString",
  });
  const filas = t.getRowModel().rows;
  const total = t.getFilteredRowModel().rows.length;
  const { pageIndex, pageSize } = t.getState().pagination;
  return (
    <div className="card overflow-hidden">
      <div className="overflow-x-auto">
        <table className="tbl">
          <thead>{t.getHeaderGroups().map((hg) => (
            <tr key={hg.id}>{hg.headers.map((h) => {
              const orden = h.column.getCanSort();
              const dir = h.column.getIsSorted();
              return (
                <th key={h.id} onClick={orden ? h.column.getToggleSortingHandler() : undefined} className={orden ? "cursor-pointer select-none" : ""} aria-sort={dir === "asc" ? "ascending" : dir === "desc" ? "descending" : undefined}>
                  {flexRender(h.column.columnDef.header, h.getContext())}{dir === "asc" ? " ↑" : dir === "desc" ? " ↓" : ""}
                </th>
              );
            })}</tr>
          ))}</thead>
          <tbody>
            {filas.length === 0 ? (
              <tr><td colSpan={cols.length} className="text-center text-muted py-10">{vacio ?? "Sin resultados"}</td></tr>
            ) : filas.map((r) => (
              <tr key={r.id} onClick={onFila ? () => onFila(r.original) : undefined} className={`${onFila ? "cursor-pointer" : ""} ${rowClass?.(r.original) ?? ""}`}>
                {r.getVisibleCells().map((c) => <td key={c.id}>{flexRender(c.column.columnDef.cell, c.getContext())}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {total > pageSize && (
        <div className="flex items-center justify-between gap-3 px-4 py-3 border-t text-sm">
          <span className="text-muted">{pageIndex * pageSize + 1}–{Math.min((pageIndex + 1) * pageSize, total)} de {total}</span>
          <div className="flex gap-2">
            <button className="btn btn-secondary btn-sm" onClick={() => t.previousPage()} disabled={!t.getCanPreviousPage()}>Anterior</button>
            <button className="btn btn-secondary btn-sm" onClick={() => t.nextPage()} disabled={!t.getCanNextPage()}>Siguiente</button>
          </div>
        </div>
      )}
    </div>
  );
}
