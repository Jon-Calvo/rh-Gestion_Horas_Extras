import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getSesion } from "@/lib/session";
import { getCatalogos } from "@/lib/catalogos";
import { PageHeader } from "@/components/ui/misc";
import { EmpleadosTabla } from "./tabla";
import type { BandaRanking, CategoriaTipo, EmpleadoResumen, IbConfig } from "@/lib/types";

export const metadata = { title: "Empleados" };

export default async function Empleados() {
  const s = (await getSesion())!;
  const sb = await createClient();
  const [emp, cat, tipos, ibs, bandas] = await Promise.all([
    sb.from("vista_empleados_resumen").select("*").order("nombre_completo").limit(5000),
    getCatalogos(),
    sb.from("categoria_tipos").select("*").eq("activo", true).order("codigo"),
    sb.from("ib_configuracion").select("*").eq("activo", true).order("descripcion"),
    sb.from("bandas_ranking").select("*").order("ranking_inferior"),
  ]);
  return (
    <>
      <PageHeader titulo="Empleados" subtitulo="Personal dentro de tu alcance de visibilidad." acciones={s.flags.puedeImportar ? <Link href="/empleados/importar" className="btn btn-secondary">Importar desde Excel</Link> : undefined} />
      <EmpleadosTabla filas={(emp.data ?? []) as EmpleadoResumen[]} cat={cat} categorias={(tipos.data ?? []) as CategoriaTipo[]} ibs={(ibs.data ?? []) as IbConfig[]} bandas={(bandas.data ?? []) as BandaRanking[]} puedeEditar={s.flags.puedeImportar} />
    </>
  );
}
