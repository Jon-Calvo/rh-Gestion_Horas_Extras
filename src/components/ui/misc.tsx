import type { Situacion, EstadoAprobacion, EstadoAsistencia } from "@/lib/types";
import { SITUACION_LABEL, APROBACION_LABEL, ASISTENCIA_LABEL } from "@/lib/types";

const tono = {
  gris: "color-mix(in srgb, var(--muted) 16%, transparent)", azul: "color-mix(in srgb, var(--primary) 16%, transparent)",
  verde: "color-mix(in srgb, var(--success) 18%, transparent)", ambar: "color-mix(in srgb, var(--warning) 20%, transparent)",
  rojo: "color-mix(in srgb, var(--danger) 16%, transparent)", violeta: "color-mix(in srgb, var(--accent) 16%, transparent)",
};
const txt = { gris: "var(--muted)", azul: "var(--primary)", verde: "var(--success)", ambar: "var(--warning)", rojo: "var(--danger)", violeta: "var(--accent)" };
export type Tono = keyof typeof tono;

export function Badge({ tono: t = "gris", children, punto }: { tono?: Tono; children: React.ReactNode; punto?: boolean }) {
  return (
    <span className="badge" style={{ background: tono[t], color: txt[t] }}>
      {punto && <span style={{ width: 6, height: 6, borderRadius: 99, background: txt[t] }} />}
      {children}
    </span>
  );
}
const SIT: Record<Situacion, Tono> = { BORRADOR: "gris", EN_APROBACION: "ambar", APROBADA: "azul", RECHAZADA: "rojo", FINALIZADA: "verde", CANCELADA: "gris", ELIMINADA: "gris" };
export function SituacionBadge({ situacion }: { situacion: Situacion }) { return <Badge tono={SIT[situacion]} punto>{SITUACION_LABEL[situacion]}</Badge>; }
const APR: Record<EstadoAprobacion, Tono> = { PENDIENTE_APROBACION: "ambar", APROBADO: "verde", RECHAZADO: "rojo" };
export function AprobacionBadge({ estado }: { estado: EstadoAprobacion }) { return <Badge tono={APR[estado]}>{APROBACION_LABEL[estado]}</Badge>; }
const ASI: Record<EstadoAsistencia, Tono> = { NO_APLICA: "gris", PENDIENTE_INGRESO: "ambar", INGRESO_REGISTRADO: "verde", YA_ESTABA_EN_PLANTA: "azul", NO_PRESENTADO: "rojo" };
export function AsistenciaBadge({ estado }: { estado: EstadoAsistencia }) { return estado === "NO_APLICA" ? <span className="text-muted">—</span> : <Badge tono={ASI[estado]}>{ASISTENCIA_LABEL[estado]}</Badge>; }

export function PageHeader({ titulo, subtitulo, acciones }: { titulo: string; subtitulo?: string; acciones?: React.ReactNode }) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-3 mb-5">
      <div><h1 className="text-xl sm:text-2xl font-bold tracking-tight">{titulo}</h1>{subtitulo && <p className="text-sm text-muted mt-1">{subtitulo}</p>}</div>
      {acciones && <div className="flex flex-wrap gap-2">{acciones}</div>}
    </div>
  );
}
export function Vacio({ titulo, detalle, accion }: { titulo: string; detalle?: string; accion?: React.ReactNode }) {
  return (
    <div className="card p-10 text-center">
      <div className="text-3xl mb-2" aria-hidden>🗂️</div>
      <p className="font-semibold">{titulo}</p>
      {detalle && <p className="text-sm text-muted mt-1 max-w-md mx-auto">{detalle}</p>}
      {accion && <div className="mt-4">{accion}</div>}
    </div>
  );
}
export function Spinner() { return <span className="spinner" aria-label="Cargando" />; }
export function Stat({ etiqueta, valor, tono: t = "azul", detalle }: { etiqueta: string; valor: React.ReactNode; tono?: Tono; detalle?: string }) {
  return (
    <div className="card p-4">
      <div className="text-xs font-semibold text-muted uppercase tracking-wide">{etiqueta}</div>
      <div className="text-3xl font-bold mt-1" style={{ color: txt[t] }}>{valor}</div>
      {detalle && <div className="text-xs text-muted mt-1">{detalle}</div>}
    </div>
  );
}
export function Campo({ etiqueta, children, ayuda }: { etiqueta: string; children: React.ReactNode; ayuda?: string }) {
  return <label className="block"><span className="label">{etiqueta}</span>{children}{ayuda && <span className="text-xs text-muted mt-1 block">{ayuda}</span>}</label>;
}
