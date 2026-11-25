"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Campo } from "@/components/ui/misc";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";
import { parseDecimal } from "@/lib/format";

type R = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
const COLORES: [string, string][] = [["color_primario", "Primario"], ["color_primario_hover", "Primario (hover)"], ["color_secundario", "Secundario"], ["color_acento", "Acento"], ["color_exito", "Éxito"], ["color_advertencia", "Advertencia"], ["color_error", "Error"]];

export function ConfiguracionForm({ general, apariencia }: { general: R | null; apariencia: R | null }) {
  const toast = useToast(); const router = useRouter();
  const [g, setG] = useState<R>(general ?? {}); const [a, setA] = useState<R>(apariencia ?? {});
  const [ocupado, setOcupado] = useState(false);
  const guardar = async () => {
    setOcupado(true);
    const sb = createClient();
    const { error: e1 } = await sb.from("configuracion_general").update({
      dias_maximos_antiguedad: Number(g.dias_maximos_antiguedad), emails_activos: !!g.emails_activos, ranking_periodo: g.ranking_periodo,
      control_ingreso_permite_eliminar: !!g.control_ingreso_permite_eliminar, nivel_auditoria_negocio: g.nivel_auditoria_negocio,
      retencion_auditoria_meses: g.retencion_auditoria_meses === "" || g.retencion_auditoria_meses == null ? null : Number(g.retencion_auditoria_meses), zona_horaria: g.zona_horaria,
      // Columnas de la migración 0005: solo se envían si ya existen en la base.
      ...("horas_maximas_solicitud" in g ? {
        horas_maximas_solicitud: g.horas_maximas_solicitud === "" || g.horas_maximas_solicitud == null ? null : parseDecimal(String(g.horas_maximas_solicitud)),
        minutos_intervalo: Number(g.minutos_intervalo ?? 1), fichadas_redondeo_minutos: Number(g.fichadas_redondeo_minutos ?? 0), fichadas_tolerancia_minutos: Number(g.fichadas_tolerancia_minutos ?? 0),
      } : {}),
      // Columnas de la migración 0006.
      ...("sesion_horas_maximas" in g ? {
        sesion_horas_maximas: g.sesion_horas_maximas === "" || g.sesion_horas_maximas == null ? null : Number(g.sesion_horas_maximas),
        sesion_cerrar_al_cerrar_navegador: g.sesion_cerrar_al_cerrar_navegador !== false,
      } : {}),
    }).eq("id", 1);
    if (e1) { setOcupado(false); toast("error", mensajeError(e1)); return; }
    const { error: e2 } = await sb.from("configuracion_apariencia").update({
      nombre_empresa: a.nombre_empresa || null, logo_url: a.logo_url || null, tema_predeterminado: a.tema_predeterminado,
      // Columnas de la migración 0003: solo se envían si ya existen en la base.
      ...("subtitulo_app" in a ? { subtitulo_app: (a.subtitulo_app ?? "").trim() || null } : {}),
      ...("logo_url_secundario" in a ? { logo_url_secundario: a.logo_url_secundario || null, nombre_empresa_secundario: a.nombre_empresa_secundario || null } : {}),
      ...Object.fromEntries(COLORES.map(([k]) => [k, a[k]])),
    }).eq("id", 1);
    setOcupado(false);
    if (e2) { toast("error", mensajeError(e2)); return; }
    toast("ok", "Configuración guardada"); router.refresh();
  };
  return (
    <div className="space-y-6 max-w-3xl">
      <section className="card p-4 space-y-4"><h2 className="font-semibold">Reglas generales</h2>
        <div className="grid sm:grid-cols-2 gap-4">
          <Campo etiqueta="Antigüedad máxima para cargar (días)" ayuda="Fechas más viejas que esto no se pueden solicitar."><input className="input" type="number" min={0} value={g.dias_maximos_antiguedad ?? ""} onChange={(e) => setG({ ...g, dias_maximos_antiguedad: e.target.value })} /></Campo>
          <Campo etiqueta="Período de reseteo del ranking"><select className="input" value={g.ranking_periodo ?? "MENSUAL"} onChange={(e) => setG({ ...g, ranking_periodo: e.target.value })}><option value="MENSUAL">Mensual</option><option value="TRIMESTRAL">Trimestral</option><option value="ANUAL">Anual</option></select></Campo>
          <Campo etiqueta="Zona horaria"><input className="input" value={g.zona_horaria ?? ""} onChange={(e) => setG({ ...g, zona_horaria: e.target.value })} /></Campo>
          <Campo etiqueta="Auditoría de negocio"><select className="input" value={g.nivel_auditoria_negocio ?? "BASICA"} onChange={(e) => setG({ ...g, nivel_auditoria_negocio: e.target.value })}><option value="DESACTIVADA">Desactivada</option><option value="BASICA">Básica</option><option value="COMPLETA">Completa</option></select></Campo>
          <Campo etiqueta="Retención de auditoría (meses)" ayuda="Vacío = sin límite."><input className="input" type="number" min={1} value={g.retencion_auditoria_meses ?? ""} onChange={(e) => setG({ ...g, retencion_auditoria_meses: e.target.value })} /></Campo>
        </div>
        {"horas_maximas_solicitud" in g ? (
          <div className="grid sm:grid-cols-2 gap-4 pt-2 border-t">
            <Campo etiqueta="Máximo de horas seguidas por solicitud" ayuda="Se controla al crear y al modificar las fechas. Vacío = sin límite. Las solicitudes ya cargadas no se tocan."><input className="input" inputMode="decimal" placeholder="Ej.: 24" value={g.horas_maximas_solicitud ?? ""} onChange={(e) => setG({ ...g, horas_maximas_solicitud: e.target.value })} /></Campo>
            <Campo etiqueta="Minutos disponibles al elegir un horario" ayuda="Paso de los minutos en inicio y fin de la solicitud. Ej.: «Cada 30» muestra :00 y :30."><select className="input" value={g.minutos_intervalo ?? 1} onChange={(e) => setG({ ...g, minutos_intervalo: Number(e.target.value) })}>
              {[[1, "Cualquier minuto"], [5, "Cada 5 minutos"], [10, "Cada 10 minutos"], [15, "Cada 15 minutos (:00, :15, :30, :45)"], [20, "Cada 20 minutos"], [30, "Cada 30 minutos (:00, :30)"], [60, "Solo horas en punto"]].map(([v, t]) => <option key={v} value={v}>{t}</option>)}</select></Campo>
            <Campo etiqueta="Conciliación: tolerancia (minutos)" ayuda="Si la fichada está a esta cantidad de minutos o menos del límite solicitado, se toma como puntual (0 a 30)."><input className="input" type="number" min={0} max={30} value={g.fichadas_tolerancia_minutos ?? 0} onChange={(e) => setG({ ...g, fichadas_tolerancia_minutos: e.target.value })} /></Campo>
            <Campo etiqueta="Conciliación: redondeo hacia abajo" ayuda="El tiempo real propuesto se redondea a múltiplos de estos minutos."><select className="input" value={g.fichadas_redondeo_minutos ?? 0} onChange={(e) => setG({ ...g, fichadas_redondeo_minutos: Number(e.target.value) })}>
              {[[0, "Sin redondeo (minuto exacto)"], [5, "5 minutos"], [10, "10 minutos"], [15, "15 minutos"], [30, "30 minutos"], [60, "1 hora"]].map(([v, t]) => <option key={v} value={v}>{t}</option>)}</select></Campo>
          </div>
        ) : <p className="text-sm text-muted">El límite de horas, el paso de minutos y la conciliación se habilitan al aplicar la migración 0005 en Supabase.</p>}
        {"sesion_horas_maximas" in g ? (
          <div className="grid sm:grid-cols-2 gap-4 pt-2 border-t">
            <Campo etiqueta="Duración máxima de la sesión (horas)" ayuda="Pasado este tiempo desde el ingreso, hay que volver a iniciar sesión. De 1 a 720; vacío = sin límite. Se aplica a los próximos ingresos."><input className="input" type="number" min={1} max={720} placeholder="Ej.: 12" value={g.sesion_horas_maximas ?? ""} onChange={(e) => setG({ ...g, sesion_horas_maximas: e.target.value })} /></Campo>
            <label className="flex items-start gap-2 text-sm sm:pt-6"><input type="checkbox" className="mt-1" checked={g.sesion_cerrar_al_cerrar_navegador !== false} onChange={(e) => setG({ ...g, sesion_cerrar_al_cerrar_navegador: e.target.checked })} /> <span>Cerrar la sesión al cerrar el navegador<span className="block text-xs text-muted">Si el navegador restaura las pestañas al abrirse, puede mantener la sesión hasta que venza la duración máxima.</span></span></label>
          </div>
        ) : <p className="text-sm text-muted">La duración de sesión se habilita al aplicar la migración 0006 en Supabase.</p>}
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!g.emails_activos} onChange={(e) => setG({ ...g, emails_activos: e.target.checked })} /> Emails activos</label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!g.control_ingreso_permite_eliminar} onChange={(e) => setG({ ...g, control_ingreso_permite_eliminar: e.target.checked })} /> Permitir quitar un control de ingreso ya registrado (además requiere el permiso individual)</label>
      </section>
      <section className="card p-4 space-y-4"><h2 className="font-semibold">Apariencia</h2>
        <div className="grid sm:grid-cols-2 gap-4">
          <Campo etiqueta="Nombre 1 (principal)"><input className="input" value={a.nombre_empresa ?? ""} onChange={(e) => setA({ ...a, nombre_empresa: e.target.value })} /></Campo>
          <Campo etiqueta="URL del logo 1"><input className="input" type="url" value={a.logo_url ?? ""} onChange={(e) => setA({ ...a, logo_url: e.target.value })} /></Campo>
          {"subtitulo_app" in a
            ? <Campo etiqueta="Texto gris debajo del nombre 1" ayuda="Vacío = «Horas extras»."><input className="input" maxLength={60} placeholder="Horas extras" value={a.subtitulo_app ?? ""} onChange={(e) => setA({ ...a, subtitulo_app: e.target.value })} /></Campo>
            : <p className="sm:col-span-2 text-sm text-muted">El texto gris editable se habilita al aplicar la migración 0004 en Supabase.</p>}
          {"logo_url_secundario" in a ? (<>
            <Campo etiqueta="Nombre 2 (opcional)" ayuda="Se muestra con el logo 2 al pie del menú y en la pantalla de ingreso."><input className="input" value={a.nombre_empresa_secundario ?? ""} onChange={(e) => setA({ ...a, nombre_empresa_secundario: e.target.value })} /></Campo>
            <Campo etiqueta="URL del logo 2 (opcional)"><input className="input" type="url" value={a.logo_url_secundario ?? ""} onChange={(e) => setA({ ...a, logo_url_secundario: e.target.value })} /></Campo>
          </>) : <p className="sm:col-span-2 text-sm text-muted">El segundo logo y nombre se habilitan al aplicar la migración 0003 en Supabase.</p>}
          <Campo etiqueta="Tema predeterminado"><select className="input" value={a.tema_predeterminado ?? "SISTEMA"} onChange={(e) => setA({ ...a, tema_predeterminado: e.target.value })}><option value="SISTEMA">Según el dispositivo</option><option value="CLARO">Claro</option><option value="OSCURO">Oscuro</option></select></Campo>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">{COLORES.map(([k, t]) => (
          <label key={k} className="block"><span className="label">{t}</span><div className="flex gap-2 items-center"><input type="color" className="h-9 w-12 rounded shrink-0" value={a[k] ?? "#000000"} onChange={(e) => setA({ ...a, [k]: e.target.value.toUpperCase() })} /><span className="text-xs text-muted">{a[k]}</span></div></label>))}</div>
      </section>
      <div className="flex justify-end"><button className="btn btn-primary" disabled={ocupado} onClick={guardar}>{ocupado ? <span className="spinner" /> : "Guardar configuración"}</button></div>
    </div>
  );
}
