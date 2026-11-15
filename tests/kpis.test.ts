import { calcularKpis, mesDe, sumarMeses, pct, topEmpleados } from "../src/lib/kpis";
let fallos = 0; const t = (n: string, ok: boolean, d?: unknown) => { console.log((ok ? "PASS " : "FAIL ") + n + (ok ? "" : " -> " + JSON.stringify(d))); if (!ok) fallos++; };
const Z = "America/Argentina/Buenos_Aires";
const f = (o: Partial<any>): any => ({ situacion: "APROBADA", fecha_hora_inicio: "2026-11-10T12:00:00Z", area_nombre: "A", sector_nombre: "S1", proceso_nombre: "P1", motivo_nombre: "M1", motivo_tipo: "PRODUCTIVO", moneda: "ARS", horas_aprobadas: 10, horas_rechazadas: 0, horas_pendientes: 0, importe_aprobado: 1000, ...o });
t("mesDe respeta la zona (01/11 01:00Z = 31/10 local)", mesDe("2026-11-01T01:00:00Z", Z) === "2026-10" && mesDe("2026-11-01T04:00:00Z", Z) === "2026-11");
t("sumarMeses cruza el año", sumarMeses("2026-01", -1) === "2025-12" && sumarMeses("2026-11", 2) === "2027-01");
t("pct sin base = null; con base", pct(5, 0) === null && pct(150, 100) === 50 && pct(50, 100) === -50);
const filas = [
  f({ horas_aprobadas: 10, importe_aprobado: 1000, proceso_nombre: "P1", motivo_nombre: "M1" }),
  f({ horas_aprobadas: 30, importe_aprobado: 500, proceso_nombre: "P2", motivo_nombre: "M2", motivo_tipo: "IMPRODUCTIVO", situacion: "FINALIZADA" }),
  f({ horas_aprobadas: 5, importe_aprobado: 9000, proceso_nombre: "P3", horas_rechazadas: 5 }),
  f({ horas_aprobadas: 99, situacion: "CANCELADA" }), f({ horas_aprobadas: 99, situacion: "BORRADOR" }),
  f({ fecha_hora_inicio: "2026-10-15T12:00:00Z", horas_aprobadas: 20, importe_aprobado: 2000 }),
  f({ fecha_hora_inicio: "2026-04-15T12:00:00Z", horas_aprobadas: 77 }), // fuera de la ventana de 6 meses
  f({ horas_aprobadas: 8, importe_aprobado: 100, moneda: "USD", proceso_nombre: "P4" }),
  ...["a", "b", "c", "d", "e", "g"].map((x, i) => f({ proceso_nombre: "X" + x, horas_aprobadas: 1 + i })),
];
const k = calcularKpis(filas as any, "2026-11", Z, true);
t("horas aprobadas del mes excluye canceladas/borradores", k.actual.horasAprob === 10 + 30 + 5 + 8 + 21, k.actual.horasAprob);
t("mes anterior = octubre (20 h)", k.previo.mes === "2026-10" && k.previo.horasAprob === 20);
t("la serie tiene 6 meses y no incluye abril", k.serie.length === 6 && k.serie[0].mes === "2026-06" && k.serie.every((m) => m.horasAprob !== 77));
t("horas rechazadas del mes", k.actual.horasRech === 5);
t("horas finalizadas (con control resuelto)", k.actual.horasFinalizadas === 30);
t("moneda principal ARS y USD informada aparte", k.monedaPrincipal === "ARS" && k.otrasMonedas.join() === "USD");
t("importe aprobado por moneda sin mezclar", k.actual.importeAprob.ARS === 1000 + 500 + 9000 + 6 * 1000 && k.actual.importeAprob.USD === 100, k.actual.importeAprob);
t("top 5 procesos por horas: tamaño 5 y orden descendente", k.topProcesoHoras.length === 5 && k.topProcesoHoras[0].nombre === "P2" && k.topProcesoHoras.every((x, i, a) => i === 0 || a[i - 1].horas >= x.horas), k.topProcesoHoras.map((x) => x.nombre + x.horas));
t("top procesos por importe: P3 (9000) primero y sin USD", k.topProcesoImporte[0].nombre === "P3" && !k.topProcesoImporte.some((x) => x.nombre === "P4"), k.topProcesoImporte.map((x) => x.nombre));
t("top motivos por horas: M1 (10+5+8+21=44) y luego M2 (30)", k.topMotivoHoras[0].nombre === "M1" && k.topMotivoHoras[0].horas === 44 && k.topMotivoHoras[1].nombre === "M2" && k.topMotivoHoras[1].horas === 30, k.topMotivoHoras.map((x) => x.nombre + x.horas));
t("mix productivo/improductivo", k.mix.improductivo === 30 && k.mix.productivo === 10 + 5 + 8 + 21, k.mix);
const sin = calcularKpis(filas as any, "2026-11", Z, false);
t("sin permiso de importes no hay montos, ni tops de importe, ni monedas", sin.monedaPrincipal === null && sin.topProcesoImporte.length === 0 && sin.topMotivoImporte.length === 0 && Object.keys(sin.actual.importeAprob).length === 0 && sin.otrasMonedas.length === 0);
t("sin permiso, las horas siguen", sin.actual.horasAprob === k.actual.horasAprob);
const emps: any[] = [
  { empleado_id: "e1", nombre_completo: "Ana", legajo: "1", solicitud_id: "s1", total_horas: 8, total_importe: 800, estado_aprobacion: "APROBADO", estado_registro: "ACTIVO" },
  { empleado_id: "e1", nombre_completo: "Ana", legajo: "1", solicitud_id: "s2", total_horas: 4, total_importe: 400, estado_aprobacion: "APROBADO", estado_registro: "ACTIVO" },
  { empleado_id: "e2", nombre_completo: "Beto", legajo: "2", solicitud_id: "s1", total_horas: 9, total_importe: 900, estado_aprobacion: "RECHAZADO", estado_registro: "ACTIVO" },
  { empleado_id: "e3", nombre_completo: "Cora", legajo: "3", solicitud_id: "s3", total_horas: 6, total_importe: 60, estado_aprobacion: "APROBADO", estado_registro: "ACTIVO" },
];
const te = topEmpleados(emps, true, "ARS", new Map([["s1", "ARS"], ["s2", "ARS"], ["s3", "USD"]]));
t("top empleados: solo aprobados, suma por empleado, ordenado", te.distintos === 2 && te.top[0].nombre === "Ana" && te.top[0].horas === 12 && te.top[0].importe === 1200 && te.top[0].solicitudes === 2, te);
t("top empleados: importe de otra moneda no se suma", te.top[1].nombre === "Cora" && te.top[1].importe === 0);
console.log(fallos === 0 ? "TODOS OK" : `${fallos} FALLOS`); process.exit(fallos ? 1 : 0);
