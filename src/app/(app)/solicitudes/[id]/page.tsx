import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { getCatalogos } from "@/lib/catalogos";
import { Detalle } from "./detalle";
import type { AuditoriaNegocio, BandaRanking, DetalleCalculo, EmpleadoDetalle, PermisosScope, SolicitudResumen } from "@/lib/types";

export const metadata = { title: "Solicitud" };

export default async function SolicitudPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const s = (await getSesion())!;
  const sb = await createClient();
  const { data: sol } = await sb.from("vista_solicitudes_resumen").select("*").eq("id", id).maybeSingle();
  if (!sol) notFound();
  const r = sol as SolicitudResumen;

  const [emps, perm, cat, bandas, aud] = await Promise.all([
    sb.from("vista_solicitud_empleados_detalle").select("*").eq("solicitud_id", id).order("legajo"),
    sb.rpc("fn_permisos_para_scope", { p_area_id: r.area_id, p_sector_id: r.sector_id, p_proceso_id: r.proceso_id }),
    getCatalogos(),
    sb.from("bandas_ranking").select("*").order("ranking_inferior"),
    s.flags.esAdmin ? sb.from("auditoria_negocio").select("*").eq("entidad_tipo", "solicitud").eq("entidad_id", id).order("fecha_hora", { ascending: false }).limit(60) : Promise.resolve({ data: [] }),
  ]);
  const empleados = (emps.data ?? []) as EmpleadoDetalle[];
  const ids = empleados.map((e) => e.solicitud_empleado_id);
  const det = ids.length ? await sb.from("solicitud_empleado_detalle").select("*").in("solicitud_empleado_id", ids).order("fecha") : { data: [] };
  const bh = await sb.from("bandas_horarias").select("id, descripcion");
  const permisos = ((Array.isArray(perm.data) ? perm.data[0] : perm.data) as PermisosScope | null) ?? { puede_ver: true, puede_modificar: false, puede_aprobar: false, puede_reabrir: false, puede_control_ingreso: false };

  return (
    <Detalle
      sol={r} empleados={empleados} permisos={permisos} cat={cat} bandas={(bandas.data ?? []) as BandaRanking[]}
      detalle={(det.data ?? []) as DetalleCalculo[]} bandasHorarias={Object.fromEntries(((bh.data ?? []) as { id: string; descripcion: string }[]).map((b) => [b.id, b.descripcion]))}
      auditoria={(aud.data ?? []) as AuditoriaNegocio[]} zona={s.zona} verImportes={s.flags.puedeVerImportes}
      puedeEliminarCancelar={s.flags.puedeEliminarCancelar} esAdmin={s.flags.esAdmin}
      diasMax={s.config?.dias_maximos_antiguedad ?? 30}
    />
  );
}
