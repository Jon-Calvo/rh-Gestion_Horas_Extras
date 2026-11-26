# Horas Extras — Interfaz web (Next.js + Supabase + Vercel)

Interfaz para el esquema **Horas Extras V2.1**. Toda la lógica de negocio vive en la base (22 funciones `rpc_*`, RLS, triggers); la interfaz solo las invoca y muestra los mensajes de error de la base. Los botones que se ven según permisos son una ayuda visual: la autoridad es siempre la base.

## Pantallas
Ingreso · Panel · Solicitudes (lista, nueva, detalle con aprobación por empleado, control de ingreso, reemplazos, rectificación, cronología) · Aprobaciones · Control de ingreso · Empleados (+ importación xlsx/CSV) · Ranking · Estadísticas · Usuarios y permisos · Catálogos · Configuración y apariencia · Auditoría. Modo claro / oscuro / según dispositivo; adaptado a PC, tablet y celular.

## Orden de actualización (cambios de noviembre)
1. Aplicá primero la migración `0002_bandas_por_dia_y_observacion_ingreso.sql` en Supabase (ver `INSTRUCCIONES_MIGRACION_0002.md`).
2. Después publicá esta versión de la interfaz. Sin la migración, las bandas no aceptan días, el control de ingreso no guarda observación y no aparece el desglose de aprobados/rechazados.

## Novedades (tercera tanda)
- **Mensajes sobre formularios abiertos**: los avisos usan la capa superior del navegador (popover), así se ven nítidos sobre cualquier ventana. Mientras hay un formulario abierto no se pueden clickear, pero se cierran solos.
- **Importes**: en el detalle y en la lista se ve total y aprobado; un botón muestra rechazado y pendiente.
- **Estadísticas** (`/estadisticas`): mes en curso por defecto, selector de mes. KPIs, comparativo contra el mes anterior (valor y %), tendencia de 6 meses, Top 5 procesos / motivos / sectores por horas e importe aprobado, Top 5 empleados, mix productivo/improductivo. Los KPIs de importe solo los ven quienes tienen permiso de importes. Se cuentan solicitudes en aprobación, aprobadas, rechazadas y finalizadas; el mes se toma por fecha de inicio; las horas aprobadas son las programadas (no se descuenta «no se presentó»). Los importes no se suman entre monedas: se muestra la principal y un aviso de las otras. No requiere migración.
- **Feriados**: botón «Importar Excel / CSV» (columnas Fecha, Descripción; con vista previa; actualiza si la fecha ya existe).
- **Usuarios**: se ve y se edita el e-mail (requiere `SUPABASE_SERVICE_ROLE_KEY`). Un admin que no es DESARROLLADOR no puede modificar e-mail ni clave de un DESARROLLADOR.
- Pruebas de lógica: `npx tsx --tsconfig tsconfig.json tests/kpis.test.ts` y `tests/tabular.test.ts`.

## Novedades (cuarta tanda)
- **Segundo logo y segundo nombre** (Configuración → Apariencia): el encabezado del menú conserva logo 1, nombre 1 y el texto gris; el logo 2 y el nombre 2 van al pie del menú y en la pantalla de ingreso. El **texto gris** (antes fijo «Horas extras») es editable. Requieren las migraciones `0003` (logo 2 y nombre 2) y `0004` (texto gris); sin ellas la pantalla funciona igual y avisa que falta.
- **Contadores en el menú**: «Aprobaciones» (solicitudes en aprobación dentro de tu alcance) y «Control de ingreso» (aprobadas pendientes de control) muestran un número rojo. Se actualizan al navegar, al volver a la pestaña y cada 60 s (`/api/pendientes`).

## Novedades (séptima tanda) — requiere la migración 0007

- **N° identificador entero e inmutable** en Áreas, Sectores, Procesos, Motivos, Tipos de categoría, Configuración IB, Usuarios y Criterios horarios. Se asigna por orden de creación, no cambia al renombrar y no se reutiliza. Se ve en la columna «N°» de Catálogos.
- **Excel de solicitudes**: nuevas columnas IdSolicitante, IdMotivo, IdArea, IdSector, IdProceso, IdCategoria, IdIB, IdUsuarioAprobacion e IdUsuarioControlIngreso. Las columnas de horas ahora son una por **criterio horario** y llevan su N° en el encabezado (`Hs [1] Extras (al 50%)`).
- **Criterios horarios** (nuevo catálogo): el criterio define nombre y factores (normal y feriado); las **franjas horarias** eligen un criterio y solo llevan días y horas. Cambiar el factor o el nombre del criterio actualiza todas sus franjas.
- **Estadísticas**: filtros Área → Sector → Proceso (en cascada) y Solicitante (selección única, por los datos de la solicitud) y vista **Año completo** (12 meses contra el año anterior). Todo viaja en la URL y se refleja en el PDF.

## Novedades (sexta tanda)

Requiere la migración `0006_alcances_multiples_y_sesion.sql` (aplicarla **antes** de publicar esta versión).

- **Duración de la sesión** (Administración → Configuración): horas máximas desde el ingreso y «cerrar la sesión al cerrar el navegador». La web guarda la cookie `he_sesion` al iniciar sesión y el proxy la revisa en cada pedido. Se aplica a los próximos ingresos; quienes ya estaban conectados deberán ingresar una vez más. Para un corte estricto del lado del servidor, Supabase ofrece además «Time-box user sessions» (plan Pro).
- **Catálogos**: orden al hacer clic en el encabezado (↑ ↓) y buscador. **Usuarios**: orden por encabezado.
- **Estadísticas**: botón «Exportar PDF» (abre la impresión del navegador: destino «Guardar como PDF»; hoja A4 apaisada, tema claro, sin menú).
- **Permisos con varios elementos**: cada permiso (ver, aprobar, modificar, reabrir) admite varias áreas, varios sectores o varios procesos, según su nivel. Se guarda con `rpc_guardar_alcance_usuario` (reemplazo atómico).
- **Excel de solicitudes**: columnas `FeriadosEnExtra`, `HsFeriado` y `FactoresAplicados` (un renglón por día, banda y factor usado).
- Pruebas: `npx tsx --tsconfig tsconfig.json tests/sesion.test.ts`, `tests/feriados-csv.test.ts`.

## Novedades (quinta tanda)

Requiere la migración `0005_limites_tipo_empleado_y_fichadas.sql` (aplicarla **antes** de publicar esta versión).

- **Límite de horas por solicitud** y **intervalo de minutos** (Administración → Configuración). El límite se valida también en la base.
- **Tipo de empleado Jornal / Mensual**: alta/edición, importación Excel (columna opcional `tipo`) y exportación CSV de solicitudes (`TipoEmpleado`).
- **Conciliación de fichadas** (menú Operación → Conciliación): importa el Excel del reloj (.xls/.xlsx, librería `@e965/xlsx`), propone el tiempo real por superposición con el horario solicitado y una persona lo confirma o indica otro horario (con observación). No modifica el horario de la solicitud; el ranking se corrige por la diferencia. La CSV suma HorasReales, InicioReal, FinReal, OrigenTiempoReal, ObservacionTiempoReal e ImporteReal (este último solo con permiso de importes).
- **Estadísticas**: filtro por tipo de empleado (Jornal / Mensual) y tabla comparativa Jornal vs Mensual (empleados, horas, % de horas, horas por empleado, importe y costo por hora si tenés permiso).
- Pruebas del lector de fichadas: `npx tsx --tsconfig tsconfig.json tests/fichadas.test.ts`.

## Decimales
En los campos decimales podés escribir **coma o punto** (`1,5` o `1.5`); se guardan igual. No uses separador de miles. En el CSV los números salen con coma decimal.

## Variables de entorno
| Variable | Dónde | Uso |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Vercel (todas) | Project URL de Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Vercel (todas) | Clave anon/publishable |
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel, **solo servidor** (sin prefijo NEXT_PUBLIC) | Crear usuarios y cambiar contraseñas desde «Usuarios». Opcional: sin ella el resto funciona y esa función avisa que falta configurarla. |

## Puesta en marcha local
```bash
cp .env.example .env.local   # completar valores
npm install
npm run dev
```

## Deploy en Vercel
1. Subí esta carpeta a un repositorio de GitHub (el `.gitignore` ya excluye `node_modules`, `.next` y `.env*`).
2. Vercel → *Add New Project* → importá el repo (Framework: Next.js, detectado solo).
3. En *Environment Variables* cargá las tres variables de arriba y desplegá.
4. Supabase → *Authentication → URL Configuration*: poné la URL de Vercel como *Site URL*.
5. Ingresá con el usuario DESARROLLADOR que creaste. Desde «Usuarios y permisos» das de alta al resto.

## Qué se verificó y qué no
- Verificado: `tsc` sin errores y `next build` exitoso; capturas de Estadísticas (claro PC / oscuro celular, datos simulados), lógica de KPIs y lectura de Excel/CSV con pruebas propias; capturas de ingreso, control de ingreso (filtros y ventana de registro), aprobaciones (IB y color) y edición de bandas, renderizadas con datos simulados; el armado del CSV probado con datos simulados.
- **No verificado**: funcionamiento contra tu Supabase real (login, RPC, RLS, importación, alta de usuarios), ni el resto de las pantallas renderizadas con datos. Hacé una pasada con usuarios de prueba (admin, aprobador, control de ingreso, sin permisos, inactivo) antes de usarlo en producción.
- Los tipos de `src/lib/types.ts` están escritos a mano según el esquema; si cambia el esquema, actualizarlos.
