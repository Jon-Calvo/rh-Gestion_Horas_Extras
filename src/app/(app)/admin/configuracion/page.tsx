import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { ConfiguracionForm } from "./form";

export const metadata = { title: "Configuración" };

export default async function Configuracion() {
  const s = (await getSesion())!;
  if (!s.flags.esAdmin) redirect("/");
  const sb = await createClient();
  const [g, a] = await Promise.all([sb.from("configuracion_general").select("*").eq("id", 1).maybeSingle(), sb.from("configuracion_apariencia").select("*").eq("id", 1).maybeSingle()]);
  return (<><PageHeader titulo="Configuración" subtitulo="Reglas generales y apariencia de la aplicación." /><ConfiguracionForm general={g.data} apariencia={a.data} /></>);
}
