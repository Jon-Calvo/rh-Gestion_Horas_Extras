import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { CatalogosAdmin } from "./catalogos";

export const metadata = { title: "Catálogos" };

const TABLAS = ["areas", "sectores", "procesos", "motivos", "categoria_tipos", "categorias", "bandas_horarias", "feriados", "ib_configuracion", "bandas_ranking"] as const;

export default async function Catalogos() {
  const s = (await getSesion())!;
  if (!s.flags.esAdmin) redirect("/");
  const sb = await createClient();
  const res = await Promise.all(TABLAS.map((t) => sb.from(t).select("*").limit(2000)));
  const datos = Object.fromEntries(TABLAS.map((t, i) => [t, (res[i].data ?? []) as Record<string, unknown>[]]));
  return (<><PageHeader titulo="Catálogos" subtitulo="Tablas maestras. Desactivá en lugar de borrar: los registros en uso no se pueden eliminar." /><CatalogosAdmin datos={datos} /></>);
}
