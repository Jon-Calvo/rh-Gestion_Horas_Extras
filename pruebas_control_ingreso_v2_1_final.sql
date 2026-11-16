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
insert into bandas_horarias(descripcion,hora_desde,hora_hasta,multiplicador,multiplicador_feriado) values ('Diurna','06:00','22:00',1.5,2.0),('Nocturna','22:00','06:00',1.7,2.2);
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
\echo '=== DIAGNOSTICO CONTROL DE INGRESO ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-10 08:00-03'::timestamptz,'2026-10-10 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa1 \gset
select rpc_agregar_empleado(:'sa1','60000000-0000-0000-0000-000000000001');
select rpc_agregar_empleado(:'sa1','60000000-0000-0000-0000-000000000002');
select rpc_enviar_a_aprobacion(:'sa1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'sa1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000006',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000006','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','2026-10-10 08:00-03'::timestamptz,'2026-10-10 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa2 \gset
select rpc_agregar_empleado(:'sa2','60000000-0000-0000-0000-000000000010');
select rpc_enviar_a_aprobacion(:'sa2');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select rpc_aprobar_masivo(:'sa2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'sa1','60000000-0000-0000-0000-000000000001')) as se_a1_e1 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'sa1','60000000-0000-0000-0000-000000000002')) as se_a1_e2 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L', :'sa2')) as se_a2 \gset
select t.ok('PRE sa1 y sa2 APROBADAS', t.q(format('select situacion from solicitudes where id=%L', :'sa1'))='APROBADA' and t.q(format('select situacion from solicitudes where id=%L', :'sa2'))='APROBADA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.fails('D1 [REGLA] U7 (control=true, visibilidad solo Area2) NO debe registrar control en solicitud de Area1', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_a1_e1'), 'No tenés permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D1b [REGLA] y no debe quedar nada registrado', t.q(format('select estado_asistencia from solicitud_empleados where id=%L', :'se_a1_e1'))='PENDIENTE_INGRESO');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update solicitud_empleados set estado_asistencia='PENDIENTE_INGRESO', fecha_hora_ingreso=null, usuario_control_ingreso_id=null where id=:'se_a1_e1';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.passes('D1c [REGLA] U7 SI opera en su area visible (Area2)', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_a2'));
select t.passes('D1d [REGLA] U7 SI finaliza en su area visible (Area2)', format('select rpc_finalizar_solicitud(%L)', :'sa2'));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('D2a [REGLA] U8 (control=true, visibilidad TODO) opera en Area1', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_a1_e1'));
select rpc_registrar_control_ingreso(:'se_a1_e2','YA_ESTABA_EN_PLANTA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('D3b [REGLA] U8 (visib TODO) NO modifica observacion', format('select rpc_modificar_observacion(%L,''x'')', :'sa1'), 'permiso');
select t.fails('D3c [REGLA] U8 (visib TODO) NO reabre', format('select rpc_reabrir_solicitud(%L,''x'')', :'sa1'), 'permiso');
select t.fails('D3d [REGLA] U8 (visib TODO) NO crea solicitudes', format('select rpc_crear_solicitud(%L,%L,%L,now(),now()+interval ''1 hour'',%L)','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'), 'permiso');
select t.passes('D2b [REGLA] U8 finaliza solicitud de Area1', format('select rpc_finalizar_solicitud(%L)', :'sa1'));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-16 08:00-03'::timestamptz,'2026-10-16 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa7 \gset
select rpc_agregar_empleado(:'sa7','60000000-0000-0000-0000-000000000004');
select rpc_enviar_a_aprobacion(:'sa7');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'sa7');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sa7','60000000-0000-0000-0000-000000000004','ACTIVO')) as se_sa7_e4 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_sa7_e4','INGRESO_REGISTRADO');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.fails('D1e [REGLA] U7 (visibilidad Area2) NO debe finalizar solicitud de Area1 sin pendientes', format('select rpc_finalizar_solicitud(%L)', :'sa7'), 'No tenés permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D1f [REGLA] y la solicitud sigue APROBADA', t.q(format('select situacion from solicitudes where id=%L', :'sa7'))='APROBADA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-14 08:00-03'::timestamptz,'2026-10-14 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa6 \gset
select rpc_agregar_empleado(:'sa6','60000000-0000-0000-0000-000000000004');
select rpc_enviar_a_aprobacion(:'sa6');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sa6','60000000-0000-0000-0000-000000000004','ACTIVO')) as se_sa6_e4 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('D3e [REGLA] U8 (visib TODO, aprobacion NADA) NO aprueba un empleado PENDIENTE', format('select rpc_aprobar_empleado(%L)', :'se_sa6_e4'), 'permiso para aprobar');
select t.fails('D3f [REGLA] U8 NO aprueba masivo', format('select rpc_aprobar_masivo(%L)', :'sa6'), 'permiso para aprobar');
select t.fails('D3g [REGLA] U8 NO rechaza', format('select rpc_rechazar_empleado(%L,''x'')', :'se_sa6_e4'), 'permiso para aprobar');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-13 08:00-03'::timestamptz,'2026-10-13 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa5 \gset
select rpc_agregar_empleado(:'sa5','60000000-0000-0000-0000-000000000003');
select rpc_enviar_a_aprobacion(:'sa5');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'sa5');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sa5','60000000-0000-0000-0000-000000000003','ACTIVO')) as se_sa5_e3 \gset
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set control_ingreso=false where usuario_id='00000000-0000-0000-0000-000000000008';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('D2c [REGLA] visibilidad TODO sin control_ingreso no alcanza', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_sa5_e3'), 'permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set control_ingreso=true where usuario_id='00000000-0000-0000-0000-000000000008';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_sa5_e3','INGRESO_REGISTRADO');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set control_ingreso_permite_eliminar=true;
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update solicitud_empleados set estado_asistencia='INGRESO_REGISTRADO', fecha_hora_ingreso=now() where id=:'se_sa5_e3';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000009',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000009','authenticated');
select t.fails('D4 [REGLA] U9 (control_ingreso=false, puede_quitar=true, ve Area1) NO debe quitar un control', format('select rpc_quitar_control_ingreso(%L)', :'se_sa5_e3'), 'permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set puede_quitar_control_ingreso=true where usuario_id='00000000-0000-0000-0000-000000000007';
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update solicitud_empleados set estado_asistencia='INGRESO_REGISTRADO', fecha_hora_ingreso=now() where id=:'se_sa5_e3';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.fails('D4c [REGLA] U7 (control+quitar, visibilidad solo Area2) NO quita en Area1', format('select rpc_quitar_control_ingreso(%L)', :'se_sa5_e3'), 'No tenés permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set puede_quitar_control_ingreso=true where usuario_id='00000000-0000-0000-0000-000000000008';
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update solicitud_empleados set estado_asistencia='INGRESO_REGISTRADO', fecha_hora_ingreso=now() where id=:'se_sa5_e3';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('D4d [REGLA] U8 (control+quitar+visibilidad TODO, interruptor general ON) quita', format('select rpc_quitar_control_ingreso(%L)', :'se_sa5_e3'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set control_ingreso_permite_eliminar=false;
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.ok('D5 [REGLA] fn_permisos_para_scope informa puede_control_ingreso=false para Area1 a U7', t.qi(format('select puede_control_ingreso::text from fn_permisos_para_scope(%L,%L,%L)','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'))='false');
select t.ok('D5b [REGLA] y true para Area2', t.qi(format('select puede_control_ingreso::text from fn_permisos_para_scope(%L,%L,%L)','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002'))='true');
\echo '=== DIAGNOSTICO FLUJO / RANKING ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-15 08:00-03'::timestamptz,'2026-10-15 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sm2 \gset
select rpc_agregar_empleado(:'sm2','60000000-0000-0000-0000-000000000002');
select rpc_enviar_a_aprobacion(:'sm2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D10 [CONSISTENCIA] solicitud de motivo SIN aprobacion con todos APROBADOS no queda EN_APROBACION tras enviarla', t.q(format('select situacion from solicitudes where id=%L', :'sm2'))='APROBADA');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG003''') as b3 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-09 08:00-03'::timestamptz,'2026-10-09 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sr1 \gset
select rpc_agregar_empleado(:'sr1','60000000-0000-0000-0000-000000000003');
select rpc_enviar_a_aprobacion(:'sr1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'sr1');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PRE-D6 LEG003 sumo 4h', t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric = :b3 + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select rpc_cancelar_solicitud(:'sr1','test');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D6 [CONSISTENCIA] cancelar una solicitud APROBADA devuelve las horas al ranking', t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric = :b3);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG004''') as b4 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-08 08:00-03'::timestamptz,'2026-10-08 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sr2 \gset
select rpc_agregar_empleado(:'sr2','60000000-0000-0000-0000-000000000004');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PRE-D6b auto-aprobado en BORRADOR suma 4h', t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric = :b4 + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_eliminar_borrador(:'sr2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D6b [CONSISTENCIA] eliminar un BORRADOR auto-aprobado devuelve las horas', t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric = :b4);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG006''') as b6 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-07 08:00-03'::timestamptz,'2026-10-07 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sr3 \gset
select rpc_agregar_empleado(:'sr3','60000000-0000-0000-0000-000000000006');
select rpc_agregar_empleado(:'sr3','60000000-0000-0000-0000-000000000007');
select rpc_enviar_a_aprobacion(:'sr3');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sr3','60000000-0000-0000-0000-000000000006','ACTIVO')) as se_sr3_e6 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_empleado(:'se_sr3_e6');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PRE-D7 LEG006 sumo 4h', t.q('select ranking_horas from empleados where legajo=''LEG006''')::numeric = :b6 + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_rechazar_empleado(:'se_sr3_e6','cambio de decision');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D7 [CONSISTENCIA] rechazar a un empleado ya APROBADO devuelve sus horas', t.q('select ranking_horas from empleados where legajo=''LEG006''')::numeric = :b6);
\echo '=== DIAGNOSTICO MOTIVO/FECHAS EN BORRADOR ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG001''') as b1 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-05 08:00-03'::timestamptz,'2026-10-05 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sx1 \gset
select rpc_agregar_empleado(:'sx1','60000000-0000-0000-0000-000000000001');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PRE-D11 LEG001 auto-aprobado suma 4h', t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric = :b1 + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_motivo(:'sx1','50000000-0000-0000-0000-000000000001');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D11 [CONSISTENCIA] BORRADOR sin->con aprobacion: queda PENDIENTE y el ranking se revierte', t.q(format('select estado_aprobacion::text from solicitud_empleados where solicitud_id=%L', :'sx1'))='PENDIENTE_APROBACION' and t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric = :b1);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG002''') as b2 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-04 08:00-03'::timestamptz,'2026-10-04 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sx2 \gset
select rpc_agregar_empleado(:'sx2','60000000-0000-0000-0000-000000000002');
select rpc_modificar_motivo(:'sx2','50000000-0000-0000-0000-000000000002');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D12 [CONSISTENCIA] BORRADOR con->sin aprobacion: queda APROBADO y suma ranking', t.q(format('select estado_aprobacion::text from solicitud_empleados where solicitud_id=%L', :'sx2'))='APROBADO' and t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric = :b2 + 4);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG004''') as b3x \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-03 08:00-03'::timestamptz,'2026-10-03 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sx3 \gset
select rpc_agregar_empleado(:'sx3','60000000-0000-0000-0000-000000000004');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PRE-D13 LEG004 suma 4h', t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric = :b3x + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_fechas(:'sx3','2026-10-03 08:00-03','2026-10-03 10:00-03');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D13 [CONSISTENCIA] BORRADOR sin aprobacion: tras acortar a 2h el ranking suma 2h (no 4h)', t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric = :b3x + 2);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_eliminar_borrador(:'sx3');
\echo '=== V2.1 NUEVAS: CONTROL DE INGRESO + USUARIOS INACTIVOS ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-02 08:00-03'::timestamptz,'2026-10-02 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sci1 \gset
select rpc_agregar_empleado(:'sci1','60000000-0000-0000-0000-000000000005');
select rpc_enviar_a_aprobacion(:'sci1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'sci1');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q(format('select id from solicitud_empleados where solicitud_id=%L', :'sci1')) as se_ci1 \gset
select t.ok('PRE-D14 sci1 APROBADA con LEG005 pendiente de ingreso', t.q(format('select situacion from solicitudes where id=%L', :'sci1'))='APROBADA' and t.q(format('select estado_asistencia::text from solicitud_empleados where id=%L', :'se_ci1'))='PENDIENTE_INGRESO');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('D14 [CONTROL] U8 activo (TODO + control_ingreso) SI registra control en sci1', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_ci1'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo=false where id in ('00000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000001');
select t.require((select count(*) from usuarios where not activo)=2,'U8 y U1 desactivados');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('D15 [INACTIVO] U8 inactivo (conserva control_ingreso y visibilidad TODO) NO registra control', format('select rpc_registrar_control_ingreso(%L,''NO_PRESENTADO'')', :'se_ci1'), 'inactivo');
select t.fails('D16 [INACTIVO] U8 inactivo NO quita control de ingreso', format('select rpc_quitar_control_ingreso(%L)', :'se_ci1'), 'inactivo');
select t.fails('D17 [INACTIVO] U8 inactivo NO finaliza la solicitud', format('select rpc_finalizar_solicitud(%L)', :'sci1'), 'inactivo');
select t.ok('D18 [INACTIVO] fn_permisos_para_scope y fn_puede_control_ingreso_sobre = false para U8 inactivo', not fn_puede_control_ingreso_sobre('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001') and (select not (puede_ver or puede_modificar or puede_aprobar or puede_reabrir or puede_control_ingreso) from fn_permisos_para_scope('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001')));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('D19 [INACTIVO] ADMIN inactivo NO registra control de ingreso (el bypass de admin tambien exige estar activo)', format('select rpc_registrar_control_ingreso(%L,''NO_PRESENTADO'')', :'se_ci1'), 'inactivo');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D20 los intentos de inactivos no cambiaron nada: sci1 sigue APROBADA con INGRESO_REGISTRADO', t.q(format('select situacion from solicitudes where id=%L', :'sci1'))='APROBADA' and t.q(format('select estado_asistencia::text from solicitud_empleados where id=%L', :'se_ci1'))='INGRESO_REGISTRADO');
update usuarios set activo=true where id in ('00000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000001');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('D21 [INACTIVO] reactivado, U8 finaliza sci1', format('select rpc_finalizar_solicitud(%L)', :'sci1'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('D22 sci1 FINALIZADA tras reactivar a U8', t.q(format('select situacion from solicitudes where id=%L', :'sci1'))='FINALIZADA');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo=false where id='00000000-0000-0000-0000-000000000002';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('D9 [INACTIVO] con usuarios.activo=false el usuario con permisos NO ejecuta RPC (SECURITY DEFINER)', format('select rpc_crear_solicitud(%L,%L,%L,now(),now()+interval ''1 hour'',%L)','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'), 'inactivo');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo=true where id='00000000-0000-0000-0000-000000000002';
\echo '=== V2.1 NUEVAS: PRIVILEGIOS EFECTIVOS ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('PV-1 anon no tiene EXECUTE sobre ninguna funcion de public (ni internas ni RPC)', t.q('select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and not exists (select 1 from pg_depend d where d.classid=''pg_proc''::regclass and d.objid=p.oid and d.deptype=''e'') and has_function_privilege(''anon'', p.oid, ''execute'')')::int = 0);
select t.ok('PV-2 authenticated ejecuta EXACTAMENTE las 22 RPC + 15 helpers de solo lectura (nada interno)', t.q('select string_agg(distinct p.proname, '','' order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and not exists (select 1 from pg_depend d where d.classid=''pg_proc''::regclass and d.objid=p.oid and d.deptype=''e'') and has_function_privilege(''authenticated'', p.oid, ''execute'')') = 'fn_banda_ranking,fn_es_admin,fn_es_desarrollador,fn_permisos_para_scope,fn_puede_aprobar,fn_puede_control_ingreso,fn_puede_control_ingreso_sobre,fn_puede_eliminar_cancelar,fn_puede_exportar,fn_puede_importar,fn_puede_modificar,fn_puede_reabrir,fn_puede_ver,fn_puede_ver_importes,fn_usuario_activo,rpc_agregar_empleado,rpc_aprobar_empleado,rpc_aprobar_masivo,rpc_cancelar_solicitud,rpc_crear_solicitud,rpc_eliminar_borrador,rpc_enviar_a_aprobacion,rpc_finalizar_solicitud,rpc_importar_empleado_excel,rpc_modificar_fechas,rpc_modificar_motivo,rpc_modificar_observacion,rpc_modificar_scope,rpc_quitar_control_ingreso,rpc_quitar_empleado,rpc_reabrir_solicitud,rpc_rechazar_empleado,rpc_rechazar_masivo,rpc_rectificar_horas_ranking,rpc_reemplazar_empleado,rpc_registrar_control_ingreso,rpc_upsert_empleado');
select t.ok('PV-3 anon: unico privilegio de tabla = SELECT en configuracion_apariencia', t.q('select string_agg(c.relname||'':''||pr, '','' order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace, unnest(array[''select'',''insert'',''update'',''delete'']) pr where n.nspname=''public'' and c.relkind in (''r'',''v'') and has_table_privilege(''anon'', c.oid, pr)') = 'configuracion_apariencia:select');
select t.ok('PV-4 authenticated solo puede ESCRIBIR (INSERT) las 18 tablas admin-gated; solicitudes/auditoria/rectificaciones/contador: solo lectura o nada', t.q('select string_agg(c.relname, '','' order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=''public'' and c.relkind=''r'' and has_table_privilege(''authenticated'', c.oid, ''insert'')') = 'areas,bandas_horarias,bandas_ranking,categoria_tipos,categorias,configuracion_apariencia,configuracion_general,empleados,feriados,ib_configuracion,motivos,niveles_aprobacion_config,procesos,sectores,usuario_permiso_scopes,usuario_permisos,usuario_roles,usuarios');
select t.ok('PV-5 contador_solicitudes: RLS activo y sin ningun privilegio para authenticated/anon', t.q('select relrowsecurity from pg_class where oid=''public.contador_solicitudes''::regclass') = 'true' and not has_table_privilege('authenticated','public.contador_solicitudes','select') and not has_table_privilege('anon','public.contador_solicitudes','select'));
select t.ok('PV-6 TODAS las tablas de public tienen RLS habilitado', t.q('select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=''public'' and c.relkind=''r'' and not c.relrowsecurity')::int = 0);
select t.ok('PV-7 TODAS las vistas de public son security_invoker', t.q('select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=''public'' and c.relkind=''v'' and not coalesce(c.reloptions @> array[''security_invoker=true''], false)')::int = 0 and t.q('select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=''public'' and c.relkind=''v''')::int = 3);
select t.ok('PV-8 TODA funcion SECURITY DEFINER fija search_path', t.q('select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=''public'' and not exists (select 1 from pg_depend d where d.classid=''pg_proc''::regclass and d.objid=p.oid and d.deptype=''e'') and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, ''{}'')) cfg where cfg like ''search_path=%'')')::int = 0);
select t.ok('PV-9 el rol authenticated NO puede ejecutar funciones internas directamente (fn_aprobar_empleado_interno)', not has_function_privilege('authenticated','fn_aprobar_empleado_interno(uuid,uuid)','execute') and not has_function_privilege('authenticated','fn_exigir_usuario_activo()','execute') and not has_function_privilege('authenticated','fn_registrar_evento_negocio(text,text,uuid,text,nivel_auditoria_negocio,text,uuid,text,text,jsonb)','execute'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
\echo '=== RESUMEN ==='
select t.resumen(53);
select 'FALLOS: '||coalesce(string_agg(label||' ['||coalesce(detail,'')||']', E'\n'),'ninguno') from t.res where not ok;
