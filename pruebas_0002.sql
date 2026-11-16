\set ON_ERROR_STOP on
\pset pager off
\pset tuples_only on

create schema t;
create table t.res(n serial, label text, ok boolean, detail text);
create function t.ok(p_label text, p_cond boolean, p_detail text default null) returns void language plpgsql security definer set search_path=public,t as $f$
begin insert into t.res(label,ok,detail) values (p_label, coalesce(p_cond,false), p_detail);
 raise notice '% : %', case when coalesce(p_cond,false) then 'PASS' else 'FAIL' end, p_label; end $f$;
create function t.q(p_sql text) returns text language plpgsql security definer set search_path=public,t as $f$
declare r text; begin execute p_sql into r; return r; end $f$;
create function t.qi(p_sql text) returns text language plpgsql as $f$
declare r text; begin execute p_sql into r; return r; end $f$;
create function t.fails(p_label text, p_stmt text, p_pat text) returns void language plpgsql as $f$
begin
  begin execute p_stmt;
  exception when others then
    perform t.ok(p_label, sqlerrm ilike '%'||p_pat||'%', 'error recibido: '||sqlerrm); return;
  end;
  perform t.ok(p_label, false, 'no hubo error');
end $f$;
create function t.passes(p_label text, p_stmt text) returns void language plpgsql as $f$
begin
  begin execute p_stmt;
  exception when others then perform t.ok(p_label,false,'error: '||sqlerrm); return; end;
  perform t.ok(p_label,true);
end $f$;
create function t.require(p_cond boolean, p_msg text) returns void language plpgsql as $f$
begin if p_cond is not true then raise exception 'PRECONDICION FALLIDA (la preparacion fallo, la prueba no es valida): %', p_msg; end if; end $f$;
create function t.sesion(p_uid text, p_rol text) returns void language plpgsql as $f$
begin
  if current_user <> coalesce(p_rol, session_user) then raise exception 'SESION INCORRECTA: current_user=% esperado=%', current_user, coalesce(p_rol, session_user); end if;
  if coalesce(auth.uid()::text,'') <> p_uid then raise exception 'SESION INCORRECTA: auth.uid()=% esperado=%', auth.uid(), p_uid; end if;
end $f$;
create function t.probe_fails(p_stmt text, p_pat text) returns text language plpgsql as $f$
begin
  begin execute p_stmt; exception when others then
    if sqlerrm ilike '%'||p_pat||'%' then return 'ok'; end if; return 'error distinto: '||sqlerrm; end;
  return 'no hubo error';
end $f$;
create function t.resumen(p_esperado int) returns void language plpgsql security definer set search_path=public,t as $f$
declare v_t int; v_p int; v_f int;
begin
  select count(*), count(*) filter (where ok), count(*) filter (where not ok) into v_t, v_p, v_f from t.res;
  raise notice 'RESUMEN total=% pass=% fail=% esperado=%', v_t, v_p, v_f, p_esperado;
  if v_t <> p_esperado then raise exception 'CANTIDAD DE PRUEBAS INESPERADA: % ejecutadas, % esperadas', v_t, p_esperado; end if;
end $f$;
grant usage on schema t to authenticated, anon;
grant execute on all functions in schema t to authenticated, anon;

insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000001','u1@test.com'),('00000000-0000-0000-0000-000000000002','u2@test.com'),('00000000-0000-0000-0000-000000000003','u3@test.com'),('00000000-0000-0000-0000-000000000004','u4@test.com'),('00000000-0000-0000-0000-000000000005','u5@test.com'),('00000000-0000-0000-0000-000000000006','u6@test.com'),('00000000-0000-0000-0000-000000000007','u7@test.com');
insert into usuarios(id,nombre_completo) values ('00000000-0000-0000-0000-000000000001','Admin'),('00000000-0000-0000-0000-000000000002','Responsable Area1'),('00000000-0000-0000-0000-000000000003','Aprobador Area1'),('00000000-0000-0000-0000-000000000004','RRHH'),('00000000-0000-0000-0000-000000000005','Consulta sin permisos'),('00000000-0000-0000-0000-000000000006','Responsable Area2'),('00000000-0000-0000-0000-000000000007','Control Ingreso fuera de area');
insert into usuario_roles select '00000000-0000-0000-0000-000000000001', id from roles where nombre='ADMIN';
insert into usuario_roles select '00000000-0000-0000-0000-000000000002', id from roles where nombre='RESPONSABLE';
insert into usuario_roles select '00000000-0000-0000-0000-000000000003', id from roles where nombre='APROBADOR';
insert into usuario_roles select '00000000-0000-0000-0000-000000000004', id from roles where nombre='RRHH';
insert into usuario_roles select '00000000-0000-0000-0000-000000000005', id from roles where nombre='CONSULTA';
insert into usuario_roles select '00000000-0000-0000-0000-000000000006', id from roles where nombre='RESPONSABLE';
insert into usuario_roles select '00000000-0000-0000-0000-000000000007', id from roles where nombre='CONTROL_INGRESO';
insert into areas(id,nombre) values ('10000000-0000-0000-0000-000000000001','Area1'),('10000000-0000-0000-0000-000000000002','Area2');
insert into sectores(id,nombre,area_id) values ('20000000-0000-0000-0000-000000000001','Sector1','10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002','Sector2','10000000-0000-0000-0000-000000000002');
insert into procesos(id,nombre,sector_id) values ('30000000-0000-0000-0000-000000000001','Proceso1','20000000-0000-0000-0000-000000000001'),('30000000-0000-0000-0000-000000000002','Proceso2','20000000-0000-0000-0000-000000000002');
insert into usuario_permisos(usuario_id,visibilidad_nivel,modificacion_nivel,aprobacion_nivel,reapertura_nivel,control_ingreso,puede_importar,puede_quitar_control_ingreso) values
('00000000-0000-0000-0000-000000000002','AREA','AREA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000003','AREA','NADA','AREA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000004','TODO','TODO','NADA','NADA',false,true,false),
('00000000-0000-0000-0000-000000000005','NADA','NADA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000006','AREA','AREA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000007','AREA','NADA','NADA','NADA',true,false,false);
insert into usuario_permiso_scopes(usuario_id,tipo_permiso,area_id) values
('00000000-0000-0000-0000-000000000002','MODIFICACION','10000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002','VISIBILIDAD','10000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000003','APROBACION','10000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000003','VISIBILIDAD','10000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000006','MODIFICACION','10000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000006','VISIBILIDAD','10000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000007','VISIBILIDAD','10000000-0000-0000-0000-000000000002');
insert into categoria_tipos(id,codigo) values ('40000000-0000-0000-0000-000000000001','CAT1'),('40000000-0000-0000-0000-000000000002','CAT2'),('40000000-0000-0000-0000-000000000003','CAT3');
insert into categorias(categoria_tipo_id,valor_hora,moneda,vigente_desde,vigente_hasta) values
('40000000-0000-0000-0000-000000000001',1000,'ARS','2020-01-01',null),
('40000000-0000-0000-0000-000000000002',10,'USD','2020-01-01',null),
('40000000-0000-0000-0000-000000000003',900,'ARS','2020-01-01','2026-09-30'),
('40000000-0000-0000-0000-000000000003',8,'USD','2026-10-01',null);
insert into motivos(id,motivo,requiere_aprobacion) values ('50000000-0000-0000-0000-000000000001','Con aprobacion',true),('50000000-0000-0000-0000-000000000002','Sin aprobacion',false),('50000000-0000-0000-0000-000000000003','Con aprobacion 2',true);
insert into empleados(id,legajo,nombre_completo,categoria_id,area_id,sector_id,proceso_id) values ('60000000-0000-0000-0000-000000000001','LEG001','Empleado 1','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000002','LEG002','Empleado 2','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000003','LEG003','Empleado 3','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000004','LEG004','Empleado 4','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000005','LEG005','Empleado 5','40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000006','LEG006','Empleado 6','40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000007','LEG007','Empleado 7','40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');

-- Bandas de la prueba (reemplazan a las de la suite anterior): semana laboral con tres bandas.
insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador,multiplicador_feriado) values
 ('Jornada','06:00','18:00',1,5,1.0,null),
 ('Extras','18:00','22:00',1,5,1.5,2.0),
 ('Extras nocturnas','22:00','06:00',1,5,1.8,null);
\echo '=== MIGRACION 0002: PREPARACION ==='
\echo '=== FIXTURE CONTROLADO ==='
update configuracion_general set dias_maximos_antiguedad = 36500 where id = 1;
select t.require((select dias_maximos_antiguedad from configuracion_general where id=1) = 36500, 'fixture dias_maximos_antiguedad');
select t.require((select count(*) from roles) = 7, 'catalogo de 7 roles presente');
insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000008','u8@t'),('00000000-0000-0000-0000-000000000009','u9@t');
insert into usuarios(id,nombre_completo) values ('00000000-0000-0000-0000-000000000008','CI visib TODO'),('00000000-0000-0000-0000-000000000009','Puede quitar sin CI');
insert into usuario_roles select '00000000-0000-0000-0000-000000000008', id from roles where nombre='CONTROL_INGRESO';
insert into usuario_roles select '00000000-0000-0000-0000-000000000009', id from roles where nombre='CONSULTA';
insert into usuario_permisos(usuario_id,visibilidad_nivel,modificacion_nivel,aprobacion_nivel,reapertura_nivel,control_ingreso,puede_quitar_control_ingreso) values ('00000000-0000-0000-0000-000000000008','TODO','NADA','NADA','NADA',true,false),('00000000-0000-0000-0000-000000000009','AREA','NADA','NADA','NADA',false,true);
insert into usuario_permiso_scopes(usuario_id,tipo_permiso,area_id) values ('00000000-0000-0000-0000-000000000009','VISIBILIDAD','10000000-0000-0000-0000-000000000001');
insert into empleados(id,legajo,nombre_completo,categoria_id,area_id,sector_id,proceso_id) values ('60000000-0000-0000-0000-000000000010','LEG010','Emp Area2','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002');
select t.require(extract(isodow from date '2026-10-12') = 1, 'el 2026-10-12 debe ser lunes');
select t.require((select count(*) from bandas_horarias) = 3, 'fixture de 3 bandas');

\echo '=== BD: BANDAS POR DIA ==='
select t.ok('BD-1 las columnas dia_desde/dia_hasta existen; una banda sin dias queda 1..7 (compatibilidad)', t.q('with x as (insert into bandas_horarias(descripcion,hora_desde,hora_hasta,activo) values (''Todos los dias'',''01:00'',''02:00'',false) returning dia_desde, dia_hasta) select dia_desde||''-''||dia_hasta from x') = '1-7');
select t.fails('BD-2a dia_desde fuera de 1..7 rechazado', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,activo) values (''X'',''01:00'',''02:00'',0,5,false)', 'check');
select t.fails('BD-2b dia_hasta fuera de 1..7 rechazado', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,activo) values (''X'',''01:00'',''02:00'',1,8,false)', 'check');
select t.ok('BD-3 22:00-06:00 de lunes a viernes: 5 rangos, el ultimo termina el sabado 06:00 (453600 s)', t.q('select array_length(r,1)||''|''||upper(r[5])||''|''||lower(r[1]) from (select fn_rangos_semanales_banda(''22:00'',''06:00'',1,5) r) z') = '5|453600|79200');
select t.ok('BD-4 22:00-06:00 solo domingo: dos rangos (domingo noche y lunes madrugada)', t.q('select array_length(r,1)||''|''||lower(r[1])||''|''||upper(r[1])||''|''||lower(r[2])||''|''||upper(r[2]) from (select fn_rangos_semanales_banda(''22:00'',''06:00'',7,7) r) z') = '2|597600|604800|0|21600');
select t.ok('BD-5a viernes 23:00 pertenece a la banda lunes-viernes 22-06', fn_banda_horaria_aplica('22:00','06:00',1,5, 4*86400+23*3600));
select t.ok('BD-5b sabado 03:00 (cola de la banda del viernes) tambien', fn_banda_horaria_aplica('22:00','06:00',1,5, 5*86400+3*3600));
select t.ok('BD-5c sabado 07:00 ya no', not fn_banda_horaria_aplica('22:00','06:00',1,5, 5*86400+7*3600));
select t.ok('BD-5d lunes 03:00 NO (esa madrugada es cola del domingo, no de la banda lunes-viernes)', not fn_banda_horaria_aplica('22:00','06:00',1,5, 3*3600));
select t.ok('BD-5e rango que pasa por el domingo (6 a 2): domingo si, miercoles no', fn_banda_horaria_aplica('08:00','10:00',6,2, 6*86400+9*3600) and not fn_banda_horaria_aplica('08:00','10:00',6,2, 2*86400+9*3600));
select t.fails('BD-6 banda lunes-viernes 20:00-23:00 se superpone con Extras (rechazada)', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador) values (''Pisa'',''20:00'',''23:00'',1,5,1)', 'superpone');
select t.passes('BD-7 mismas horas en otros dias (sabado-domingo 18:00-22:00) se permite', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador) values (''Fin de semana'',''18:00'',''22:00'',6,7,2.0)');
select t.passes('BD-8 domingo 22:00-06:00 no se superpone con lunes-viernes 22:00-06:00', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador) values (''Dom noche'',''22:00'',''06:00'',7,7,2.2)');
select t.fails('BD-9 viernes-sabado 22:00-06:00 se superpone con la cola del viernes (rechazada)', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador) values (''Pisa2'',''22:00'',''06:00'',5,6,1)', 'superpone');
select t.passes('BD-10 sabado 22:00-06:00 se permite (cola el domingo hasta 06:00, la de domingo empieza 22:00)', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,multiplicador) values (''Sab noche'',''22:00'',''06:00'',6,6,2.0)');
select t.fails('BD-11 cambiar los dias de una banda existente hacia un solapamiento tambien se rechaza', 'update bandas_horarias set dia_desde=5 where descripcion=''Fin de semana''', 'superpone');
select t.passes('BD-12 una banda INACTIVA puede solaparse (no cuenta)', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,dia_desde,dia_hasta,activo) values (''Inactiva'',''18:00'',''22:00'',1,5,false)');

\echo '=== BC: CALCULO POR DIA ==='
insert into feriados(fecha,descripcion) values ('2026-10-14','Feriado de prueba');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-12 18:00-03'::timestamptz,'2026-10-12 23:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','lunes')).id as s_lun \gset
select rpc_agregar_empleado(:'s_lun','60000000-0000-0000-0000-000000000001');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-16 20:00-03'::timestamptz,'2026-10-17 02:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','viernes a sabado')).id as s_vie \gset
select rpc_agregar_empleado(:'s_vie','60000000-0000-0000-0000-000000000002');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-12 00:00-03'::timestamptz,'2026-10-12 02:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','madrugada de lunes')).id as s_mad \gset
select rpc_agregar_empleado(:'s_mad','60000000-0000-0000-0000-000000000003');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-17 10:00-03'::timestamptz,'2026-10-17 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','sabado sin banda')).id as s_sab \gset
select t.fails('BC-4 sabado 10:00-12:00 no tiene banda (Jornada es de lunes a viernes): error explicito con el dia', format('select rpc_agregar_empleado(%L,%L)', :'s_sab','60000000-0000-0000-0000-000000000004'), 'No hay ninguna banda horaria');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-14 18:00-03'::timestamptz,'2026-10-14 20:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','feriado miercoles')).id as s_fer \gset
select rpc_agregar_empleado(:'s_fer','60000000-0000-0000-0000-000000000004');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('BC-1 lunes 18-23: 4 h Extras x1,5 + 1 h nocturnas x1,8 = 5 h / 7800', t.q(format('select total_horas||''|''||total_importe from solicitud_empleados where solicitud_id=%L', :'s_lun')) = '5.00|7800.00');
select t.ok('BC-2 viernes 20:00 a sabado 02:00: 2 h Extras + 4 h nocturnas (la madrugada del sabado es del viernes) = 6 h / 10200', t.q(format('select total_horas||''|''||total_importe from solicitud_empleados where solicitud_id=%L', :'s_vie')) = '6.00|10200.00');
select t.ok('BC-2b la madrugada del sabado usa la banda "Extras nocturnas"', t.q(format('select string_agg(distinct b.descripcion, '','') from solicitud_empleado_detalle d join bandas_horarias b on b.id=d.banda_horaria_id join solicitud_empleados se on se.id=d.solicitud_empleado_id where se.solicitud_id=%L and d.fecha=''2026-10-17''', :'s_vie')) = 'Extras nocturnas');
select t.ok('BC-3 lunes 00:00-02:00 usa la banda del domingo 22-06 (x2,2): 2 h / 4400', t.q(format('select total_horas||''|''||total_importe from solicitud_empleados where solicitud_id=%L', :'s_mad')) = '2.00|4400.00');
select t.ok('BC-5 feriado: usa multiplicador_feriado de la banda del dia (2,0): 2 h / 4000 y es_feriado', t.q(format('select se.total_importe||''|''||bool_and(d.es_feriado) from solicitud_empleados se join solicitud_empleado_detalle d on d.solicitud_empleado_id=se.id where se.solicitud_id=%L group by se.total_importe', :'s_fer')) = '4000.00|true');
select t.ok('BC-6 el rechazo del sabado no dejo nada a medias', (select count(*) from solicitud_empleados where solicitud_id=:'s_sab') = 0);

\echo '=== CO: OBSERVACION EN CONTROL DE INGRESO ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-19 18:00-03'::timestamptz,'2026-10-19 20:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','sin aprobacion')).id as s_ci \gset
select rpc_agregar_empleado(:'s_ci','60000000-0000-0000-0000-000000000001');
select rpc_agregar_empleado(:'s_ci','60000000-0000-0000-0000-000000000002');
select rpc_agregar_empleado(:'s_ci','60000000-0000-0000-0000-000000000003');
select rpc_agregar_empleado(:'s_ci','60000000-0000-0000-0000-000000000004');
select rpc_enviar_a_aprobacion(:'s_ci');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.require(t.q(format('select situacion from solicitudes where id=%L', :'s_ci')) = 'APROBADA', 'la solicitud sin aprobacion debe quedar APROBADA');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_ci','60000000-0000-0000-0000-000000000001')) as ce1 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_ci','60000000-0000-0000-0000-000000000002')) as ce2 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_ci','60000000-0000-0000-0000-000000000003')) as ce3 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_ci','60000000-0000-0000-0000-000000000004')) as ce4 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.fails('CO-1 operador de Area2 sigue SIN permiso en Area1 aunque mande fecha y observacion', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'',''2026-10-19 18:07-03''::timestamptz,''x'')', :'ce1'), 'No tenés permiso');
reset role; select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('CO-2 Ingreso con fecha/hora elegida y observacion con espacios', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'',''2026-10-19 18:07-03''::timestamptz,''  Entró por portería  '')', :'ce1'));
select t.passes('CO-3 Ya estaba en planta con observacion', format('select rpc_registrar_control_ingreso(%L,''YA_ESTABA_EN_PLANTA'',now(),''Venia del turno anterior'')', :'ce2'));
select t.passes('CO-4 llamada de 3 argumentos (formato anterior) sigue funcionando', format('select rpc_registrar_control_ingreso(%L,''NO_PRESENTADO'',now())', :'ce3'));
select t.passes('CO-5 observacion solo con espacios se guarda como vacia', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'',''2026-10-19 18:30-03''::timestamptz,''   '')', :'ce4'));
select t.fails('CO-6 observacion de mas de 1000 caracteres rechazada', format('select rpc_registrar_control_ingreso(%L,''NO_PRESENTADO'',now(),%L)', :'ce3', repeat('a',1001)), 'no puede superar');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CO-2b queda la fecha elegida (no now()) y la observacion sin espacios', t.q(format('select fecha_hora_ingreso||''|''||observacion_control_ingreso from solicitud_empleados where id=%L', :'ce1')) = '2026-10-19 21:07:00+00|Entró por portería');
select t.ok('CO-3b "Ya estaba" no guarda fecha de ingreso pero si observacion', t.q(format('select coalesce(fecha_hora_ingreso::text,''nula'')||''|''||observacion_control_ingreso from solicitud_empleados where id=%L', :'ce2')) = 'nula|Venia del turno anterior');
select t.ok('CO-4b sin observacion queda NULL', t.q(format('select (observacion_control_ingreso is null)::text from solicitud_empleados where id=%L', :'ce3')) = 'true');
select t.ok('CO-5b observacion en blanco queda NULL', t.q(format('select (observacion_control_ingreso is null)::text from solicitud_empleados where id=%L', :'ce4')) = 'true');
select t.ok('CO-7 la vista de detalle expone observacion_control_ingreso', t.q(format('select observacion_control_ingreso from vista_solicitud_empleados_detalle where solicitud_empleado_id=%L', :'ce1')) = 'Entró por portería');
select t.ok('CO-8 el evento de auditoria guarda la observacion', t.q(format('select datos->>''observacion'' from auditoria_negocio where entidad_id=%L and evento=''CONTROL_INGRESO_REGISTRADO'' order by fecha_hora desc limit 1', :'ce1')) = 'Entró por portería');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.passes('CO-9 el administrador quita el control de ingreso', format('select rpc_quitar_control_ingreso(%L)', :'ce1'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CO-9b al quitar el control se borran fecha y observacion', t.q(format('select coalesce(fecha_hora_ingreso::text,''nula'')||''|''||coalesce(observacion_control_ingreso,''nula'')||''|''||estado_asistencia from solicitud_empleados where id=%L', :'ce1')) = 'nula|nula|PENDIENTE_INGRESO');
update usuarios set activo=false where id='00000000-0000-0000-0000-000000000008';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('CO-10 usuario inactivo bloqueado tambien con la firma nueva', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'',now(),''x'')', :'ce1'), 'inactivo');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo=true where id='00000000-0000-0000-0000-000000000008';

\echo '=== VS: DESGLOSE EN LA VISTA DE SOLICITUDES ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-26 18:00-03'::timestamptz,'2026-10-26 20:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','desglose')).id as s_vs \gset
select rpc_agregar_empleado(:'s_vs','60000000-0000-0000-0000-000000000001');
select rpc_agregar_empleado(:'s_vs','60000000-0000-0000-0000-000000000002');
select rpc_agregar_empleado(:'s_vs','60000000-0000-0000-0000-000000000003');
select rpc_enviar_a_aprobacion(:'s_vs');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_vs','60000000-0000-0000-0000-000000000001')) as ve1 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s_vs','60000000-0000-0000-0000-000000000002')) as ve2 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_empleado(:'ve1');
select rpc_rechazar_empleado(:'ve2','no corresponde');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('VS-1 la vista cuenta empleados: 3 en total, 1 aprobado, 1 rechazado, 1 pendiente', t.q(format('select cantidad_empleados||''|''||empleados_aprobados||''|''||empleados_rechazados||''|''||empleados_pendientes from vista_solicitudes_resumen where id=%L', :'s_vs')) = '3|1|1|1');
select t.ok('VS-2 y las horas: 6 en total (sin cambios: incluye rechazados), 2 aprobadas, 2 rechazadas, 2 pendientes', t.q(format('select total_horas_solicitud||''|''||horas_aprobadas||''|''||horas_rechazadas||''|''||horas_pendientes from vista_solicitudes_resumen where id=%L', :'s_vs')) = '6.00|2.00|2.00|2.00');
select t.ok('VS-3 la observacion de la solicitud sigue en la vista', t.q(format('select observacion from vista_solicitudes_resumen where id=%L', :'s_vs')) = 'desglose');

\echo '=== PV: PRIVILEGIOS TRAS LA MIGRACION ==='
select t.ok('PV-0a las funciones nuevas e internas no son ejecutables por anon ni authenticated', not has_function_privilege('anon','fn_rangos_semanales_banda(time,time,integer,integer)','execute') and not has_function_privilege('authenticated','fn_rangos_semanales_banda(time,time,integer,integer)','execute') and not has_function_privilege('anon','fn_banda_horaria_aplica(time,time,integer,integer,integer)','execute') and not has_function_privilege('authenticated','fn_banda_horaria_aplica(time,time,integer,integer,integer)','execute'));
select t.ok('PV-0b rpc_registrar_control_ingreso: una sola firma (la de 4 parametros), authenticated si, anon no', t.q('select count(*) from pg_proc where proname=''rpc_registrar_control_ingreso''')::int = 1 and has_function_privilege('authenticated','rpc_registrar_control_ingreso(uuid,estado_asistencia_empleado,timestamptz,text)','execute') and not has_function_privilege('anon','rpc_registrar_control_ingreso(uuid,estado_asistencia_empleado,timestamptz,text)','execute'));
select t.ok('PV-0c anon sigue sin EXECUTE sobre ninguna funcion propia de public', t.q('select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and not exists (select 1 from pg_depend d where d.classid=''pg_proc''::regclass and d.objid=p.oid and d.deptype=''e'') and has_function_privilege(''anon'', p.oid, ''execute'')')::int = 0);
select t.ok('PV-0d toda funcion SECURITY DEFINER propia fija search_path; las nuevas internas tambien', t.q('select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and not exists (select 1 from pg_depend d where d.classid=''pg_proc''::regclass and d.objid=p.oid and d.deptype=''e'') and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, ''{}'')) cfg where cfg like ''search_path=%'')')::int = 0 and (select count(*) from pg_proc where proname in ('fn_rangos_semanales_banda','fn_banda_horaria_aplica') and proconfig is not null) = 2);
select t.ok('PV-0e las tres vistas siguen siendo security_invoker', t.q('select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=''public'' and c.relkind=''v'' and c.reloptions @> array[''security_invoker=true'']')::int = 3);
\echo '=== RESUMEN ==='
select t.resumen(47);
select 'FALLOS: '||coalesce(string_agg(label||' ['||coalesce(detail,'')||']', E'\n'),'ninguno') from t.res where not ok;
