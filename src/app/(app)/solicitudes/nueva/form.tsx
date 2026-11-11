"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { ScopeSelect, type Scope } from "@/components/ui/scope-select";
import { Campo } from "@/components/ui/misc";
import { useRpc } from "@/lib/use-accion";
import { localToIso, nowLocal } from "@/lib/format";
import type { Catalogos } from "@/lib/catalogos";

export function NuevaSolicitudForm({ cat, zona, diasMax }: { cat: Catalogos; zona: string; diasMax: number }) {
  const router = useRouter();
  const { rpc, ocupado } = useRpc();
  const [scope, setScope] = useState<Scope>({ area_id: "", sector_id: "", proceso_id: "" });
  const [inicio, setInicio] = useState(nowLocal(zona));
  const [fin, setFin] = useState("");
  const [motivo, setMotivo] = useState("");
  const [obs, setObs] = useState("");
  const m = cat.motivos.find((x) => x.id === motivo);
  const valido = scope.proceso_id && inicio && fin && motivo && fin > inicio;

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    const r = await rpc<{ id: string }>("rpc_crear_solicitud", {
      p_area_id: scope.area_id, p_sector_id: scope.sector_id, p_proceso_id: scope.proceso_id,
      p_fecha_hora_inicio: localToIso(inicio, zona), p_fecha_hora_fin: localToIso(fin, zona),
      p_motivo_id: motivo, p_observacion: obs.trim() || null,
    }, "Solicitud creada como borrador", { refrescar: false });
    if (r.ok && r.data?.id) router.push(`/solicitudes/${r.data.id}`);
  };

  return (
    <form onSubmit={enviar} className="card p-5 sm:p-6 max-w-3xl space-y-5">
      <ScopeSelect value={scope} onChange={setScope} areas={cat.areas} sectores={cat.sectores} procesos={cat.procesos} />
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Inicio" ayuda={`Hora de ${zona}. Antigüedad máxima: ${diasMax} días.`}><input className="input" type="datetime-local" required value={inicio} onChange={(e) => setInicio(e.target.value)} /></Campo>
        <Campo etiqueta="Fin"><input className="input" type="datetime-local" required min={inicio} value={fin} onChange={(e) => setFin(e.target.value)} /></Campo>
      </div>
      <Campo etiqueta="Motivo" ayuda={m ? (m.requiere_aprobacion ? "Este motivo requiere aprobación." : "Este motivo no requiere aprobación: los empleados quedan aprobados al agregarlos.") : undefined}>
        <select className="input" required value={motivo} onChange={(e) => setMotivo(e.target.value)}>
          <option value="">Seleccionar…</option>{cat.motivos.filter((x) => x.activo).map((x) => <option key={x.id} value={x.id}>{x.motivo} ({x.tipo === "PRODUCTIVO" ? "productivo" : "improductivo"})</option>)}
        </select>
      </Campo>
      <Campo etiqueta="Observación (opcional)"><textarea className="input" rows={3} value={obs} onChange={(e) => setObs(e.target.value)} /></Campo>
      <div className="flex gap-2 justify-end">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>Cancelar</button>
        <button className="btn btn-primary" disabled={!valido || !!ocupado}>{ocupado ? <span className="spinner" /> : "Crear borrador"}</button>
      </div>
    </form>
  );
}
