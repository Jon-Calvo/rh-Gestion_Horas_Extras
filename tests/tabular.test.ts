import { existsSync } from "node:fs";
import readXlsxFile from "read-excel-file/node";
import { parseFechaFlexible, parseCsv } from "../src/lib/tabular";
let fallos = 0; const t = (n: string, ok: boolean, d?: unknown) => { console.log((ok ? "PASS " : "FAIL ") + n + (ok ? "" : " -> " + JSON.stringify(d))); if (!ok) fallos++; };
t("yyyy-mm-dd", parseFechaFlexible("2027-01-01") === "2027-01-01");
t("dd/mm/yyyy", parseFechaFlexible("24/03/2027") === "2027-03-24");
t("d/m/yy", parseFechaFlexible("5/7/27") === "2027-07-05");
t("dd-mm-yyyy y dd.mm.yyyy", parseFechaFlexible("09-07-2027") === "2027-07-09" && parseFechaFlexible("09.07.2027") === "2027-07-09");
t("fecha con hora ISO", parseFechaFlexible("2027-05-25T00:00:00.000Z") === "2027-05-25");
t("serie de Excel 46388 = 2027-01-01", parseFechaFlexible("46388") === "2027-01-01", parseFechaFlexible("46388"));
t("rechaza 31/02, mes 13, texto y años absurdos", [parseFechaFlexible("31/02/2027"), parseFechaFlexible("1/13/2027"), parseFechaFlexible("hola"), parseFechaFlexible("01/01/1850"), parseFechaFlexible("")].every((x) => x === null));
const csv = parseCsv("﻿Fecha;Descripción\r\n01/01/2027;Año Nuevo\r\n24/03/2027;\"Memoria; con punto y coma\"\r\n");
t("CSV con BOM, ; y comillas", csv.length === 3 && csv[0][0] === "Fecha" && csv[2][1] === "Memoria; con punto y coma", csv);
(async () => {
  // Prueba con un .xlsx real (fechas como celdas de fecha y como texto); se omite si el archivo de ejemplo no está.
  if (!existsSync("/tmp/feriados_test.xlsx")) { console.log("(se omite la prueba de .xlsx: falta /tmp/feriados_test.xlsx)"); console.log(fallos === 0 ? "TODOS OK" : `${fallos} FALLOS`); process.exit(fallos ? 1 : 0); }
  const filas = await readXlsxFile("/tmp/feriados_test.xlsx");
  const f = filas.slice(1).map((r) => (r[0] instanceof Date ? r[0].toISOString().slice(0, 10) : String(r[0])));
  t("xlsx: celdas de fecha y de texto", f[0] === "2027-01-01" && parseFechaFlexible(f[1]) === "2027-03-24" && f[2] === "2027-05-25", f);
  console.log(fallos === 0 ? "TODOS OK" : `${fallos} FALLOS`); process.exit(fallos ? 1 : 0);
})();
