export function fmtFechaHora(iso: string | null | undefined, tz: string): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("es-AR", { timeZone: tz, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso));
}
export function fmtFecha(iso: string | null | undefined, tz: string): string {
  if (!iso) return "—";
  const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(iso + "T12:00:00Z") : new Date(iso);
  return new Intl.DateTimeFormat("es-AR", { timeZone: /^\d{4}-\d{2}-\d{2}$/.test(iso) ? "UTC" : tz, day: "2-digit", month: "2-digit", year: "numeric" }).format(d);
}
export function fmtHoras(n: number | null | undefined): string {
  return new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(n ?? 0));
}
export function fmtImporte(n: number | null | undefined, moneda?: string | null): string {
  if (n === null || n === undefined) return "—";
  const v = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(n));
  return moneda ? `${moneda} ${v}` : v;
}

// Desfase (ms) de una zona horaria respecto de UTC en un instante dado.
function offsetMs(tz: string, at: Date): number {
  const p = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" }).formatToParts(at);
  const g = (t: string) => Number(p.find((x) => x.type === t)!.value);
  return Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"), g("second")) - Math.floor(at.getTime() / 1000) * 1000;
}
/** "2026-10-21T08:00" interpretado en la zona `tz` → ISO UTC. */
export function localToIso(local: string, tz: string): string {
  const [d, t] = local.split("T");
  const [y, m, dd] = d.split("-").map(Number);
  const [hh, mm] = t.split(":").map(Number);
  const guess = new Date(Date.UTC(y, m - 1, dd, hh, mm));
  let ms = guess.getTime() - offsetMs(tz, guess);
  ms = guess.getTime() - offsetMs(tz, new Date(ms));
  return new Date(ms).toISOString();
}
/** ISO UTC → "YYYY-MM-DDTHH:mm" en la zona `tz` (para <input type="datetime-local">). */
export function isoToLocal(iso: string, tz: string): string {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).formatToParts(new Date(iso));
  const g = (t: string) => p.find((x) => x.type === t)!.value;
  return `${g("year")}-${g("month")}-${g("day")}T${g("hour")}:${g("minute")}`;
}
export function nowLocal(tz: string): string { return isoToLocal(new Date().toISOString(), tz); }
