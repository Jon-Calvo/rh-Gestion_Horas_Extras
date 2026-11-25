import { fmtHoras, fmtImporte } from "@/lib/format";
import { TIPO_LABEL, type ComparativoTipos, type Kpis, type TipoPago } from "@/lib/kpis";
import { PageHeader, Vacio } from "@/components/ui/misc";
import { SITUACION_LABEL, type Situacion } from "@/lib/types";
import { SelectorMes } from "./selector-mes";
import { BotonPdf } from "./boton-pdf";
import { Delta, KpiCard, Mix, Tendencia, TopLista, fh, fi, mesLargo } from "./graficos";

export interface TopEmp { nombre: string; legajo: string; horas: number; importe: number; solicitudes: number }

export function VistaEstadisticas({ k, te, mes, hoy, verImp, hayDatos, tipo, comp }: { k: Kpis; te: { distintos: number; top: TopEmp[] }; mes: string; hoy: string; verImp: boolean; hayDatos: boolean; tipo: TipoPago | null; comp: ComparativoTipos | null }) {
  const a = k.actual, p = k.previo, ant = mesLargo(k.anterior);
  const totalPedido = a.horasAprob + a.horasRech + a.horasPend, totalPedidoPrev = p.horasAprob + p.horasRech + p.horasPend;
  const tasaRech = totalPedido > 0 ? (a.horasRech / totalPedido) * 100 : 0, tasaPrev = totalPedidoPrev > 0 ? (p.horasRech / totalPedidoPrev) * 100 : 0;
  const mon = k.monedaPrincipal, impA = mon ? a.importeAprob[mon] ?? 0 : 0, impP = mon ? p.importeAprob[mon] ?? 0 : 0;
  const fimp = fi(mon), pctTxt = (n: number) => `${new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(n)} %`;
  const pctPlano = (n: number) => `${new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(n)} pp`;
  const nStr = (n: number) => new Intl.NumberFormat("es-AR").format(n);

  const filaComp = (nombre: string, va: number, vp: number, f: (n: number) => string) => {
    const d = va - vp, pc = vp === 0 ? null : (d / vp) * 100;
    return <tr key={nombre}><td>{nombre}</td><td className="text-right tabular-nums font-medium">{f(va)}</td><td className="text-right tabular-nums text-muted">{f(vp)}</td><td className="text-right tabular-nums">{d > 0 ? "+" : ""}{f(d)}</td><td className="text-right tabular-nums">{pc === null ? "—" : `${pc > 0 ? "+" : ""}${pctTxt(pc)}`}</td></tr>;
  };

  return (
    <>
      <PageHeader titulo="Estadísticas" subtitulo={`Mes de la extra: ${mesLargo(mes)}.${tipo ? ` Solo empleados ${TIPO_LABEL[tipo].toLowerCase()}.` : ""} Se cuentan las solicitudes en aprobación, aprobadas, rechazadas y finalizadas que podés ver.`} acciones={<><SelectorMes mes={mes} actual={hoy} tipo={tipo} conTipo={comp !== null} /><BotonPdf nombreArchivo={`Estadisticas-${mes}${tipo ? `-${TIPO_LABEL[tipo]}` : ""}`} /></>} />
      <div className="solo-print mb-3 text-sm" aria-hidden>Estadísticas · {mesLargo(mes)}{tipo ? ` · ${TIPO_LABEL[tipo]}` : " · Jornal y mensual"} · Generado el {new Date().toLocaleDateString("es-AR")}</div>
      {!hayDatos && <Vacio titulo="Sin solicitudes en el período" detalle="No hay solicitudes de los últimos 6 meses con tu alcance de visibilidad." />}
      {hayDatos && <>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
          <KpiCard titulo="Solicitudes" valor={nStr(a.solicitudes)}><Delta actual={a.solicitudes} anterior={p.solicitudes} formato={nStr} etiquetaAnterior={ant} /></KpiCard>
          <KpiCard titulo="Horas aprobadas" valor={fh(a.horasAprob)} ayuda="Horas de los empleados aprobados (programadas)"><Delta actual={a.horasAprob} anterior={p.horasAprob} formato={fh} etiquetaAnterior={ant} /></KpiCard>
          {verImp && (mon ? <KpiCard titulo={`Importe aprobado (${mon})`} valor={fimp(impA)}><Delta actual={impA} anterior={impP} formato={fimp} etiquetaAnterior={ant} /></KpiCard> : <KpiCard titulo="Importe aprobado" valor="—" />)}
          <KpiCard titulo="Horas rechazadas" valor={fh(a.horasRech)} ayuda="Porcentaje sobre el total de horas pedidas (aprobadas + rechazadas + pendientes)">
            <div className="text-xs text-muted mt-1">{pctTxt(tasaRech)} de lo pedido <span>(mes anterior: {pctTxt(tasaPrev)}, {tasaRech - tasaPrev > 0 ? "+" : ""}{pctPlano(tasaRech - tasaPrev)})</span></div>
          </KpiCard>
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
          <KpiCard titulo="Pendientes de aprobación" valor={fh(a.horasPend)} ayuda="Horas de empleados que todavía esperan decisión"><div className="text-xs text-muted mt-1">{nStr(k.porSituacion["EN_APROBACION"] ?? 0)} solicitud(es) en aprobación</div></KpiCard>
          <KpiCard titulo="Con control de ingreso resuelto" valor={fh(a.horasFinalizadas)} ayuda="Horas aprobadas de solicitudes finalizadas"><div className="text-xs text-muted mt-1">{a.horasAprob > 0 ? pctTxt((a.horasFinalizadas / a.horasAprob) * 100) : "—"} de las aprobadas</div></KpiCard>
          <KpiCard titulo="Empleados con extras" valor={nStr(te.distintos)} ayuda="Empleados distintos con horas aprobadas en el mes"><div className="text-xs text-muted mt-1">Promedio {te.distintos > 0 ? fmtHoras(a.horasAprob / te.distintos) : "—"} h por empleado</div></KpiCard>
          {verImp && mon && a.horasAprob > 0 ? <KpiCard titulo={`Costo promedio por hora (${mon})`} valor={fmtImporte(impA / a.horasAprob)} ayuda="Importe aprobado / horas aprobadas de la moneda principal"><div className="text-xs text-muted mt-1">{p.horasAprob > 0 && impP > 0 ? `Mes anterior: ${fmtImporte(impP / p.horasAprob)}` : "Sin base en el mes anterior"}</div></KpiCard>
            : <KpiCard titulo="Horas por solicitud" valor={a.solicitudes > 0 ? fh(a.horasAprob / a.solicitudes) : "—"}><div className="text-xs text-muted mt-1">Promedio de horas aprobadas</div></KpiCard>}
        </div>
        {verImp && k.otrasMonedas.length > 0 && <p className="text-xs rounded-lg px-3 py-2 mb-4" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)" }}>Hay importes en otras monedas ({k.otrasMonedas.join(", ")}) que no se suman: los importes de esta pantalla corresponden solo a {mon}.</p>}

        <div className="grid lg:grid-cols-2 gap-3 mb-3">
          <Tendencia titulo="Horas aprobadas · últimos 6 meses" serie={k.serie} valor={(m) => m.horasAprob} formato={(n) => nStr(Math.round(n))} mes={mes} />
          {verImp && mon ? <Tendencia titulo={`Importe aprobado (${mon}) · últimos 6 meses`} serie={k.serie} valor={(m) => m.importeAprob[mon] ?? 0} formato={(n) => new Intl.NumberFormat("es-AR", { notation: "compact", maximumFractionDigits: 1 }).format(n)} mes={mes} /> : <Mix productivo={k.mix.productivo} improductivo={k.mix.improductivo} />}
        </div>

        {comp === null && <p className="text-xs rounded-lg px-3 py-2 mb-3" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)" }}>No se pudo leer el tipo de empleado (Jornal/Mensual). Verificá que la migración 0005 esté aplicada.</p>}
        {comp && !comp.hayTipos && <p className="text-xs rounded-lg px-3 py-2 mb-3" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)" }}>La comparación Jornal vs Mensual aparece cuando hay empleados con tipo asignado. Asignalo en Empleados (editar o importar con la columna «tipo»).</p>}
        {comp && comp.hayTipos && <section className="card overflow-hidden mb-3">
          <div className="px-4 pt-4 pb-2"><h3 className="font-semibold text-sm">Jornal vs Mensual · {mesLargo(mes)}</h3><p className="text-xs text-muted">Solo empleados aprobados. Esta tabla muestra siempre ambos tipos, aunque filtres arriba.</p></div>
          <div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Tipo</th><th className="text-right">Empleados</th><th className="text-right">Solicitudes</th><th className="text-right">Horas</th><th className="text-right">% de horas</th><th className="text-right">Horas por empleado</th>{verImp && comp.moneda && <><th className="text-right">Importe ({comp.moneda})</th><th className="text-right">Costo por hora</th></>}<th className="text-right">Horas {ant}</th></tr></thead>
            <tbody>{(() => { const tot = comp.filas.reduce((x, f) => x + f.horas, 0); return comp.filas.map((f) => <tr key={f.tipo}><td className="font-medium">{TIPO_LABEL[f.tipo]}</td><td className="text-right tabular-nums">{nStr(f.empleados)}</td><td className="text-right tabular-nums">{nStr(f.solicitudes)}</td><td className="text-right tabular-nums font-medium whitespace-nowrap">{fh(f.horas)}</td><td className="text-right tabular-nums">{tot > 0 ? pctTxt((f.horas / tot) * 100) : "—"}</td><td className="text-right tabular-nums">{f.empleados > 0 ? fmtHoras(f.horas / f.empleados) : "—"}</td>{verImp && comp.moneda && <><td className="text-right tabular-nums whitespace-nowrap">{fimp(f.importe)}</td><td className="text-right tabular-nums">{f.horas > 0 ? fmtImporte(f.importe / f.horas) : "—"}</td></>}<td className="text-right tabular-nums text-muted whitespace-nowrap">{fh(f.horasPrevio)}</td></tr>); })()}</tbody></table></div>
        </section>}

        <section className="card overflow-hidden mb-3">
          <div className="px-4 pt-4 pb-2"><h3 className="font-semibold text-sm">Comparativo contra el mes anterior</h3></div>
          <div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Indicador</th><th className="text-right">{mesLargo(mes)}</th><th className="text-right">{ant}</th><th className="text-right">Diferencia</th><th className="text-right">Variación</th></tr></thead>
            <tbody>
              {filaComp("Solicitudes", a.solicitudes, p.solicitudes, nStr)}
              {filaComp("Horas aprobadas", a.horasAprob, p.horasAprob, fh)}
              {filaComp("Horas rechazadas", a.horasRech, p.horasRech, fh)}
              {filaComp("Horas pendientes", a.horasPend, p.horasPend, fh)}
              {verImp && mon && filaComp(`Importe aprobado (${mon})`, impA, impP, fimp)}
            </tbody></table></div>
        </section>

        <div className="grid md:grid-cols-2 gap-3">
          <TopLista titulo="Top 5 procesos · horas aprobadas" items={k.topProcesoHoras.map((x) => ({ clave: x.clave, nombre: x.nombre, detalle: x.detalle, v: x.horas, extra: `${x.solicitudes} solicitud(es)` }))} formato={fh} />
          {verImp && <TopLista titulo={`Top 5 procesos · importe aprobado${mon ? ` (${mon})` : ""}`} items={k.topProcesoImporte.map((x) => ({ clave: x.clave, nombre: x.nombre, detalle: x.detalle, v: x.importe, extra: `${fh(x.horas)}` }))} formato={fimp} />}
          <TopLista titulo="Top 5 motivos · horas aprobadas" items={k.topMotivoHoras.map((x) => ({ clave: x.clave, nombre: x.nombre, v: x.horas, extra: `${x.solicitudes} solicitud(es)` }))} formato={fh} />
          {verImp && <TopLista titulo={`Top 5 motivos · importe aprobado${mon ? ` (${mon})` : ""}`} items={k.topMotivoImporte.map((x) => ({ clave: x.clave, nombre: x.nombre, v: x.importe, extra: `${fh(x.horas)}` }))} formato={fimp} />}
          <TopLista titulo="Top 5 sectores · horas aprobadas" items={k.topSectorHoras.map((x) => ({ clave: x.clave, nombre: x.nombre, detalle: x.detalle, v: x.horas, extra: `${x.solicitudes} solicitud(es)` }))} formato={fh} />
          <TopLista titulo="Top 5 empleados · horas aprobadas" items={te.top.map((x) => ({ clave: x.legajo, nombre: x.nombre, detalle: x.legajo, v: x.horas, extra: `${x.solicitudes} solicitud(es)${verImp && mon ? ` · ${fimp(x.importe)}` : ""}` }))} formato={fh} pie="Útil para detectar sobrecarga de horas en pocas personas." />
          {verImp && mon ? <Mix productivo={k.mix.productivo} improductivo={k.mix.improductivo} /> : null}
          <section className="card p-4"><h3 className="font-semibold text-sm mb-3">Solicitudes del mes por estado</h3>
            <ul className="flex flex-wrap gap-2">{Object.entries(k.porSituacion).length === 0 ? <li className="text-sm text-muted">Sin datos en el mes</li> : Object.entries(k.porSituacion).map(([sit, n]) => <li key={sit} className="badge" style={{ background: "var(--surface-2)", color: "var(--text)" }}>{SITUACION_LABEL[sit as Situacion] ?? sit}: <b className="ml-1">{n}</b></li>)}</ul>
          </section>
        </div>
        <p className="text-xs text-muted mt-4">Las horas e importes «aprobados» son los programados en la solicitud para los empleados aprobados (no se descuentan quienes luego figuran como «no se presentó»). El mes se toma por la fecha de inicio de la extra. Las solicitudes canceladas, eliminadas y en borrador no se cuentan.{!verImp && " Tu usuario no tiene permiso para ver importes."}</p>
      </>}
    </>
  );
}
