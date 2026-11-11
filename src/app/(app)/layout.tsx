import { redirect } from "next/navigation";
import { getApariencia, getSesion } from "@/lib/session";
import { ROL_LABEL } from "@/lib/types";
import { AppShell, type NavItem } from "@/components/layout/app-shell";
import { CuentaInactiva } from "@/components/layout/cuenta-inactiva";

export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const s = await getSesion();
  if (!s) redirect("/login");
  if (!s.activo) return <CuentaInactiva nombre={s.nombre} sinPerfil={s.roles.length === 0} />;

  const p = s.permisos, f = s.flags;
  const puedeCrear = f.esAdmin || (!!p && p.modificacion_nivel !== "NADA");
  const puedeAprobar = f.esAdmin || (!!p && p.aprobacion_nivel !== "NADA");
  const nav: NavItem[] = [
    { href: "/", label: "Panel", icon: "home", grupo: "" },
    { href: "/solicitudes", label: "Solicitudes", icon: "list", grupo: "Operación" },
    ...(puedeCrear ? [{ href: "/solicitudes/nueva", label: "Nueva solicitud", icon: "plus", grupo: "Operación" }] : []),
    ...(puedeAprobar ? [{ href: "/aprobaciones", label: "Aprobaciones", icon: "check", grupo: "Operación" }] : []),
    ...(f.puedeControlIngreso ? [{ href: "/control-ingreso", label: "Control de ingreso", icon: "door", grupo: "Operación" }] : []),
    { href: "/empleados", label: "Empleados", icon: "users", grupo: "Personal" },
    { href: "/ranking", label: "Ranking", icon: "trophy", grupo: "Personal" },
    ...(f.puedeImportar ? [{ href: "/empleados/importar", label: "Importar empleados", icon: "upload", grupo: "Personal" }] : []),
    ...(f.esAdmin ? [
      { href: "/admin/usuarios", label: "Usuarios y permisos", icon: "shield", grupo: "Administración" },
      { href: "/admin/catalogos", label: "Catálogos", icon: "layers", grupo: "Administración" },
      { href: "/admin/configuracion", label: "Configuración", icon: "cog", grupo: "Administración" },
      { href: "/auditoria", label: "Auditoría", icon: "history", grupo: "Administración" },
    ] : []),
  ];
  const ap = await getApariencia();
  return (
    <AppShell nav={nav} nombre={s.nombre} roles={s.roles.map((r) => ROL_LABEL[r] ?? r)} empresa={ap?.nombre_empresa || "Mi empresa"} logoUrl={ap?.logo_url ?? null}>
      {children}
    </AppShell>
  );
}
