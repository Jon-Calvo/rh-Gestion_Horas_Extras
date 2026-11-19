// Ejecutar: npx tsx --tsconfig tsconfig.json tests/fichadas.test.ts   (opcional: FICHADAS_XLS=ruta/al/archivo.xls para probar con un archivo real)
import { parsearFichadas, leerMatrizFichadas } from "../src/lib/fichadas";

let fallos = 0, total = 0;
const ok = (c: boolean, m: string) => { total++; if (!c) { fallos++; console.log("FAIL:", m); } else console.log("PASS:", m); };
const Z = "America/Argentina/Buenos_Aires";
const fila = (...c: string[]) => { const f = Array(11).fill(""); c.forEach((v, i) => (f[5 + i] = v)); return f; };

const m: string[][] = [
  fila("Todas las empresas"), (() => { const f = Array(11).fill(""); f[10] = "Período de evaluación : 16/11/2026 - 17/11/2026 entre las 00:00 y las 23:59"; return f; })(),
  ["ABACA MATIAS", "", "", "", "", "N. Legajo", "3510043", "", "", "Total", "3"],
  fila("lunes", "16/11/2026", "07:07", "Entrada"), fila("lunes", "16/11/2026", "16:33", "Salida"), fila("martes", "17/11/2026", "07:04", "Entrada"),
  ["PEREZ ANA", "", "", "", "", "N. Legajo", "3510100", "", "", "Total", "2"],
  fila("lunes", "16/11/2026", "16:21", "Entrada"), fila("martes", "17/11/2026", "02:00", "Salida"),
];
const r = parsearFichadas(m, Z);
ok(r.eventos.length === 5 && r.legajos === 2 && r.entradas === 3 && r.salidas === 2, "5 eventos, 2 legajos, 3 entradas, 2 salidas");
ok(r.periodoDesde === "2026-11-16" && r.periodoHasta === "2026-11-17", "período tomado del encabezado");
ok(r.eventos[0].fecha_hora === "2026-11-16T10:07:00.000Z" && r.eventos[0].legajo === "3510043" && r.eventos[0].tipo === "ENTRADA", "07:07 de Buenos Aires (UTC-3) = 10:07Z");
ok(r.eventos[4].fecha_hora === "2026-11-17T05:00:00.000Z", "turno noche: salida 02:00 del día siguiente");
ok(r.avisos.length === 0, "sin avisos en un archivo limpio");

let msg = ""; try { parsearFichadas([["nada"]], Z); } catch (e) { msg = (e as Error).message; }
ok(/No encontré fichadas/.test(msg), "un archivo sin fichadas da un error claro");

const sinPeriodo = m.filter((_, i) => i !== 1);
const r2 = parsearFichadas(sinPeriodo, Z);
ok(r2.periodoDesde === "2026-11-16" && r2.periodoHasta === "2026-11-17" && r2.avisos.length === 1, "sin encabezado de período se deduce de las fechas y avisa");

msg = ""; try { parsearFichadas([...m.slice(0, 2), ...m.slice(2), fila("x", "20/11/2026", "08:00", "Entrada")], Z); } catch (e) { msg = (e as Error).message; }
ok(/fuera del período/.test(msg), "fichadas fuera del período del encabezado se rechazan");

const r3 = parsearFichadas([fila("lunes", "16/11/2026", "07:00", "Entrada"), ...m], Z);
ok(r3.eventos.length === 5 && r3.avisos.some((a) => /antes de un/.test(a)), "una fila antes del primer legajo se ignora con aviso");

const r4 = parsearFichadas([...m.slice(0, 3), fila("lunes", "16/11/2026", "25:99", "Entrada"), fila("lunes", "16/11/2026", "08:00", "ENTRADA ")], Z);
ok(r4.eventos.length === 1 && r4.avisos.some((a) => /inválida/.test(a)), "hora inválida se ignora con aviso; 'ENTRADA ' con espacio/mayúsculas se acepta");

(async () => {
  const X = await import("@e965/xlsx");
  const ws = X.utils.aoa_to_sheet(m); const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, ws, "Hoja");
  const buf = X.write(wb, { type: "buffer", bookType: "biff8" }) as Buffer;
  const mat = await leerMatrizFichadas(new Blob([new Uint8Array(buf)]));
  const r5 = parsearFichadas(mat, Z);
  ok(r5.eventos.length === 5 && r5.periodoDesde === "2026-11-16", "ida y vuelta por un .xls (BIFF8) real");
  const buf2 = X.write(wb, { type: "buffer", bookType: "xlsx" }) as Buffer;
  ok(parsearFichadas(await leerMatrizFichadas(new Blob([new Uint8Array(buf2)])), Z).eventos.length === 5, "ida y vuelta por un .xlsx");
  const real = process.env.FICHADAS_XLS;
  if (real) {
    const fs = await import("node:fs");
    const rr = parsearFichadas(await leerMatrizFichadas(new Blob([new Uint8Array(fs.readFileSync(real))])), Z);
    console.log("ARCHIVO REAL:", rr.legajos, "legajos,", rr.eventos.length, "eventos,", rr.entradas, "entradas,", rr.salidas, "salidas, período", rr.periodoDesde, "a", rr.periodoHasta, "avisos:", rr.avisos);
    ok(rr.eventos.length > 0 && rr.entradas + rr.salidas === rr.eventos.length, "el archivo real se interpreta");
  }
  console.log(`\n${total - fallos}/${total} OK`); process.exit(fallos ? 1 : 0);
})();
