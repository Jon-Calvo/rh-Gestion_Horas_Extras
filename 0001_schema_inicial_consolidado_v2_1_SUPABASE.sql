-- ============================================================================
-- 0001 · SCHEMA INICIAL CONSOLIDADO — horas-extras (V2.1 · SUPABASE)
-- ----------------------------------------------------------------------------
-- Migración única, construida desde cero. Reemplaza lo que hasta ahora
-- eran 53 migraciones separadas (0001-0039 ya aplicadas + Etapas 1-4B
-- diseñadas pero nunca aplicadas), MÁS las correcciones del cierre
-- funcional V2: scope real vía usuario_permiso_scopes, motor de cálculo
-- multi-tramo, timezone configurable, rol RRHH, eliminación de borradores
-- siempre a ELIMINADA, control_ingreso_permite_eliminar conectada.
--
-- V2.1: integra TODAS las correcciones de la auditoría (sin parches
-- posteriores). Para ejecutar UNA sola vez en un proyecto Supabase nuevo y
-- limpio. No contiene ninguna instrucción destructiva (sin DROP/TRUNCATE).
--   - Control de Ingreso (registrar/finalizar/quitar) respeta el alcance de
--     VISIBILIDAD de la solicitud (fn_puede_control_ingreso_sobre).
--   - Usuarios con usuarios.activo = false no pueden operar (helpers, RLS y
--     TODAS las RPC SECURITY DEFINER exigen fn_exigir_usuario_activo()).
--   - Ranking coherente al cancelar/eliminar borrador/rechazar/modificar
--     motivo o fechas. Cancelar una FINALIZADA NO toca el ranking: la
--     corrección de horas consolidadas es rpc_rectificar_horas_ranking().
--   - Solicitudes con motivo sin aprobación ya no quedan en EN_APROBACION.
-- ============================================================================


-- ============================================================================
-- PARTE 1 · Extensiones
-- ============================================================================
create extension if not exists pgcrypto;
create extension if not exists btree_gist;


-- ============================================================================
-- PARTE 2 · Tipos / enums
-- ============================================================================

create type nivel_permiso as enum ('TODO', 'AREA', 'SECTOR', 'PROCESO', 'NADA');
create type estado_empleado as enum ('ACTIVO', 'INACTIVO');
create type estado_empleado_aprobacion as enum ('PENDIENTE_APROBACION', 'APROBADO', 'RECHAZADO');
create type accion_auditoria as enum ('INSERT', 'UPDATE', 'DELETE', 'APPROVE', 'REJECT', 'REOPEN');
create type origen_auditoria as enum ('USUARIO', 'SISTEMA');
create type tipo_motivo as enum ('PRODUCTIVO', 'IMPRODUCTIVO');

create domain hex_color as text check (value ~ '^#[0-9A-Fa-f]{6}$');

create type bloqueo_seleccion as enum ('PERMITIDO', 'ADVERTENCIA', 'BLOQUEADO');
create type nivel_auditoria_negocio as enum ('DESACTIVADA', 'BASICA', 'COMPLETA');

create type situacion_solicitud as enum (
  'BORRADOR', 'EN_APROBACION', 'APROBADA', 'RECHAZADA', 'FINALIZADA', 'CANCELADA', 'ELIMINADA'
);
create type estado_asistencia_empleado as enum (
  'NO_APLICA', 'PENDIENTE_INGRESO', 'INGRESO_REGISTRADO', 'YA_ESTABA_EN_PLANTA', 'NO_PRESENTADO'
);
create type estado_registro_empleado as enum ('ACTIVO', 'REEMPLAZADO', 'CANCELADO');


-- ============================================================================
-- PARTE 3 · Función genérica de updated_at
-- ============================================================================
create or replace function fn_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ============================================================================
-- PARTE 4 · Estructura organizacional
-- ============================================================================

create table areas (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table sectores (
  id          uuid primary key default gen_random_uuid(),
  area_id     uuid not null references areas(id),
  nombre      text not null,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (area_id, nombre)
);

create table procesos (
  id          uuid primary key default gen_random_uuid(),
  sector_id   uuid not null references sectores(id),
  nombre      text not null,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (sector_id, nombre)
);

create trigger trg_updated_at_areas before update on areas for each row execute function fn_set_updated_at();
create trigger trg_updated_at_sectores before update on sectores for each row execute function fn_set_updated_at();
create trigger trg_updated_at_procesos before update on procesos for each row execute function fn_set_updated_at();

create index idx_sectores_area on sectores(area_id);
create index idx_procesos_sector on procesos(sector_id);


-- ============================================================================
-- PARTE 5 · Tablas maestras
-- ============================================================================

create table categoria_tipos (
  id            uuid primary key default gen_random_uuid(),
  codigo        text not null unique,
  descripcion   text,
  activo        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_updated_at_categoria_tipos before update on categoria_tipos for each row execute function fn_set_updated_at();

create table categorias (
  id                uuid primary key default gen_random_uuid(),
  categoria_tipo_id uuid not null references categoria_tipos(id),
  valor_hora        numeric(12,4) not null,
  moneda            text not null,
  vigente_desde     date not null,
  vigente_hasta     date,
  created_at        timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde),
  exclude using gist (
    categoria_tipo_id with =,
    daterange(vigente_desde, vigente_hasta, '[]') with &&
  )
);

create index idx_categorias_tipo on categorias(categoria_tipo_id);

create table bandas_horarias (
  id                    uuid primary key default gen_random_uuid(),
  descripcion           text not null,
  hora_desde            time not null,
  hora_hasta            time not null,
  multiplicador         numeric(5,2) not null default 1,
  -- Si un tramo cae en feriado y este valor está cargado, reemplaza al
  -- multiplicador normal de esta banda para ese tramo. Si es feriado pero
  -- este campo es NULL, se usa el multiplicador normal (evita importes
  -- nulos inesperados) — regla confirmada en el cierre funcional V2.
  multiplicador_feriado numeric(5,2),
  activo                boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  -- Corrección obligatoria B: un rango de largo cero (desde = hasta) es
  -- ambiguo (¿0 horas o 24 horas?) — nunca una configuración válida.
  check (hora_desde <> hora_hasta)
);

create trigger trg_updated_at_bandas_horarias before update on bandas_horarias for each row execute function fn_set_updated_at();

-- ----------------------------------------------------------------------------
-- Corrección obligatoria B — selección determinística de banda horaria.
-- ----------------------------------------------------------------------------
-- bandas_horarias no tiene ninguna restricción de tabla que impida cargar
-- dos bandas activas cuyos rangos horarios se solapen (cada banda es un
-- rango [hora_desde, hora_hasta) sobre un reloj de 24 h, que puede cruzar
-- medianoche cuando hora_desde > hora_hasta — un EXCLUDE con `time`/
-- `timerange` simple no modela ese caso circular). Sin esta validación,
-- fn_calcular_detalle_solicitud_empleado podía terminar con más de una
-- banda aplicable al mismo instante y elegir una arbitrariamente
-- (`limit 1` sin `order by`).
--
-- Se resuelve en dos niveles, ambos obligatorios:
--   1) Acá: se bloquea en el origen — no se puede guardar una banda activa
--      que se solape con otra banda activa ya existente.
--   2) Más abajo, dentro de fn_calcular_detalle_solicitud_empleado: el
--      motor de cálculo vuelve a validar en tiempo de cálculo (0 bandas
--      aplicables → error; 2+ aplicables → error), como defensa en
--      profundidad frente a datos cargados antes de esta corrección o
--      cualquier vía de escritura futura que no pase por este trigger.
--
-- fn_rangos_banda_horaria() convierte [hora_desde, hora_hasta) a uno o dos
-- int4range en minutos-desde-medianoche (0..1440): un solo rango si no
-- cruza medianoche, dos rangos si la cruza (ej. 22:00–06:00 → [1320,1440)
-- y [0,360)). Comparar con && entre todas las combinaciones de rangos de
-- dos bandas detecta cualquier solapamiento real, incluyendo el caso de
-- cruce de medianoche.
create or replace function fn_rangos_banda_horaria(p_hora_desde time, p_hora_hasta time)
returns int4range[]
language sql
immutable
as $$
  select case
    when p_hora_desde < p_hora_hasta then
      array[int4range(
        (extract(epoch from p_hora_desde) / 60)::int,
        (extract(epoch from p_hora_hasta) / 60)::int,
        '[)'
      )]
    else
      array[
        int4range((extract(epoch from p_hora_desde) / 60)::int, 1440, '[)'),
        int4range(0, (extract(epoch from p_hora_hasta) / 60)::int, '[)')
      ]
  end;
$$;

create or replace function fn_validar_solapamiento_bandas_horarias()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rangos_nuevo int4range[];
  v_rangos_otro  int4range[];
  v_rec          record;
  v_r1           int4range;
  v_r2           int4range;
begin
  if not new.activo then
    return new;
  end if;

  v_rangos_nuevo := fn_rangos_banda_horaria(new.hora_desde, new.hora_hasta);

  for v_rec in
    select id, descripcion, hora_desde, hora_hasta
    from bandas_horarias
    where activo and id <> new.id
  loop
    v_rangos_otro := fn_rangos_banda_horaria(v_rec.hora_desde, v_rec.hora_hasta);
    foreach v_r1 in array v_rangos_nuevo loop
      foreach v_r2 in array v_rangos_otro loop
        if v_r1 && v_r2 then
          raise exception 'La banda horaria "%" (% - %) se superpone con la banda activa existente "%" (% - %) — las bandas horarias activas no pueden solaparse',
            new.descripcion, new.hora_desde, new.hora_hasta, v_rec.descripcion, v_rec.hora_desde, v_rec.hora_hasta;
        end if;
      end loop;
    end loop;
  end loop;

  return new;
end;
$$;

create trigger trg_validar_solapamiento_bandas_horarias
  before insert or update of hora_desde, hora_hasta, activo on bandas_horarias
  for each row execute function fn_validar_solapamiento_bandas_horarias();

create table feriados (
  id          uuid primary key default gen_random_uuid(),
  fecha       date not null unique,
  descripcion text,
  created_at  timestamptz not null default now()
);

create table motivos (
  id                    uuid primary key default gen_random_uuid(),
  motivo                text not null unique,
  tipo                  tipo_motivo not null default 'PRODUCTIVO',
  requiere_aprobacion   boolean not null default true,
  activo                boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create trigger trg_updated_at_motivos before update on motivos for each row execute function fn_set_updated_at();

create table ib_configuracion (
  id            uuid primary key default gen_random_uuid(),
  descripcion   text not null unique,
  activo        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_updated_at_ib_configuracion before update on ib_configuracion for each row execute function fn_set_updated_at();

comment on table ib_configuracion is
  'Catálogo de valores de IB. Dato propio del empleado, cargado por RRHH '
  '(manual o Excel) — nunca se deriva de ningún ranking.';

create table bandas_ranking (
  id                  uuid primary key default gen_random_uuid(),
  descripcion         text not null,
  ranking_inferior    numeric(10,2) not null,
  ranking_superior    numeric(10,2),
  color               hex_color not null,
  aplica_a_solicitud  boolean not null default true,
  aplica_a_real       boolean not null default false,
  bloqueo_seleccion   bloqueo_seleccion not null default 'PERMITIDO',
  activo              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (ranking_superior is null or ranking_superior >= ranking_inferior),
  check (aplica_a_solicitud or aplica_a_real),
  exclude using gist (
    numrange(ranking_inferior, ranking_superior) with &&
  ) where (aplica_a_solicitud)
);

alter table bandas_ranking add constraint bandas_ranking_real_sin_solapar
  exclude using gist (
    numrange(ranking_inferior, ranking_superior) with &&
  ) where (aplica_a_real);

create trigger trg_updated_at_bandas_ranking before update on bandas_ranking for each row execute function fn_set_updated_at();
-- ============================================================================
-- PARTE 6 · Enums adicionales
-- ============================================================================
create type periodo_reseteo as enum ('MENSUAL', 'TRIMESTRAL', 'ANUAL');
create type tema_app as enum ('CLARO', 'OSCURO', 'SISTEMA');


-- ============================================================================
-- PARTE 7 · Usuarios, roles y permisos
-- ----------------------------------------------------------------------------
-- Rol DESARROLLADOR protegido + rol RRHH (cierre funcional V2: capacidades
-- operativas amplias SIN bypass especial en código — sus permisos salen
-- 100% de usuario_permisos/usuario_permiso_scopes, igual que cualquier
-- otro usuario; fn_es_admin() NO lo incluye). Sin VISUALIZADOR (eliminado
-- en el cierre V2: no había diferencia de negocio real con CONSULTA).
-- ============================================================================

create table usuarios (
  id                uuid primary key references auth.users(id) on delete cascade,
  nombre_completo   text not null,
  activo            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create trigger trg_updated_at_usuarios before update on usuarios for each row execute function fn_set_updated_at();

create table roles (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null unique,
  descripcion   text
);

insert into roles (nombre, descripcion) values
  ('DESARROLLADOR', 'Acceso total al sistema. Protegido: ningún administrador puede quitarle el rol, sus permisos, desactivarlo ni eliminarlo.'),
  ('ADMIN', 'Administración completa del sistema (se muestra como "Administrador" en la interfaz, sin cambiar este valor interno).'),
  ('RRHH', 'Capacidades operativas amplias (empleados, solicitudes, importar/exportar) sin acceso a configuración estructural del sistema — sin bypass especial en código, sus capacidades salen 100% de su configuración de permisos, igual que cualquier otro usuario.'),
  ('RESPONSABLE', 'Crea y gestiona solicitudes de horas extra dentro de su scope.'),
  ('APROBADOR', 'Aprueba/rechaza empleados dentro de su scope.'),
  ('CONTROL_INGRESO', 'Registra y quita control de ingreso.'),
  ('CONSULTA', 'Solo lectura, según su scope de visibilidad.');

create table usuario_roles (
  usuario_id  uuid not null references usuarios(id) on delete cascade,
  rol_id      uuid not null references roles(id),
  primary key (usuario_id, rol_id)
);

create table usuario_permisos (
  usuario_id                    uuid primary key references usuarios(id) on delete cascade,
  visibilidad_nivel             nivel_permiso not null default 'NADA',
  aprobacion_nivel              nivel_permiso not null default 'NADA',
  modificacion_nivel            nivel_permiso not null default 'NADA',
  reapertura_nivel              nivel_permiso not null default 'NADA',
  control_ingreso               boolean not null default false,
  puede_ver_importes            boolean not null default true,
  puede_eliminar_cancelar       boolean not null default false,
  puede_importar                boolean not null default false,
  puede_exportar                boolean not null default false,
  puede_quitar_control_ingreso  boolean not null default false,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now()
);

create trigger trg_updated_at_usuario_permisos before update on usuario_permisos for each row execute function fn_set_updated_at();

comment on column usuario_permisos.puede_ver_importes is
  'Default true a propósito: sin este permiso, usuarios ya existentes '
  'quedarían bloqueados de ver importes que antes veían. El resto de los '
  'permisos booleanos son capacidades sensibles nuevas — default false.';

-- ----------------------------------------------------------------------------
-- Scope real del usuario (cierre funcional V2) — NUNCA se deriva de
-- `empleados`. Un scope independiente por tipo de permiso; en esta V2, un
-- solo scope por tipo (no una lista).
-- ----------------------------------------------------------------------------
create table usuario_permiso_scopes (
  usuario_id    uuid not null references usuarios(id) on delete cascade,
  tipo_permiso  text not null check (tipo_permiso in ('VISIBILIDAD', 'APROBACION', 'MODIFICACION', 'REAPERTURA')),
  area_id       uuid references areas(id),
  sector_id     uuid references sectores(id),
  proceso_id    uuid references procesos(id),
  primary key (usuario_id, tipo_permiso)
);

comment on table usuario_permiso_scopes is
  'Scope real de cada usuario, independiente por tipo de permiso. Se usa '
  'el campo que corresponda según el nivel configurado en '
  'usuario_permisos (AREA→area_id, SECTOR→sector_id, PROCESO→proceso_id; '
  'TODO/NADA no necesitan ningún valor acá). Nunca se deriva de empleados.';

-- ----------------------------------------------------------------------------
-- Protección del rol DESARROLLADOR — triggers, no solo RLS.
-- ----------------------------------------------------------------------------

create or replace function fn_proteger_usuario_desarrollador()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_es_desarrollador boolean;
begin
  select exists (
    select 1 from usuario_roles ur join roles r on r.id = ur.rol_id
    where ur.usuario_id = old.id and r.nombre = 'DESARROLLADOR'
  ) into v_es_desarrollador;

  if not v_es_desarrollador then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    raise exception 'No se puede eliminar a un usuario con rol DESARROLLADOR';
  end if;

  if tg_op = 'UPDATE' and new.activo = false and old.activo = true then
    raise exception 'No se puede desactivar a un usuario con rol DESARROLLADOR';
  end if;

  return new;
end;
$$;

create trigger trg_proteger_usuario_desarrollador
  before update or delete on usuarios
  for each row execute function fn_proteger_usuario_desarrollador();

create or replace function fn_proteger_rol_desarrollador()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nombre_rol text;
begin
  select nombre into v_nombre_rol from roles where id = old.rol_id;
  if v_nombre_rol = 'DESARROLLADOR' then
    raise exception 'No se puede quitar el rol DESARROLLADOR';
  end if;
  return old;
end;
$$;

create trigger trg_proteger_rol_desarrollador
  before delete on usuario_roles
  for each row execute function fn_proteger_rol_desarrollador();

create or replace function fn_proteger_permisos_desarrollador()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_es_desarrollador boolean;
begin
  select exists (
    select 1 from usuario_roles ur join roles r on r.id = ur.rol_id
    where ur.usuario_id = old.usuario_id and r.nombre = 'DESARROLLADOR'
  ) into v_es_desarrollador;

  if v_es_desarrollador then
    raise exception 'No se pueden modificar los permisos de un usuario DESARROLLADOR';
  end if;

  return new;
end;
$$;

create trigger trg_proteger_permisos_desarrollador
  before update on usuario_permisos
  for each row execute function fn_proteger_permisos_desarrollador();


-- ============================================================================
-- PARTE 8 · Empleados y ranking
-- ============================================================================

create table empleados (
  id                    uuid primary key default gen_random_uuid(),
  legajo                text not null unique,
  nombre_completo       text not null,
  categoria_id          uuid not null references categoria_tipos(id),
  area_id               uuid references areas(id),
  sector_id             uuid references sectores(id),
  proceso_id            uuid references procesos(id),
  estado                estado_empleado not null default 'ACTIVO',
  ranking_horas         numeric(10,2) not null default 0,
  ranking_horas_real    numeric(10,2),
  ib_id                 uuid references ib_configuracion(id),
  fecha_alta            date not null default current_date,
  fecha_baja            date,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create trigger trg_updated_at_empleados before update on empleados for each row execute function fn_set_updated_at();

create index idx_empleados_area on empleados(area_id);
create index idx_empleados_sector on empleados(sector_id);
create index idx_empleados_proceso on empleados(proceso_id);
create index idx_empleados_estado on empleados(estado);

comment on column empleados.ranking_horas is
  'Ranking SEGÚN SOLICITUD. No se deriva ib_id de este valor bajo ninguna circunstancia.';

create table ranking_horas_historico (
  id                    uuid primary key default gen_random_uuid(),
  empleado_id           uuid not null references empleados(id),
  ranking_horas_final   numeric(10,2) not null,
  fecha_reseteo         timestamptz not null default now()
);

create index idx_ranking_historico_empleado on ranking_horas_historico(empleado_id);


-- ============================================================================
-- PARTE 9 · Configuración general y de apariencia
-- ----------------------------------------------------------------------------
-- zona_horaria (cierre funcional V2): referencia para TODA determinación
-- de "día calendario" del sistema — antigüedad y motor de cálculo
-- multi-tramo, nunca el timezone del servidor ni el de la sesión.
-- ============================================================================

create table configuracion_general (
  id                                 smallint primary key default 1,
  dias_maximos_antiguedad            integer not null default 30,
  emails_activos                     boolean not null default true,
  ranking_periodo                    periodo_reseteo not null default 'MENSUAL',
  control_ingreso_permite_eliminar   boolean not null default false,
  nivel_auditoria_negocio            nivel_auditoria_negocio not null default 'BASICA',
  retencion_auditoria_meses          integer,
  zona_horaria                       text not null default 'America/Argentina/Buenos_Aires',
  -- Corrección obligatoria E: instante del último reseteo de ranking
  -- efectivamente ejecutado por fn_resetear_ranking_si_corresponde(). NULL
  -- = todavía no hubo ningún reseteo. Se usa para que una aprobación de un
  -- período ya cerrado y archivado (anterior a este instante) nunca reste
  -- horas del ranking_horas del período vigente al revertirse/invalidarse.
  ultimo_reseteo_ranking             timestamptz,
  created_at                         timestamptz not null default now(),
  updated_at                         timestamptz not null default now(),
  check (id = 1)
);

create trigger trg_updated_at_configuracion_general before update on configuracion_general for each row execute function fn_set_updated_at();

insert into configuracion_general (id) values (1);

comment on column configuracion_general.retencion_auditoria_meses is
  'Meses a conservar la auditoría de negocio antes de purgar/archivar. '
  'NULL = indefinido. Es solo configuración: no existe todavía ningún job '
  'que la aplique — mejora futura documentada, no implementada.';

comment on column configuracion_general.zona_horaria is
  'Referencia para toda determinación de "día calendario" (antigüedad, '
  'motor de cálculo multi-tramo). Nunca se usa el timezone del servidor '
  'ni el de la sesión del usuario.';

create table configuracion_apariencia (
  id                      smallint primary key default 1,
  nombre_empresa          text,
  logo_url                text,
  color_primario          hex_color not null default '#2563EB',
  color_primario_hover    hex_color not null default '#1D4ED8',
  color_secundario        hex_color not null default '#64748B',
  color_acento            hex_color not null default '#7C3AED',
  color_exito             hex_color not null default '#16A34A',
  color_advertencia       hex_color not null default '#D97706',
  color_error             hex_color not null default '#DC2626',
  tema_predeterminado     tema_app not null default 'SISTEMA',
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (id = 1)
);

create trigger trg_updated_at_configuracion_apariencia before update on configuracion_apariencia for each row execute function fn_set_updated_at();

insert into configuracion_apariencia (id) values (1);

create table niveles_aprobacion_config (
  id            uuid primary key default gen_random_uuid(),
  nivel         integer not null unique,
  descripcion   text
);
-- ============================================================================
-- PARTE 10 · Solicitudes — con la máquina de estados de la Etapa 4A/4B
-- integrada de nacimiento.
-- ============================================================================

create table solicitudes (
  id                    uuid primary key default gen_random_uuid(),
  numero                text unique,
  situacion             situacion_solicitud not null default 'BORRADOR',
  solicitante_id        uuid not null references usuarios(id),
  area_id               uuid not null references areas(id),
  sector_id             uuid not null references sectores(id),
  proceso_id            uuid not null references procesos(id),
  fecha_hora_inicio     timestamptz not null,
  fecha_hora_fin        timestamptz not null,
  motivo_id             uuid not null references motivos(id),
  observacion           text,
  moneda                text,
  fecha_hora_solicitud  timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (fecha_hora_fin > fecha_hora_inicio)
);

create trigger trg_updated_at_solicitudes before update on solicitudes for each row execute function fn_set_updated_at();

create index idx_solicitudes_area on solicitudes(area_id);
create index idx_solicitudes_sector on solicitudes(sector_id);
create index idx_solicitudes_proceso on solicitudes(proceso_id);
create index idx_solicitudes_situacion on solicitudes(situacion);
create index idx_solicitudes_solicitante on solicitudes(solicitante_id);

create table contador_solicitudes (
  id              smallint primary key default 1,
  ultimo_numero   integer not null default 0,
  check (id = 1)
);

insert into contador_solicitudes (id) values (1);

create or replace function fn_asignar_numero_solicitud()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_numero integer;
begin
  update contador_solicitudes set ultimo_numero = ultimo_numero + 1 where id = 1
    returning ultimo_numero into v_numero;
  new.numero := 'SOL-' || to_char(now(), 'YYYY') || '-' || lpad(v_numero::text, 6, '0');
  return new;
end;
$$;

create trigger trg_asignar_numero_solicitud
  before insert on solicitudes
  for each row execute function fn_asignar_numero_solicitud();

-- ============================================================================
-- PARTE 11 · Empleados dentro de una solicitud
-- ============================================================================

create table solicitud_empleados (
  id                          uuid primary key default gen_random_uuid(),
  solicitud_id                uuid not null references solicitudes(id) on delete cascade,
  empleado_id                 uuid not null references empleados(id),

  estado_aprobacion           estado_empleado_aprobacion not null default 'PENDIENTE_APROBACION',
  estado_asistencia           estado_asistencia_empleado not null default 'NO_APLICA',
  estado_registro             estado_registro_empleado not null default 'ACTIVO',
  reemplaza_a                 uuid references solicitud_empleados(id),
  motivo_rechazo              text,

  ranking_horas_al_momento    numeric(10,2),
  ib_al_momento               uuid references ib_configuracion(id),

  total_horas                 numeric(10,2) not null default 0,
  total_importe                numeric(12,2) not null default 0,

  fecha_hora_aprobacion       timestamptz,
  usuario_aprobacion_id       uuid references usuarios(id),

  fecha_hora_ingreso          timestamptz,
  usuario_control_ingreso_id  uuid references usuarios(id),

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  check (
    estado_asistencia = 'NO_APLICA'
    or (estado_aprobacion = 'APROBADO' and estado_registro = 'ACTIVO')
  ),
  check (estado_aprobacion <> 'RECHAZADO' or motivo_rechazo is not null)
);

create trigger trg_updated_at_solicitud_empleados before update on solicitud_empleados for each row execute function fn_set_updated_at();

create unique index uq_solicitud_empleados_activo
  on solicitud_empleados(solicitud_id, empleado_id)
  where estado_registro = 'ACTIVO';

create index idx_solicitud_empleados_solicitud on solicitud_empleados(solicitud_id);
create index idx_solicitud_empleados_empleado on solicitud_empleados(empleado_id);
create index idx_solicitud_empleados_registro on solicitud_empleados(estado_registro);
create index idx_solicitud_empleados_reemplaza_a on solicitud_empleados(reemplaza_a) where reemplaza_a is not null;
-- Soporte de la política usuarios_select (PARTE 30).
create index idx_solicitud_empleados_usuario_aprob on solicitud_empleados(usuario_aprobacion_id) where usuario_aprobacion_id is not null;
create index idx_solicitud_empleados_usuario_ingreso on solicitud_empleados(usuario_control_ingreso_id) where usuario_control_ingreso_id is not null;

create or replace function fn_normalizar_asistencia()
returns trigger
language plpgsql
as $$
begin
  if new.estado_aprobacion = 'APROBADO' and new.estado_registro = 'ACTIVO' then
    if old.estado_aprobacion is distinct from new.estado_aprobacion
       or old.estado_registro is distinct from new.estado_registro then
      if new.estado_asistencia = 'NO_APLICA' then
        new.estado_asistencia := 'PENDIENTE_INGRESO';
      end if;
    end if;
  else
    new.estado_asistencia := 'NO_APLICA';
  end if;

  if new.estado_aprobacion <> 'RECHAZADO' then
    new.motivo_rechazo := null;
  end if;

  return new;
end;
$$;

create trigger trg_normalizar_asistencia
  before insert or update of estado_aprobacion, estado_registro on solicitud_empleados
  for each row execute function fn_normalizar_asistencia();

create or replace function fn_solicitud_empleados_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empleado empleados;
begin
  select * into v_empleado from empleados where id = new.empleado_id;
  new.ranking_horas_al_momento := v_empleado.ranking_horas;
  new.ib_al_momento := v_empleado.ib_id;
  return new;
end;
$$;

create trigger trg_solicitud_empleados_before_insert
  before insert on solicitud_empleados
  for each row execute function fn_solicitud_empleados_before_insert();


-- ============================================================================
-- PARTE 12 · Detalle de cálculo de horas/importe (motor de cálculo)
-- ============================================================================

create table solicitud_empleado_detalle (
  id                      uuid primary key default gen_random_uuid(),
  solicitud_empleado_id   uuid not null references solicitud_empleados(id) on delete cascade,
  fecha                   date not null,
  -- Corrección obligatoria B: ya no puede ser NULL — el motor de cálculo
  -- ahora falla explícitamente si no hay una banda aplicable en vez de
  -- insertar una fila sin banda (ver fn_calcular_detalle_solicitud_empleado).
  banda_horaria_id        uuid not null references bandas_horarias(id),
  horas                   numeric(10,2) not null,
  valor_hora              numeric(12,4) not null,
  -- Moneda de ESTE tramo puntual (puede diferir entre tramos de un mismo
  -- empleado si la vigencia del valor-hora cruza un cambio de moneda, y es
  -- lo que permite a fn_calcular_detalle_solicitud_empleado detectarlo y
  -- validar consistencia real tramo por tramo, no solo contra la fecha de
  -- inicio de la solicitud — corrección confirmada #3).
  moneda                  text not null,
  multiplicador           numeric(5,2) not null default 1,
  importe                 numeric(12,2) not null,
  es_feriado              boolean not null default false,
  created_at              timestamptz not null default now()
);

create index idx_solicitud_empleado_detalle_se on solicitud_empleado_detalle(solicitud_empleado_id);

create table solicitud_aprobaciones (
  id              uuid primary key default gen_random_uuid(),
  solicitud_id    uuid not null references solicitudes(id) on delete cascade,
  nivel           integer not null default 1,
  usuario_id      uuid references usuarios(id),
  aprobado        boolean,
  fecha_hora      timestamptz,
  created_at      timestamptz not null default now()
);

create index idx_solicitud_aprobaciones_solicitud on solicitud_aprobaciones(solicitud_id);


-- ============================================================================
-- PARTE 13 · Notificaciones (log de envíos)
-- ============================================================================

create table notificaciones_log (
  id            uuid primary key default gen_random_uuid(),
  solicitud_id  uuid references solicitudes(id),
  tipo          text not null,
  destinatario  text,
  enviado       boolean not null default false,
  error         text,
  created_at    timestamptz not null default now()
);


-- ============================================================================
-- PARTE 14 · Auditoría técnica (genérica) + auditoría de negocio
-- ============================================================================

create table auditoria (
  id                  uuid primary key default gen_random_uuid(),
  fecha               timestamptz not null default now(),
  usuario_id          uuid references usuarios(id),
  accion              accion_auditoria not null,
  tabla               text not null,
  registro_id         uuid,
  origen              origen_auditoria not null default 'USUARIO',
  datos_anteriores    jsonb,
  datos_nuevos        jsonb
);

create index idx_auditoria_tabla_registro on auditoria(tabla, registro_id);
create index idx_auditoria_fecha on auditoria(fecha desc);

create table auditoria_negocio (
  id                        uuid primary key default gen_random_uuid(),
  fecha_hora                timestamptz not null default now(),
  usuario_id                uuid references usuarios(id),
  origen                    origen_auditoria not null default 'USUARIO',
  nivel                     nivel_auditoria_negocio not null,
  modulo                    text not null,
  entidad_tipo              text not null,
  entidad_id                uuid,
  entidad_relacionada_tipo  text,
  entidad_relacionada_id    uuid,
  evento                    text not null,
  estado_anterior           text,
  estado_nuevo              text,
  datos                     jsonb
);

create index idx_auditoria_negocio_entidad on auditoria_negocio(entidad_tipo, entidad_id);
create index idx_auditoria_negocio_relacionada on auditoria_negocio(entidad_relacionada_tipo, entidad_relacionada_id) where entidad_relacionada_id is not null;
create index idx_auditoria_negocio_fecha on auditoria_negocio(fecha_hora desc);
create index idx_auditoria_negocio_modulo on auditoria_negocio(modulo);

comment on table auditoria_negocio is
  'Genérica a propósito (modulo/entidad_tipo/evento son TEXT, no enum) '
  'para sumar futuros módulos sin alterar tipos por cada evento nuevo. '
  'Todo insert pasa por fn_registrar_evento_negocio().';
-- ============================================================================
-- PARTE 15 · Helpers de permisos y scope (cierre funcional V2)
-- ----------------------------------------------------------------------------
-- fn_es_admin() incluye DESARROLLADOR, NO incluye RRHH (RRHH no tiene
-- ningún bypass de código — sus capacidades salen 100% de su
-- configuración de permisos normal).
-- ============================================================================

-- V2.1: un usuario con usuarios.activo = false NUNCA recibe ningún permiso,
-- aunque conserve roles/permisos asignados. fn_usuario_activo() es la única
-- fuente de verdad; fn_exigir_usuario_activo() la usan TODAS las RPC como
-- primera instrucción (las RPC son SECURITY DEFINER: no pueden confiar en
-- que RLS se aplique al usuario final).
create or replace function fn_usuario_activo()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select activo from usuarios where id = auth.uid()), false);
$$;

create or replace function fn_exigir_usuario_activo()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not fn_usuario_activo() then
    raise exception 'Usuario inactivo o sin sesión válida: operación no permitida';
  end if;
end;
$$;

create or replace function fn_es_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_usuario_activo() and exists (
    select 1 from usuario_roles ur join roles r on r.id = ur.rol_id
    where ur.usuario_id = auth.uid() and r.nombre in ('ADMIN', 'DESARROLLADOR')
  );
$$;

create or replace function fn_es_desarrollador()
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_usuario_activo() and exists (
    select 1 from usuario_roles ur join roles r on r.id = ur.rol_id
    where ur.usuario_id = auth.uid() and r.nombre = 'DESARROLLADOR'
  );
$$;

create or replace function fn_scope_ok(
  p_nivel       nivel_permiso,
  p_area_id     uuid,
  p_sector_id   uuid,
  p_proceso_id  uuid,
  p_usuario_area_id    uuid,
  p_usuario_sector_id  uuid,
  p_usuario_proceso_id uuid
)
returns boolean
language sql stable as $$
  select case p_nivel
    when 'TODO' then true
    when 'AREA' then p_area_id = p_usuario_area_id
    when 'SECTOR' then p_sector_id = p_usuario_sector_id
    when 'PROCESO' then p_proceso_id = p_usuario_proceso_id
    else false
  end;
$$;

-- Estas 4 funciones son las ÚNICAS que resuelven "¿puede este usuario
-- hacer X sobre un registro con este área/sector/proceso?" — RLS, RPC y
-- frontend (vía fn_permisos_para_scope) consultan siempre a estas mismas.
-- El scope de cada usuario sale exclusivamente de usuario_permiso_scopes
-- — nunca de empleados.
create or replace function fn_puede_ver(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce((
    select fn_scope_ok(up.visibilidad_nivel, p_area_id, p_sector_id, p_proceso_id, ups.area_id, ups.sector_id, ups.proceso_id)
    from usuario_permisos up
    left join usuario_permiso_scopes ups on ups.usuario_id = up.usuario_id and ups.tipo_permiso = 'VISIBILIDAD'
    where up.usuario_id = auth.uid()
  ), false));
$$;

create or replace function fn_puede_modificar(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce((
    select fn_scope_ok(up.modificacion_nivel, p_area_id, p_sector_id, p_proceso_id, ups.area_id, ups.sector_id, ups.proceso_id)
    from usuario_permisos up
    left join usuario_permiso_scopes ups on ups.usuario_id = up.usuario_id and ups.tipo_permiso = 'MODIFICACION'
    where up.usuario_id = auth.uid()
  ), false));
$$;

create or replace function fn_puede_aprobar(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce((
    select fn_scope_ok(up.aprobacion_nivel, p_area_id, p_sector_id, p_proceso_id, ups.area_id, ups.sector_id, ups.proceso_id)
    from usuario_permisos up
    left join usuario_permiso_scopes ups on ups.usuario_id = up.usuario_id and ups.tipo_permiso = 'APROBACION'
    where up.usuario_id = auth.uid()
  ), false));
$$;

create or replace function fn_puede_reabrir(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce((
    select fn_scope_ok(up.reapertura_nivel, p_area_id, p_sector_id, p_proceso_id, ups.area_id, ups.sector_id, ups.proceso_id)
    from usuario_permisos up
    left join usuario_permiso_scopes ups on ups.usuario_id = up.usuario_id and ups.tipo_permiso = 'REAPERTURA'
    where up.usuario_id = auth.uid()
  ), false));
$$;

-- Capacidad GLOBAL (flag), sin alcance. NO autoriza operaciones por sí sola:
-- toda operación de Control de Ingreso usa fn_puede_control_ingreso_sobre().
create or replace function fn_puede_control_ingreso()
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce(
    (select control_ingreso from usuario_permisos where usuario_id = auth.uid()),
    false
  ));
$$;

-- V2.1: Control de Ingreso es un permiso INDEPENDIENTE de aprobación/
-- modificación/reapertura, pero SIEMPRE dentro del alcance de VISIBILIDAD
-- del usuario (TODO + control_ingreso permite operar entre áreas; una
-- visibilidad restringida limita la operación a ese alcance). No otorga
-- ningún permiso de aprobación, modificación, reapertura ni creación.
create or replace function fn_puede_control_ingreso_sobre(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (
    fn_usuario_activo()
    and coalesce((select control_ingreso from usuario_permisos where usuario_id = auth.uid()), false)
    and fn_puede_ver(p_area_id, p_sector_id, p_proceso_id)
  );
$$;

create or replace function fn_puede_eliminar_cancelar()
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce(
    (select puede_eliminar_cancelar from usuario_permisos where usuario_id = auth.uid()),
    false
  ));
$$;

create or replace function fn_puede_ver_importes()
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce(
    (select puede_ver_importes from usuario_permisos where usuario_id = auth.uid()),
    true
  ));
$$;

-- Capacidades de importar/exportar (rol RRHH, cierre funcional V2). Son
-- gates de CAPACIDAD; el scope real sobre QUÉ puede importar/exportar lo
-- sigue resolviendo fn_puede_modificar/ver por separado en cada RPC.
create or replace function fn_puede_importar()
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce(
    (select puede_importar from usuario_permisos where usuario_id = auth.uid()),
    false
  ));
$$;

create or replace function fn_puede_exportar()
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin() or (fn_usuario_activo() and coalesce(
    (select puede_exportar from usuario_permisos where usuario_id = auth.uid()),
    false
  ));
$$;

create or replace function fn_permisos_para_scope(p_area_id uuid, p_sector_id uuid, p_proceso_id uuid)
returns table (
  puede_ver boolean,
  puede_modificar boolean,
  puede_aprobar boolean,
  puede_reabrir boolean,
  puede_control_ingreso boolean
)
language sql stable security definer set search_path = public as $$
  select
    fn_puede_ver(p_area_id, p_sector_id, p_proceso_id),
    fn_puede_modificar(p_area_id, p_sector_id, p_proceso_id),
    fn_puede_aprobar(p_area_id, p_sector_id, p_proceso_id),
    fn_puede_reabrir(p_area_id, p_sector_id, p_proceso_id),
    fn_puede_control_ingreso_sobre(p_area_id, p_sector_id, p_proceso_id);
$$;

create or replace function fn_banda_ranking(p_ranking numeric, p_campo text)
returns bandas_ranking
language sql stable security definer set search_path = public as $$
  select *
  from bandas_ranking
  where activo
    and case p_campo
          when 'SOLICITUD' then aplica_a_solicitud
          when 'REAL' then aplica_a_real
          else false
        end
    and p_ranking >= ranking_inferior
    and (ranking_superior is null or p_ranking <= ranking_superior)
  order by ranking_inferior
  limit 1;
$$;


-- ============================================================================
-- PARTE 16 · Auditoría técnica genérica + trigger de tablas singleton
-- ============================================================================

create or replace function fn_registrar_auditoria()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_accion accion_auditoria;
begin
  if tg_op = 'INSERT' then v_accion := 'INSERT';
  elsif tg_op = 'UPDATE' then v_accion := 'UPDATE';
  elsif tg_op = 'DELETE' then v_accion := 'DELETE';
  end if;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen, datos_anteriores, datos_nuevos)
  values (
    auth.uid(),
    v_accion,
    tg_table_name,
    coalesce(new.id, old.id),
    -- Hallazgo real (detectado recién al EJECUTAR la migración, no por
    -- lectura ni por el parser sintáctico): sin el cast explícito acá,
    -- Postgres resuelve el CASE entre dos literales de texto como `text`
    -- y falla al insertarlo en una columna `origen_auditoria` (enum) —
    -- "column is of type origen_auditoria but expression is of type
    -- text". Esta corrección no formaba parte de los 5 puntos pedidos:
    -- se encontró y se corrige acá por la validación de ejecución real
    -- de esta auditoría (ver Entregable 2).
    (case when auth.uid() is null then 'SISTEMA' else 'USUARIO' end)::origen_auditoria,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

create or replace function fn_registrar_auditoria_singleton()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_accion accion_auditoria;
begin
  if tg_op = 'INSERT' then v_accion := 'INSERT';
  elsif tg_op = 'UPDATE' then v_accion := 'UPDATE';
  elsif tg_op = 'DELETE' then v_accion := 'DELETE';
  end if;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen, datos_anteriores, datos_nuevos)
  values (
    auth.uid(),
    v_accion,
    tg_table_name,
    null,
    (case when auth.uid() is null then 'SISTEMA' else 'USUARIO' end)::origen_auditoria,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

-- Hallazgo real (detectado al EJECUTAR la migración, no por lectura ni por
-- el parser sintáctico): fn_registrar_auditoria() genérica asume
-- `new.id`/`old.id` — falla con "record new has no field id" en cualquier
-- tabla sin columna `id`. usuario_permisos (PK = usuario_id) y
-- usuario_permiso_scopes (PK compuesta usuario_id+tipo_permiso) son las
-- dos únicas tablas auditadas sin ese campo. Variante dedicada: usa
-- usuario_id como registro_id (ambas tablas lo tienen); el estado
-- completo del registro — incluido tipo_permiso en el caso de scopes —
-- ya queda igualmente trazado en datos_anteriores/datos_nuevos. Esta
-- corrección no formaba parte de los 5 puntos pedidos: se encontró y se
-- corrige acá por la validación de ejecución real de esta auditoría (ver
-- Entregable 2).
create or replace function fn_registrar_auditoria_usuario_permisos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_accion accion_auditoria;
begin
  if tg_op = 'INSERT' then v_accion := 'INSERT';
  elsif tg_op = 'UPDATE' then v_accion := 'UPDATE';
  elsif tg_op = 'DELETE' then v_accion := 'DELETE';
  end if;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen, datos_anteriores, datos_nuevos)
  values (
    auth.uid(),
    v_accion,
    tg_table_name,
    coalesce(new.usuario_id, old.usuario_id),
    (case when auth.uid() is null then 'SISTEMA' else 'USUARIO' end)::origen_auditoria,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_auditoria_areas after insert or update or delete on areas for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_sectores after insert or update or delete on sectores for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_procesos after insert or update or delete on procesos for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_motivos after insert or update or delete on motivos for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_empleados after insert or update or delete on empleados for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_usuario_permisos after insert or update or delete on usuario_permisos for each row execute function fn_registrar_auditoria_usuario_permisos();
create trigger trg_auditoria_usuario_permiso_scopes after insert or update or delete on usuario_permiso_scopes for each row execute function fn_registrar_auditoria_usuario_permisos();
create trigger trg_auditoria_solicitudes after insert or update or delete on solicitudes for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_solicitud_empleados after insert or update or delete on solicitud_empleados for each row execute function fn_registrar_auditoria();
create trigger trg_auditoria_bandas_ranking after insert or update or delete on bandas_ranking for each row execute function fn_registrar_auditoria();

create trigger trg_auditoria_configuracion_general after update on configuracion_general for each row execute function fn_registrar_auditoria_singleton();
create trigger trg_auditoria_configuracion_apariencia after update on configuracion_apariencia for each row execute function fn_registrar_auditoria_singleton();


-- ============================================================================
-- PARTE 17 · Auditoría de negocio — punto único de entrada
-- ============================================================================

create or replace function fn_registrar_evento_negocio(
  p_modulo text,
  p_entidad_tipo text,
  p_entidad_id uuid,
  p_evento text,
  p_nivel nivel_auditoria_negocio,
  p_entidad_relacionada_tipo text default null,
  p_entidad_relacionada_id uuid default null,
  p_estado_anterior text default null,
  p_estado_nuevo text default null,
  p_datos jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nivel_configurado nivel_auditoria_negocio;
begin
  select nivel_auditoria_negocio into v_nivel_configurado from configuracion_general where id = 1;

  if v_nivel_configurado = 'DESACTIVADA' then
    return;
  end if;

  if v_nivel_configurado = 'BASICA' and p_nivel = 'COMPLETA' then
    return;
  end if;

  insert into auditoria_negocio (
    usuario_id, origen, nivel, modulo, entidad_tipo, entidad_id,
    entidad_relacionada_tipo, entidad_relacionada_id, evento,
    estado_anterior, estado_nuevo, datos
  ) values (
    auth.uid(),
    (case when auth.uid() is null then 'SISTEMA' else 'USUARIO' end)::origen_auditoria,
    p_nivel, p_modulo, p_entidad_tipo, p_entidad_id,
    p_entidad_relacionada_tipo, p_entidad_relacionada_id, p_evento,
    p_estado_anterior, p_estado_nuevo, p_datos
  );
end;
$$;


-- ============================================================================
-- PARTE 18 · Motor de cálculo MULTI-TRAMO (cierre funcional V2)
-- ----------------------------------------------------------------------------
-- Reemplaza el cálculo de un único segmento. Parte el rango
-- [inicio, fin) en sub-tramos que nunca cruzan medianoche (según la zona
-- horaria configurada) ni un límite de banda horaria; cada sub-tramo
-- resuelve su propia fecha, banda, feriado y valor-hora vigente. Una fila
-- por sub-tramo en solicitud_empleado_detalle — trazabilidad completa
-- reproducible.
-- ============================================================================

create or replace function fn_valor_hora_vigente(p_categoria_id uuid, p_fecha date)
returns table (valor_hora numeric, moneda text)
language sql stable as $$
  select c.valor_hora, c.moneda
  from categorias c
  where c.categoria_tipo_id = p_categoria_id
    and c.vigente_desde <= p_fecha
    and (c.vigente_hasta is null or c.vigente_hasta >= p_fecha)
  limit 1;
$$;

create or replace function fn_calcular_detalle_solicitud_empleado(p_solicitud_empleado_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_se solicitud_empleados;
  v_solicitud solicitudes;
  v_empleado empleados;
  v_tz text;
  v_cortes timestamptz[];
  v_corte timestamptz;
  v_t_desde timestamptz;
  v_t_hasta timestamptz;
  v_fecha date;
  v_hora_local time;
  v_banda bandas_horarias;
  v_bandas_encontradas integer;
  v_es_feriado boolean;
  v_multiplicador numeric;
  v_valor_hora numeric;
  v_moneda text;
  v_horas numeric;
  v_importe numeric;
  v_total_horas numeric := 0;
  v_total_importe numeric := 0;
  v_banda_rec record;
  v_medianoche timestamptz;
  i integer;
begin
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;
  select * into v_solicitud from solicitudes where id = v_se.solicitud_id;
  select * into v_empleado from empleados where id = v_se.empleado_id;

  select zona_horaria into v_tz from configuracion_general where id = 1;

  delete from solicitud_empleado_detalle where solicitud_empleado_id = p_solicitud_empleado_id;

  -- Paso 1: puntos de corte — cada medianoche (en v_tz) y cada límite de
  -- banda horaria activa, evaluados día por día dentro del rango.
  v_cortes := array[v_solicitud.fecha_hora_inicio, v_solicitud.fecha_hora_fin];

  v_medianoche := date_trunc('day', v_solicitud.fecha_hora_inicio at time zone v_tz) at time zone v_tz;
  while v_medianoche < v_solicitud.fecha_hora_fin loop
    v_medianoche := v_medianoche + interval '1 day';
    if v_medianoche > v_solicitud.fecha_hora_inicio and v_medianoche < v_solicitud.fecha_hora_fin then
      v_cortes := array_append(v_cortes, v_medianoche);
    end if;
  end loop;

  for v_banda_rec in select * from bandas_horarias where activo loop
    v_fecha := (v_solicitud.fecha_hora_inicio at time zone v_tz)::date;
    while (v_fecha::timestamp at time zone v_tz) < v_solicitud.fecha_hora_fin loop
      v_corte := (v_fecha + v_banda_rec.hora_desde)::timestamp at time zone v_tz;
      if v_corte > v_solicitud.fecha_hora_inicio and v_corte < v_solicitud.fecha_hora_fin then
        v_cortes := array_append(v_cortes, v_corte);
      end if;
      v_corte := (v_fecha + v_banda_rec.hora_hasta)::timestamp at time zone v_tz;
      if v_corte > v_solicitud.fecha_hora_inicio and v_corte < v_solicitud.fecha_hora_fin then
        v_cortes := array_append(v_cortes, v_corte);
      end if;
      v_fecha := v_fecha + 1;
    end loop;
  end loop;

  select array_agg(distinct c order by c) into v_cortes from unnest(v_cortes) as c;

  -- Paso 2: recorrer cada sub-tramo consecutivo.
  for i in 1 .. array_length(v_cortes, 1) - 1 loop
    v_t_desde := v_cortes[i];
    v_t_hasta := v_cortes[i + 1];
    if v_t_hasta <= v_t_desde then
      continue;
    end if;

    v_fecha := (v_t_desde at time zone v_tz)::date;
    v_hora_local := (v_t_desde at time zone v_tz)::time;

    -- Corrección obligatoria B: selección determinística, nunca un
    -- `limit 1` arbitrario. El trigger trg_validar_solapamiento_bandas_
    -- horarias ya impide guardar bandas activas que se solapen, pero acá
    -- se vuelve a comprobar en tiempo de cálculo (defensa en profundidad,
    -- y porque es el único lugar que también detecta el caso de que NO
    -- haya ninguna banda aplicable — una configuración perfectamente
    -- válida si las bandas no cubren las 24 h, pero que no puede
    -- calcularse en silencio).
    select count(*) into v_bandas_encontradas
      from bandas_horarias
      where activo
        and (
          (hora_desde < hora_hasta and v_hora_local >= hora_desde and v_hora_local < hora_hasta)
          or (hora_desde >= hora_hasta and (v_hora_local >= hora_desde or v_hora_local < hora_hasta))
        );

    if v_bandas_encontradas = 0 then
      raise exception 'No hay ninguna banda horaria activa configurada para el horario % del % — no se puede calcular este tramo', v_hora_local, v_fecha;
    elsif v_bandas_encontradas > 1 then
      raise exception 'Hay % bandas horarias activas que se superponen para el horario % del % — corregí la configuración de bandas horarias antes de calcular', v_bandas_encontradas, v_hora_local, v_fecha;
    end if;

    select * into v_banda from bandas_horarias
      where activo
        and (
          (hora_desde < hora_hasta and v_hora_local >= hora_desde and v_hora_local < hora_hasta)
          or (hora_desde >= hora_hasta and (v_hora_local >= hora_desde or v_hora_local < hora_hasta))
        );

    select exists(select 1 from feriados where fecha = v_fecha) into v_es_feriado;

    if v_es_feriado and v_banda.multiplicador_feriado is not null then
      v_multiplicador := v_banda.multiplicador_feriado;
    else
      v_multiplicador := coalesce(v_banda.multiplicador, 1);
    end if;

    select vh.valor_hora, vh.moneda into v_valor_hora, v_moneda
      from fn_valor_hora_vigente(v_empleado.categoria_id, v_fecha) vh;

    if v_moneda is null then
      raise exception 'No hay valor-hora vigente para la categoría del empleado en la fecha %', v_fecha;
    end if;

    v_horas := extract(epoch from (v_t_hasta - v_t_desde)) / 3600.0;
    v_importe := v_horas * v_valor_hora * v_multiplicador;

    insert into solicitud_empleado_detalle (solicitud_empleado_id, fecha, banda_horaria_id, horas, valor_hora, moneda, multiplicador, importe, es_feriado)
    values (p_solicitud_empleado_id, v_fecha, v_banda.id, v_horas, v_valor_hora, v_moneda, v_multiplicador, v_importe, v_es_feriado);

    v_total_horas := v_total_horas + v_horas;
    v_total_importe := v_total_importe + v_importe;
  end loop;

  -- ------------------------------------------------------------------------
  -- Validación de moneda centralizada (corrección confirmada #3): única
  -- fuente de verdad, acá adentro, en vez de 3 chequeos parciales
  -- distintos repetidos en rpc_agregar_empleado/rpc_reemplazar_empleado/
  -- rpc_modificar_fechas. Dos niveles:
  --   1) consistencia INTERNA de este empleado — todos sus propios tramos
  --      deben resolver la misma moneda (podría no ser así si la vigencia
  --      del valor-hora cruza un cambio de moneda a mitad de la solicitud).
  --   2) consistencia CONTRA la solicitud — si la solicitud ya tiene
  --      moneda fijada (por otro empleado), este empleado debe coincidir;
  --      si todavía no tiene, se fija acá (reemplaza el fijado que antes
  --      hacían las RPC de alta/reemplazo antes de insertar).
  -- ------------------------------------------------------------------------
  declare
    v_monedas_distintas integer;
    v_moneda_empleado text;
    v_moneda_solicitud text;
  begin
    select count(distinct moneda) into v_monedas_distintas
      from solicitud_empleado_detalle where solicitud_empleado_id = p_solicitud_empleado_id;

    if v_monedas_distintas > 1 then
      raise exception 'Esta solicitud cruza una vigencia de valor-hora que cambia de moneda dentro del mismo empleado — no se puede calcular de forma consistente';
    end if;

    if v_monedas_distintas = 1 then
      select moneda into v_moneda_empleado
        from solicitud_empleado_detalle where solicitud_empleado_id = p_solicitud_empleado_id limit 1;

      select moneda into v_moneda_solicitud from solicitudes where id = v_se.solicitud_id;

      if v_moneda_solicitud is null then
        update solicitudes set moneda = v_moneda_empleado where id = v_se.solicitud_id;
      elsif v_moneda_solicitud <> v_moneda_empleado then
        raise exception 'No se puede mezclar monedas en la misma solicitud (solicitud en %, este empleado en %)', v_moneda_solicitud, v_moneda_empleado;
      end if;
    end if;
  end;

  update solicitud_empleados
    set total_horas = v_total_horas, total_importe = v_total_importe
    where id = p_solicitud_empleado_id;
end;
$$;

create or replace function fn_solicitud_empleados_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_calcular_detalle_solicitud_empleado(new.id);
  return new;
end;
$$;

create trigger trg_solicitud_empleados_after_insert
  after insert on solicitud_empleados
  for each row execute function fn_solicitud_empleados_after_insert();


-- ============================================================================
-- PARTE 19 · Única fuente de verdad de `situacion`
-- ============================================================================

create or replace function fn_recalcular_situacion_solicitud(p_solicitud_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_situacion_actual situacion_solicitud;
  v_pendientes integer;
  v_aprobados integer;
  v_vigentes integer;
  v_nueva situacion_solicitud;
begin
  select situacion into v_situacion_actual from solicitudes where id = p_solicitud_id for update;

  if v_situacion_actual not in ('EN_APROBACION', 'APROBADA', 'RECHAZADA') then
    return;
  end if;

  select
    count(*) filter (where estado_aprobacion = 'PENDIENTE_APROBACION'),
    count(*) filter (where estado_aprobacion = 'APROBADO'),
    count(*)
  into v_pendientes, v_aprobados, v_vigentes
  from solicitud_empleados
  where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO';

  if v_vigentes = 0 or v_pendientes > 0 then
    v_nueva := 'EN_APROBACION';
  elsif v_aprobados > 0 then
    v_nueva := 'APROBADA';
  else
    v_nueva := 'RECHAZADA';
  end if;

  if v_nueva <> v_situacion_actual then
    update solicitudes set situacion = v_nueva, updated_at = now() where id = p_solicitud_id;

    perform fn_registrar_evento_negocio(
      p_modulo := 'HORAS_EXTRA',
      p_entidad_tipo := 'SOLICITUD',
      p_entidad_id := p_solicitud_id,
      p_evento := 'SOLICITUD_CAMBIO_ESTADO',
      p_nivel := 'BASICA',
      p_estado_anterior := v_situacion_actual::text,
      p_estado_nuevo := v_nueva::text
    );
  end if;
end;
$$;

create or replace function fn_trigger_recalcular_situacion()
returns trigger
language plpgsql
as $$
begin
  perform fn_recalcular_situacion_solicitud(coalesce(new.solicitud_id, old.solicitud_id));
  return coalesce(new, old);
end;
$$;

create trigger trg_recalcular_situacion
  after insert or update of estado_aprobacion, estado_registro or delete on solicitud_empleados
  for each row execute function fn_trigger_recalcular_situacion();


-- ============================================================================
-- PARTE 20 · Funciones internas compartidas — aprobar/rechazar
-- ============================================================================

create or replace function fn_aprobar_empleado_interno(p_solicitud_empleado_id uuid, p_usuario_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
begin
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;

  if v_se.estado_aprobacion = 'APROBADO' then
    return;
  end if;

  update solicitud_empleados
    set estado_aprobacion = 'APROBADO', fecha_hora_aprobacion = now(), usuario_aprobacion_id = p_usuario_id
    where id = p_solicitud_empleado_id;

  update empleados set ranking_horas = ranking_horas + v_se.total_horas where id = v_se.empleado_id;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen)
  values (p_usuario_id, 'APPROVE', 'solicitud_empleados', p_solicitud_empleado_id,
    case when p_usuario_id is null then 'SISTEMA'::origen_auditoria else 'USUARIO'::origen_auditoria end);

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'EMPLEADO_APROBADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id);
end;
$$;

create or replace function fn_rechazar_empleado_interno(p_solicitud_empleado_id uuid, p_usuario_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
begin
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;

  if v_se.estado_aprobacion = 'RECHAZADO' then
    return;
  end if;

  -- V2.1: si ya estaba APROBADO, sus horas dejan de contar en el ranking.
  perform fn_revertir_ranking_si_aprobado(p_solicitud_empleado_id);

  update solicitud_empleados
    set estado_aprobacion = 'RECHAZADO', fecha_hora_aprobacion = now(), usuario_aprobacion_id = p_usuario_id, motivo_rechazo = p_motivo
    where id = p_solicitud_empleado_id;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen)
  values (p_usuario_id, 'REJECT', 'solicitud_empleados', p_solicitud_empleado_id, 'USUARIO');

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'EMPLEADO_RECHAZADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id,
    p_datos := jsonb_build_object('motivo', p_motivo));
end;
$$;

-- ============================================================================
-- PARTE 20B · Helpers de ranking — un solo lugar que implementa "revertir
-- el aporte al ranking antes de invalidar una aprobación" (correcciones
-- confirmadas #1 y #5). Antes esta regla estaba duplicada de forma
-- incompleta: rpc_reabrir_solicitud la tenía bien, pero
-- rpc_quitar_empleado y rpc_reemplazar_empleado NO la aplicaban — un
-- empleado quitado o reemplazado después de APROBADO dejaba su aporte
-- inflado en empleados.ranking_horas para siempre. Centralizado acá, cada
-- RPC que invalida una aprobación llama a uno de estos dos, nunca repite
-- el UPDATE a mano.
-- ============================================================================

-- Para UN solo registro (quitar/reemplazar un empleado puntual).
create or replace function fn_revertir_ranking_si_aprobado(p_solicitud_empleado_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_ultimo_reseteo timestamptz;
begin
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;
  if v_se.estado_aprobacion = 'APROBADO' then
    select ultimo_reseteo_ranking into v_ultimo_reseteo from configuracion_general where id = 1;

    -- Corrección obligatoria E: si la aprobación pertenece a un período de
    -- ranking ya cerrado (fecha_hora_aprobacion anterior al último
    -- reseteo), esas horas ya fueron archivadas en
    -- ranking_horas_historico y el ranking_horas de ese empleado ya volvió
    -- a 0 para el período nuevo. Restarlas ahora descontaría horas de un
    -- período que nunca las tuvo. Solo se revierte si la aprobación es del
    -- período vigente (posterior al último reseteo, o si todavía no hubo
    -- ninguno).
    if v_ultimo_reseteo is null or v_se.fecha_hora_aprobacion > v_ultimo_reseteo then
      update empleados set ranking_horas = greatest(0, ranking_horas - v_se.total_horas) where id = v_se.empleado_id;
    end if;
  end if;
end;
$$;

-- Para TODOS los vigentes de una solicitud a la vez (reapertura,
-- modificación de fecha, modificación de motivo) — revierte el ranking de
-- los que estaban APROBADO y los resetea a PENDIENTE_APROBACION en el
-- mismo paso, siempre juntos, nunca uno sin el otro.
create or replace function fn_invalidar_aprobaciones_vigentes(p_solicitud_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ultimo_reseteo timestamptz;
begin
  select ultimo_reseteo_ranking into v_ultimo_reseteo from configuracion_general where id = 1;

  -- Corrección obligatoria E: mismo criterio que fn_revertir_ranking_si_
  -- aprobado — solo se descuenta del ranking_horas ACTUAL el aporte de
  -- aprobaciones del período vigente (posteriores al último reseteo). Las
  -- de un período ya cerrado y archivado se dejan intactas.
  update empleados e set ranking_horas = greatest(0, e.ranking_horas - se.total_horas)
    from solicitud_empleados se
    where se.solicitud_id = p_solicitud_id and se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'APROBADO'
      and e.id = se.empleado_id
      and (v_ultimo_reseteo is null or se.fecha_hora_aprobacion > v_ultimo_reseteo);

  -- El reseteo del ESTADO de aprobación a PENDIENTE_APROBACION sí se
  -- aplica siempre a todos los vigentes, sin importar el período: es una
  -- cuestión de flujo de trabajo (hay que volver a aprobar), no de
  -- ranking.
  update solicitud_empleados
    set estado_aprobacion = 'PENDIENTE_APROBACION', fecha_hora_aprobacion = null, usuario_aprobacion_id = null, motivo_rechazo = null
    where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO';
end;
$$;
-- ============================================================================
-- PARTE 21 · RPC de negocio — solicitudes
-- ----------------------------------------------------------------------------
-- Convención uniforme: toda RPC que muta una solicitud o su equipo arranca
-- con `select ... for update` sobre `solicitudes`.
-- ============================================================================

create or replace function rpc_crear_solicitud(
  p_area_id uuid,
  p_sector_id uuid,
  p_proceso_id uuid,
  p_fecha_hora_inicio timestamptz,
  p_fecha_hora_fin timestamptz,
  p_motivo_id uuid,
  p_observacion text default null
)
returns solicitudes
language plpgsql security definer set search_path = public as $$
declare
  v_dias_max integer;
  v_tz text;
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  if not fn_puede_modificar(p_area_id, p_sector_id, p_proceso_id) then
    raise exception 'No tenés permiso para crear solicitudes en ese área/sector/proceso';
  end if;

  if p_fecha_hora_fin <= p_fecha_hora_inicio then
    raise exception 'fecha_hora_fin debe ser posterior a fecha_hora_inicio';
  end if;

  select dias_maximos_antiguedad, zona_horaria into v_dias_max, v_tz from configuracion_general where id = 1;
  if (p_fecha_hora_inicio at time zone v_tz)::date < ((now() at time zone v_tz)::date - v_dias_max) then
    raise exception 'La fecha de inicio supera los % días de antigüedad permitidos', v_dias_max;
  end if;

  insert into solicitudes (solicitante_id, area_id, sector_id, proceso_id, fecha_hora_inicio, fecha_hora_fin, motivo_id, observacion, situacion)
  values (auth.uid(), p_area_id, p_sector_id, p_proceso_id, p_fecha_hora_inicio, p_fecha_hora_fin, p_motivo_id, p_observacion, 'BORRADOR')
  returning * into v_solicitud;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', v_solicitud.id, 'SOLICITUD_CREADA', 'BASICA');

  return v_solicitud;
end;
$$;

create or replace function rpc_enviar_a_aprobacion(p_solicitud_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_dias_max integer;
  v_tz text;
  v_cantidad_empleados integer;
  v_situacion_final text;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'BORRADOR' then
    raise exception 'Solo se puede enviar a aprobación una solicitud en BORRADOR (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  select count(*) into v_cantidad_empleados from solicitud_empleados
    where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO';
  if v_cantidad_empleados = 0 then
    raise exception 'No se puede enviar a aprobación una solicitud sin empleados';
  end if;

  select dias_maximos_antiguedad, zona_horaria into v_dias_max, v_tz from configuracion_general where id = 1;
  if (v_solicitud.fecha_hora_inicio at time zone v_tz)::date < ((now() at time zone v_tz)::date - v_dias_max) then
    raise exception 'La fecha de inicio supera los % días de antigüedad permitidos', v_dias_max;
  end if;

  update solicitudes set situacion = 'EN_APROBACION', updated_at = now() where id = p_solicitud_id;

  -- V2.1: si todos los empleados ya están APROBADO (motivo sin aprobación) la
  -- solicitud pasa a APROBADA en vez de quedar trabada en EN_APROBACION.
  perform fn_recalcular_situacion_solicitud(p_solicitud_id);
  select situacion::text into v_situacion_final from solicitudes where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_ENVIADA_A_APROBACION', 'BASICA', p_estado_anterior := 'BORRADOR', p_estado_nuevo := v_situacion_final);
end;
$$;

create or replace function rpc_aprobar_empleado(p_solicitud_empleado_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_se solicitud_empleados;
begin
  perform fn_exigir_usuario_activo();
  select se.* into v_se from solicitud_empleados se where se.id = p_solicitud_empleado_id;
  if v_se.id is null then raise exception 'El registro no existe'; end if;

  select * into v_solicitud from solicitudes where id = v_se.solicitud_id for update;
  if v_solicitud.situacion <> 'EN_APROBACION' then
    raise exception 'Solo se puede aprobar mientras la solicitud está EN_APROBACION (actual: %)', v_solicitud.situacion;
  end if;
  if v_se.estado_registro <> 'ACTIVO' then
    raise exception 'Este registro ya no está vigente (%), no se puede decidir sobre él', v_se.estado_registro;
  end if;
  if not fn_puede_aprobar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para aprobar en ese área/sector/proceso';
  end if;

  perform fn_aprobar_empleado_interno(p_solicitud_empleado_id, auth.uid());
end;
$$;

create or replace function rpc_rechazar_empleado(p_solicitud_empleado_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_se solicitud_empleados;
begin
  perform fn_exigir_usuario_activo();
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'El motivo de rechazo es obligatorio';
  end if;

  select se.* into v_se from solicitud_empleados se where se.id = p_solicitud_empleado_id;
  if v_se.id is null then raise exception 'El registro no existe'; end if;

  select * into v_solicitud from solicitudes where id = v_se.solicitud_id for update;
  if v_solicitud.situacion <> 'EN_APROBACION' then
    raise exception 'Solo se puede rechazar mientras la solicitud está EN_APROBACION (actual: %)', v_solicitud.situacion;
  end if;
  if v_se.estado_registro <> 'ACTIVO' then
    raise exception 'Este registro ya no está vigente (%), no se puede decidir sobre él', v_se.estado_registro;
  end if;
  if not fn_puede_aprobar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para aprobar/rechazar en ese área/sector/proceso';
  end if;

  perform fn_rechazar_empleado_interno(p_solicitud_empleado_id, auth.uid(), p_motivo);
end;
$$;

create or replace function rpc_aprobar_masivo(p_solicitud_id uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_se record;
  v_cantidad integer := 0;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'EN_APROBACION' then
    raise exception 'Solo se puede aprobar mientras la solicitud está EN_APROBACION (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_aprobar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para aprobar en ese área/sector/proceso';
  end if;

  for v_se in
    select id from solicitud_empleados
    where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' and estado_aprobacion = 'PENDIENTE_APROBACION'
  loop
    perform fn_aprobar_empleado_interno(v_se.id, auth.uid());
    v_cantidad := v_cantidad + 1;
  end loop;

  return v_cantidad;
end;
$$;

create or replace function rpc_rechazar_masivo(p_solicitud_id uuid, p_motivo text)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_se record;
  v_cantidad integer := 0;
begin
  perform fn_exigir_usuario_activo();
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'El motivo de rechazo es obligatorio';
  end if;

  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'EN_APROBACION' then
    raise exception 'Solo se puede rechazar mientras la solicitud está EN_APROBACION (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_aprobar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para aprobar/rechazar en ese área/sector/proceso';
  end if;

  for v_se in
    select id from solicitud_empleados
    where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' and estado_aprobacion = 'PENDIENTE_APROBACION'
  loop
    perform fn_rechazar_empleado_interno(v_se.id, auth.uid(), p_motivo);
    v_cantidad := v_cantidad + 1;
  end loop;

  return v_cantidad;
end;
$$;

create or replace function rpc_agregar_empleado(p_solicitud_id uuid, p_empleado_id uuid)
returns solicitud_empleados
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_empleado  empleados;
  v_se solicitud_empleados;
  v_banda_solicitud bandas_ranking;
  v_banda_real bandas_ranking;
  v_requiere_aprobacion boolean;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion not in ('BORRADOR', 'EN_APROBACION', 'APROBADA') then
    raise exception 'No se pueden agregar empleados en el estado actual (%)', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  select * into v_empleado from empleados where id = p_empleado_id;
  if v_empleado.id is null or v_empleado.estado <> 'ACTIVO' then
    raise exception 'El empleado no existe o no está ACTIVO';
  end if;

  select * into v_banda_solicitud from fn_banda_ranking(v_empleado.ranking_horas, 'SOLICITUD');
  if v_banda_solicitud.bloqueo_seleccion = 'BLOQUEADO' then
    raise exception 'El empleado no puede seleccionarse: su ranking según solicitud está en la banda "%" (bloqueada)', v_banda_solicitud.descripcion;
  end if;
  if v_empleado.ranking_horas_real is not null then
    select * into v_banda_real from fn_banda_ranking(v_empleado.ranking_horas_real, 'REAL');
    if v_banda_real.bloqueo_seleccion = 'BLOQUEADO' then
      raise exception 'El empleado no puede seleccionarse: su ranking real está en la banda "%" (bloqueada)', v_banda_real.descripcion;
    end if;
  end if;

  if exists (select 1 from solicitud_empleados where solicitud_id = p_solicitud_id and empleado_id = p_empleado_id and estado_registro = 'ACTIVO') then
    raise exception 'El empleado ya está en el equipo vigente de esta solicitud';
  end if;

  if exists (
    select 1 from solicitud_empleados se join solicitudes s on s.id = se.solicitud_id
    where se.empleado_id = p_empleado_id and se.estado_registro = 'ACTIVO' and se.estado_aprobacion <> 'RECHAZADO'
      and s.situacion not in ('CANCELADA', 'ELIMINADA') and s.id <> p_solicitud_id
      and (s.fecha_hora_inicio, s.fecha_hora_fin) overlaps (v_solicitud.fecha_hora_inicio, v_solicitud.fecha_hora_fin)
  ) then
    raise exception 'El empleado ya tiene horas asignadas que se superponen con este horario en otra solicitud';
  end if;

  -- La moneda ya NO se pre-chequea acá (corrección #3): fn_calcular_detalle_
  -- solicitud_empleado, disparada por el trigger after_insert de abajo,
  -- es la única que fija/valida la moneda — tramo por tramo, con zona
  -- horaria correcta, no solo contra la fecha de inicio.

  select m.requiere_aprobacion into v_requiere_aprobacion from motivos m where m.id = v_solicitud.motivo_id;

  -- Hallazgo real (ejecución): sin el cast explícito, el CASE con dos
  -- literales de texto resuelve a `text` y falla al insertar en una
  -- columna `estado_empleado_aprobacion` (enum) — mismo tipo de defecto
  -- ya corregido en fn_registrar_auditoria (ver Entregable 2).
  insert into solicitud_empleados (solicitud_id, empleado_id, estado_aprobacion)
  values (p_solicitud_id, p_empleado_id, (case when v_requiere_aprobacion then 'PENDIENTE_APROBACION' else 'APROBADO' end)::estado_empleado_aprobacion)
  returning * into v_se;

  if not v_requiere_aprobacion then
    select * into v_se from solicitud_empleados where id = v_se.id;
    update solicitud_empleados set fecha_hora_aprobacion = now() where id = v_se.id;
    update empleados set ranking_horas = ranking_horas + v_se.total_horas where id = p_empleado_id;
    insert into auditoria (usuario_id, accion, tabla, registro_id, origen) values (null, 'APPROVE', 'solicitud_empleados', v_se.id, 'SISTEMA');
  end if;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'EMPLEADO_AGREGADO', 'COMPLETA',
    p_entidad_relacionada_tipo := 'EMPLEADO', p_entidad_relacionada_id := p_empleado_id,
    p_datos := jsonb_build_object('legajo', v_empleado.legajo, 'nombre', v_empleado.nombre_completo));

  return v_se;
end;
$$;

create or replace function rpc_quitar_empleado(p_solicitud_empleado_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;
  if v_se.id is null then raise exception 'El registro no existe'; end if;

  select * into v_solicitud from solicitudes where id = v_se.solicitud_id for update;
  if v_solicitud.situacion not in ('BORRADOR', 'EN_APROBACION', 'APROBADA') then
    raise exception 'No se pueden quitar empleados en el estado actual (%)', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;
  if v_se.estado_registro <> 'ACTIVO' then
    raise exception 'Este registro ya no está vigente';
  end if;

  if v_se.estado_aprobacion = 'PENDIENTE_APROBACION' then
    delete from solicitud_empleados where id = p_solicitud_empleado_id;
    perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', v_se.solicitud_id, 'EMPLEADO_ELIMINADO', 'COMPLETA',
      p_entidad_relacionada_tipo := 'EMPLEADO', p_entidad_relacionada_id := v_se.empleado_id);
  else
    -- Corrección #1: si ya estaba APROBADO, su aporte a ranking_horas se
    -- revierte ANTES de marcarlo CANCELADO — si no, el ranking queda
    -- inflado para siempre (estado_aprobacion se conserva histórico
    -- intacto, pero su efecto en el ranking activo no debe persistir).
    perform fn_revertir_ranking_si_aprobado(p_solicitud_empleado_id);
    update solicitud_empleados set estado_registro = 'CANCELADO' where id = p_solicitud_empleado_id;
    perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', v_se.solicitud_id, 'EMPLEADO_ELIMINADO', 'COMPLETA',
      p_entidad_relacionada_tipo := 'EMPLEADO', p_entidad_relacionada_id := v_se.empleado_id,
      p_datos := jsonb_build_object('estado_aprobacion_preservado', v_se.estado_aprobacion));
  end if;
end;
$$;

create or replace function rpc_reemplazar_empleado(p_solicitud_empleado_id uuid, p_empleado_nuevo_id uuid)
returns solicitud_empleados
language plpgsql security definer set search_path = public as $$
declare
  v_se_a solicitud_empleados;
  v_solicitud solicitudes;
  v_empleado_b empleados;
  v_se_b solicitud_empleados;
  v_banda_solicitud bandas_ranking;
  v_banda_real bandas_ranking;
  v_requiere_aprobacion boolean;
begin
  perform fn_exigir_usuario_activo();
  select * into v_se_a from solicitud_empleados where id = p_solicitud_empleado_id;
  if v_se_a.id is null then raise exception 'El registro a reemplazar no existe'; end if;
  if v_se_a.estado_registro <> 'ACTIVO' then
    raise exception 'Este registro ya no está vigente, no se puede reemplazar';
  end if;
  if v_se_a.empleado_id = p_empleado_nuevo_id then
    raise exception 'No se puede reemplazar un empleado por sí mismo';
  end if;

  select * into v_solicitud from solicitudes where id = v_se_a.solicitud_id for update;
  if v_solicitud.situacion not in ('EN_APROBACION', 'APROBADA') then
    raise exception 'No se pueden reemplazar empleados en el estado actual (%)', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  select * into v_empleado_b from empleados where id = p_empleado_nuevo_id;
  if v_empleado_b.id is null or v_empleado_b.estado <> 'ACTIVO' then
    raise exception 'El empleado de reemplazo no existe o no está ACTIVO';
  end if;

  select * into v_banda_solicitud from fn_banda_ranking(v_empleado_b.ranking_horas, 'SOLICITUD');
  if v_banda_solicitud.bloqueo_seleccion = 'BLOQUEADO' then
    raise exception 'El empleado de reemplazo no puede seleccionarse: banda "%" bloqueada', v_banda_solicitud.descripcion;
  end if;
  if v_empleado_b.ranking_horas_real is not null then
    select * into v_banda_real from fn_banda_ranking(v_empleado_b.ranking_horas_real, 'REAL');
    if v_banda_real.bloqueo_seleccion = 'BLOQUEADO' then
      raise exception 'El empleado de reemplazo no puede seleccionarse: banda real "%" bloqueada', v_banda_real.descripcion;
    end if;
  end if;

  if exists (select 1 from solicitud_empleados where solicitud_id = v_se_a.solicitud_id and empleado_id = p_empleado_nuevo_id and estado_registro = 'ACTIVO') then
    raise exception 'El empleado de reemplazo ya está en el equipo vigente de esta solicitud';
  end if;

  -- Corrección #7: faltaba esta validación — rpc_agregar_empleado ya la
  -- tenía, rpc_reemplazar_empleado no la replicaba para el empleado nuevo.
  if exists (
    select 1 from solicitud_empleados se join solicitudes s on s.id = se.solicitud_id
    where se.empleado_id = p_empleado_nuevo_id and se.estado_registro = 'ACTIVO' and se.estado_aprobacion <> 'RECHAZADO'
      and s.situacion not in ('CANCELADA', 'ELIMINADA') and s.id <> v_se_a.solicitud_id
      and (s.fecha_hora_inicio, s.fecha_hora_fin) overlaps (v_solicitud.fecha_hora_inicio, v_solicitud.fecha_hora_fin)
  ) then
    raise exception 'El empleado de reemplazo ya tiene horas asignadas que se superponen con este horario en otra solicitud';
  end if;

  -- La moneda ya NO se pre-chequea acá (corrección #3): se valida dentro
  -- de fn_calcular_detalle_solicitud_empleado, disparada por el trigger
  -- after_insert al insertar la fila de B más abajo.

  -- Corrección #1: revertir el aporte de A al ranking ANTES de marcarlo
  -- REEMPLAZADO, si ya estaba APROBADO — su estado_aprobacion histórico
  -- no se toca, pero su efecto en el ranking activo no debe persistir.
  perform fn_revertir_ranking_si_aprobado(p_solicitud_empleado_id);

  update solicitud_empleados set estado_registro = 'REEMPLAZADO' where id = p_solicitud_empleado_id;

  select m.requiere_aprobacion into v_requiere_aprobacion from motivos m where m.id = v_solicitud.motivo_id;

  insert into solicitud_empleados (solicitud_id, empleado_id, estado_aprobacion, reemplaza_a)
  -- Hallazgo real (ejecución): mismo cast explícito que en rpc_agregar_empleado.
  values (v_se_a.solicitud_id, p_empleado_nuevo_id, (case when v_requiere_aprobacion then 'PENDIENTE_APROBACION' else 'APROBADO' end)::estado_empleado_aprobacion, p_solicitud_empleado_id)
  returning * into v_se_b;

  if not v_requiere_aprobacion then
    select * into v_se_b from solicitud_empleados where id = v_se_b.id;
    update solicitud_empleados set fecha_hora_aprobacion = now() where id = v_se_b.id;
    update empleados set ranking_horas = ranking_horas + v_se_b.total_horas where id = p_empleado_nuevo_id;
    insert into auditoria (usuario_id, accion, tabla, registro_id, origen) values (null, 'APPROVE', 'solicitud_empleados', v_se_b.id, 'SISTEMA');
  end if;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', v_se_a.solicitud_id, 'EMPLEADO_REEMPLAZADO', 'COMPLETA',
    p_entidad_relacionada_tipo := 'EMPLEADO', p_entidad_relacionada_id := p_empleado_nuevo_id,
    p_datos := jsonb_build_object(
      'empleado_reemplazado_id', v_se_a.empleado_id,
      'solicitud_empleado_reemplazado_id', p_solicitud_empleado_id,
      'empleado_nuevo_id', p_empleado_nuevo_id,
      'solicitud_empleado_nuevo_id', v_se_b.id,
      'jornada_ya_iniciada', now() > v_solicitud.fecha_hora_inicio
    ));

  return v_se_b;
end;
$$;

create or replace function rpc_registrar_control_ingreso(
  p_solicitud_empleado_id uuid,
  p_resultado estado_asistencia_empleado,
  p_fecha_hora timestamptz default now()
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  if p_resultado not in ('INGRESO_REGISTRADO', 'YA_ESTABA_EN_PLANTA', 'NO_PRESENTADO') then
    raise exception 'Resultado de control de ingreso inválido: %', p_resultado;
  end if;

  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;
  if v_se.id is null then raise exception 'El registro no existe'; end if;

  select * into v_solicitud from solicitudes where id = v_se.solicitud_id for update;
  if v_solicitud.situacion <> 'APROBADA' then
    raise exception 'El control de ingreso solo está disponible mientras la solicitud está APROBADA (actual: %)', v_solicitud.situacion;
  end if;
  if v_se.estado_aprobacion <> 'APROBADO' or v_se.estado_registro <> 'ACTIVO' then
    raise exception 'Este empleado no está en condiciones de registrar control de ingreso';
  end if;
  if not fn_puede_control_ingreso_sobre(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para registrar control de ingreso';
  end if;

  update solicitud_empleados
    set estado_asistencia = p_resultado,
        usuario_control_ingreso_id = auth.uid(),
        fecha_hora_ingreso = case when p_resultado = 'INGRESO_REGISTRADO' then p_fecha_hora else null end
    where id = p_solicitud_empleado_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'CONTROL_INGRESO_REGISTRADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id,
    p_estado_nuevo := p_resultado::text);
end;
$$;

create or replace function rpc_quitar_control_ingreso(p_solicitud_empleado_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_solicitud solicitudes;
  v_permite_general boolean;
begin
  perform fn_exigir_usuario_activo();
  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id;
  if v_se.id is null then raise exception 'El registro no existe'; end if;

  select * into v_solicitud from solicitudes where id = v_se.solicitud_id for update;
  if v_solicitud.situacion <> 'APROBADA' then
    raise exception 'Solo se puede quitar el control de ingreso mientras la solicitud está APROBADA';
  end if;

  select control_ingreso_permite_eliminar into v_permite_general from configuracion_general where id = 1;

  -- Admin siempre puede; si no, hace falta el interruptor general Y el
  -- permiso individual, ambos en true (cierre funcional V2).
  -- V2.1: ademas del interruptor general y del permiso individual hace falta
  -- ser operador de control de ingreso DENTRO del alcance de visibilidad.
  if not (
    fn_es_admin()
    or (v_permite_general
        and coalesce((select puede_quitar_control_ingreso from usuario_permisos where usuario_id = auth.uid()), false)
        and fn_puede_control_ingreso_sobre(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id))
  ) then
    raise exception 'No tenés permiso para quitar un control de ingreso ya registrado';
  end if;

  if v_se.estado_asistencia = 'PENDIENTE_INGRESO' then
    raise exception 'Este empleado todavía no tiene control de ingreso registrado';
  end if;

  update solicitud_empleados
    set estado_asistencia = 'PENDIENTE_INGRESO', usuario_control_ingreso_id = null, fecha_hora_ingreso = null
    where id = p_solicitud_empleado_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'CONTROL_INGRESO_ELIMINADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id);
end;
$$;

create or replace function rpc_finalizar_solicitud(p_solicitud_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_pendientes_ingreso integer;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'APROBADA' then
    raise exception 'Solo se puede finalizar una solicitud APROBADA (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_control_ingreso_sobre(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para finalizar el control de ingreso de esta solicitud';
  end if;

  select count(*) into v_pendientes_ingreso from solicitud_empleados
    where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' and estado_asistencia = 'PENDIENTE_INGRESO';
  if v_pendientes_ingreso > 0 then
    raise exception 'Todavía hay % empleado(s) sin resolver su control de ingreso', v_pendientes_ingreso;
  end if;

  update solicitudes set situacion = 'FINALIZADA', updated_at = now() where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_CAMBIO_ESTADO', 'BASICA',
    p_estado_anterior := 'APROBADA', p_estado_nuevo := 'FINALIZADA');
end;
$$;

create or replace function rpc_cancelar_solicitud(p_solicitud_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'El motivo de cancelación es obligatorio';
  end if;

  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion in ('CANCELADA', 'ELIMINADA') then
    raise exception 'La solicitud ya está en un estado terminal (%)', v_solicitud.situacion;
  end if;
  if not fn_puede_eliminar_cancelar() then
    raise exception 'No tenés permiso para cancelar solicitudes';
  end if;

  -- V2.1: cancelar BORRADOR/EN_APROBACION/APROBADA devuelve las horas aprobadas
  -- al ranking. Cancelar una FINALIZADA NO toca el ranking (horas consolidadas):
  -- se corrige solo con rpc_rectificar_horas_ranking(), con trazabilidad.
  if v_solicitud.situacion <> 'FINALIZADA' then
    perform fn_revertir_ranking_si_aprobado(se.id)
      from solicitud_empleados se where se.solicitud_id = p_solicitud_id and se.estado_registro = 'ACTIVO';
  end if;

  update solicitudes set situacion = 'CANCELADA', updated_at = now() where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_CANCELADA', 'BASICA',
    p_estado_anterior := v_solicitud.situacion::text, p_estado_nuevo := 'CANCELADA',
    p_datos := jsonb_build_object('motivo', p_motivo, 'ranking_revertido', v_solicitud.situacion <> 'FINALIZADA'));
end;
$$;

-- Nunca DELETE físico (cierre funcional V2): toda solicitud ya tiene
-- número asignado desde el INSERT, y se conservan numeración,
-- trazabilidad, auditoría e historial siempre — una sola rama.
create or replace function rpc_eliminar_borrador(p_solicitud_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'BORRADOR' then
    raise exception 'Solo se pueden eliminar solicitudes en BORRADOR (para otros estados, usar cancelar)';
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para eliminar esta solicitud';
  end if;

  -- V2.1: un BORRADOR con motivo sin aprobacion tiene empleados auto-aprobados sumando ranking.
  perform fn_revertir_ranking_si_aprobado(se.id)
    from solicitud_empleados se where se.solicitud_id = p_solicitud_id and se.estado_registro = 'ACTIVO';

  update solicitudes set situacion = 'ELIMINADA', updated_at = now() where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_ELIMINADA', 'BASICA',
    p_estado_anterior := 'BORRADOR', p_estado_nuevo := 'ELIMINADA');
end;
$$;

create or replace function rpc_reabrir_solicitud(p_solicitud_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'El motivo de reapertura es obligatorio';
  end if;

  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion not in ('APROBADA', 'RECHAZADA', 'FINALIZADA') then
    raise exception 'Solo se pueden reabrir solicitudes APROBADA, RECHAZADA o FINALIZADA (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_reabrir(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para reabrir en ese área/sector/proceso';
  end if;

  -- Corrección #5: helper centralizado (reemplaza al bloque duplicado que
  -- antes repetía esta misma lógica en 3 lugares distintos).
  perform fn_invalidar_aprobaciones_vigentes(p_solicitud_id);

  update solicitudes set situacion = 'EN_APROBACION', updated_at = now() where id = p_solicitud_id;

  insert into auditoria (usuario_id, accion, tabla, registro_id, origen)
  values (auth.uid(), 'REOPEN', 'solicitudes', p_solicitud_id, 'USUARIO');

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_REABIERTA', 'BASICA',
    p_estado_anterior := v_solicitud.situacion::text, p_estado_nuevo := 'EN_APROBACION',
    p_datos := jsonb_build_object('motivo', p_motivo));
end;
$$;


-- ============================================================================
-- PARTE 22 · Modificación de solicitudes
-- ============================================================================

create or replace function rpc_modificar_scope(
  p_solicitud_id uuid,
  p_area_id uuid,
  p_sector_id uuid,
  p_proceso_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion <> 'BORRADOR' then
    raise exception 'El área/sector/proceso solo se pueden modificar mientras la solicitud está en BORRADOR (actual: %)', v_solicitud.situacion;
  end if;

  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;
  if not fn_puede_modificar(p_area_id, p_sector_id, p_proceso_id) then
    raise exception 'No tenés permiso para mover la solicitud a ese área/sector/proceso';
  end if;

  if v_solicitud.area_id = p_area_id and v_solicitud.sector_id = p_sector_id and v_solicitud.proceso_id = p_proceso_id then
    return;
  end if;

  update solicitudes set area_id = p_area_id, sector_id = p_sector_id, proceso_id = p_proceso_id, updated_at = now()
    where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'SOLICITUD_MODIFICADA', 'COMPLETA',
    p_datos := jsonb_build_object(
      'campo', 'area_sector_proceso',
      'anterior', jsonb_build_object('area_id', v_solicitud.area_id, 'sector_id', v_solicitud.sector_id, 'proceso_id', v_solicitud.proceso_id),
      'nuevo', jsonb_build_object('area_id', p_area_id, 'sector_id', p_sector_id, 'proceso_id', p_proceso_id)
    ));
end;
$$;

create or replace function rpc_modificar_fechas(
  p_solicitud_id uuid,
  p_fecha_hora_inicio timestamptz,
  p_fecha_hora_fin timestamptz
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_dias_max integer;
  v_tz text;
  v_se_id uuid;
begin
  perform fn_exigir_usuario_activo();
  if p_fecha_hora_fin <= p_fecha_hora_inicio then
    raise exception 'fecha_hora_fin debe ser posterior a fecha_hora_inicio';
  end if;

  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion not in ('BORRADOR', 'EN_APROBACION') then
    raise exception 'La fecha solo se puede modificar en BORRADOR o EN_APROBACION (actual: %). Si ya está APROBADA, reabrila primero.', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  select dias_maximos_antiguedad, zona_horaria into v_dias_max, v_tz from configuracion_general where id = 1;
  if (p_fecha_hora_inicio at time zone v_tz)::date < ((now() at time zone v_tz)::date - v_dias_max) then
    raise exception 'La nueva fecha de inicio supera los % días de antigüedad permitidos', v_dias_max;
  end if;

  if v_solicitud.fecha_hora_inicio = p_fecha_hora_inicio and v_solicitud.fecha_hora_fin = p_fecha_hora_fin then
    return;
  end if;

  -- Corrección #5: helper centralizado.
  -- V2.1: tambien en BORRADOR. Con motivo sin aprobacion los empleados estan
  -- auto-APROBADOS y su aporte al ranking depende de total_horas, que cambia.
  perform fn_invalidar_aprobaciones_vigentes(p_solicitud_id);

  update solicitudes set fecha_hora_inicio = p_fecha_hora_inicio, fecha_hora_fin = p_fecha_hora_fin, updated_at = now()
    where id = p_solicitud_id;

  -- Corrección obligatoria C: antes de recalcular se limpia la moneda de
  -- cabecera en vez de dejar el valor viejo ahí. Sin este paso, el primer
  -- empleado recalculado con las fechas NUEVAS podía comparar su moneda
  -- recién resuelta contra la moneda VIEJA guardada en solicitudes.moneda
  -- (la de antes de este cambio de fechas) y rechazar la operación aunque
  -- todos los empleados fueran perfectamente consistentes ENTRE SÍ con las
  -- fechas nuevas. Al limpiarla acá, fn_calcular_detalle_solicitud_empleado
  -- la vuelve a fijar desde cero con el primer empleado que procesa en
  -- este mismo loop, y valida a los siguientes contra ESE valor — nunca
  -- contra uno obsoleto.
  update solicitudes set moneda = null where id = p_solicitud_id;

  -- fn_calcular_detalle_solicitud_empleado valida la consistencia de
  -- moneda por su cuenta, tramo por tramo, dentro de este mismo loop. Si
  -- algún empleado queda en conflicto, esa llamada lanza una excepción que
  -- revierte automáticamente TODA la transacción (fechas, el reseteo de
  -- moneda de arriba, y cualquier recálculo ya aplicado a empleados
  -- anteriores en este mismo loop) — no hay ninguna ventana donde quede un
  -- estado a medio aplicar.
  for v_se_id in select id from solicitud_empleados where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' loop
    perform fn_calcular_detalle_solicitud_empleado(v_se_id);
  end loop;

  -- V2.1: motivo sin aprobacion: se vuelve a auto-aprobar con las horas NUEVAS.
  if not coalesce((select requiere_aprobacion from motivos where id = v_solicitud.motivo_id), true) then
    for v_se_id in select id from solicitud_empleados where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' loop
      perform fn_aprobar_empleado_interno(v_se_id, null);
    end loop;
  end if;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'CAMBIO_FECHA', 'COMPLETA',
    p_datos := jsonb_build_object(
      'fecha_hora_inicio_anterior', v_solicitud.fecha_hora_inicio, 'fecha_hora_fin_anterior', v_solicitud.fecha_hora_fin,
      'fecha_hora_inicio_nueva', p_fecha_hora_inicio, 'fecha_hora_fin_nueva', p_fecha_hora_fin,
      'invalido_aprobaciones', true
    ));
end;
$$;

create or replace function rpc_modificar_motivo(p_solicitud_id uuid, p_motivo_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
  v_requiere_antes boolean;
  v_requiere_despues boolean;
  v_se_id uuid;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion not in ('BORRADOR', 'EN_APROBACION') then
    raise exception 'El motivo solo se puede modificar en BORRADOR o EN_APROBACION (actual: %)', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  if v_solicitud.motivo_id = p_motivo_id then
    return;
  end if;

  select requiere_aprobacion into v_requiere_antes from motivos where id = v_solicitud.motivo_id;
  select requiere_aprobacion into v_requiere_despues from motivos where id = p_motivo_id;
  if v_requiere_despues is null then
    raise exception 'El motivo nuevo no existe';
  end if;

  update solicitudes set motivo_id = p_motivo_id, updated_at = now() where id = p_solicitud_id;

  -- V2.1: tambien en BORRADOR (los empleados ya tienen estado_aprobacion derivado del motivo).
  -- MT-B: con aprobacion -> con aprobacion NO invalida (requiere_antes = requiere_despues).
  if v_requiere_antes is distinct from v_requiere_despues then
    -- Corrección #5: helper centralizado.
    perform fn_invalidar_aprobaciones_vigentes(p_solicitud_id);

    if not v_requiere_despues then
      for v_se_id in select id from solicitud_empleados where solicitud_id = p_solicitud_id and estado_registro = 'ACTIVO' loop
        perform fn_aprobar_empleado_interno(v_se_id, null);
      end loop;
    end if;
  end if;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'CAMBIO_MOTIVO', 'COMPLETA',
    p_datos := jsonb_build_object(
      'motivo_anterior_id', v_solicitud.motivo_id, 'motivo_nuevo_id', p_motivo_id,
      'requiere_aprobacion_antes', v_requiere_antes, 'requiere_aprobacion_despues', v_requiere_despues,
      'invalido_aprobaciones', v_requiere_antes is distinct from v_requiere_despues
    ));
end;
$$;

create or replace function rpc_modificar_observacion(p_solicitud_id uuid, p_observacion text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_solicitud solicitudes;
begin
  perform fn_exigir_usuario_activo();
  select * into v_solicitud from solicitudes where id = p_solicitud_id for update;
  if v_solicitud.id is null then raise exception 'La solicitud no existe'; end if;
  if v_solicitud.situacion in ('CANCELADA', 'ELIMINADA') then
    raise exception 'No se puede modificar una solicitud %', v_solicitud.situacion;
  end if;
  if not fn_puede_modificar(v_solicitud.area_id, v_solicitud.sector_id, v_solicitud.proceso_id) then
    raise exception 'No tenés permiso para modificar esta solicitud';
  end if;

  if v_solicitud.observacion is not distinct from p_observacion then
    return;
  end if;

  update solicitudes set observacion = p_observacion, updated_at = now() where id = p_solicitud_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD', p_solicitud_id, 'CAMBIO_OBSERVACION', 'COMPLETA',
    p_datos := jsonb_build_object('anterior', v_solicitud.observacion, 'nuevo', p_observacion));
end;
$$;
-- ============================================================================
-- PARTE 23 · RPC de empleados — alta/edición manual e importación Excel
-- ----------------------------------------------------------------------------
-- Cierre funcional V2: ya no exige fn_es_admin() a secas — exige la
-- capacidad fn_puede_importar() (admin/desarrollador siempre, RRHH si
-- tiene el permiso) MÁS el scope real de modificación sobre el área/
-- sector/proceso que se está escribiendo (nunca derivado de empleados).
-- Esto es lo que impide que RRHH sobrescriba información fuera de su
-- alcance configurado.
-- ============================================================================

create or replace function rpc_upsert_empleado(
  p_legajo text,
  p_nombre_completo text,
  p_categoria_codigo text,
  p_area_id uuid,
  p_sector_id uuid,
  p_proceso_id uuid,
  p_estado estado_empleado default 'ACTIVO',
  p_ib_id uuid default null,
  p_ranking_horas_real numeric default null,
  p_borrar_ib boolean default false,
  p_borrar_ranking_real boolean default false
)
returns empleados
language plpgsql security definer set search_path = public as $$
declare
  v_categoria_id uuid;
  v_empleado empleados;
  v_existente empleados;
  v_ib_id_alta uuid;
  v_ranking_real_alta numeric;
begin
  perform fn_exigir_usuario_activo();
  if p_legajo is null or length(trim(p_legajo)) = 0 then
    raise exception 'El legajo es obligatorio';
  end if;

  if p_nombre_completo is null or length(trim(p_nombre_completo)) = 0 then
    raise exception 'El nombre completo es obligatorio';
  end if;

  if not fn_puede_importar() then
    raise exception 'No tenés permiso para dar de alta/modificar empleados';
  end if;

  if not fn_puede_modificar(p_area_id, p_sector_id, p_proceso_id) then
    raise exception 'No tenés permiso para gestionar empleados en ese área/sector/proceso';
  end if;

  select * into v_existente from empleados where legajo = trim(p_legajo);
  if v_existente.id is not null
     and not fn_puede_modificar(v_existente.area_id, v_existente.sector_id, v_existente.proceso_id) then
    raise exception 'El empleado con legajo % pertenece a una unidad fuera de tu alcance — no podés modificarlo', trim(p_legajo);
  end if;

  select id into v_categoria_id from categoria_tipos where codigo = p_categoria_codigo;
  if v_categoria_id is null then
    raise exception 'La categoría % no existe', p_categoria_codigo;
  end if;

  v_ib_id_alta := case when p_borrar_ib then null else p_ib_id end;
  v_ranking_real_alta := case when p_borrar_ranking_real then null else p_ranking_horas_real end;

  insert into empleados (legajo, nombre_completo, categoria_id, area_id, sector_id, proceso_id, estado, ib_id, ranking_horas_real)
  values (trim(p_legajo), trim(p_nombre_completo), v_categoria_id, p_area_id, p_sector_id, p_proceso_id, p_estado, v_ib_id_alta, v_ranking_real_alta)
  on conflict (legajo) do update set
    nombre_completo = excluded.nombre_completo,
    categoria_id = excluded.categoria_id,
    area_id = excluded.area_id,
    sector_id = excluded.sector_id,
    proceso_id = excluded.proceso_id,
    estado = excluded.estado,
    ib_id = case
      when p_borrar_ib then null
      else coalesce(excluded.ib_id, empleados.ib_id)
    end,
    ranking_horas_real = case
      when p_borrar_ranking_real then null
      else coalesce(excluded.ranking_horas_real, empleados.ranking_horas_real)
    end
  returning * into v_empleado;

  return v_empleado;
end;
$$;

create or replace function rpc_importar_empleado_excel(
  p_legajo text,
  p_nombre_completo text,
  p_categoria_codigo text,
  p_area_nombre text,
  p_sector_nombre text,
  p_proceso_nombre text,
  p_estado text default 'ACTIVO',
  p_ib_nombre text default null,
  p_ranking_horas_real text default null
)
returns empleados
language plpgsql security definer set search_path = public as $$
declare
  v_area_id uuid;
  v_sector_id uuid;
  v_proceso_id uuid;
  v_ib_id uuid;
  v_ranking_real numeric;
begin
  perform fn_exigir_usuario_activo();
  if not fn_puede_importar() then
    raise exception 'No tenés permiso para importar empleados';
  end if;

  -- Área/sector/proceso ahora son obligatorios en la importación (antes
  -- eran opcionales): un empleado importado sin unidad organizativa podía
  -- terminar evaluando fn_puede_modificar(NULL,NULL,NULL) de forma
  -- ambigua para usuarios con scope AREA/SECTOR/PROCESO. Se exige que la
  -- fila del Excel traiga los 3 valores y que resuelvan a una jerarquía
  -- real — confirmado por el usuario.
  if p_area_nombre is null or length(trim(p_area_nombre)) = 0 then
    raise exception 'El área es obligatoria para importar un empleado';
  end if;
  select id into v_area_id from areas where nombre = trim(p_area_nombre);
  if v_area_id is null then
    raise exception 'No existe el área "%"', p_area_nombre;
  end if;

  if p_sector_nombre is null or length(trim(p_sector_nombre)) = 0 then
    raise exception 'El sector es obligatorio para importar un empleado';
  end if;
  select id into v_sector_id from sectores where nombre = trim(p_sector_nombre) and area_id = v_area_id;
  if v_sector_id is null then
    raise exception 'No existe el sector "%" dentro del área "%"', p_sector_nombre, p_area_nombre;
  end if;

  if p_proceso_nombre is null or length(trim(p_proceso_nombre)) = 0 then
    raise exception 'El proceso es obligatorio para importar un empleado';
  end if;
  select id into v_proceso_id from procesos where nombre = trim(p_proceso_nombre) and sector_id = v_sector_id;
  if v_proceso_id is null then
    raise exception 'No existe el proceso "%" dentro del sector "%"', p_proceso_nombre, p_sector_nombre;
  end if;

  if p_ib_nombre is not null and length(trim(p_ib_nombre)) > 0 then
    select id into v_ib_id from ib_configuracion where descripcion = trim(p_ib_nombre);
    if v_ib_id is null then
      raise exception 'No existe el IB "%" — cargalo primero en el catálogo de IB', p_ib_nombre;
    end if;
  end if;

  if p_ranking_horas_real is not null and length(trim(p_ranking_horas_real)) > 0 then
    begin
      v_ranking_real := trim(p_ranking_horas_real)::numeric;
    exception when others then
      raise exception 'El ranking real "%" no es un número válido', p_ranking_horas_real;
    end;
  end if;

  -- El scope real (fn_puede_modificar sobre area/sector/proceso resueltos)
  -- se valida dentro de rpc_upsert_empleado, al que esta función delega —
  -- no se duplica el chequeo acá.
  return rpc_upsert_empleado(
    p_legajo := p_legajo,
    p_nombre_completo := p_nombre_completo,
    p_categoria_codigo := p_categoria_codigo,
    p_area_id := v_area_id,
    p_sector_id := v_sector_id,
    p_proceso_id := v_proceso_id,
    p_estado := p_estado::estado_empleado,
    p_ib_id := v_ib_id,
    p_ranking_horas_real := v_ranking_real
  );
end;
$$;

-- ============================================================================
-- PARTE 24 · Reseteo periódico de ranking (según solicitud) — sin cambios.
-- Solo toca ranking_horas; ranking_horas_real es dato de RRHH, nunca lo
-- toca este job.
-- ============================================================================

create or replace function fn_resetear_ranking_si_corresponde()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empleado record;
begin
  for v_empleado in select id, ranking_horas from empleados where estado = 'ACTIVO' and ranking_horas > 0 loop
    insert into ranking_horas_historico (empleado_id, ranking_horas_final)
    values (v_empleado.id, v_empleado.ranking_horas);

    update empleados set ranking_horas = 0 where id = v_empleado.id;
  end loop;

  -- Corrección obligatoria E: se registra el instante del reseteo pase lo
  -- que pase (incluso si ningún empleado tenía ranking_horas > 0) — el
  -- límite de período es un evento del sistema, no de cada empleado
  -- individual. fn_revertir_ranking_si_aprobado/fn_invalidar_
  -- aprobaciones_vigentes lo usan para no tocar el ranking del período
  -- nuevo con aprobaciones de uno viejo ya archivado. Una invocación
  -- repetida es inofensiva: una segunda corrida el mismo período no
  -- encuentra a nadie con ranking_horas > 0 (ya quedaron en 0 tras la
  -- primera) salvo que de verdad haya habido aprobaciones nuevas en el
  -- medio — en cuyo caso resetearlas también es el comportamiento
  -- correcto, no un bug.
  update configuracion_general set ultimo_reseteo_ranking = now() where id = 1;
end;
$$;
-- ============================================================================
-- PARTE 24B · Rectificación explícita de horas ya consolidadas (V2.1)
-- ----------------------------------------------------------------------------
-- Cancelar una solicitud FINALIZADA NO descuenta horas del ranking. Si hay
-- que corregir horas ya consolidadas se hace acá, de forma explícita, solo
-- ADMIN/DESARROLLADOR, con motivo obligatorio y una fila de trazabilidad
-- inmutable (sin escritura directa) + evento de auditoría de negocio.
-- ============================================================================

create table ranking_rectificaciones (
  id                    uuid primary key default gen_random_uuid(),
  solicitud_empleado_id uuid not null references solicitud_empleados(id),
  solicitud_id          uuid not null references solicitudes(id),
  empleado_id           uuid not null references empleados(id),
  horas_descontadas     numeric(10,2) not null check (horas_descontadas > 0),
  ranking_antes         numeric(10,2) not null,
  ranking_despues       numeric(10,2) not null,
  motivo                text not null check (length(trim(motivo)) > 0),
  usuario_id            uuid not null references usuarios(id),
  created_at            timestamptz not null default now()
);
create index idx_ranking_rectificaciones_se on ranking_rectificaciones(solicitud_empleado_id);
create index idx_ranking_rectificaciones_empleado on ranking_rectificaciones(empleado_id);

alter table ranking_rectificaciones enable row level security;
create policy ranking_rectificaciones_select on ranking_rectificaciones for select to authenticated using (fn_es_admin());

create or replace function rpc_rectificar_horas_ranking(p_solicitud_empleado_id uuid, p_horas numeric, p_motivo text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_sol solicitudes;
  v_emp empleados;
  v_ult timestamptz;
  v_ya numeric;
  v_prev text;
  v_id uuid;
begin
  perform fn_exigir_usuario_activo();
  if not fn_es_admin() then
    raise exception 'No tenés permiso para rectificar horas del ranking';
  end if;
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'El motivo de la rectificación es obligatorio';
  end if;
  if p_horas is null or p_horas <= 0 then
    raise exception 'Las horas a rectificar deben ser mayores que cero';
  end if;

  select * into v_se from solicitud_empleados where id = p_solicitud_empleado_id for update;
  if v_se.id is null then raise exception 'El empleado de la solicitud no existe'; end if;
  select * into v_sol from solicitudes where id = v_se.solicitud_id for update;

  if v_se.estado_registro <> 'ACTIVO' or v_se.estado_aprobacion <> 'APROBADO' then
    raise exception 'Solo se rectifican horas de empleados ACTIVOS con estado APROBADO';
  end if;

  if v_sol.situacion = 'CANCELADA' then
    select estado_anterior into v_prev from auditoria_negocio
      where entidad_tipo = 'SOLICITUD' and entidad_id = v_sol.id and evento = 'SOLICITUD_CANCELADA'
      order by fecha_hora desc limit 1;
    if v_prev is distinct from 'FINALIZADA' then
      raise exception 'Solo se rectifican solicitudes FINALIZADAS o canceladas estando FINALIZADAS (en los demás estados el ranking ya se ajustó al cancelar)';
    end if;
  elsif v_sol.situacion <> 'FINALIZADA' then
    raise exception 'Solo se rectifican solicitudes FINALIZADAS o canceladas estando FINALIZADAS (actual: %)', v_sol.situacion;
  end if;

  select ultimo_reseteo_ranking into v_ult from configuracion_general where id = 1;
  if v_ult is not null and v_se.fecha_hora_aprobacion <= v_ult then
    raise exception 'Esas horas pertenecen a un período de ranking ya cerrado y archivado en el histórico: no se rectifican desde acá';
  end if;

  select coalesce(sum(horas_descontadas), 0) into v_ya from ranking_rectificaciones where solicitud_empleado_id = v_se.id;
  if v_ya + p_horas > v_se.total_horas then
    raise exception 'Las horas a rectificar (%) superan las horas consolidadas disponibles (% de % ya rectificadas)', p_horas, v_ya, v_se.total_horas;
  end if;

  select * into v_emp from empleados where id = v_se.empleado_id for update;
  if v_emp.ranking_horas < p_horas then
    raise exception 'El ranking actual del empleado (%) es menor que las horas a rectificar (%)', v_emp.ranking_horas, p_horas;
  end if;

  update empleados set ranking_horas = ranking_horas - p_horas where id = v_emp.id;

  insert into ranking_rectificaciones (solicitud_empleado_id, solicitud_id, empleado_id, horas_descontadas, ranking_antes, ranking_despues, motivo, usuario_id)
  values (v_se.id, v_sol.id, v_emp.id, p_horas, v_emp.ranking_horas, v_emp.ranking_horas - p_horas, trim(p_motivo), auth.uid())
  returning id into v_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', v_se.id, 'RANKING_RECTIFICADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_sol.id,
    p_datos := jsonb_build_object('rectificacion_id', v_id, 'empleado_id', v_emp.id, 'horas', p_horas,
                                  'ranking_antes', v_emp.ranking_horas, 'ranking_despues', v_emp.ranking_horas - p_horas, 'motivo', trim(p_motivo)));
  return v_id;
end;
$$;


-- ============================================================================
-- PARTE 25 · Validación de jerarquía organizacional
-- ============================================================================

create or replace function fn_trigger_validar_jerarquia()
returns trigger
language plpgsql
as $$
declare
  v_sector sectores;
  v_proceso procesos;
begin
  if new.sector_id is not null then
    select * into v_sector from sectores where id = new.sector_id;
    if v_sector.area_id <> new.area_id then
      raise exception 'El sector no pertenece al área indicada';
    end if;
  end if;

  if new.proceso_id is not null then
    select * into v_proceso from procesos where id = new.proceso_id;
    if v_proceso.sector_id <> new.sector_id then
      raise exception 'El proceso no pertenece al sector indicado';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_validar_jerarquia_empleados
  before insert or update of area_id, sector_id, proceso_id on empleados
  for each row execute function fn_trigger_validar_jerarquia();

create trigger trg_validar_jerarquia_solicitudes
  before insert or update of area_id, sector_id, proceso_id on solicitudes
  for each row execute function fn_trigger_validar_jerarquia();


-- ============================================================================
-- PARTE 26 · Notificaciones por email (log)
-- ============================================================================

create or replace function fn_notificar_solicitud()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emails_activos boolean;
begin
  select emails_activos into v_emails_activos from configuracion_general where id = 1;
  if not v_emails_activos then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    insert into notificaciones_log (solicitud_id, tipo) values (new.id, 'CREACION');
  elsif tg_op = 'UPDATE' then
    if old.fecha_hora_inicio is distinct from new.fecha_hora_inicio
       or old.fecha_hora_fin is distinct from new.fecha_hora_fin
       or old.motivo_id is distinct from new.motivo_id
       or old.observacion is distinct from new.observacion then
      insert into notificaciones_log (solicitud_id, tipo) values (new.id, 'MODIFICACION');
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_notificar_solicitud_insert
  after insert on solicitudes
  for each row execute function fn_notificar_solicitud();

create trigger trg_notificar_solicitud_update
  after update on solicitudes
  for each row execute function fn_notificar_solicitud();


-- ============================================================================
-- PARTE 27 · Vistas definitivas
-- ============================================================================

create or replace view vista_solicitudes_resumen
with (security_invoker = true)
as
select
  s.id, s.numero, s.situacion, s.solicitante_id, u.nombre_completo as solicitante_nombre,
  s.area_id, a.nombre as area_nombre, s.sector_id, sec.nombre as sector_nombre,
  s.proceso_id, proc.nombre as proceso_nombre, s.motivo_id, m.motivo as motivo_nombre, m.tipo as motivo_tipo,
  s.fecha_hora_inicio, s.fecha_hora_fin, s.observacion, s.moneda, s.fecha_hora_solicitud,
  count(se.id) filter (where se.estado_registro = 'ACTIVO') as cantidad_empleados,
  coalesce(sum(se.total_horas) filter (where se.estado_registro = 'ACTIVO'), 0) as total_horas_solicitud,
  case when fn_puede_ver_importes() then coalesce(sum(se.total_importe) filter (where se.estado_registro = 'ACTIVO'), 0) else null end as total_importe_solicitud,
  case when fn_puede_ver_importes() then coalesce(sum(se.total_importe) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'APROBADO'), 0) else null end as importe_aprobado,
  case when fn_puede_ver_importes() then coalesce(sum(se.total_importe) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'RECHAZADO'), 0) else null end as importe_rechazado,
  case when fn_puede_ver_importes() then coalesce(sum(se.total_importe) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'PENDIENTE_APROBACION'), 0) else null end as importe_pendiente
from solicitudes s
join usuarios u on u.id = s.solicitante_id
join areas a on a.id = s.area_id
join sectores sec on sec.id = s.sector_id
join procesos proc on proc.id = s.proceso_id
join motivos m on m.id = s.motivo_id
left join solicitud_empleados se on se.solicitud_id = s.id
group by s.id, u.nombre_completo, a.nombre, sec.nombre, proc.nombre, m.motivo, m.tipo;

create or replace view vista_solicitud_empleados_detalle
with (security_invoker = true)
as
select
  se.id as solicitud_empleado_id,
  se.solicitud_id,
  se.empleado_id,
  e.legajo,
  e.nombre_completo,
  ib.descripcion as ib_descripcion,
  se.ranking_horas_al_momento,
  se.estado_aprobacion,
  se.estado_asistencia,
  se.estado_registro,
  se.motivo_rechazo,
  se.total_horas,
  case when fn_puede_ver_importes() then se.total_importe else null end as total_importe,
  se.fecha_hora_aprobacion,
  se.usuario_aprobacion_id,
  se.fecha_hora_ingreso,
  se.usuario_control_ingreso_id,
  se.reemplaza_a,
  eo.legajo as reemplaza_a_legajo,
  eo.nombre_completo as reemplaza_a_nombre
from solicitud_empleados se
join empleados e on e.id = se.empleado_id
left join ib_configuracion ib on ib.id = se.ib_al_momento
left join solicitud_empleados sea on sea.id = se.reemplaza_a
left join empleados eo on eo.id = sea.empleado_id;

create or replace view vista_empleados_resumen
with (security_invoker = true)
as
select
  e.id,
  e.legajo,
  e.nombre_completo,
  ct.codigo as categoria_codigo,
  e.area_id,
  a.nombre as area_nombre,
  e.sector_id,
  sec.nombre as sector_nombre,
  e.proceso_id,
  proc.nombre as proceso_nombre,
  e.estado,
  e.ranking_horas,
  e.ranking_horas_real,
  e.ib_id,
  ib.descripcion as ib_descripcion,
  e.fecha_alta,
  e.fecha_baja
from empleados e
join categoria_tipos ct on ct.id = e.categoria_id
left join areas a on a.id = e.area_id
left join sectores sec on sec.id = e.sector_id
left join procesos proc on proc.id = e.proceso_id
left join ib_configuracion ib on ib.id = e.ib_id;
-- ============================================================================
-- PARTE 28 · RLS — tablas maestras y organizacionales
-- ----------------------------------------------------------------------------
-- Corrección obligatoria D (revisión de políticas SELECT permisivas en
-- tablas maestras): se revisaron todas las de esta sección. Se dejan
-- abiertas a `authenticated` (y `configuracion_apariencia` también a
-- `anon`, para poder pintar nombre/logo/colores antes del login) a
-- propósito: son catálogos operativos (áreas, sectores, procesos, tipos de
-- categoría, valores vigentes por categoría, bandas horarias, feriados,
-- motivos, catálogo de IB, bandas de ranking, niveles de aprobación) que
-- cualquier usuario autenticado necesita leer ampliamente para operar la
-- aplicación (completar formularios, ver el detalle de un cálculo, etc.).
-- Ninguna fila de estas tablas identifica a una PERSONA ni expone permisos
-- o alcances de nadie — es la diferencia con usuario_roles/usuario_
-- permisos/usuario_permiso_scopes, que sí se restringieron arriba. No se
-- encontró ningún acceso indebido en este grupo de tablas.
-- ============================================================================

alter table areas enable row level security;
alter table sectores enable row level security;
alter table procesos enable row level security;
alter table categoria_tipos enable row level security;
alter table categorias enable row level security;
alter table bandas_horarias enable row level security;
alter table feriados enable row level security;
alter table motivos enable row level security;
alter table ib_configuracion enable row level security;
alter table bandas_ranking enable row level security;
alter table niveles_aprobacion_config enable row level security;

create policy areas_select on areas for select to authenticated using (fn_usuario_activo());
create policy areas_write on areas for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy sectores_select on sectores for select to authenticated using (fn_usuario_activo());
create policy sectores_write on sectores for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy procesos_select on procesos for select to authenticated using (fn_usuario_activo());
create policy procesos_write on procesos for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy categoria_tipos_select on categoria_tipos for select to authenticated using (fn_usuario_activo());
create policy categoria_tipos_write on categoria_tipos for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy categorias_select on categorias for select to authenticated using (fn_usuario_activo());
create policy categorias_write on categorias for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy bandas_horarias_select on bandas_horarias for select to authenticated using (fn_usuario_activo());
create policy bandas_horarias_write on bandas_horarias for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy feriados_select on feriados for select to authenticated using (fn_usuario_activo());
create policy feriados_write on feriados for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy motivos_select on motivos for select to authenticated using (fn_usuario_activo());
create policy motivos_write on motivos for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy ib_configuracion_select on ib_configuracion for select to authenticated using (fn_usuario_activo());
create policy ib_configuracion_write on ib_configuracion for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy bandas_ranking_select on bandas_ranking for select to authenticated using (fn_usuario_activo());
create policy bandas_ranking_write on bandas_ranking for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy niveles_aprobacion_config_select on niveles_aprobacion_config for select to authenticated using (fn_usuario_activo());
create policy niveles_aprobacion_config_write on niveles_aprobacion_config for all to authenticated using (fn_es_admin()) with check (fn_es_admin());


-- ============================================================================
-- PARTE 29 · RLS — configuración
-- ============================================================================

alter table configuracion_general enable row level security;
alter table configuracion_apariencia enable row level security;

create policy configuracion_general_select on configuracion_general for select to authenticated using (fn_usuario_activo());
create policy configuracion_general_write on configuracion_general for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy configuracion_apariencia_select on configuracion_apariencia for select to anon, authenticated using (true);
create policy configuracion_apariencia_write on configuracion_apariencia for all to authenticated using (fn_es_admin()) with check (fn_es_admin());


-- ============================================================================
-- PARTE 30 · RLS — usuarios, roles, permisos y scopes
-- ----------------------------------------------------------------------------
-- usuario_permiso_scopes: solo admin/desarrollador escribe — ni siquiera
-- RRHH (que no pasa fn_es_admin()) puede tocar su propio scope ni el de
-- nadie más. Es la garantía de que nadie pueda ampliar su propio alcance.
--
-- Corrección obligatoria D: las políticas SELECT de usuario_roles,
-- usuario_permisos y usuario_permiso_scopes eran `using (true)` — CUALQUIER
-- usuario autenticado (incluido CONSULTA) podía leer la fila de CUALQUIER
-- otro usuario: qué roles tiene, su nivel de permiso por tipo y su
-- área/sector/proceso de alcance. Eso expone el mapa completo de quién
-- puede aprobar/modificar/reabrir qué, y de quién es ADMIN/DESARROLLADOR
-- — información de administración de accesos, no un catálogo operativo.
--
-- Qué necesita cada perfil para operar:
--   - La AUTORIZACIÓN real (¿puede este usuario hacer X?) nunca pasa por
--     una consulta directa a estas tablas desde el cliente: la resuelven
--     fn_puede_ver/modificar/aprobar/reabrir/fn_es_admin (PARTE 15), que
--     son `security definer` y consultan estas tablas con los privilegios
--     del dueño de la función — no están sujetas a estas políticas SELECT
--     en absoluto. Restringir el acceso DIRECTO a la tabla no le quita a
--     la aplicación ninguna capacidad de autorizar operaciones.
--   - Un usuario normal sí necesita poder leer SU PROPIA fila (para que el
--     frontend muestre "tus permisos"/"tu alcance" en una pantalla de
--     perfil, por ejemplo) — se cubre con `usuario_id = auth.uid()`.
--   - Un ADMIN/DESARROLLADOR necesita seguir viendo TODAS las filas para
--     las pantallas de administración de usuarios — se cubre agregando
--     `or fn_es_admin()`, que no cambia nada para quien ya administraba
--     usuarios.
-- Con esto, ningún usuario pierde una capacidad que ya tuviera realmente
-- en uso (autorización vía las funciones, admin ve todo, cada quien ve lo
-- suyo); lo único que se cierra es poder listar a los demás.
--
-- Revisión final (cierre V2): `usuarios` y `roles` YA NO quedan abiertas a
-- todo autenticado. `usuarios` guarda nombre_completo, `activo` y fechas
-- (el email vive en auth.users, que no se expone); `roles` guarda el
-- catálogo de roles con su descripción (revela qué existe un rol
-- DESARROLLADOR/RRHH y sus alcances). Nada de eso lo necesita un usuario
-- común más allá de lo que ve en pantalla:
--   - usuarios: la propia fila, y las filas de las personas que aparecen en
--     solicitudes que ESE usuario puede ver (solicitante, quien aprobó,
--     quien registró el control de ingreso). Admin ve todas. Las vistas
--     corren con `security_invoker = true`, así que el join de
--     vista_solicitudes_resumen contra usuarios queda sujeto a esta misma
--     política: el solicitante de toda solicitud visible es visible por la
--     segunda rama, por lo que el inner join no pierde filas (verificado
--     por ejecución). Las subconsultas a solicitudes/solicitud_empleados
--     respetan RLS del invocador (fn_puede_ver) y esas políticas no
--     consultan usuarios, así que no hay recursión.
--   - roles: solo los roles que el propio usuario tiene asignados (vía
--     usuario_roles, ya acotada a la propia fila) y, para admin, todos.
--
-- Sobre llamadas recursivas de RLS: fn_es_admin() consulta usuario_roles
-- (la misma tabla que protege la política de usuario_roles_select). No es
-- un problema: fn_es_admin() es `security definer`, corre con los
-- privilegios del dueño de la función, y ninguna de estas tablas tiene
-- `FORCE ROW LEVEL SECURITY` activado — por diseño de Postgres, el dueño
-- de una tabla omite RLS salvo que se fuerce explícitamente. La consulta
-- interna de fn_es_admin() ve todas las filas sin aplicar la política de
-- nuevo, así que no hay recursión ni resultado incorrecto.
-- ============================================================================

alter table usuarios enable row level security;
alter table roles enable row level security;
alter table usuario_roles enable row level security;
alter table usuario_permisos enable row level security;
alter table usuario_permiso_scopes enable row level security;

create policy usuarios_select on usuarios for select to authenticated
  using (
    (id = auth.uid() and fn_usuario_activo())
    or fn_es_admin()
    or (fn_usuario_activo() and (
         exists (select 1 from solicitudes s where s.solicitante_id = usuarios.id)
         or exists (select 1 from solicitud_empleados se
                    where se.usuario_aprobacion_id = usuarios.id or se.usuario_control_ingreso_id = usuarios.id)))
  );
create policy usuarios_write on usuarios for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy roles_select on roles for select to authenticated
  using (
    fn_es_admin()
    or (fn_usuario_activo() and exists (select 1 from usuario_roles ur where ur.rol_id = roles.id and ur.usuario_id = auth.uid()))
  );

create policy usuario_roles_select on usuario_roles for select to authenticated
  using ((usuario_id = auth.uid() and fn_usuario_activo()) or fn_es_admin());
create policy usuario_roles_write on usuario_roles for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy usuario_permisos_select on usuario_permisos for select to authenticated
  using ((usuario_id = auth.uid() and fn_usuario_activo()) or fn_es_admin());
create policy usuario_permisos_write on usuario_permisos for all to authenticated using (fn_es_admin()) with check (fn_es_admin());

create policy usuario_permiso_scopes_select on usuario_permiso_scopes for select to authenticated
  using ((usuario_id = auth.uid() and fn_usuario_activo()) or fn_es_admin());
create policy usuario_permiso_scopes_write on usuario_permiso_scopes for all to authenticated using (fn_es_admin()) with check (fn_es_admin());


-- ============================================================================
-- PARTE 31 · RLS — empleados y ranking histórico
-- ============================================================================

alter table empleados enable row level security;
alter table ranking_horas_historico enable row level security;

create policy empleados_select on empleados for select to authenticated
  using (fn_puede_ver(area_id, sector_id, proceso_id));

create policy empleados_write on empleados for all to authenticated
  using (fn_es_admin()) with check (fn_es_admin());

create policy ranking_horas_historico_select on ranking_horas_historico for select to authenticated
  using (fn_es_admin());


-- ============================================================================
-- PARTE 32 · RLS — solicitudes y equipo (sin escritura directa, todo por RPC)
-- ============================================================================

alter table solicitudes enable row level security;
alter table solicitud_empleados enable row level security;
alter table solicitud_empleado_detalle enable row level security;
alter table solicitud_aprobaciones enable row level security;
-- Revisión final: contador_solicitudes era la única tabla sin RLS. Sin
-- políticas y sin GRANT para anon/authenticated: solo la toca
-- fn_asignar_numero_solicitud (security definer, dueño de la tabla).
alter table contador_solicitudes enable row level security;

create policy solicitudes_select on solicitudes for select to authenticated
  using (fn_puede_ver(area_id, sector_id, proceso_id));

create policy solicitud_empleados_select on solicitud_empleados for select to authenticated
  using (
    exists (
      select 1 from solicitudes s
      where s.id = solicitud_empleados.solicitud_id
        and fn_puede_ver(s.area_id, s.sector_id, s.proceso_id)
    )
  );

create policy solicitud_empleado_detalle_select on solicitud_empleado_detalle for select to authenticated
  using (
    exists (
      select 1 from solicitud_empleados se join solicitudes s on s.id = se.solicitud_id
      where se.id = solicitud_empleado_detalle.solicitud_empleado_id
        and fn_puede_ver(s.area_id, s.sector_id, s.proceso_id)
    )
  );

create policy solicitud_aprobaciones_select on solicitud_aprobaciones for select to authenticated
  using (
    exists (
      select 1 from solicitudes s
      where s.id = solicitud_aprobaciones.solicitud_id
        and fn_puede_ver(s.area_id, s.sector_id, s.proceso_id)
    )
  );


-- ============================================================================
-- PARTE 33 · RLS — auditoría (técnica y de negocio) y notificaciones
-- ============================================================================

alter table auditoria enable row level security;
alter table auditoria_negocio enable row level security;
alter table notificaciones_log enable row level security;

create policy auditoria_select on auditoria for select to authenticated using (fn_es_admin());
create policy auditoria_negocio_select on auditoria_negocio for select to authenticated using (fn_es_admin());
create policy notificaciones_log_select on notificaciones_log for select to authenticated using (fn_es_admin());


-- ============================================================================
-- PARTE 34 · Privilegios EXECUTE de funciones (corrección obligatoria A)
-- ----------------------------------------------------------------------------
-- Postgres otorga EXECUTE a PUBLIC automáticamente en toda función recién
-- creada, salvo que se revoque explícitamente. Como Supabase expone
-- automáticamente toda función del schema public como RPC invocable por
-- PostgREST, eso dejaba callable DIRECTAMENTE — incluso por cualquier
-- usuario autenticado sin ningún permiso de negocio, y en varios casos
-- incluso por `anon` — a funciones internas del motor que NO tienen
-- ningún chequeo de permiso/scope/estado propio: confían en que quien las
-- invoca ya validó todo antes (la RPC pública que las envuelve). Ejemplos
-- concretos de lo que esto permitía antes de esta corrección:
--   - Llamar fn_calcular_detalle_solicitud_empleado(id) directo sobre
--     cualquier solicitud_empleado_id, sin pasar por ningún chequeo de
--     fn_puede_modificar.
--   - Llamar fn_aprobar_empleado_interno(id, usuario_id)/fn_rechazar_
--     empleado_interno directo, aprobando/rechazando a mano con CUALQUIER
--     usuario_id, sin que la solicitud esté EN_APROBACION ni chequear
--     fn_puede_aprobar.
--   - Llamar fn_invalidar_aprobaciones_vigentes/fn_revertir_ranking_si_
--     aprobado directo, alterando ranking_horas de cualquier empleado.
--   - Llamar fn_registrar_evento_negocio directo, insertando entradas de
--     auditoría de negocio falsificadas.
--   - Llamar fn_resetear_ranking_si_corresponde directo (pensada para
--     correr solo desde un job programado), forzando un reseteo de
--     ranking a voluntad.
--
-- Política aplicada: se revoca EXECUTE de PUBLIC en TODAS las funciones
-- del schema public (recupera el default seguro "nadie puede" en vez de
-- "cualquiera puede"), y se otorga EXECUTE explícitamente solo a
-- `authenticated`, solo en:
--   (a) las RPC de negocio reales (rpc_*), que sí validan permiso/scope/
--       estado internamente antes de mutar nada, y
--   (b) los helpers de solo lectura fn_puede_*/fn_es_*/fn_permisos_para_
--       scope/fn_banda_ranking — sin efectos secundarios, son la MISMA
--       fuente de verdad que ya usan RLS y las RPC (PARTE 15); exponerlas
--       no otorga ningún permiso nuevo, solo permite que el frontend
--       pregunte "¿puedo hacer X?" sin duplicar la lógica de autorización.
-- Nunca se otorga nada a `anon`: toda la aplicación requiere sesión.
--
-- Lo que NO recibe ningún grant (triggers y funciones internas del motor)
-- sigue funcionando exactamente igual después de este REVOKE, porque:
--   - Los triggers se ejecutan automáticamente como parte de la sentencia
--     que los dispara — Postgres no exige privilegio EXECUTE para que un
--     trigger corra, sin importar estos REVOKE.
--   - Toda llamada función→función (ej. una RPC `rpc_*` llamando a
--     fn_calcular_detalle_solicitud_empleado, o esta llamando a
--     fn_valor_hora_vigente) ocurre ya con los privilegios del DUEÑO de
--     la función exterior, porque esa función exterior es `security
--     definer`. El dueño de una función siempre tiene EXECUTE implícito
--     sobre sus propios objetos, sin importar lo que se le haya revocado
--     a PUBLIC/authenticated/anon — esos REVOKE solo afectan a quien
--     intenta invocarla DIRECTAMENTE desde afuera (ej. vía
--     supabase.rpc(...) desde el cliente).
--   - fn_resetear_ranking_si_corresponde() se invoca solo desde un job
--     programado externo (pg_cron o una Edge Function con la service_role
--     key) — ese camino no pasa por los grants de anon/authenticated que
--     se manejan acá.
--
-- Search_path: todas las funciones `security definer` de este archivo ya
-- se crearon con `set search_path = public` (criterio ya aplicado de
-- forma consistente en todo el archivo original — verificado función por
-- función en esta auditoría, sin excepciones). Se revisaron además los
-- dos helpers de solo lectura que NO son `security definer`
-- (fn_scope_ok y fn_valor_hora_vigente): fn_scope_ok no referencia ningún
-- objeto de schema (solo compara los parámetros recibidos), así que no
-- tiene superficie de ataque por search_path; fn_valor_hora_vigente sí
-- referencia la tabla `categorias` sin schema-qualificar, así que se le
-- agrega `set search_path = public` acá debajo como endurecimiento
-- preventivo (no depende de este GRANT/REVOKE, es manejo de search_path).
-- ============================================================================

alter function fn_valor_hora_vigente(uuid, date) set search_path = public;

-- V2.1: punto de partida determinista (igual criterio que PARTE 35 con las
-- tablas). En Supabase los privilegios por defecto del schema public otorgan
-- EXECUTE de toda función nueva directamente a anon, authenticated y
-- service_role (no solo a PUBLIC): revocar de PUBLIC no alcanza. Se parte de
-- cero y se otorga solo lo explícito de más abajo. service_role se conserva
-- (jobs/Edge Functions de confianza, p. ej. fn_resetear_ranking_si_corresponde).
revoke execute on all functions in schema public from public, anon, authenticated;

revoke execute on function fn_set_updated_at() from public;
revoke execute on function fn_proteger_usuario_desarrollador() from public;
revoke execute on function fn_proteger_rol_desarrollador() from public;
revoke execute on function fn_proteger_permisos_desarrollador() from public;
revoke execute on function fn_asignar_numero_solicitud() from public;
revoke execute on function fn_normalizar_asistencia() from public;
revoke execute on function fn_solicitud_empleados_before_insert() from public;
revoke execute on function fn_solicitud_empleados_after_insert() from public;
revoke execute on function fn_trigger_recalcular_situacion() from public;
revoke execute on function fn_trigger_validar_jerarquia() from public;
revoke execute on function fn_notificar_solicitud() from public;
revoke execute on function fn_registrar_auditoria() from public;
revoke execute on function fn_registrar_auditoria_singleton() from public;
revoke execute on function fn_registrar_auditoria_usuario_permisos() from public;
revoke execute on function fn_rangos_banda_horaria(time, time) from public;
revoke execute on function fn_validar_solapamiento_bandas_horarias() from public;
revoke execute on function fn_scope_ok(nivel_permiso, uuid, uuid, uuid, uuid, uuid, uuid) from public;
revoke execute on function fn_registrar_evento_negocio(text, text, uuid, text, nivel_auditoria_negocio, text, uuid, text, text, jsonb) from public;
revoke execute on function fn_valor_hora_vigente(uuid, date) from public;
revoke execute on function fn_calcular_detalle_solicitud_empleado(uuid) from public;
revoke execute on function fn_recalcular_situacion_solicitud(uuid) from public;
revoke execute on function fn_trigger_recalcular_situacion() from public;
revoke execute on function fn_aprobar_empleado_interno(uuid, uuid) from public;
revoke execute on function fn_rechazar_empleado_interno(uuid, uuid, text) from public;
revoke execute on function fn_revertir_ranking_si_aprobado(uuid) from public;
revoke execute on function fn_invalidar_aprobaciones_vigentes(uuid) from public;
revoke execute on function fn_resetear_ranking_si_corresponde() from public;

revoke execute on function fn_es_admin() from public;
revoke execute on function fn_es_desarrollador() from public;
revoke execute on function fn_puede_ver(uuid, uuid, uuid) from public;
revoke execute on function fn_puede_modificar(uuid, uuid, uuid) from public;
revoke execute on function fn_puede_aprobar(uuid, uuid, uuid) from public;
revoke execute on function fn_puede_reabrir(uuid, uuid, uuid) from public;
revoke execute on function fn_puede_control_ingreso() from public;
revoke execute on function fn_puede_eliminar_cancelar() from public;
revoke execute on function fn_puede_ver_importes() from public;
revoke execute on function fn_puede_importar() from public;
revoke execute on function fn_puede_exportar() from public;
revoke execute on function fn_permisos_para_scope(uuid, uuid, uuid) from public;
revoke execute on function fn_banda_ranking(numeric, text) from public;

revoke execute on function rpc_crear_solicitud(uuid, uuid, uuid, timestamptz, timestamptz, uuid, text) from public;
revoke execute on function rpc_enviar_a_aprobacion(uuid) from public;
revoke execute on function rpc_aprobar_empleado(uuid) from public;
revoke execute on function rpc_rechazar_empleado(uuid, text) from public;
revoke execute on function rpc_aprobar_masivo(uuid) from public;
revoke execute on function rpc_rechazar_masivo(uuid, text) from public;
revoke execute on function rpc_agregar_empleado(uuid, uuid) from public;
revoke execute on function rpc_quitar_empleado(uuid) from public;
revoke execute on function rpc_reemplazar_empleado(uuid, uuid) from public;
revoke execute on function rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz) from public;
revoke execute on function rpc_quitar_control_ingreso(uuid) from public;
revoke execute on function rpc_finalizar_solicitud(uuid) from public;
revoke execute on function rpc_cancelar_solicitud(uuid, text) from public;
revoke execute on function rpc_eliminar_borrador(uuid) from public;
revoke execute on function rpc_reabrir_solicitud(uuid, text) from public;
revoke execute on function rpc_modificar_scope(uuid, uuid, uuid, uuid) from public;
revoke execute on function rpc_modificar_fechas(uuid, timestamptz, timestamptz) from public;
revoke execute on function rpc_modificar_motivo(uuid, uuid) from public;
revoke execute on function rpc_modificar_observacion(uuid, text) from public;
revoke execute on function rpc_upsert_empleado(text, text, text, uuid, uuid, uuid, estado_empleado, uuid, numeric, boolean, boolean) from public;
revoke execute on function rpc_importar_empleado_excel(text, text, text, text, text, text, text, text, text) from public;
revoke execute on function fn_usuario_activo() from public;
revoke execute on function fn_exigir_usuario_activo() from public;
revoke execute on function fn_puede_control_ingreso_sobre(uuid, uuid, uuid) from public;
revoke execute on function rpc_rectificar_horas_ranking(uuid, numeric, text) from public;

-- Otorgado explícitamente a `authenticated` — helpers de solo lectura
-- (sin efectos secundarios, ya son la fuente única de verdad de RLS/RPC):
grant execute on function fn_es_admin() to authenticated;
grant execute on function fn_es_desarrollador() to authenticated;
grant execute on function fn_puede_ver(uuid, uuid, uuid) to authenticated;
grant execute on function fn_puede_modificar(uuid, uuid, uuid) to authenticated;
grant execute on function fn_puede_aprobar(uuid, uuid, uuid) to authenticated;
grant execute on function fn_puede_reabrir(uuid, uuid, uuid) to authenticated;
grant execute on function fn_puede_control_ingreso() to authenticated;
grant execute on function fn_puede_control_ingreso_sobre(uuid, uuid, uuid) to authenticated;
grant execute on function fn_usuario_activo() to authenticated;
grant execute on function fn_puede_eliminar_cancelar() to authenticated;
grant execute on function fn_puede_ver_importes() to authenticated;
grant execute on function fn_puede_importar() to authenticated;
grant execute on function fn_puede_exportar() to authenticated;
grant execute on function fn_permisos_para_scope(uuid, uuid, uuid) to authenticated;
grant execute on function fn_banda_ranking(numeric, text) to authenticated;

-- Otorgado explícitamente a `authenticated` — RPC de negocio reales (cada
-- una valida permiso/scope/estado por su cuenta antes de mutar nada):
grant execute on function rpc_crear_solicitud(uuid, uuid, uuid, timestamptz, timestamptz, uuid, text) to authenticated;
grant execute on function rpc_enviar_a_aprobacion(uuid) to authenticated;
grant execute on function rpc_aprobar_empleado(uuid) to authenticated;
grant execute on function rpc_rechazar_empleado(uuid, text) to authenticated;
grant execute on function rpc_aprobar_masivo(uuid) to authenticated;
grant execute on function rpc_rechazar_masivo(uuid, text) to authenticated;
grant execute on function rpc_agregar_empleado(uuid, uuid) to authenticated;
grant execute on function rpc_quitar_empleado(uuid) to authenticated;
grant execute on function rpc_reemplazar_empleado(uuid, uuid) to authenticated;
grant execute on function rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz) to authenticated;
grant execute on function rpc_quitar_control_ingreso(uuid) to authenticated;
grant execute on function rpc_finalizar_solicitud(uuid) to authenticated;
grant execute on function rpc_cancelar_solicitud(uuid, text) to authenticated;
grant execute on function rpc_eliminar_borrador(uuid) to authenticated;
grant execute on function rpc_reabrir_solicitud(uuid, text) to authenticated;
grant execute on function rpc_modificar_scope(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function rpc_modificar_fechas(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function rpc_modificar_motivo(uuid, uuid) to authenticated;
grant execute on function rpc_modificar_observacion(uuid, text) to authenticated;
grant execute on function rpc_upsert_empleado(text, text, text, uuid, uuid, uuid, estado_empleado, uuid, numeric, boolean, boolean) to authenticated;
grant execute on function rpc_importar_empleado_excel(text, text, text, text, text, text, text, text, text) to authenticated;
grant execute on function rpc_rectificar_horas_ranking(uuid, numeric, text) to authenticated;


-- ============================================================================
-- PARTE 35 · Privilegios de tabla para RLS (hallazgo real, ejecución)
-- ----------------------------------------------------------------------------
-- Hallazgo real (detectado recién al EJECUTAR la migración completa en un
-- Postgres 16 limpio contra los roles `anon`/`authenticated`, no por
-- lectura ni por el parser sintáctico — ver Entregable 2): activar RLS y
-- crear políticas en las PARTEs 28-33 NUNCA otorga por sí solo ningún
-- privilegio de base sobre la tabla (SELECT/INSERT/UPDATE/DELETE). RLS
-- solo FILTRA FILAS dentro de los comandos que el rol ya tiene permitido
-- ejecutar a nivel de tabla — sin el GRANT de base, Postgres rechaza la
-- operación con "permission denied for table ..." antes de siquiera
-- evaluar ninguna política, y todas las políticas SELECT ya creadas (que
-- sí fueron diseñadas para que el frontend lea directo de las tablas, no
-- solo a través de RPC) quedaban inalcanzables para `anon`/`authenticated`.
-- Esta corrección no formaba parte de los 5 puntos pedidos: se encontró y
-- se corrige acá por la validación de ejecución real de esta auditoría.
--
-- No se trata de una corrección de negocio ni cambia ninguna política ya
-- aprobada: los GRANT de acá reproducen exactamente, tabla por tabla, lo
-- que su propia política RLS ya expresa — nunca más que eso:
--   - Tablas con política `..._select` (abierta o acotada) MÁS política
--     `..._write for all using (fn_es_admin())`: se otorgan SELECT,
--     INSERT, UPDATE, DELETE a `authenticated` — el GRANT solo habilita
--     el camino, RLS sigue siendo quien decide fila por fila (y en el
--     caso de `_write`, solo admin/desarrollador pasa esa política,
--     sin importar que el GRANT exista).
--   - Tablas con política de solo lectura (`solicitudes`,
--     `solicitud_empleados`, `solicitud_empleado_detalle`,
--     `solicitud_aprobaciones`, `roles`, `ranking_horas_historico`,
--     `auditoria`, `auditoria_negocio`, `notificaciones_log`): se otorga
--     únicamente SELECT — nunca INSERT/UPDATE/DELETE, igual que ya
--     documentaba el comentario de la PARTE 32 ("sin escritura directa,
--     todo por RPC"). Esto es defensa en profundidad explícita a nivel
--     de GRANT, no solo de política: aunque alguien agregara por error
--     una política de escritura más adelante, sin el GRANT de base
--     seguiría sin poder escribirse directo a estas tablas desde
--     `anon`/`authenticated`.
--   - `configuracion_apariencia`: SELECT también a `anon`, igual que su
--     política (necesaria para pintar nombre/logo/colores antes del
--     login).
--   - Ninguna tabla recibe ningún privilegio para `anon` fuera de ese
--     caso puntual — toda la aplicación requiere sesión, igual que ya
--     establece la PARTE 34 para las funciones.
-- ============================================================================

-- Revisión final: punto de partida determinista. En Supabase, los privilegios
-- por defecto pueden entregar ALL sobre toda tabla nueva de `public` a
-- anon/authenticated; se parte de cero y se otorga solo lo de abajo.
revoke all on all tables in schema public from anon, authenticated;

-- Catálogos/maestras: select abierto + write admin-gated (RLS ya lo filtra).
grant select, insert, update, delete on
  areas, sectores, procesos, categoria_tipos, categorias, bandas_horarias,
  feriados, motivos, ib_configuracion, bandas_ranking, niveles_aprobacion_config
  to authenticated;

-- Configuración.
grant select, insert, update, delete on configuracion_general to authenticated;
grant select, insert, update, delete on configuracion_apariencia to authenticated;
grant select on configuracion_apariencia to anon;

-- Usuarios, roles, permisos y scopes.
grant select, insert, update, delete on usuarios to authenticated;
grant select on roles to authenticated;  -- sin política de escritura: catálogo fijo, no editable vía RLS.
grant select, insert, update, delete on usuario_roles to authenticated;
grant select, insert, update, delete on usuario_permisos to authenticated;
grant select, insert, update, delete on usuario_permiso_scopes to authenticated;

-- Empleados y ranking histórico.
grant select, insert, update, delete on empleados to authenticated;
grant select on ranking_horas_historico to authenticated;
grant select on ranking_rectificaciones to authenticated;  -- solo lectura (RLS: admin); se escribe únicamente vía rpc_rectificar_horas_ranking.

-- Solicitudes y equipo — solo lectura directa; toda escritura pasa por RPC
-- (`security definer`, que no depende de estos GRANT para escribir, ya
-- que corre con los privilegios del dueño de la función).
grant select on solicitudes to authenticated;
grant select on solicitud_empleados to authenticated;
grant select on solicitud_empleado_detalle to authenticated;
grant select on solicitud_aprobaciones to authenticated;

-- Auditoría (técnica y de negocio) y notificaciones — solo lectura, y solo
-- llega a ver algo quien pase fn_es_admin() dentro de la política.
grant select on auditoria to authenticated;
grant select on auditoria_negocio to authenticated;
grant select on notificaciones_log to authenticated;

-- Vistas (security_invoker = true): el invocador necesita SELECT sobre la
-- vista Y sobre las tablas base; las filas las sigue filtrando la RLS de
-- las tablas base. Sin este GRANT la vista daba "permission denied" (hallazgo
-- real de la revisión final, por ejecución).
grant select on vista_solicitudes_resumen to authenticated;
grant select on vista_solicitud_empleados_detalle to authenticated;
grant select on vista_empleados_resumen to authenticated;


-- ============================================================================
-- NOTA DE DISEÑO — futuro módulo de conciliación de horas reales
-- ----------------------------------------------------------------------------
-- NO IMPLEMENTADO EN ESTA MIGRACIÓN. Documentado acá para dejar registrado
-- que el schema actual no lo bloquea, y cómo se conectaría cuando se
-- diseñe en detalle (igual criterio que ya se usó con horas_reales en la
-- Etapa 4: no se construye especulativamente, solo se verifica que no
-- haga falta rediseñar nada de lo ya cerrado).
--
-- Concepto (según lo descrito por el usuario): importar el fichaje real
-- de cada empleado (Excel, desde otro sistema) y conciliarlo contra las
-- horas aprobadas + el control de ingreso de este sistema — asistido,
-- con confirmación manual, permitiendo conciliaciones manuales, con un
-- estado "pagado" que vuelve el registro inmutable salvo reversión
-- explícita del pago.
--
-- Cómo se conectaría, sin tocar nada de lo ya diseñado:
--   - Tabla nueva (ej. `conciliaciones_horas`), con FK a
--     `solicitud_empleados` (de donde sale `total_horas` aprobadas ya
--     calculado) + los datos del fichaje real importado (horas reales,
--     fecha). `solicitud_empleados` ya expone exactamente el dato que
--     esta tabla futura necesitaría referenciar — no hace falta agregarle
--     nada ahora.
--   - Estado de conciliación (ej. `PENDIENTE`/`CONCILIADA`/`AJUSTE_MANUAL`)
--     + `pagado boolean default false` + `fecha_pago`/`usuario_pago_id`.
--     Inmutabilidad una vez pagado: un trigger `BEFORE UPDATE/DELETE` que
--     bloquee cualquier cambio mientras `pagado = true`, salvo a través de
--     una RPC dedicada `rpc_revertir_pago_conciliacion` que primero
--     ponga `pagado = false` explícitamente — mismo patrón ya usado acá
--     para proteger al rol DESARROLLADOR (trigger de protección, no solo
--     RLS).
--   - Import: mismo patrón que `rpc_importar_empleado_excel` — una
--     capacidad (`fn_puede_importar()` ya existe y ya se podría reusar,
--     o un booleano nuevo específico si se quiere separar el permiso) +
--     scope real (`fn_puede_modificar` sobre la unidad organizativa del
--     empleado, mismo criterio ya establecido — nunca derivado del
--     registro importado).
--   - Auditoría: `fn_registrar_evento_negocio()` ya acepta cualquier
--     `modulo`/`evento` como texto libre — `modulo := 'CONCILIACION'` 
--     funcionaría sin ningún cambio de schema.
--
-- Nada de lo anterior requiere crear la tabla ahora — se deja señalado
-- para cuando se diseñe en detalle, en una etapa separada.
-- ============================================================================
