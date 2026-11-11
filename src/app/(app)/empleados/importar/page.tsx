import { redirect } from "next/navigation";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { Importador } from "./importador";

export const metadata = { title: "Importar empleados" };

export default async function Importar() {
  const s = (await getSesion())!;
  if (!s.flags.puedeImportar) redirect("/empleados");
  return (<><PageHeader titulo="Importar empleados" subtitulo="Cargá un Excel (.xlsx) o CSV. Cada fila se valida en la base; las que fallan no frenan al resto." /><Importador /></>);
}
