-- ============================================================================
-- Horas Extras — MIGRACIÓN 0002 (sobre V2.1 ya instalada)
--   1) Bandas horarias por día de la semana (dia_desde / dia_hasta, 1=lunes … 7=domingo).
--   2) Observación en el control de ingreso (columna + parámetro de la RPC).
--   3) Vistas: desglose de empleados/horas aprobados, rechazados y pendientes por solicitud.
--
-- Se ejecuta UNA vez, en el SQL Editor, sobre el proyecto que ya tiene instalado
-- 0001_schema_inicial_consolidado_v2_1_SUPABASE.sql. Es idempotente en lo que agrega
-- (add column if not exists) y no toca datos existentes: las bandas actuales quedan
-- con dia_desde=1 y dia_hasta=7, o sea, aplican todos los días como hasta ahora.
-- Única sentencia destructiva: reemplaza la firma anterior de rpc_registrar_control_ingreso
-- (3 parámetros) por la nueva (4 parámetros, el último opcional).
--
-- REGLA DE DÍAS: dia_desde..dia_hasta (inclusive). Si dia_desde > dia_hasta el rango pasa
-- por el domingo (ej. 6 a 2 = sábado, domingo, lunes, martes). Una banda que cruza
-- medianoche (22:00-06:00) pertenece al día en que EMPIEZA: la de "lunes a viernes"
-- cubre desde el lunes 22:00 hasta el sábado 06:00.
-- Los horarios sin banda para su día/hora siguen rechazándose al calcular (error explícito).
-- ============================================================================
begin;

do $chk$
begin
  if to_regprocedure('fn_usuario_activo()') is null or to_regclass('public.ranking_rectificaciones') is null then
    raise exception 'Esta migración requiere la V2.1 instalada (0001_schema_inicial_consolidado_v2_1_SUPABASE.sql)';
  end if;
end
$chk$;

-- 1) Columnas de días
alter table bandas_horarias add column if not exists dia_desde smallint not null default 1;
alter table bandas_horarias add column if not exists dia_hasta smallint not null default 7;
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'ck_bandas_dias' and conrelid = 'public.bandas_horarias'::regclass) then
    alter table bandas_horarias add constraint ck_bandas_dias check (dia_desde between 1 and 7 and dia_hasta between 1 and 7);
  end if;
end
$c$;

-- Rangos de la banda sobre la semana, en segundos desde el lunes 00:00 (0..604800).
create or replace function fn_rangos_semanales_banda(p_hora_desde time, p_hora_hasta time, p_dia_desde integer, p_dia_hasta integer)
returns int4range[]
language plpgsql
immutable
set search_path = public
as $$
declare
  v_res int4range[] := '{}';
  v_d integer := floor(extract(epoch from p_hora_desde))::int;
  v_h integer := floor(extract(epoch from p_hora_hasta))::int;
  v_dur integer;
  v_n integer;
  v_ini integer;
  v_fin integer;
  k integer;
begin
  v_dur := case when v_d < v_h then v_h - v_d else 86400 - v_d + v_h end;
  v_n := ((p_dia_hasta - p_dia_desde + 7) % 7) + 1;
  for k in 0 .. v_n - 1 loop
    v_ini := ((p_dia_desde - 1 + k) % 7) * 86400 + v_d;
    v_fin := v_ini + v_dur;
    if v_fin <= 604800 then
      v_res := v_res || int4range(v_ini, v_fin, '[)');
    else
      v_res := v_res || int4range(v_ini, 604800, '[)') || int4range(0, v_fin - 604800, '[)');
    end if;
  end loop;
  return v_res;
end;
$$;

create or replace function fn_banda_horaria_aplica(p_hora_desde time, p_hora_hasta time, p_dia_desde integer, p_dia_hasta integer, p_seg_semana integer)
returns boolean
language sql
immutable
set search_path = public
as $$
  select exists (
    select 1 from unnest(fn_rangos_semanales_banda(p_hora_desde, p_hora_hasta, p_dia_desde, p_dia_hasta)) r
    where r @> p_seg_semana
  );
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

  v_rangos_nuevo := fn_rangos_semanales_banda(new.hora_desde, new.hora_hasta, new.dia_desde, new.dia_hasta);

  for v_rec in
    select id, descripcion, hora_desde, hora_hasta, dia_desde, dia_hasta
    from bandas_horarias
    where activo and id <> new.id
  loop
    v_rangos_otro := fn_rangos_semanales_banda(v_rec.hora_desde, v_rec.hora_hasta, v_rec.dia_desde, v_rec.dia_hasta);
    foreach v_r1 in array v_rangos_nuevo loop
      foreach v_r2 in array v_rangos_otro loop
        if v_r1 && v_r2 then
          raise exception 'La banda horaria "%" (días %-% de % a %) se superpone con la banda activa existente "%" (días %-% de % a %) — las bandas horarias activas no pueden solaparse (1=lunes … 7=domingo; una banda que cruza medianoche pertenece al día en que empieza)',
            new.descripcion, new.dia_desde, new.dia_hasta, new.hora_desde, new.hora_hasta, v_rec.descripcion, v_rec.dia_desde, v_rec.dia_hasta, v_rec.hora_desde, v_rec.hora_hasta;
        end if;
      end loop;
    end loop;
  end loop;

  return new;
end;
$$;

create or replace trigger trg_validar_solapamiento_bandas_horarias
  before insert or update of hora_desde, hora_hasta, dia_desde, dia_hasta, activo on bandas_horarias
  for each row execute function fn_validar_solapamiento_bandas_horarias();

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
  v_seg_semana integer;
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
    -- V2.2: instante dentro de la semana (segundos desde el lunes 00:00, hora local).
    v_seg_semana := (extract(isodow from v_fecha)::int - 1) * 86400 + floor(extract(epoch from v_hora_local))::int;

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
        and fn_banda_horaria_aplica(hora_desde, hora_hasta, dia_desde, dia_hasta, v_seg_semana);

    if v_bandas_encontradas = 0 then
      raise exception 'No hay ninguna banda horaria activa configurada para el horario % del % (día de la semana %, 1=lunes … 7=domingo) — no se puede calcular este tramo', v_hora_local, v_fecha, extract(isodow from v_fecha)::int;
    elsif v_bandas_encontradas > 1 then
      raise exception 'Hay % bandas horarias activas que se superponen para el horario % del % (día de la semana %) — corregí la configuración de bandas horarias antes de calcular', v_bandas_encontradas, v_hora_local, v_fecha, extract(isodow from v_fecha)::int;
    end if;

    select * into v_banda from bandas_horarias
      where activo
        and fn_banda_horaria_aplica(hora_desde, hora_hasta, dia_desde, dia_hasta, v_seg_semana);

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

-- 2) Observación del control de ingreso
alter table solicitud_empleados add column if not exists observacion_control_ingreso text;

drop function if exists rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz);

create or replace function rpc_registrar_control_ingreso(
  p_solicitud_empleado_id uuid,
  p_resultado estado_asistencia_empleado,
  p_fecha_hora timestamptz default now(),
  p_observacion text default null
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_se solicitud_empleados;
  v_solicitud solicitudes;
  v_obs text := nullif(btrim(coalesce(p_observacion, '')), '');
begin
  perform fn_exigir_usuario_activo();
  if v_obs is not null and char_length(v_obs) > 1000 then
    raise exception 'La observación del control de ingreso no puede superar los 1000 caracteres';
  end if;
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
        fecha_hora_ingreso = case when p_resultado = 'INGRESO_REGISTRADO' then coalesce(p_fecha_hora, now()) else null end,
        observacion_control_ingreso = v_obs
    where id = p_solicitud_empleado_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'CONTROL_INGRESO_REGISTRADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id,
    p_estado_nuevo := p_resultado::text,
    p_datos := case when v_obs is null then null else jsonb_build_object('observacion', v_obs) end);
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
    set estado_asistencia = 'PENDIENTE_INGRESO', usuario_control_ingreso_id = null, fecha_hora_ingreso = null, observacion_control_ingreso = null
    where id = p_solicitud_empleado_id;

  perform fn_registrar_evento_negocio('HORAS_EXTRA', 'SOLICITUD_EMPLEADO', p_solicitud_empleado_id, 'CONTROL_INGRESO_ELIMINADO', 'BASICA',
    p_entidad_relacionada_tipo := 'SOLICITUD', p_entidad_relacionada_id := v_se.solicitud_id);
end;
$$;

-- 3) Vistas (solo se agregan columnas al final)
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
  case when fn_puede_ver_importes() then coalesce(sum(se.total_importe) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'PENDIENTE_APROBACION'), 0) else null end as importe_pendiente,
  -- V2.2: desglose por estado de aprobación (los totales de arriba no cambian: incluyen a los rechazados).
  count(se.id) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'APROBADO') as empleados_aprobados,
  count(se.id) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'RECHAZADO') as empleados_rechazados,
  count(se.id) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'PENDIENTE_APROBACION') as empleados_pendientes,
  coalesce(sum(se.total_horas) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'APROBADO'), 0) as horas_aprobadas,
  coalesce(sum(se.total_horas) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'RECHAZADO'), 0) as horas_rechazadas,
  coalesce(sum(se.total_horas) filter (where se.estado_registro = 'ACTIVO' and se.estado_aprobacion = 'PENDIENTE_APROBACION'), 0) as horas_pendientes
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
  eo.nombre_completo as reemplaza_a_nombre,
  se.observacion_control_ingreso
from solicitud_empleados se
join empleados e on e.id = se.empleado_id
left join ib_configuracion ib on ib.id = se.ib_al_momento
left join solicitud_empleados sea on sea.id = se.reemplaza_a
left join empleados eo on eo.id = sea.empleado_id;


-- Privilegios: las funciones nuevas son internas (no se exponen a anon ni authenticated).
revoke execute on function fn_rangos_semanales_banda(time, time, integer, integer) from public, anon, authenticated;
revoke execute on function fn_banda_horaria_aplica(time, time, integer, integer, integer) from public, anon, authenticated;
revoke execute on function fn_validar_solapamiento_bandas_horarias() from public, anon, authenticated;
revoke execute on function fn_calcular_detalle_solicitud_empleado(uuid) from public, anon, authenticated;
revoke execute on function rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz, text) from public, anon, authenticated;
revoke execute on function rpc_quitar_control_ingreso(uuid) from public, anon;
grant execute on function rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz, text) to authenticated;
grant execute on function rpc_quitar_control_ingreso(uuid) to authenticated;

commit;
