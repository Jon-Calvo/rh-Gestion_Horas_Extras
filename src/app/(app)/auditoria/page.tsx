import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { AuditoriaTabla } from "./tabla";

export const metadata = { title: "Auditoría" };

export default async function Auditoria() {
  const s = (await getSesion())!;
  if (!s.flags.esAdmin) redirect("/");
  const sb = await createClient();
  const [a, u] = await Promise.all([
    sb.from("auditoria_negocio").select("id, fecha_hora, usuario_id, origen, modulo, entidad_tipo, entidad_id, evento, estado_anterior, estado_nuevo, datos").order("fecha_hora", { ascending: false }).limit(500),
    sb.from("usuarios").select("id, nombre_completo"),
  ]);
  const nombres = Object.fromEntries((u.data ?? []).map((x: { id: string; nombre_completo: string }) => [x.id, x.nombre_completo]));
  return (<><PageHeader titulo="Auditoría" subtitulo="Últimos 500 eventos de negocio." /><AuditoriaTabla filas={(a.data ?? []) as never[]} nombres={nombres} zona={s.zona} /></>);
}
