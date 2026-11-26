import { fmtHoras, fmtImporte } from "@/lib/format";
import { pct, type ItemTop, type MesKpi } from "@/lib/kpis";

const nf = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
export const mesLargo = (m: string) => /^\d{4}$/.test(m) ? `año ${m}` : new Intl.DateTimeFormat("es-AR", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(`${m}-15T12:00:00Z`));
const mesCorto = (m: string) => new Intl.DateTimeFormat("es-AR", { month: "short", timeZone: "UTC" }).format(new Date(`${m}-15T12:00:00Z`)).replace(".", "");

/** Variación contra el mes anterior, en valor y en porcentaje. Es informativa: no pinta "bueno/malo". */
export function Delta({ actual, anterior, formato, etiquetaAnterior }: { actual: number; anterior: number; formato: (n: number) => string; etiquetaAnterior: string }) {
  const d = actual - anterior, p = pct(actual, anterior);
  const flecha = d > 0 ? "▲" : d < 0 ? "▼" : "＝";
  return (
    <div className="text-xs text-muted mt-1">
      <span className="font-semibold text-fg">{flecha} {d > 0 ? "+" : ""}{formato(d)}</span>
      {p === null ? <span> · sin base en {etiquetaAnterior}</span> : <span> ({p > 0 ? "+" : ""}{nf.format(p)} %)</span>}
      <span> vs {etiquetaAnterior}</span>
    </div>
  );
}

export function KpiCard({ titulo, valor, children, ayuda }: { titulo: string; valor: React.ReactNode; children?: React.ReactNode; ayuda?: string }) {
  return (
    <div className="card p-4" title={ayuda}>
      <div className="text-xs font-semibold text-muted uppercase tracking-wide">{titulo}</div>
      <div className="text-2xl font-bold mt-1 tabular-nums">{valor}</div>
      {children}
    </div>
  );
}

/** Ranking de barras horizontales. El valor siempre figura como texto. */
export function TopLista({ titulo, items, formato, vacio = "Sin datos en el período", pie }: { titulo: string; items: { clave: string; nombre: string; detalle?: string; v: number; extra?: string }[]; formato: (n: number) => string; vacio?: string; pie?: string }) {
  const max = Math.max(...items.map((i) => i.v), 0);
  return (
    <section className="card p-4">
      <h3 className="font-semibold text-sm mb-3">{titulo}</h3>
      {items.length === 0 ? <p className="text-sm text-muted py-4">{vacio}</p> : (
        <ol className="space-y-2.5">
          {items.map((i, n) => (
            <li key={i.clave}>
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <span className="min-w-0 truncate"><span className="text-muted tabular-nums mr-1.5">{n + 1}.</span><span className="font-medium">{i.nombre}</span>{i.detalle && <span className="text-xs text-muted"> · {i.detalle}</span>}</span>
                <span className="font-semibold tabular-nums whitespace-nowrap">{formato(i.v)}</span>
              </div>
              <div className="h-2 rounded-full mt-1" style={{ background: "var(--surface-2)" }} role="presentation"><div className="h-2 rounded-full" style={{ width: `${max > 0 ? Math.max((i.v / max) * 100, 2) : 0}%`, background: "var(--primary)" }} /></div>
              {i.extra && <div className="text-xs text-muted mt-0.5">{i.extra}</div>}
            </li>))}
        </ol>)}
      {pie && <p className="text-xs text-muted mt-3">{pie}</p>}
    </section>
  );
}

/** Columnas de los últimos meses; el mes elegido va resaltado. Cada columna lleva su valor escrito. */
export function Tendencia({ titulo, serie, valor, formato, mes }: { titulo: string; serie: MesKpi[]; valor: (m: MesKpi) => number; formato: (n: number) => string; mes: string }) {
  const max = Math.max(...serie.map(valor), 0);
  const W = 100 / serie.length;
  return (
    <section className="card p-4">
      <h3 className="font-semibold text-sm mb-3">{titulo}</h3>
      <div className="flex items-end gap-2 h-40" role="img" aria-label={`${titulo}: ${serie.map((m) => `${mesCorto(m.mes)} ${formato(valor(m))}`).join(", ")}`}>
        {serie.map((m) => {
          const v = valor(m), h = max > 0 ? (v / max) * 100 : 0, sel = m.mes === mes;
          return (
            <div key={m.mes} className="flex-1 min-w-0 h-full flex flex-col justify-end items-center gap-1" style={{ maxWidth: `${W}%` }}>
              <span className={`text-[11px] tabular-nums truncate max-w-full ${sel ? "font-bold" : "text-muted"}`}>{formato(v)}</span>
              <div className="w-full rounded-t" style={{ height: `${Math.max(h, v > 0 ? 3 : 0)}%`, background: sel ? "var(--primary)" : "color-mix(in srgb, var(--primary) 35%, var(--surface-2))" }} />
              <span className={`text-xs ${sel ? "font-bold" : "text-muted"}`}>{mesCorto(m.mes)}</span>
            </div>);
        })}
      </div>
    </section>
  );
}

export function Mix({ productivo, improductivo }: { productivo: number; improductivo: number }) {
  const t = productivo + improductivo;
  const p = t > 0 ? (productivo / t) * 100 : 0;
  return (
    <section className="card p-4">
      <h3 className="font-semibold text-sm mb-3">Horas aprobadas: productivas vs improductivas</h3>
      {t === 0 ? <p className="text-sm text-muted py-4">Sin datos en el período</p> : <>
        <div className="flex h-3 rounded-full overflow-hidden" role="img" aria-label={`Productivas ${nf.format(p)} %, improductivas ${nf.format(100 - p)} %`}>
          <div style={{ width: `${p}%`, background: "var(--success)" }} /><div style={{ width: `${100 - p}%`, background: "var(--warning)" }} />
        </div>
        <dl className="grid grid-cols-2 gap-3 mt-3 text-sm">
          <div><dt className="text-xs text-muted flex items-center gap-1.5"><span style={{ width: 8, height: 8, borderRadius: 99, background: "var(--success)" }} />Productivas</dt><dd className="font-semibold tabular-nums">{fmtHoras(productivo)} h <span className="text-muted font-normal">({nf.format(p)} %)</span></dd></div>
          <div><dt className="text-xs text-muted flex items-center gap-1.5"><span style={{ width: 8, height: 8, borderRadius: 99, background: "var(--warning)" }} />Improductivas</dt><dd className="font-semibold tabular-nums">{fmtHoras(improductivo)} h <span className="text-muted font-normal">({nf.format(100 - p)} %)</span></dd></div>
        </dl></>}
    </section>
  );
}

export const fh = (n: number) => `${fmtHoras(n)} h`;
export const fi = (moneda: string | null) => (n: number) => fmtImporte(n, moneda);
export type { ItemTop };
