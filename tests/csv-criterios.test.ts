import { criteriosUsados, sumaCriterio } from "../src/lib/csv-criterios";
let fallos = 0; const t = (n: string, c: boolean, x?: unknown) => { if (!c) { fallos++; console.log("FAIL:", n, x ?? ""); } else console.log("PASS:", n); };
const conceptos: any[] = [{ id: "c1", numero: 1, descripcion: "Extras (al 50%)", multiplicador: 1.5 }, { id: "c2", numero: 2, descripcion: "Extras Nocturnas (al 50%)", multiplicador: 1.8 }];
const bandas: any[] = [
  { id: "b1", concepto_id: "c1", descripcion: "Extras (al 50%)", multiplicador: 1.5 }, { id: "b2", concepto_id: "c1", descripcion: "Extras (al 50%)", multiplicador: 1.5 },
  { id: "b3", concepto_id: "c2", descripcion: "Extras Nocturnas (al 50%)", multiplicador: 1.8 }, { id: "b4", concepto_id: null, descripcion: "Legado", multiplicador: 1.2 }];
const d = (banda: string, horas: number, importe = 0): any => ({ banda_horaria_id: banda, horas, importe });

const det = [d("b1", 2, 200), d("b2", 3, 300), d("b3", 1, 180)];
const r = criteriosUsados(det, bandas, conceptos);
t("dos franjas del mismo criterio son UNA columna", r.cols.length === 2, r.cols);
t("el encabezado lleva el N° del criterio", r.cols[0].etiqueta === "[1] Extras (al 50%)" && r.cols[1].etiqueta === "[2] Extras Nocturnas (al 50%)", r.cols);
const s = sumaCriterio(det, r.cols[0].clave, r.claveDe);
t("suma horas e importe de todas las franjas del criterio", s.horas === 5 && s.total === 500 && s.n === 2, s);
t("sin tramos en el criterio: n=0", sumaCriterio([d("b3", 1)], r.cols[0].clave, r.claveDe).n === 0);
const leg = criteriosUsados([d("b4", 1), d("b1", 1)], bandas, conceptos);
t("franja sin criterio: columna propia [-] y ordenada por factor", leg.cols.length === 2 && leg.cols[0].etiqueta === "[-] Legado", leg.cols);
t("tramo de franja inexistente se ignora", criteriosUsados([d("zzz", 1)], bandas, conceptos).cols.length === 0);
const renombrado = criteriosUsados(det, bandas, [{ ...conceptos[0], descripcion: "Otro nombre" }, conceptos[1]]);
t("al renombrar el criterio cambia el texto pero no el N°", renombrado.cols[0].etiqueta === "[1] Otro nombre");
if (fallos) { console.log(`${fallos} fallo(s)`); process.exit(1); } else console.log("OK");
