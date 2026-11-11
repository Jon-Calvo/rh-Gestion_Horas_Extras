import { getCatalogos } from "@/lib/catalogos";
import { getSesion } from "@/lib/session";
import { PageHeader } from "@/components/ui/misc";
import { NuevaSolicitudForm } from "./form";

export const metadata = { title: "Nueva solicitud" };

export default async function Nueva() {
  const s = (await getSesion())!;
  const cat = await getCatalogos();
  return (
    <>
      <PageHeader titulo="Nueva solicitud" subtitulo="Se crea como borrador. Después agregás empleados y la enviás a aprobación." />
      <NuevaSolicitudForm cat={cat} zona={s.zona} diasMax={s.config?.dias_maximos_antiguedad ?? 30} />
    </>
  );
}
