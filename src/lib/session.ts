import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { ConfigApariencia, ConfigGeneral, UsuarioPermisos } from "@/lib/types";

export interface Flags {
  esAdmin: boolean; esDesarrollador: boolean; puedeImportar: boolean; puedeExportar: boolean;
  puedeEliminarCancelar: boolean; puedeVerImportes: boolean; puedeControlIngreso: boolean;
}
export interface Sesion {
  userId: string; email: string | null; nombre: string; activo: boolean; roles: string[];
  permisos: UsuarioPermisos | null; flags: Flags; zona: string; config: ConfigGeneral | null;
}

/** Perfil del usuario autenticado. Una sola vez por request. */
export const getSesion = cache(async (): Promise<Sesion | null> => {
  const sb = await createClient();
  const { data: auth } = await sb.auth.getUser();
  if (!auth.user) return null;

  const [u, roles, perm, cfg, adm, dev, imp, exp, eli, imps, ci] = await Promise.all([
    sb.from("usuarios").select("nombre_completo, activo").eq("id", auth.user.id).maybeSingle(),
    sb.from("usuario_roles").select("roles(nombre)").eq("usuario_id", auth.user.id),
    sb.from("usuario_permisos").select("*").eq("usuario_id", auth.user.id).maybeSingle(),
    sb.from("configuracion_general").select("*").eq("id", 1).maybeSingle(),
    sb.rpc("fn_es_admin"), sb.rpc("fn_es_desarrollador"), sb.rpc("fn_puede_importar"), sb.rpc("fn_puede_exportar"),
    sb.rpc("fn_puede_eliminar_cancelar"), sb.rpc("fn_puede_ver_importes"), sb.rpc("fn_puede_control_ingreso"),
  ]);

  const rolesList = ((roles.data ?? []) as unknown as { roles: { nombre: string } | { nombre: string }[] | null }[])
    .flatMap((r) => (Array.isArray(r.roles) ? r.roles : r.roles ? [r.roles] : []))
    .map((r) => r.nombre);

  return {
    userId: auth.user.id,
    email: auth.user.email ?? null,
    nombre: u.data?.nombre_completo ?? auth.user.email ?? "Usuario",
    activo: u.data?.activo === true,
    roles: rolesList,
    permisos: (perm.data as UsuarioPermisos | null) ?? null,
    flags: {
      esAdmin: adm.data === true, esDesarrollador: dev.data === true, puedeImportar: imp.data === true,
      puedeExportar: exp.data === true, puedeEliminarCancelar: eli.data === true,
      puedeVerImportes: imps.data === true, puedeControlIngreso: ci.data === true,
    },
    zona: (cfg.data as ConfigGeneral | null)?.zona_horaria ?? "America/Argentina/Buenos_Aires",
    config: (cfg.data as ConfigGeneral | null) ?? null,
  };
});

export async function getApariencia(): Promise<ConfigApariencia | null> {
  const sb = await createClient();
  const { data } = await sb.from("configuracion_apariencia").select("*").eq("id", 1).maybeSingle();
  return (data as ConfigApariencia | null) ?? null;
}
