import { resumenFeriadosFactores } from "../src/lib/feriados-csv";
let fallos = 0; const t = (n: string, c: boolean, x?: unknown) => { if (!c) { fallos++; console.log("FAIL:", n, x ?? ""); } else console.log("PASS:", n); };
const bandas: any[] = [{ id: "b1", descripcion: "Jornada" }, { id: "b2", descripcion: "Extras" }, { id: "b3", descripcion: "Nocturna" }];
const d = (fecha: string, banda: string, horas: number, mult: number, fer = false): any => ({ fecha, banda_horaria_id: banda, horas, multiplicador: mult, es_feriado: fer });
const feriados = new Map<string, string | null>([["2026-11-21", "Día de la Soberanía"], ["2026-12-08", null]]);

const sin = resumenFeriadosFactores([d("2026-11-18", "b2", 2, 1.5)], bandas, feriados);
t("sin feriado: columnas de feriado vacías y factor informado", sin.feriados === "" && sin.horasFeriado === "" && sin.factores === "18/11/2026 Extras ×1,50: 2,00 h", sin);

const cruce = resumenFeriadosFactores([d("2026-11-18", "b2", 2, 1.5), d("2026-11-18", "b3", 1, 1.8)], bandas, feriados);
t("cruza dos bandas: dos factores en la misma fila", cruce.factores === "18/11/2026 Extras ×1,50: 2,00 h | 18/11/2026 Nocturna ×1,80: 1,00 h", cruce);

const dia = resumenFeriadosFactores([d("2026-11-20", "b3", 2, 1.8), d("2026-11-21", "b3", 3, 2.5, true)], bandas, feriados);
t("empieza día normal y termina en feriado: dos factores y solo las horas del feriado", dia.factores === "20/11/2026 Nocturna ×1,80: 2,00 h | 21/11/2026 Nocturna ×2,50 (feriado): 3,00 h" && dia.horasFeriado === "3,00" && dia.feriados === "21/11/2026 (Día de la Soberanía)", dia);

const sinDesc = resumenFeriadosFactores([d("2026-12-08", "b2", 1, 1.5, true)], bandas, feriados);
t("feriado sin descripción: solo la fecha", sinDesc.feriados === "08/12/2026", sinDesc);

const igual = resumenFeriadosFactores([d("2026-11-21", "b2", 1, 2, true), d("2026-11-21", "b2", 1.5, 2, true)], bandas, feriados);
t("tramos del mismo día/banda/factor se suman", igual.factores === "21/11/2026 Extras ×2,00 (feriado): 2,50 h", igual);

const fer1 = resumenFeriadosFactores([d("2026-11-21", "b2", 1, 1.5, true)], bandas, feriados);
t("feriado cuya banda no tiene factor de feriado: se marca feriado pero con el factor normal", fer1.factores.includes("×1,50 (feriado)") && fer1.horasFeriado === "1,00");

t("sin tramos (empleado sin cálculo): todo vacío", JSON.stringify(resumenFeriadosFactores([], bandas, feriados)) === JSON.stringify({ feriados: "", horasFeriado: "", factores: "" }));
process.exit(fallos ? 1 : 0);
