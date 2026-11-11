import { getApariencia } from "@/lib/session";
import { LoginForm } from "./login-form";

export const metadata = { title: "Ingresar" };
export const dynamic = "force-dynamic";

export default async function LoginPage() {
  const ap = await getApariencia().catch(() => null);
  return (
    <div className="min-h-dvh grid lg:grid-cols-2">
      <div className="hidden lg:flex flex-col justify-between p-12 text-white" style={{ background: "linear-gradient(135deg, var(--primary), var(--accent))" }}>
        <div className="flex items-center gap-3 font-bold text-lg">
          {ap?.logo_url ? /* eslint-disable-next-line @next/next/no-img-element */ <img src={ap.logo_url} alt="" className="h-9 w-9 rounded-lg bg-white/20 object-contain" /> : <div className="h-9 w-9 rounded-lg bg-white/20 grid place-items-center">HE</div>}
          {ap?.nombre_empresa || "Horas Extras"}
        </div>
        <div>
          <h2 className="text-4xl font-bold leading-tight">Solicitudes de horas extras,<br />del pedido al control de ingreso.</h2>
          <p className="mt-4 text-white/80 max-w-md">Pedí, aprobá y controlá horas extras con permisos por área, sector y proceso.</p>
        </div>
        <p className="text-sm text-white/60">Acceso solo para personal autorizado.</p>
      </div>
      <div className="grid place-items-center p-6"><LoginForm /></div>
    </div>
  );
}
