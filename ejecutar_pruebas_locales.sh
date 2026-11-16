#!/usr/bin/env bash
# ============================================================================
# Pruebas LOCALES de Horas Extras V2.1 en un PostgreSQL local (NO Supabase).
#
#   bash ejecutar_pruebas_locales.sh
#
# Qué hace (cada suite en una base temporal NUEVA, creada y borrada por este script):
#   1. instala los stubs locales (roles, auth.users, auth.uid, privilegios por defecto de Supabase)
#   2. instala el esquema consolidado V2.1 y luego la migración 0002 (se DETIENE en el primer error real)
#   3. ejecuta regresion_v2_1_final.sql y pruebas_control_ingreso_v2_1_final.sql
#   4. muestra total / PASS / FAIL de cada suite y sale con código distinto de 0 si algo falla
#
# PROTECCIONES (no se pueden desactivar por variables de entorno):
#   - Solo conecta por SOCKET UNIX local (ruta absoluta existente). Nunca TCP/host remoto.
#   - Ignora PGHOST/PGPORT/PGSERVICE/DATABASE_URL, etc. (los elimina del entorno).
#   - Se niega a correr si el servidor parece Supabase u otro entorno gestionado.
#   - Nunca ejecuta DROP SCHEMA. Lo único que borra es la base temporal horas_extras_test_<8 hex>
#     que ESTE script acaba de crear.
# Variables opcionales: LOCAL_PG_SOCKET_DIR (carpeta del socket), LOCAL_PG_PORT, LOCAL_PG_USER, KEEP_DB=1.
# ============================================================================
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$D/0001_schema_inicial_consolidado_v2_1_SUPABASE.sql"
MIG2="$D/0002_bandas_por_dia_y_observacion_ingreso.sql"
MIG3="$D/0003_segundo_logo_y_nombre.sql"
STUBS="$D/local_stubs/00_stubs_supabase_local.sql"
SUITES=("regresion_v2_1_final.sql" "pruebas_control_ingreso_v2_1_final.sql" "pruebas_0002.sql" "pruebas_0003.sql")

die() { echo "ERROR: $*" >&2; exit 2; }

# --- 1) nada de conexiones remotas heredadas del entorno
for v in PGHOST PGHOSTADDR PGPORT PGSERVICE PGSERVICEFILE PGDATABASE PGUSER PGPASSWORD PGPASSFILE PGSSLMODE PGSSLROOTCERT PGOPTIONS PGCONNECT_TIMEOUT DATABASE_URL SUPABASE_DB_URL SUPABASE_URL; do unset "$v"; done
command -v psql >/dev/null || die "no se encontró psql"
for f in "$SCHEMA" "$MIG2" "$MIG3" "$STUBS"; do [ -f "$f" ] || die "falta el archivo $f"; done
for s in "${SUITES[@]}"; do [ -f "$D/$s" ] || die "falta el archivo $D/$s"; done

# --- 2) el esquema de producción no puede contener instrucciones destructivas
if grep -Eiq '^[[:space:]]*(drop|truncate)[[:space:]]' "$SCHEMA"; then die "el esquema contiene DROP/TRUNCATE: se aborta"; fi
# la migración 0002 solo puede contener UN drop: el de la firma anterior de rpc_registrar_control_ingreso
if grep -Eiq '^[[:space:]]*(drop|truncate)[[:space:]]' "$MIG3"; then die "la migración 0003 contiene DROP/TRUNCATE: se aborta"; fi
if grep -Eiq '^[[:space:]]*truncate[[:space:]]' "$MIG2"; then die "la migración 0002 contiene TRUNCATE: se aborta"; fi
if grep -Ei '^[[:space:]]*drop[[:space:]]' "$MIG2" | grep -Eivq '^[[:space:]]*drop function if exists rpc_registrar_control_ingreso\(uuid, estado_asistencia_empleado, timestamptz\);[[:space:]]*$'; then die "la migración 0002 contiene un DROP no permitido: se aborta"; fi

# --- 3) socket UNIX local obligatorio
SOCK="${LOCAL_PG_SOCKET_DIR:-}"
if [ -z "$SOCK" ]; then for c in /var/run/postgresql /run/postgresql /tmp; do ls "$c"/.s.PGSQL.* >/dev/null 2>&1 && { SOCK="$c"; break; }; done; fi
[ -n "$SOCK" ] || die "no encontré un socket UNIX de PostgreSQL local. Definí LOCAL_PG_SOCKET_DIR (ruta absoluta de la carpeta del socket)."
case "$SOCK" in /*) ;; *) die "LOCAL_PG_SOCKET_DIR debe ser una ruta absoluta (se rechazan hosts/IP): '$SOCK'";; esac
[ -d "$SOCK" ] || die "'$SOCK' no es una carpeta"
PORT="${LOCAL_PG_PORT:-5432}"
[ -S "$SOCK/.s.PGSQL.$PORT" ] || die "no existe el socket $SOCK/.s.PGSQL.$PORT (definí LOCAL_PG_PORT si usa otro puerto)"
UARG=(); [ -n "${LOCAL_PG_USER:-}" ] && UARG=(-U "$LOCAL_PG_USER")
PSQL=(psql -X -q -h "$SOCK" -p "$PORT" "${UARG[@]}" -v ON_ERROR_STOP=1)

# --- 4) verificación dentro del servidor: socket local y NO Supabase
V=$("${PSQL[@]}" -d postgres -At -c "select (inet_server_addr() is null)::text || '|' ||
   exists(select 1 from pg_roles where rolname in ('supabase_admin','supabase_auth_admin','authenticator','pgbouncer','supabase_storage_admin'))::text || '|' ||
   exists(select 1 from pg_namespace where nspname in ('supabase_functions','supabase_migrations','realtime','vault','graphql','storage'))::text || '|' ||
   exists(select 1 from pg_extension where extname in ('pg_net','supabase_vault','pg_graphql','supautils'))::text || '|' ||
   current_setting('server_version_num')" 2>&1) || die "no pude conectar por socket local: $V"
IFS='|' read -r ES_LOCAL R_SUPA S_SUPA E_SUPA VER <<<"$V"
[ "$ES_LOCAL" = "true" ] || die "la conexión NO es por socket UNIX local (inet_server_addr no es nulo): se aborta"
if [ "$R_SUPA" = "true" ] || [ "$S_SUPA" = "true" ] || [ "$E_SUPA" = "true" ]; then die "el servidor parece Supabase/gestionado (roles, schemas o extensiones propios): se aborta. Este script solo corre contra un PostgreSQL local de pruebas."; fi
echo "Servidor local OK (socket $SOCK, puerto $PORT, server_version_num=$VER)"
[ "${VER:0:2}" = "16" ] || echo "AVISO: los resultados informados se obtuvieron en PostgreSQL 16; este servidor es $VER."

# --- 5) cada suite en una base temporal nueva
RES=0; SUMMARY=""
run_suite() {
  local suite="$1" db="horas_extras_test_$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  [[ "$db" =~ ^horas_extras_test_[0-9a-f]{8}$ ]] || die "nombre de base temporal inválido"
  "${PSQL[@]}" -d postgres -c "create database $db" >/dev/null 2>&1 || die "no pude crear la base temporal $db"
  cleanup() { [ "${KEEP_DB:-0}" = "1" ] && { echo "KEEP_DB=1: se conserva $db"; return; }; "${PSQL[@]}" -d postgres -c "drop database if exists $db" >/dev/null 2>&1; }
  echo; echo "=== $suite (base temporal $db) ==="
  if ! "${PSQL[@]}" -d "$db" -f "$STUBS" >"/tmp/$db.stubs.log" 2>&1; then echo "FALLÓ LA PREPARACIÓN (stubs). Primer error:"; grep -m1 -E 'ERROR|FATAL' "/tmp/$db.stubs.log"; cleanup; exit 1; fi
  if ! "${PSQL[@]}" -d "$db" -f "$SCHEMA" >"/tmp/$db.schema.log" 2>&1; then echo "FALLÓ LA INSTALACIÓN DEL ESQUEMA. Primer error real:"; grep -m1 -E 'ERROR|FATAL' "/tmp/$db.schema.log"; echo "(log completo: /tmp/$db.schema.log; no se ejecutaron pruebas)"; cleanup; exit 1; fi
  if ! "${PSQL[@]}" -d "$db" -f "$MIG2" >"/tmp/$db.mig2.log" 2>&1; then echo "FALLÓ LA MIGRACIÓN 0002. Primer error real:"; grep -m1 -E 'ERROR|FATAL' "/tmp/$db.mig2.log"; echo "(log completo: /tmp/$db.mig2.log; no se ejecutaron pruebas)"; cleanup; exit 1; fi
  if ! "${PSQL[@]}" -d "$db" -f "$MIG3" >"/tmp/$db.mig3.log" 2>&1; then echo "FALLÓ LA MIGRACIÓN 0003. Primer error real:"; grep -m1 -E 'ERROR|FATAL' "/tmp/$db.mig3.log"; cleanup; exit 1; fi
  echo "Esquema V2.1 + migraciones 0002 y 0003 instalados sin errores."
  local log="/tmp/$db.$suite.log"
  PGOPTIONS="-c client_min_messages=notice" "${PSQL[@]}" -d "$db" -f "$D/$suite" >"$log" 2>&1; local rc=$?
  local p f line tot esp
  p=$(grep -c 'NOTICE:  PASS' "$log"); f=$(grep -c 'NOTICE:  FAIL' "$log")
  line=$(grep -m1 'RESUMEN total=' "$log" | sed 's/.*RESUMEN //')
  tot=$(sed -n 's/.*total=\([0-9]*\).*/\1/p' <<<"$line"); esp=$(sed -n 's/.*esperado=\([0-9]*\).*/\1/p' <<<"$line")
  local estado="OK"
  if [ $rc -ne 0 ]; then estado="DETENIDA (psql rc=$rc): $(grep -m1 -E 'ERROR|FATAL' "$log" | sed 's/^psql:[^ ]* //')"; fi
  if [ -z "$line" ] && [ "$estado" = "OK" ]; then estado="SIN RESUMEN (la suite no llegó al final)"; fi
  if [ -n "$line" ] && { [ "$tot" != "$esp" ] || [ "$tot" != "$((p+f))" ]; }; then estado="INCONSISTENTE: resumen=$tot esperado=$esp PASS+FAIL contados=$((p+f))"; fi
  if [ "$estado" = "OK" ] && [ "$f" -gt 0 ]; then estado="CON FALLOS"; fi
  echo "Resultado: total=${tot:-?} PASS=$p FAIL=$f -> $estado"
  grep 'NOTICE:  FAIL' "$log" | sed 's/^psql:[^ ]* NOTICE:  /  /'
  SUMMARY+=$(printf '\n  %-42s total=%-4s PASS=%-4s FAIL=%-3s %s' "$suite" "${tot:-?}" "$p" "$f" "$estado")
  [ "$estado" = "OK" ] || RES=1
  cleanup
}
for s in "${SUITES[@]}"; do run_suite "$s"; done
echo; echo "=================== RESUMEN FINAL ==================="; echo "$SUMMARY"; echo
[ $RES -eq 0 ] && echo "TODAS LAS SUITES OK (PostgreSQL local; NO equivale a verificar Supabase real)." || echo "HAY SUITES CON PROBLEMAS: revisá los logs en /tmp/horas_extras_test_*.log"
exit $RES
