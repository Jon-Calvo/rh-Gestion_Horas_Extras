"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Campo } from "@/components/ui/misc";
import { useToast } from "@/components/ui/toast";
import { mensajeError } from "@/lib/errors";

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
    }).eq("id", 1);
    if (e1) { setOcupado(false); toast("error", mensajeError(e1)); return; }
    const { error: e2 } = await sb.from("configuracion_apariencia").update({
      nombre_empresa: a.nombre_empresa || null, logo_url: a.logo_url || null, tema_predeterminado: a.tema_predeterminado,
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
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!g.emails_activos} onChange={(e) => setG({ ...g, emails_activos: e.target.checked })} /> Emails activos</label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!g.control_ingreso_permite_eliminar} onChange={(e) => setG({ ...g, control_ingreso_permite_eliminar: e.target.checked })} /> Permitir quitar un control de ingreso ya registrado (además requiere el permiso individual)</label>
      </section>
      <section className="card p-4 space-y-4"><h2 className="font-semibold">Apariencia</h2>
        <div className="grid sm:grid-cols-2 gap-4">
          <Campo etiqueta="Nombre de la empresa"><input className="input" value={a.nombre_empresa ?? ""} onChange={(e) => setA({ ...a, nombre_empresa: e.target.value })} /></Campo>
          <Campo etiqueta="URL del logo"><input className="input" type="url" value={a.logo_url ?? ""} onChange={(e) => setA({ ...a, logo_url: e.target.value })} /></Campo>
          <Campo etiqueta="Tema predeterminado"><select className="input" value={a.tema_predeterminado ?? "SISTEMA"} onChange={(e) => setA({ ...a, tema_predeterminado: e.target.value })}><option value="SISTEMA">Según el dispositivo</option><option value="CLARO">Claro</option><option value="OSCURO">Oscuro</option></select></Campo>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">{COLORES.map(([k, t]) => (
          <label key={k} className="block"><span className="label">{t}</span><div className="flex gap-2 items-center"><input type="color" className="h-9 w-12 rounded shrink-0" value={a[k] ?? "#000000"} onChange={(e) => setA({ ...a, [k]: e.target.value.toUpperCase() })} /><span className="text-xs text-muted">{a[k]}</span></div></label>))}</div>
      </section>
      <div className="flex justify-end"><button className="btn btn-primary" disabled={ocupado} onClick={guardar}>{ocupado ? <span className="spinner" /> : "Guardar configuración"}</button></div>
    </div>
  );
}
