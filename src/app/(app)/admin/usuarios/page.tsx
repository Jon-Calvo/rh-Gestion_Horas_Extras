import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { getCatalogos } from "@/lib/catalogos";
import { PageHeader } from "@/components/ui/misc";
import { UsuariosAdmin, type UsuarioFila, type RolFila, type ScopeFila } from "./usuarios";
import type { UsuarioPermisos } from "@/lib/types";

export const metadata = { title: "Usuarios y permisos" };

export default async function Usuarios() {
  const s = (await getSesion())!;
  if (!s.flags.esAdmin) redirect("/");
  const sb = await createClient();
  const [u, ur, roles, perm, sc, cat] = await Promise.all([
    sb.from("usuarios").select("id, nombre_completo, activo").order("nombre_completo"),
    sb.from("usuario_roles").select("usuario_id, rol_id"),
    sb.from("roles").select("id, nombre, descripcion").order("nombre"),
    sb.from("usuario_permisos").select("*"),
    sb.from("usuario_permiso_scopes").select("*"),
    getCatalogos(),
  ]);
  return (
    <>
      <PageHeader titulo="Usuarios y permisos" subtitulo="Cada tipo de permiso (ver, aprobar, modificar, reabrir) tiene su propio nivel y alcance." />
      <UsuariosAdmin usuarios={(u.data ?? []) as UsuarioFila[]} usuarioRoles={(ur.data ?? []) as { usuario_id: string; rol_id: string }[]} roles={(roles.data ?? []) as RolFila[]}
        permisos={(perm.data ?? []) as UsuarioPermisos[]} scopes={(sc.data ?? []) as ScopeFila[]} cat={cat} yo={s.userId} puedeCrear />
    </>
  );
}
