# Informe final — Horas Extras V2.1

Fecha de cierre: 2026-11-09/10. Resultados medidos en **PostgreSQL 16.15 local** (`server_version_num=160015`), no en Supabase.

## 1. Confirmación expresa

El archivo `0001_schema_inicial_consolidado_v2_1_SUPABASE.sql` **ya contiene todas las correcciones**. No depende de ningún parche posterior, no tiene código pendiente de integración y no contiene `DROP` ni `TRUNCATE` (verificado por `grep` y por el propio script de pruebas, que se niega a correr si los encuentra). Se generó a partir de `0001_schema_inicial_consolidado_v2_final.sql` mediante reemplazos con aserciones (cada reemplazo debe coincidir exactamente una vez; si no, la generación falla), y el resultado se reconstruyó y comparó byte a byte con el empaquetado.

## 2. Cambios realizados

**Control de Ingreso**
- Nueva `fn_puede_control_ingreso_sobre(area, sector, proceso)`: administrador, o `control_ingreso=true` **y** visibilidad sobre esa solicitud (`fn_puede_ver`). Visibilidad `TODO` + flag permite operar entre áreas; visibilidad restringida limita a su alcance. No agrega un quinto tipo de alcance.
- `rpc_registrar_control_ingreso` y `rpc_finalizar_solicitud` la usan. `rpc_quitar_control_ingreso` exige además el interruptor general y `puede_quitar_control_ingreso`.
- `fn_permisos_para_scope` informa el permiso efectivo (con alcance) y todo `false` para un inactivo.
- Control de Ingreso no otorga aprobación, modificación, reapertura ni creación. Se validó el alcance de la **solicitud**; no se agregaron reglas sobre el alcance del empleado.

**Usuarios inactivos**
- `fn_usuario_activo()` y `fn_exigir_usuario_activo()`. `fn_es_admin`, `fn_es_desarrollador`, `fn_puede_*` y los flags devuelven `false` para un inactivo (también un ADMIN inactivo).
- Las **22 RPC** (SECURITY DEFINER) ejecutan `fn_exigir_usuario_activo()` como primera instrucción (no confían en RLS).
- Las políticas de lectura de catálogos, `usuarios`, `roles` y permisos exigen usuario activo.

**Ranking y flujo**
- Cancelar BORRADOR/EN_APROBACION/APROBADA devuelve las horas aprobadas al ranking. Eliminar borrador con empleados auto-aprobados y rechazar a un empleado ya APROBADO también lo revierten.
- Cambiar motivo o fechas en BORRADOR deja estados y ranking coherentes (re-aprobación con las horas nuevas si el motivo no requiere aprobación).
- `rpc_enviar_a_aprobacion` recalcula la situación; una solicitud sin aprobación necesaria pasa a APROBADA en vez de quedar en EN_APROBACION. **El evento de auditoría registra la situación final real**, no una constante.
- **MT-B se conserva**: con aprobación → con aprobación no invalida aprobaciones (condición `requiere_antes is distinct from requiere_despues`).

**Cancelar una FINALIZADA**
- No descuenta horas del ranking. La corrección de horas consolidadas es la nueva `rpc_rectificar_horas_ranking(solicitud_empleado_id, horas, motivo)`: solo ADMIN/DESARROLLADOR activos, motivo obligatorio, aplica a solicitudes FINALIZADAS (o canceladas estando FINALIZADAS), no excede las horas consolidadas (acumulado), no toca períodos ya archivados. Deja una fila en la nueva tabla `ranking_rectificaciones` (sin escritura directa; solo lectura para administradores por RLS) y un evento `RANKING_RECTIFICADO` en `auditoria_negocio`. Es la única funcionalidad nueva, necesaria para cumplir tu regla de "procedimiento explícito con trazabilidad".

**Privilegios**
- Se parte de `revoke execute on all functions in schema public from public, anon, authenticated` (en Supabase los privilegios por defecto otorgan EXECUTE directamente a `anon`/`authenticated`) y se otorga solo lo explícito.

## 3. Pruebas efectivamente ejecutadas

Ejecutadas con `ejecutar_pruebas_locales.sh`, cada suite en una base temporal nueva con el esquema completo instalado antes:

| Suite | Total | PASS | FAIL |
|---|---|---|---|
| `regresion_v2_1_final.sql` | 191 | 191 | 0 |
| `pruebas_control_ingreso_v2_1_final.sql` | 53 | 53 | 0 |

- Las 128 pruebas de regresión y las 34 de diagnóstico previas siguen presentes (comparadas por identificador) y se agregaron pruebas nuevas: usuarios inactivos (IN-1…IN-25: crear, modificar, aprobar, rechazar, Control de Ingreso, finalizar, cancelar, rectificar, reabrir, lectura, helpers y las 22 RPC), auditoría del envío (AU-1…AU-3), cancelación de FINALIZADAS (CA), rectificación (RC-1…RC-21) y Control de Ingreso con alcance.
- **Fechas:** las pruebas usan un fixture controlado (octubre 2026) con `dias_maximos_antiguedad` ampliado a 36500 solo dentro de la base de pruebas, para que no venzan con el tiempo. La regla real se prueba aparte con fechas relativas a `now()` (AN-1: 31 días supera el máximo de 30).
- **Arnés:** `\set ON_ERROR_STOP on`; precondiciones (`t.require`) que abortan si la preparación falló; verificación de rol y `auth.uid()` de cada sesión simulada; el script cuenta PASS/FAIL del log, exige que el total ejecutado coincida con el esperado y que PASS+FAIL = total, se detiene si falla la instalación del esquema o los stubs, y devuelve código distinto de 0 si algo falla.
- **Las pruebas detectan defectos (mutación, ejecutado):** se probaron variantes del esquema con un cambio de una línea y las suites fallaron como corresponde: quitar el chequeo de usuario activo en una RPC (2+1 fallos), volver a `fn_puede_control_ingreso()` sin alcance (2+2), cancelar FINALIZADA descontando ranking (3), registrar en el evento de envío la constante `EN_APROBACION` (1), romper MT-B con `if true` (1), y una preparación rota (la suite se detiene sin ejecutar pruebas). Un `DROP SCHEMA` agregado al esquema es rechazado por el script antes de instalarlo.
- **Protección del script (ejecutado):** rechaza host/IP en `LOCAL_PG_SOCKET_DIR`, ignora `PGHOST`/`DATABASE_URL`/`PGPORT`, exige socket UNIX local, se niega ante roles/extensiones/schemas típicos de Supabase, y solo borra la base temporal que él mismo creó.
- **Revisión estática del esquema instalado (ejecutada):** 29 tablas, todas con RLS; 0 funciones ejecutables por `anon`; 0 por PUBLIC; 57 SECURITY DEFINER, todas con `search_path` fijo; `authenticated` ejecuta 37 funciones (las `rpc_*` más 15 helpers de solo lectura de permisos); todas las vistas son `security_invoker`; `anon` solo tiene `SELECT` en `configuracion_apariencia` (a propósito, política pública); la escritura directa de `authenticated` está limitada por RLS a administración. El SQL del administrador inicial se probó localmente.

## 4. Limitaciones no verificadas

- **Supabase real no fue probado.** Quedan sin verificar allí: JWT y `auth.uid()` reales, roles `supabase_*`, privilegios por defecto reales, extensiones `pgcrypto`/`btree_gist`, comportamiento de PostgREST y del SQL Editor ante un error a mitad del script (si hace rollback total o deja estado parcial), y que el propietario de las funciones SECURITY DEFINER sea `postgres` con `BYPASSRLS` como se asume.
- Las sesiones de las pruebas se simulan con `request.jwt.uid` y `set role`, no con tokens.
- No hay pruebas de carga ni de concurrencia (dos usuarios aprobando a la vez).
- No se probó la aplicación Next.js contra este esquema (no hubo cambios de TypeScript).
- `fn_resetear_ranking_si_corresponde` requiere un job externo (pg_cron o Edge Function); no se programó nada.
- Los stubs locales reproducen solo lo mínimo de Supabase (roles, `auth.users`, `auth.uid()`, privilegios por defecto).

## 5. Decisiones funcionales aplicadas (según tus reglas)

Usuario inactivo sin operaciones (incluidas RPC); cancelar FINALIZADA no toca el ranking y se rectifica explícitamente; Control de Ingreso con alcance de visibilidad de la solicitud; sin reglas adicionales sobre el alcance del empleado. Cancelar otros estados sí revierte el ranking aprobado, porque esas horas nunca se consolidaron (justificación: el ranking acumulaba horas de solicitudes que ya no existen).

## 6. Contenido del ZIP

`0001_schema_inicial_consolidado_v2_1_SUPABASE.sql`, `regresion_v2_1_final.sql`, `pruebas_control_ingreso_v2_1_final.sql`, `ejecutar_pruebas_locales.sh`, `local_stubs/00_stubs_supabase_local.sql`, `INSTRUCCIONES_EJECUCION_SUPABASE.md`, `INFORME_FINAL_V2_1.md`.
