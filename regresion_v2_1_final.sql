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

insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000001','u1@test.com'),('00000000-0000-0000-0000-000000000002','u2@test.com'),('00000000-0000-0000-0000-000000000003','u3@test.com'),('00000000-0000-0000-0000-000000000004','u4@test.com'),('00000000-0000-0000-0000-000000000005','u5@test.com'),('00000000-0000-0000-0000-000000000006','u6@test.com'),('00000000-0000-0000-0000-000000000007','u7@test.com'),('00000000-0000-0000-0000-000000000008','u8@test.com');
insert into usuarios(id,nombre_completo) values ('00000000-0000-0000-0000-000000000001','Admin'),('00000000-0000-0000-0000-000000000002','Responsable Area1'),('00000000-0000-0000-0000-000000000003','Aprobador Area1'),('00000000-0000-0000-0000-000000000004','RRHH'),('00000000-0000-0000-0000-000000000005','Consulta sin permisos'),('00000000-0000-0000-0000-000000000006','Responsable Area2'),('00000000-0000-0000-0000-000000000007','Control Ingreso fuera de area'),('00000000-0000-0000-0000-000000000008','Control Ingreso TODO');
insert into usuario_roles select '00000000-0000-0000-0000-000000000001', id from roles where nombre='ADMIN';
insert into usuario_roles select '00000000-0000-0000-0000-000000000002', id from roles where nombre='RESPONSABLE';
insert into usuario_roles select '00000000-0000-0000-0000-000000000003', id from roles where nombre='APROBADOR';
insert into usuario_roles select '00000000-0000-0000-0000-000000000004', id from roles where nombre='RRHH';
insert into usuario_roles select '00000000-0000-0000-0000-000000000005', id from roles where nombre='CONSULTA';
insert into usuario_roles select '00000000-0000-0000-0000-000000000006', id from roles where nombre='RESPONSABLE';
insert into usuario_roles select '00000000-0000-0000-0000-000000000007', id from roles where nombre='CONTROL_INGRESO';
insert into usuario_roles select '00000000-0000-0000-0000-000000000008', id from roles where nombre='CONTROL_INGRESO';
insert into areas(id,nombre) values ('10000000-0000-0000-0000-000000000001','Area1'),('10000000-0000-0000-0000-000000000002','Area2');
insert into sectores(id,nombre,area_id) values ('20000000-0000-0000-0000-000000000001','Sector1','10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002','Sector2','10000000-0000-0000-0000-000000000002');
insert into procesos(id,nombre,sector_id) values ('30000000-0000-0000-0000-000000000001','Proceso1','20000000-0000-0000-0000-000000000001'),('30000000-0000-0000-0000-000000000002','Proceso2','20000000-0000-0000-0000-000000000002');
insert into usuario_permisos(usuario_id,visibilidad_nivel,modificacion_nivel,aprobacion_nivel,reapertura_nivel,control_ingreso,puede_importar,puede_quitar_control_ingreso) values
('00000000-0000-0000-0000-000000000002','AREA','AREA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000003','AREA','NADA','AREA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000004','TODO','TODO','NADA','NADA',false,true,false),
('00000000-0000-0000-0000-000000000005','NADA','NADA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000006','AREA','AREA','NADA','NADA',false,false,false),
('00000000-0000-0000-0000-000000000007','AREA','NADA','NADA','NADA',true,false,false),
('00000000-0000-0000-0000-000000000008','TODO','NADA','NADA','NADA',true,false,false);
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
\echo '=== MULTI-TRAMO / FLUJO S1 ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-10 20:00-03'::timestamptz,'2026-10-11 08:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s1 \gset
select rpc_agregar_empleado(:'s1','60000000-0000-0000-0000-000000000001');
select rpc_agregar_empleado(:'s1','60000000-0000-0000-0000-000000000002');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MT-1 12h partidas en 4 sub-tramos por empleado', t.q(format('select count(*) from solicitud_empleado_detalle d join solicitud_empleados se on se.id=d.solicitud_empleado_id where se.solicitud_id=%L and se.empleado_id=%L', :'s1','60000000-0000-0000-0000-000000000001'))::int = 4);
select t.ok('MT-2 total 12h y importe 19600 (2h*1.5+2h*1.7+6h*1.7+2h*1.5 a 1000/h)', t.q(format('select total_horas||''/''||total_importe from solicitud_empleados where solicitud_id=%L and empleado_id=%L', :'s1','60000000-0000-0000-0000-000000000001')) = '12.00/19600.00');
select t.ok('MT-3 moneda de cabecera fijada en ARS', t.q(format('select moneda from solicitudes where id=%L', :'s1')) = 'ARS');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_enviar_a_aprobacion(:'s1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'s1');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('FL-1 S1 APROBADA tras aprobar a todos', t.q(format('select situacion from solicitudes where id=%L', :'s1')) = 'APROBADA');
select t.ok('FL-2 ranking LEG001 = 12', t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric = 12);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-1 invariante ranking_horas = suma de aprobaciones vigentes (tras S1)', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
\echo '=== CONTROL DE INGRESO fuera de alcance ==='
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s1','60000000-0000-0000-0000-000000000001','ACTIVO')) as se_s1_e1 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s1','60000000-0000-0000-0000-000000000002','ACTIVO')) as se_s1_e2 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000007',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000007','authenticated');
select t.ok('CI-1 U7 (control_ingreso, visibilidad solo Area2) NO ve la solicitud de Area1 (RLS)', t.qi(format('select count(*) from solicitudes where id=%L', :'s1'))::int = 0);
select t.fails('CI-2 [REGLA] U7 (control_ingreso=true, visibilidad solo Area2) NO registra control en solicitud de Area1 (RPC SECURITY DEFINER)', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_s1_e1'), 'No tenés permiso');
select t.fails('CI-2b [REGLA] U7 NO finaliza solicitud de Area1', format('select rpc_finalizar_solicitud(%L)', :'s1'), 'No tenés permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CI-2c [REGLA] y nada quedo registrado ni finalizado', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L and estado_asistencia<>''PENDIENTE_INGRESO''', :'s1'))::int = 0 and t.q(format('select situacion from solicitudes where id=%L', :'s1')) = 'APROBADA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('CI-3 U2 (modifica Area1 pero sin control_ingreso) rechazado', format('select rpc_registrar_control_ingreso(%L,''YA_ESTABA_EN_PLANTA'')', :'se_s1_e2'), 'permiso para registrar control');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000005',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000005','authenticated');
select t.fails('CI-4 U5 (sin control_ingreso) rechazado', format('select rpc_registrar_control_ingreso(%L,''YA_ESTABA_EN_PLANTA'')', :'se_s1_e2'), 'permiso para registrar control');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('CI-4b [REGLA] U8 (control_ingreso, visibilidad TODO) registra control en Area1', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_s1_e1'));
select t.fails('CI-5 U8 no finaliza con un empleado sin resolver', format('select rpc_finalizar_solicitud(%L)', :'s1'), 'sin resolver');
select rpc_registrar_control_ingreso(:'se_s1_e2','NO_PRESENTADO');
select t.passes('CI-6 [REGLA] U8 finaliza solicitud de Area1', format('select rpc_finalizar_solicitud(%L)', :'s1'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CI-7 S1 FINALIZADA', t.q(format('select situacion from solicitudes where id=%L', :'s1')) = 'FINALIZADA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-02 08:00-03'::timestamptz,'2026-10-02 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sci \gset
select rpc_agregar_empleado(:'sci','60000000-0000-0000-0000-000000000005');
select rpc_enviar_a_aprobacion(:'sci');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sci','60000000-0000-0000-0000-000000000005','ACTIVO')) as se_sci \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('CI-12 [REGLA] U8 (visibilidad TODO, aprobacion NADA) NO aprueba', format('select rpc_aprobar_empleado(%L)', :'se_sci'), 'permiso para aprobar');
select t.fails('CI-13 [REGLA] U8 NO aprueba masivo', format('select rpc_aprobar_masivo(%L)', :'sci'), 'permiso para aprobar');
select t.fails('CI-14 [REGLA] U8 NO rechaza', format('select rpc_rechazar_empleado(%L,''x'')', :'se_sci'), 'permiso para aprobar');
select t.fails('CI-15 [REGLA] U8 NO modifica observacion', format('select rpc_modificar_observacion(%L,''x'')', :'sci'), 'permiso');
select t.fails('CI-16 [REGLA] U8 NO crea solicitudes', format('select rpc_crear_solicitud(%L,%L,%L,''2026-10-02 08:00-03''::timestamptz,''2026-10-02 12:00-03''::timestamptz,%L,''x'')', '10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'), 'permiso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CI-17 sci sigue EN_APROBACION tras los intentos de U8', t.q(format('select situacion from solicitudes where id=%L', :'sci')) = 'EN_APROBACION');
\echo '=== REEMPLAZO EN SOLICITUD APROBADA ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-12 08:00-03'::timestamptz,'2026-10-12 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s2 \gset
select rpc_agregar_empleado(:'s2','60000000-0000-0000-0000-000000000001');
select rpc_agregar_empleado(:'s2','60000000-0000-0000-0000-000000000002');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-12 10:00-03'::timestamptz,'2026-10-12 14:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s3 \gset
select rpc_agregar_empleado(:'s3','60000000-0000-0000-0000-000000000004');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s2','60000000-0000-0000-0000-000000000001','ACTIVO')) as se_s2_e1 \gset
select t.fails('RE-0 reemplazar en BORRADOR no permitido', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s2_e1','60000000-0000-0000-0000-000000000003'), 'estado actual');
select rpc_enviar_a_aprobacion(:'s2');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'s2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RE-1 S2 APROBADA, ranking LEG001 = 16 (12+4)', t.q(format('select situacion from solicitudes where id=%L', :'s2')) = 'APROBADA' and t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric = 16);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('RE-2 reemplazo por empleado con horas solapadas en otra solicitud rechazado', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s2_e1','60000000-0000-0000-0000-000000000004'), 'superponen');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RE-3 tras el rechazo (atomicidad) LEG001 sigue ACTIVO/APROBADO y ranking intacto en 16', t.q(format('select estado_registro::text||estado_aprobacion::text from solicitud_empleados where id=%L', :'se_s2_e1'))='ACTIVOAPROBADO' and t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric=16);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('RE-4 reemplazo por alguien ya en el equipo rechazado', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s2_e1','60000000-0000-0000-0000-000000000002'), 'ya está en el equipo');
select t.fails('RE-5 reemplazo por si mismo rechazado', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s2_e1','60000000-0000-0000-0000-000000000001'), 'sí mismo');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000006',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000006','authenticated');
select t.fails('RE-6 U6 (Area2) no puede reemplazar en solicitud de Area1', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s2_e1','60000000-0000-0000-0000-000000000003'), 'permiso');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_reemplazar_empleado(:'se_s2_e1','60000000-0000-0000-0000-000000000003');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s2','60000000-0000-0000-0000-000000000003','ACTIVO')) as se_s2_e3 \gset
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RE-7 fila de LEG001 REEMPLAZADO conservando estado_aprobacion APROBADO', t.q(format('select estado_registro::text||estado_aprobacion::text from solicitud_empleados where id=%L', :'se_s2_e1'))='REEMPLAZADOAPROBADO');
select t.ok('RE-8 ranking LEG001 revertido a 12 (no 16)', t.q('select ranking_horas from empleados where legajo=''LEG001''')::numeric = 12);
select t.ok('RE-9 nuevo LEG003 PENDIENTE, enlazado con reemplaza_a, ranking 0', t.q(format('select estado_aprobacion||(reemplaza_a=%L)::text from solicitud_empleados where id=%L', :'se_s2_e1', :'se_s2_e3'))='PENDIENTE_APROBACIONtrue' and t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric=0);
select t.ok('RE-10 solicitud vuelve a EN_APROBACION (hay un pendiente)', t.q(format('select situacion from solicitudes where id=%L', :'s2')) = 'EN_APROBACION');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_empleado(:'se_s2_e3');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RE-11 aprobado el reemplazo: S2 APROBADA y ranking LEG003 = 4', t.q(format('select situacion from solicitudes where id=%L', :'s2')) = 'APROBADA' and t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric = 4);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-2 invariante ranking tras reemplazo', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select t.fails('RE-12 aprobar la fila ya REEMPLAZADA es rechazado', format('select rpc_aprobar_empleado(%L)', :'se_s2_e1'), 'Solo se puede aprobar');
\echo '=== MONEDAS INCOMPATIBLES ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-13 08:00-03'::timestamptz,'2026-10-13 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s4 \gset
select rpc_agregar_empleado(:'s4','60000000-0000-0000-0000-000000000001');
select t.fails('MO-1 agregar empleado USD a solicitud ARS rechazado', format('select rpc_agregar_empleado(%L,%L)', :'s4', '60000000-0000-0000-0000-000000000005'), 'mezclar monedas');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-2 sin cambios parciales: 1 solo empleado vigente y moneda ARS', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L', :'s4'))::int=1 and t.q(format('select moneda from solicitudes where id=%L', :'s4'))='ARS');
select t.ok('MO-3 sin detalle huérfano del empleado rechazado', t.q(format('select count(*) from solicitud_empleado_detalle d join solicitud_empleados se on se.id=d.solicitud_empleado_id where se.solicitud_id=%L and se.empleado_id=%L', :'s4','60000000-0000-0000-0000-000000000005'))::int=0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_enviar_a_aprobacion(:'s4');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s4','60000000-0000-0000-0000-000000000001','ACTIVO')) as se_s4_e1 \gset
select t.fails('MO-4 reemplazar por empleado de otra moneda rechazado', format('select rpc_reemplazar_empleado(%L,%L)', :'se_s4_e1','60000000-0000-0000-0000-000000000005'), 'mezclar monedas');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-5 atomicidad del reemplazo: LEG001 sigue ACTIVO y no hay fila REEMPLAZADO/LEG005', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L', :'s4'))::int=1 and t.q(format('select estado_registro from solicitud_empleados where id=%L', :'se_s4_e1'))='ACTIVO');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-14 08:00-03'::timestamptz,'2026-10-14 10:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s5 \gset
select rpc_agregar_empleado(:'s5','60000000-0000-0000-0000-000000000006');
select rpc_agregar_empleado(:'s5','60000000-0000-0000-0000-000000000007');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-6 dos empleados CAT3 en octubre: moneda USD', t.q(format('select moneda from solicitudes where id=%L', :'s5'))='USD');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_fechas(:'s5','2026-09-25 08:00-03','2026-09-25 10:00-03');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-7 modificar fechas a septiembre cambia la moneda de cabecera a ARS (consistente para ambos)', t.q(format('select moneda from solicitudes where id=%L', :'s5'))='ARS' and t.q(format('select count(distinct d.moneda)||string_agg(distinct d.moneda,'''') from solicitud_empleado_detalle d join solicitud_empleados se on se.id=d.solicitud_empleado_id where se.solicitud_id=%L', :'s5'))='1ARS');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_agregar_empleado(:'s5','60000000-0000-0000-0000-000000000001');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-8 LEG001 (ARS) compatible con la solicitud en ARS', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L', :'s5'))::int=3);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('MO-9 volver a octubre mezclaría USD (CAT3) con ARS (CAT1): rechazado', format('select rpc_modificar_fechas(%L,%L,%L)', :'s5','2026-10-14 08:00-03','2026-10-14 10:00-03'), 'mezclar monedas');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-10 atomicidad: fechas, moneda y detalle siguen en septiembre/ARS', t.q(format('select moneda||fecha_hora_inicio::text from solicitudes where id=%L', :'s5'))='ARS2026-09-25 11:00:00+00' and t.q(format('select count(*) from solicitud_empleado_detalle d join solicitud_empleados se on se.id=d.solicitud_empleado_id where se.solicitud_id=%L and d.fecha=''2026-09-25''', :'s5'))::int=3);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-09-30 20:00-03'::timestamptz,'2026-10-01 04:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s9 \gset
select t.fails('MO-11 un mismo empleado que cruza el cambio ARS->USD a medianoche rechazado', format('select rpc_agregar_empleado(%L,%L)', :'s9', '60000000-0000-0000-0000-000000000006'), 'cambia de moneda');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MO-12 sin fila insertada tras el rechazo', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L', :'s9'))::int=0);
\echo '=== MODIFICACION DE MOTIVO ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-15 08:00-03'::timestamptz,'2026-10-15 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s6 \gset
select rpc_agregar_empleado(:'s6','60000000-0000-0000-0000-000000000002');
select rpc_agregar_empleado(:'s6','60000000-0000-0000-0000-000000000003');
select rpc_enviar_a_aprobacion(:'s6');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s6','60000000-0000-0000-0000-000000000002','ACTIVO')) as se_s6_e2 \gset
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'s6','60000000-0000-0000-0000-000000000003','ACTIVO')) as se_s6_e3 \gset
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select (t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric) as r2_antes \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_empleado(:'se_s6_e2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MT-A S6 sigue EN_APROBACION con uno aprobado; LEG002 sube 4h', t.q(format('select situacion from solicitudes where id=%L', :'s6'))='EN_APROBACION' and t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric = :r2_antes + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_motivo(:'s6','50000000-0000-0000-0000-000000000003');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MT-B con->con (mismo requiere_aprobacion): NO invalida, LEG002 sigue APROBADO', t.q(format('select estado_aprobacion from solicitud_empleados where id=%L', :'se_s6_e2'))='APROBADO' and t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric = :r2_antes + 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_motivo(:'s6','50000000-0000-0000-0000-000000000002');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MT-C con->sin aprobacion: ambos APROBADOS automáticamente (sistema), sin doble conteo de ranking', t.q(format('select count(*) from solicitud_empleados where solicitud_id=%L and estado_aprobacion=''APROBADO'' and usuario_aprobacion_id is null', :'s6'))::int=2 and t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric = :r2_antes + 4);
select t.ok('MT-D S6 APROBADA', t.q(format('select situacion from solicitudes where id=%L', :'s6'))='APROBADA');
\echo '--- quitar control de ingreso ---'
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_s6_e2','INGRESO_REGISTRADO');
select t.fails('CI-8 U8 (control_ingreso=true pero sin puede_quitar_control_ingreso) no puede quitarlo', format('select rpc_quitar_control_ingreso(%L)', :'se_s6_e2'), 'quitar un control');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.passes('CI-9 admin siempre puede quitar un control de ingreso', format('select rpc_quitar_control_ingreso(%L)', :'se_s6_e2'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set puede_quitar_control_ingreso=true where usuario_id='00000000-0000-0000-0000-000000000008';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_s6_e2','INGRESO_REGISTRADO');
select t.fails('CI-10 permiso individual SIN interruptor general (control_ingreso_permite_eliminar=false) tampoco alcanza', format('select rpc_quitar_control_ingreso(%L)', :'se_s6_e2'), 'quitar un control');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set control_ingreso_permite_eliminar=true;
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('CI-11 interruptor general + permiso individual: puede quitar', format('select rpc_quitar_control_ingreso(%L)', :'se_s6_e2'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set control_ingreso_permite_eliminar=false;
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-3 invariante ranking tras cambios de motivo con->sin', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-17 08:00-03'::timestamptz,'2026-10-17 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as s8 \gset
select rpc_agregar_empleado(:'s8','60000000-0000-0000-0000-000000000004');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select (t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric) as r4_auto \gset
select t.ok('MT-E motivo sin aprobacion: LEG004 entra APROBADO y suma 4h al ranking', t.q(format('select estado_aprobacion from solicitud_empleados where solicitud_id=%L', :'s8'))='APROBADO' and :r4_auto = 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_modificar_motivo(:'s8','50000000-0000-0000-0000-000000000001');
select rpc_enviar_a_aprobacion(:'s8');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('MT-F sin->con aprobacion: LEG004 vuelve a PENDIENTE y su ranking se revierte a 0', t.q(format('select estado_aprobacion from solicitud_empleados where solicitud_id=%L', :'s8'))='PENDIENTE_APROBACION' and t.q('select ranking_horas from empleados where legajo=''LEG004''')::numeric=0);
select t.ok('MT-G S8 queda EN_APROBACION', t.q(format('select situacion from solicitudes where id=%L', :'s8'))='EN_APROBACION');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000005',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000005','authenticated');
select t.fails('MT-H usuario sin permiso no puede cambiar el motivo', format('select rpc_modificar_motivo(%L,%L)', :'s8','50000000-0000-0000-0000-000000000002'), 'permiso');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('MT-I no se puede cambiar el motivo de una solicitud APROBADA', format('select rpc_modificar_motivo(%L,%L)', :'s6','50000000-0000-0000-0000-000000000001'), 'BORRADOR o EN_APROBACION');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-4 invariante ranking tras sin->con', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
\echo '=== IMPORTACION ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000004',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000004','authenticated');
select t.q('select count(*) from empleados') as n_emp_antes \gset
select t.fails('IM-1 area NULL rechazada', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',NULL,''Sector1'',''Proceso1'')', 'área es obligatoria');
select t.fails('IM-2 area vacia rechazada', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''  '',''Sector1'',''Proceso1'')', 'área es obligatoria');
select t.fails('IM-3 sector NULL rechazado', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''Area1'',NULL,''Proceso1'')', 'sector es obligatorio');
select t.fails('IM-4 proceso vacio rechazado', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''Area1'',''Sector1'','''')', 'proceso es obligatorio');
select t.fails('IM-5 area inexistente rechazada', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''AreaX'',''Sector1'',''Proceso1'')', 'No existe el área');
select t.fails('IM-6 sector de OTRA area rechazado', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''Area1'',''Sector2'',''Proceso2'')', 'No existe el sector');
select t.fails('IM-7 proceso de OTRO sector rechazado', 'select rpc_importar_empleado_excel(''LEG100'',''Import'',''CAT1'',''Area1'',''Sector1'',''Proceso2'')', 'No existe el proceso');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('IM-8 ningun rechazo dejo empleados a medias', t.q('select count(*) from empleados')=:'n_emp_antes');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000004',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000004','authenticated');
select t.passes('IM-9 importacion valida completa por RRHH', 'select rpc_importar_empleado_excel(''LEG100'',''Import OK'',''CAT1'',''Area1'',''Sector1'',''Proceso1'')');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('IM-10 empleado importado con area/sector/proceso resueltos', t.q('select count(*) from empleados where legajo=''LEG100'' and area_id is not null and sector_id is not null and proceso_id is not null')::int=1);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000005',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000005','authenticated');
select t.fails('IM-11 usuario sin puede_importar rechazado', 'select rpc_importar_empleado_excel(''LEG101'',''X'',''CAT1'',''Area1'',''Sector1'',''Proceso1'')', 'permiso para importar');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuario_permisos set puede_importar=true where usuario_id='00000000-0000-0000-0000-000000000006';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000006',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000006','authenticated');
select t.fails('IM-12 importador de Area2 no puede pisar legajo existente de Area1', 'select rpc_importar_empleado_excel(''LEG001'',''Pisado'',''CAT1'',''Area2'',''Sector2'',''Proceso2'')', 'fuera de tu alcance');
select t.fails('IM-13 importador de Area2 no puede dar de alta en Area1', 'select rpc_importar_empleado_excel(''LEG102'',''X'',''CAT1'',''Area1'',''Sector1'',''Proceso1'')', 'permiso para gestionar');
select t.passes('IM-14 importador de Area2 importa dentro de su alcance','select rpc_importar_empleado_excel(''LEG103'',''A2'',''CAT1'',''Area2'',''Sector2'',''Proceso2'')');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('IM-15 LEG001 no fue modificado', t.q('select nombre_completo from empleados where legajo=''LEG001''')='Empleado 1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000004',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000004','authenticated');
select t.fails('IM-16 categoria inexistente rechazada', 'select rpc_upsert_empleado(''LEG104'',''X'',''NOEXISTE'',''10000000-0000-0000-0000-000000000001'',''20000000-0000-0000-0000-000000000001'',''30000000-0000-0000-0000-000000000001'')', 'categoría');
\echo '=== BANDAS / FERIADO ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.fails('BA-1 banda activa solapada rechazada por trigger', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta) values (''Dup'',''07:00'',''09:00'')', 'superpone');
select t.fails('BA-2 banda solapada que cruza medianoche rechazada', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta) values (''Dup2'',''23:00'',''01:00'')', 'superpone');
select t.fails('BA-3 banda de largo cero rechazada', 'insert into bandas_horarias(descripcion,hora_desde,hora_hasta,activo) values (''Cero'',''10:00'',''10:00'',false)', 'check');
insert into feriados(fecha) values ('2026-10-15');
select fn_calcular_detalle_solicitud_empleado(:'se_s6_e2');
select t.ok('BA-5 detalle de S6 con es_feriado y multiplicador 2.00 (importe 4h*1000*2)', t.q(format('select es_feriado::text||multiplicador||importe from solicitud_empleado_detalle where solicitud_empleado_id=%L', :'se_s6_e2'))='true2.008000.00');
delete from feriados;
begin; update bandas_horarias set activo=false where descripcion='Diurna';
select t.probe_fails(format('select fn_calcular_detalle_solicitud_empleado(%L)', :'se_s6_e2'), 'ninguna banda horaria activa') as r_ba6 \gset
rollback;
select t.ok('BA-6 sin banda aplicable: error claro', :'r_ba6' = 'ok', :'r_ba6');
begin; alter table bandas_horarias disable trigger trg_validar_solapamiento_bandas_horarias; insert into bandas_horarias(descripcion,hora_desde,hora_hasta) values ('DupForzada','09:00','12:00');
select t.probe_fails(format('select fn_calcular_detalle_solicitud_empleado(%L)', :'se_s6_e2'), 'se superponen') as r_ba7 \gset
rollback;
select t.ok('BA-7 dos bandas aplicables (trigger saltado a proposito): el motor igual rechaza', :'r_ba7' = 'ok', :'r_ba7');
\echo '=== RANKING / PERIODOS ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-5 invariante ranking antes del reseteo', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
select count(*) as n_con_ranking from empleados where ranking_horas>0 \gset
select fn_resetear_ranking_si_corresponde();
select t.ok('RK-1 todos en 0 tras el reseteo', t.q('select count(*) from empleados where ranking_horas>0')::int=0);
select t.ok('RK-2 historico tiene una fila por empleado reseteado', t.q('select count(*) from ranking_horas_historico')::int=:n_con_ranking);
select fn_resetear_ranking_si_corresponde();
select t.ok('RK-3 reseteo repetido NO duplica historial', t.q('select count(*) from ranking_horas_historico')::int=:n_con_ranking);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-17 14:00-03'::timestamptz,'2026-10-17 17:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s11 \gset
select rpc_agregar_empleado(:'s11','60000000-0000-0000-0000-000000000003');
select rpc_enviar_a_aprobacion(:'s11');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'s11');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RK-4 LEG003 = 3 en el periodo nuevo', t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric=3);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_quitar_empleado(:'se_s2_e3');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RK-5 quitar aprobacion del periodo ANTERIOR (S2, 4h) no resta del periodo nuevo: LEG003 sigue en 3', t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric=3);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-17 18:00-03'::timestamptz,'2026-10-17 20:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as s12 \gset
select rpc_agregar_empleado(:'s12','60000000-0000-0000-0000-000000000002');
select rpc_enviar_a_aprobacion(:'s12');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select rpc_aprobar_masivo(:'s12');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RK-5b LEG002 = 2 en el periodo nuevo', t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric=2);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select rpc_reabrir_solicitud(:'s2','reapertura post reseteo');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RK-6 reabrir solicitud de periodo anterior no toca ranking del periodo nuevo (LEG002 = 2, no 0)', t.q('select ranking_horas from empleados where legajo=''LEG002''')::numeric=2 and t.q('select ranking_horas from empleados where legajo=''LEG003''')::numeric=3);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('INV-6 invariante ranking tras reseteo y operaciones', t.q('select count(*) from empleados e where e.ranking_horas <> coalesce((select sum(se.total_horas) from solicitud_empleados se, configuracion_general cg where se.empleado_id=e.id and se.estado_registro=''ACTIVO'' and se.estado_aprobacion=''APROBADO'' and cg.id=1 and (cg.ultimo_reseteo_ranking is null or se.fecha_hora_aprobacion > cg.ultimo_reseteo_ranking)),0)')::int = 0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('RK-7 usuario comun no puede ejecutar el reseteo', 'select fn_resetear_ranking_si_corresponde()', 'permission denied');
select t.fails('RK-8 usuario comun no puede ejecutar el helper de ranking', 'select fn_revertir_ranking_si_aprobado(gen_random_uuid())', 'permission denied');
\echo '=== PRIVILEGIOS Y RLS ==='
reset role; select set_config('request.jwt.uid','',false); set role anon; select t.sesion('','anon');
select t.fails('PR-1 anon no lee solicitudes', 'select count(*) from solicitudes', 'permission denied');
select t.fails('PR-2 anon no lee usuarios', 'select count(*) from usuarios', 'permission denied');
select t.fails('PR-3 anon no ejecuta RPC', 'select rpc_crear_solicitud(null,null,null,now(),now(),null)', 'permission denied');
select t.fails('PR-4 anon no ejecuta helpers fn_es_admin', 'select fn_es_admin()', 'permission denied');
select t.passes('PR-5 anon SI lee configuracion_apariencia (login)','select count(*) from configuracion_apariencia');
select t.fails('PR-6 anon no escribe configuracion_apariencia', 'update configuracion_apariencia set nombre_empresa=''x''', 'permission denied');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('PR-7 authenticated no lee contador_solicitudes', 'select count(*) from contador_solicitudes', 'permission denied');
select t.fails('PR-8 authenticated no inserta directo en solicitudes', 'insert into solicitudes(solicitante_id,area_id,sector_id,proceso_id,fecha_hora_inicio,fecha_hora_fin,motivo_id) values (auth.uid(),null,null,null,now(),now()+interval ''1 h'',null)', 'permission denied');
select t.fails('PR-9 authenticated no actualiza directo solicitud_empleados', 'update solicitud_empleados set total_horas=999', 'permission denied');
select t.fails('PR-10 authenticated no borra directo solicitud_empleado_detalle', 'delete from solicitud_empleado_detalle', 'permission denied');
select t.fails('PR-11 no admin no escribe areas (RLS)', 'insert into areas(nombre) values (''X'')', 'row-level security');
select t.fails('PR-12 no admin no puede modificar roles', 'update roles set descripcion=''x''', 'permission denied');
select t.fails('PR-13 no admin no ejecuta fn_calcular_detalle directo', 'select fn_calcular_detalle_solicitud_empleado(gen_random_uuid())', 'permission denied');
select t.fails('PR-14 no admin no ejecuta fn_registrar_evento_negocio directo', 'select fn_registrar_evento_negocio(''X'',''X'',gen_random_uuid(),''X'',''BASICA'')', 'permission denied');
select t.ok('PR-15 no admin ve 0 filas de auditoria', t.qi('select count(*) from auditoria')::int=0);
select t.ok('PR-16 no admin ve 0 filas de auditoria_negocio', t.qi('select count(*) from auditoria_negocio')::int=0);
select t.ok('PR-17 U2 ve solicitudes de su area', t.qi('select count(*) from solicitudes')::int>0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000006',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000006','authenticated');
select t.ok('PR-18 U6 (Area2) ve 0 solicitudes y 0 empleados de Area1', t.qi('select count(*) from solicitudes')::int=0 and t.qi('select count(*) from empleados where area_id=''10000000-0000-0000-0000-000000000001''')::int=0);
select t.ok('PR-19 U6 no ve solicitud_empleados ni detalle de Area1', t.qi('select count(*) from solicitud_empleados')::int=0 and t.qi('select count(*) from solicitud_empleado_detalle')::int=0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.ok('PR-20 vista_solicitudes_resumen accesible y con solicitante_nombre (join a usuarios bajo RLS no pierde filas)', t.qi('select count(*) from vista_solicitudes_resumen')::int = t.qi('select count(*) from solicitudes')::int and t.qi('select count(*) from vista_solicitudes_resumen where solicitante_nombre is null')::int=0 and t.qi('select count(*) from vista_solicitudes_resumen')::int>0);
select t.ok('PR-21 vista_empleados_resumen y vista_solicitud_empleados_detalle accesibles', t.qi('select count(*) from vista_empleados_resumen')::int>0 and t.qi('select count(*) from vista_solicitud_empleados_detalle')::int>0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select t.ok('PR-22 U3 (aprobador Area1) ve en usuarios: el mismo + solicitantes de lo que ve (U2)', t.qi('select string_agg(nombre_completo, '','' order by nombre_completo) from usuarios')='Aprobador Area1,Control Ingreso TODO,Responsable Area1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000006',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000006','authenticated');
select t.ok('PR-23 U6 ve solo su propia fila de usuarios', t.qi('select string_agg(nombre_completo,'','') from usuarios')='Responsable Area2');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000005',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000005','authenticated');
select t.ok('PR-24 U5 ve solo su propia fila de usuarios', t.qi('select string_agg(nombre_completo,'','') from usuarios')='Consulta sin permisos');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.ok('PR-25 admin ve las 8 filas de usuarios', t.qi('select count(*) from usuarios')::int=8);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000005',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000005','authenticated');
select t.ok('PR-26 U5 ve solo su rol (CONSULTA) en roles', t.qi('select string_agg(nombre,'','') from roles')='CONSULTA');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.ok('PR-27 U2 ve solo su rol en usuario_roles/usuario_permisos/usuario_permiso_scopes', t.qi('select count(*) from usuario_roles')::int=1 and t.qi('select count(*) from usuario_permisos')::int=1 and t.qi('select count(*) from usuario_permiso_scopes')::int=2);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.ok('PR-28 admin ve todos los roles (7)', t.qi('select count(*) from roles')::int=7);
select t.passes('PR-29 admin si escribe areas', 'insert into areas(nombre) values (''AreaNueva'')');
select t.passes('PR-30 admin ve auditoria', 'select count(*) from auditoria');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000004',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000004','authenticated');
select t.fails('PR-31 RRHH (sin bypass admin) no escribe areas', 'insert into areas(nombre) values (''X2'')', 'row-level security');
select t.ok('PR-32 RRHH (visibilidad TODO) ve empleados de ambas areas', t.qi('select count(distinct area_id) from empleados')::int=2);
\echo '=== V2.1 NUEVAS: PREPARACION ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
insert into empleados(id,legajo,nombre_completo,categoria_id,area_id,sector_id,proceso_id) values ('60000000-0000-0000-0000-000000000111','LEG011','Empleado 11','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000112','LEG012','Empleado 12','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000113','LEG013','Empleado 13','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000114','LEG014','Empleado 14','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000115','LEG015','Empleado 15','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),('60000000-0000-0000-0000-000000000116','LEG016','Empleado 16','40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
select t.require((select count(*) from empleados where legajo in ('LEG011','LEG012','LEG013','LEG014','LEG015','LEG016'))=6,'6 empleados nuevos');
\echo '=== V2.1 NUEVAS: USUARIOS INACTIVOS ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-20 08:00-03'::timestamptz,'2026-10-20 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as si1 \gset
select rpc_agregar_empleado(:'si1','60000000-0000-0000-0000-000000000111');
select rpc_enviar_a_aprobacion(:'si1');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'si1','60000000-0000-0000-0000-000000000111','ACTIVO')) as se_si1 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-21 08:00-03'::timestamptz,'2026-10-21 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as si2 \gset
select rpc_agregar_empleado(:'si2','60000000-0000-0000-0000-000000000112');
select rpc_enviar_a_aprobacion(:'si2');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'si2','60000000-0000-0000-0000-000000000112','ACTIVO')) as se_si2 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-22 08:00-03'::timestamptz,'2026-10-22 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as si3 \gset
select rpc_agregar_empleado(:'si3','60000000-0000-0000-0000-000000000113');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('IN-0a PRE si1 EN_APROBACION con LEG011 pendiente', t.q(format('select situacion from solicitudes where id=%L', :'si1')) = 'EN_APROBACION' and t.q(format('select estado_aprobacion::text from solicitud_empleados where id=%L', :'se_si1'))='PENDIENTE_APROBACION');
select t.ok('IN-0b PRE si2 APROBADA (motivo sin aprobacion), si3 BORRADOR', t.q(format('select situacion from solicitudes where id=%L', :'si2')) = 'APROBADA' and t.q(format('select situacion from solicitudes where id=%L', :'si3')) = 'BORRADOR');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.passes('IN-0c PRE (control positivo) U8 activo SI registra control de ingreso en si2', format('select rpc_registrar_control_ingreso(%L,''INGRESO_REGISTRADO'')', :'se_si2'));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.q('select count(*) from solicitudes') as n_sol_activo \gset
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.require(:n_sol_activo::int > 0,'U2 activo ve solicitudes');
update usuarios set activo = false where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000008');
select t.require((select count(*) from usuarios where not activo)=4,'4 usuarios desactivados');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('IN-1 inactivo (responsable con permisos) NO crea solicitud', format('select rpc_crear_solicitud(%L,%L,%L,now(),now()+interval ''2 hours'',%L,''x'')','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'), 'inactivo');
select t.fails('IN-2 inactivo NO agrega empleado', format('select rpc_agregar_empleado(%L,%L)', :'si3','60000000-0000-0000-0000-000000000114'), 'inactivo');
select t.fails('IN-3 inactivo NO modifica observacion', format('select rpc_modificar_observacion(%L,''x'')', :'si3'), 'inactivo');
select t.fails('IN-4 inactivo NO modifica fechas', format('select rpc_modificar_fechas(%L,''2026-10-22 08:00-03''::timestamptz,''2026-10-22 10:00-03''::timestamptz)', :'si3'), 'inactivo');
select t.fails('IN-5 inactivo NO modifica motivo', format('select rpc_modificar_motivo(%L,%L)', :'si3','50000000-0000-0000-0000-000000000002'), 'inactivo');
select t.fails('IN-6 inactivo NO envia a aprobacion', format('select rpc_enviar_a_aprobacion(%L)', :'si3'), 'inactivo');
select t.fails('IN-7 inactivo NO elimina borrador', format('select rpc_eliminar_borrador(%L)', :'si3'), 'inactivo');
select t.fails('IN-8 inactivo NO quita empleado', format('select rpc_quitar_empleado(%L)', :'se_si1'), 'inactivo');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000003',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000003','authenticated');
select t.fails('IN-9 inactivo (aprobador) NO aprueba empleado', format('select rpc_aprobar_empleado(%L)', :'se_si1'), 'inactivo');
select t.fails('IN-10 inactivo NO aprueba masivo', format('select rpc_aprobar_masivo(%L)', :'si1'), 'inactivo');
select t.fails('IN-11 inactivo NO rechaza empleado', format('select rpc_rechazar_empleado(%L,''x'')', :'se_si1'), 'inactivo');
select t.fails('IN-12 inactivo NO rechaza masivo', format('select rpc_rechazar_masivo(%L,''x'')', :'si1'), 'inactivo');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('IN-13 inactivo (control_ingreso + visibilidad TODO) NO registra control de ingreso', format('select rpc_registrar_control_ingreso(%L,''NO_PRESENTADO'')', :'se_si2'), 'inactivo');
select t.fails('IN-14 inactivo NO quita control de ingreso', format('select rpc_quitar_control_ingreso(%L)', :'se_si2'), 'inactivo');
select t.fails('IN-15 inactivo NO finaliza solicitud', format('select rpc_finalizar_solicitud(%L)', :'si2'), 'inactivo');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('IN-16 inactivo (ADMIN) NO cancela', format('select rpc_cancelar_solicitud(%L,''x'')', :'si1'), 'inactivo');
select t.fails('IN-17 inactivo (ADMIN) NO rectifica ranking', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', :'se_si2'), 'inactivo');
select t.fails('IN-18 inactivo (ADMIN) NO reabre', format('select rpc_reabrir_solicitud(%L,''x'')', :'si2'), 'inactivo');
select t.fails('IN-19 inactivo (ADMIN) NO escribe tablas maestras (RLS)', 'insert into areas(nombre) values (''AreaX'')', 'row-level security');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.ok('IN-20 inactivo no ve NINGUNA fila (solicitudes, empleados, areas, su propio usuario)', t.qi('select count(*) from solicitudes')::int=0 and t.qi('select count(*) from empleados')::int=0 and t.qi('select count(*) from areas')::int=0 and t.qi('select count(*) from usuarios')::int=0 and t.qi('select count(*) from usuario_permisos')::int=0);
select t.ok('IN-21 helpers de permisos devuelven false para inactivo (aunque conserve permisos)', not fn_puede_ver('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001') and not fn_puede_modificar('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001') and not fn_puede_control_ingreso() and not fn_usuario_activo());
select t.ok('IN-22 fn_permisos_para_scope todo false para inactivo', (select not (puede_ver or puede_modificar or puede_aprobar or puede_reabrir or puede_control_ingreso) from fn_permisos_para_scope('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001')));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.ok('IN-23 ADMIN inactivo: fn_es_admin() = false y no lee auditoria', not fn_es_admin() and t.qi('select count(*) from auditoria_negocio')::int=0);
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('IN-24 los intentos de usuarios inactivos NO cambiaron nada (si1 EN_APROBACION, si3 BORRADOR, si2 APROBADA con control registrado)', t.q(format('select situacion from solicitudes where id=%L', :'si1')) = 'EN_APROBACION' and t.q(format('select situacion from solicitudes where id=%L', :'si3')) = 'BORRADOR' and t.q(format('select situacion from solicitudes where id=%L', :'si2')) = 'APROBADA' and t.q(format('select estado_asistencia::text from solicitud_empleados where id=%L', :'se_si2'))='INGRESO_REGISTRADO');
create function t.rpc_sin_gate() returns text language plpgsql as $f$
declare r record; args text; n int := 0; bad text := '';
begin
  for r in select p.oid, p.proname, p.proargtypes::oid[] as ts from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
           where ns.nspname='public' and p.proname like 'rpc\_%' order by p.proname loop
    n := n + 1;
    select string_agg('null::'||format_type(x.t, null), ',' order by x.o) into args from unnest(r.ts) with ordinality as x(t,o);
    begin
      execute format('select public.%I(%s)', r.proname, coalesce(args,''));
      bad := bad || r.proname || '(sin error) ';
    exception when others then
      if sqlerrm not ilike '%inactivo%' then bad := bad || r.proname || ': ' || sqlerrm || ' | '; end if;
    end;
  end loop;
  return n || '|' || bad;
end $f$;
grant execute on function t.rpc_sin_gate() to authenticated;
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.ok('IN-25 las 22 RPC del esquema rechazan a un usuario inactivo (primer chequeo = usuario activo)', t.qi('select t.rpc_sin_gate()') = '22|');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo = true where id = '00000000-0000-0000-0000-000000000002';
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.passes('IN-26 reactivado, U2 vuelve a poder crear solicitudes', format('select rpc_crear_solicitud(%L,%L,%L,now(),now()+interval ''2 hours'',%L,''x'')','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update usuarios set activo = true where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000008');
select t.require((select count(*) from usuarios where not activo)=0,'todos los usuarios reactivados');
\echo '=== V2.1 NUEVAS: AUDITORIA ENVIAR A APROBACION ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-23 08:00-03'::timestamptz,'2026-10-23 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sa1 \gset
select rpc_agregar_empleado(:'sa1','60000000-0000-0000-0000-000000000113');
select rpc_enviar_a_aprobacion(:'sa1');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-24 08:00-03'::timestamptz,'2026-10-24 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000001','test')).id as sa2 \gset
select rpc_agregar_empleado(:'sa2','60000000-0000-0000-0000-000000000114');
select rpc_enviar_a_aprobacion(:'sa2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('AU-1 motivo SIN aprobacion: la solicitud queda APROBADA (no trabada en EN_APROBACION)', t.q(format('select situacion from solicitudes where id=%L', :'sa1')) = 'APROBADA');
select t.ok('AU-2 el evento SOLICITUD_ENVIADA_A_APROBACION registra la situacion FINAL real (APROBADA)', t.q(format('select estado_nuevo from auditoria_negocio where entidad_id=%L and evento=''SOLICITUD_ENVIADA_A_APROBACION''', :'sa1')) = 'APROBADA' and t.q(format('select count(*) from auditoria_negocio where entidad_id=%L and evento=''SOLICITUD_ENVIADA_A_APROBACION''', :'sa1'))::int = 1);
select t.ok('AU-3 motivo CON aprobacion: situacion y evento = EN_APROBACION', t.q(format('select situacion from solicitudes where id=%L', :'sa2')) = 'EN_APROBACION' and t.q(format('select estado_nuevo from auditoria_negocio where entidad_id=%L and evento=''SOLICITUD_ENVIADA_A_APROBACION''', :'sa2')) = 'EN_APROBACION');
\echo '=== V2.1 NUEVAS: CANCELACION ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-25 08:00-03'::timestamptz,'2026-10-25 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sc1 \gset
select rpc_agregar_empleado(:'sc1','60000000-0000-0000-0000-000000000114');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select rpc_enviar_a_aprobacion(:'sc1');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sc1','60000000-0000-0000-0000-000000000114','ACTIVO')) as se_sc1 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_sc1','INGRESO_REGISTRADO');
select rpc_finalizar_solicitud(:'sc1');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG014''')::numeric as b_sc1 \gset
select t.ok('CA-0 PRE sc1 FINALIZADA y LEG014 tiene horas en el ranking (>= 4)', t.q(format('select situacion from solicitudes where id=%L', :'sc1')) = 'FINALIZADA' and :b_sc1::numeric >= 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select rpc_cancelar_solicitud(:'sc1','correccion administrativa');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CA-1 cancelar una FINALIZADA NO descuenta horas del ranking historico/actual', t.q(format('select situacion from solicitudes where id=%L', :'sc1')) = 'CANCELADA' and t.q('select ranking_horas from empleados where legajo=''LEG014''')::numeric = :b_sc1);
select t.ok('CA-2 el evento de cancelacion deja constancia ranking_revertido=false', t.q(format('select (datos->>''ranking_revertido'') from auditoria_negocio where entidad_id=%L and evento=''SOLICITUD_CANCELADA''', :'sc1')) = 'false');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-26 08:00-03'::timestamptz,'2026-10-26 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sc2 \gset
select rpc_agregar_empleado(:'sc2','60000000-0000-0000-0000-000000000115');
select rpc_enviar_a_aprobacion(:'sc2');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG015''')::numeric as b_sc2 \gset
select t.ok('CA-3 PRE sc2 APROBADA y LEG015 suma >= 4h', t.q(format('select situacion from solicitudes where id=%L', :'sc2')) = 'APROBADA' and :b_sc2::numeric >= 4);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select rpc_cancelar_solicitud(:'sc2','prueba');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('CA-4 cancelar una APROBADA SI devuelve sus horas (ranking = antes - 4)', t.q(format('select situacion from solicitudes where id=%L', :'sc2')) = 'CANCELADA' and t.q('select ranking_horas from empleados where legajo=''LEG015''')::numeric = :b_sc2::numeric - 4);
select t.ok('CA-5 el evento de cancelacion deja constancia ranking_revertido=true', t.q(format('select (datos->>''ranking_revertido'') from auditoria_negocio where entidad_id=%L and evento=''SOLICITUD_CANCELADA''', :'sc2')) = 'true');
\echo '=== V2.1 NUEVAS: RECTIFICACION EXPLICITA ==='
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select (rpc_crear_solicitud('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','2026-10-27 08:00-03'::timestamptz,'2026-10-27 12:00-03'::timestamptz,'50000000-0000-0000-0000-000000000002','test')).id as sr1 \gset
select rpc_agregar_empleado(:'sr1','60000000-0000-0000-0000-000000000116');
select rpc_enviar_a_aprobacion(:'sr1');
select t.q(format('select id from solicitud_empleados where solicitud_id=%L and empleado_id=%L and estado_registro=%L order by created_at desc limit 1', :'sr1','60000000-0000-0000-0000-000000000116','ACTIVO')) as se_sr1 \gset
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select rpc_registrar_control_ingreso(:'se_sr1','INGRESO_REGISTRADO');
select rpc_finalizar_solicitud(:'sr1');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.q('select ranking_horas from empleados where legajo=''LEG016''')::numeric as b_sr1 \gset
select t.ok('RC-0 PRE sr1 FINALIZADA, LEG016 con >= 4h en ranking, 4h consolidadas', t.q(format('select situacion from solicitudes where id=%L', :'sr1')) = 'FINALIZADA' and :b_sr1::numeric >= 4 and t.q(format('select total_horas from solicitud_empleados where id=%L', :'se_sr1'))::numeric = 4 and (select count(*) from ranking_rectificaciones) = 0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('RC-1 usuario con modificacion pero NO admin no puede rectificar', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', :'se_sr1'), 'No tenés permiso');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000008',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000008','authenticated');
select t.fails('RC-2 control_ingreso + visibilidad TODO (no admin) no puede rectificar', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', :'se_sr1'), 'No tenés permiso');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000004',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000004','authenticated');
select t.fails('RC-3 RRHH (sin bypass de admin) no puede rectificar', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', :'se_sr1'), 'No tenés permiso');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('RC-4 el motivo es obligatorio', format('select rpc_rectificar_horas_ranking(%L,1,''   '')', :'se_sr1'), 'motivo');
select t.fails('RC-5 las horas deben ser > 0', format('select rpc_rectificar_horas_ranking(%L,0,''x'')', :'se_sr1'), 'mayores que cero');
select t.fails('RC-6 no puede superar las horas consolidadas (5 > 4)', format('select rpc_rectificar_horas_ranking(%L,5,''x'')', :'se_sr1'), 'superan');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RC-7 los rechazos no cambiaron el ranking ni dejaron trazas', t.q('select ranking_horas from empleados where legajo=''LEG016''')::numeric = :b_sr1 and (select count(*) from ranking_rectificaciones) = 0);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.passes('RC-8 admin rectifica 1.5h de una FINALIZADA', format('select rpc_rectificar_horas_ranking(%L,1.5,''error de carga detectado'')', :'se_sr1'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RC-9 ranking = antes - 1.5 y queda fila de trazabilidad completa', t.q('select ranking_horas from empleados where legajo=''LEG016''')::numeric = :b_sr1::numeric - 1.5 and t.q('select count(*) from ranking_rectificaciones')::int = 1 and (select horas_descontadas = 1.5 and ranking_antes = :b_sr1::numeric and ranking_despues = :b_sr1::numeric - 1.5 and usuario_id = '00000000-0000-0000-0000-000000000001' and motivo = 'error de carga detectado' and solicitud_empleado_id = :'se_sr1' from ranking_rectificaciones));
select t.ok('RC-10 queda evento de auditoria de negocio RANKING_RECTIFICADO', t.q(format('select count(*) from auditoria_negocio where entidad_id=%L and evento=''RANKING_RECTIFICADO''', :'se_sr1'))::int = 1);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('RC-11 acumulado: 1.5 ya rectificadas + 3 > 4 consolidadas: rechazado', format('select rpc_rectificar_horas_ranking(%L,3,''x'')', :'se_sr1'), 'superan');
select t.passes('RC-12 el saldo restante (2.5h) si se puede rectificar', format('select rpc_rectificar_horas_ranking(%L,2.5,''saldo'')', :'se_sr1'));
select t.fails('RC-13 agotadas las horas consolidadas no se rectifica de nuevo', format('select rpc_rectificar_horas_ranking(%L,0.5,''x'')', :'se_sr1'), 'superan');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.ok('RC-14 ranking final = antes - 4 y 2 filas de trazabilidad', t.q('select ranking_horas from empleados where legajo=''LEG016''')::numeric = :b_sr1::numeric - 4 and t.q('select count(*) from ranking_rectificaciones')::int = 2);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.passes('RC-15 solicitud CANCELADA estando FINALIZADA (sc1) SI se puede rectificar', format('select rpc_rectificar_horas_ranking(%L,1,''ajuste post-cancelacion'')', :'se_sc1'));
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('RC-16 solicitud CANCELADA estando APROBADA (sc2) NO se rectifica (el ranking ya se ajusto)', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', t.q(format('select id from solicitud_empleados where solicitud_id=%L', :'sc2'))), 'FINALIZADAS');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('RC-17 solicitud APROBADA (si2, aun sin finalizar) NO se rectifica', format('select rpc_rectificar_horas_ranking(%L,1,''x'')', :'se_si2'), 'FINALIZADAS');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.ok('RC-18 admin ve las rectificaciones; un usuario comun no ve ninguna (RLS)', t.qi('select count(*) from ranking_rectificaciones')::int = 3);
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.ok('RC-19 usuario comun no ve ninguna fila de rectificaciones', t.qi('select count(*) from ranking_rectificaciones')::int = 0);
select t.fails('RC-20 nadie escribe rectificaciones por fuera de la RPC (sin GRANT de escritura)', 'insert into ranking_rectificaciones(solicitud_empleado_id,solicitud_id,empleado_id,horas_descontadas,ranking_antes,ranking_despues,motivo,usuario_id) select id,solicitud_id,empleado_id,1,0,0,''x'',''00000000-0000-0000-0000-000000000001'' from solicitud_empleados limit 1', 'permission denied');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select coalesce(ultimo_reseteo_ranking::text,'') as v_reset_old from configuracion_general where id=1 \gset
update configuracion_general set ultimo_reseteo_ranking = now() + interval '1 minute' where id = 1;
select t.require((select ultimo_reseteo_ranking > now() from configuracion_general where id=1), 'reseteo simulado aplicado');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000001',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000001','authenticated');
select t.fails('RC-21 horas de un periodo ya cerrado/archivado NO se rectifican desde la RPC', format('select rpc_rectificar_horas_ranking(%L,0.5,''x'')', :'se_sc1'), 'período');
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set ultimo_reseteo_ranking = nullif(:'v_reset_old','')::timestamptz where id = 1;
select t.require((select ultimo_reseteo_ranking is not distinct from nullif(:'v_reset_old','')::timestamptz from configuracion_general where id=1), 'ultimo_reseteo_ranking restaurado');
\echo '=== V2.1 NUEVAS: ANTIGUEDAD (fechas relativas a now) ==='
update configuracion_general set dias_maximos_antiguedad = 30 where id = 1;
select t.require((select dias_maximos_antiguedad from configuracion_general where id=1)=30,'dias_maximos_antiguedad=30');
select set_config('request.jwt.uid','00000000-0000-0000-0000-000000000002',false); reset role; set role authenticated; select t.sesion('00000000-0000-0000-0000-000000000002','authenticated');
select t.fails('AN-1 inicio hace 31 dias supera dias_maximos_antiguedad=30: rechazado', format('select rpc_crear_solicitud(%L,%L,%L,now()-interval ''31 days'',now()-interval ''31 days''+interval ''2 hours'',%L,''x'')','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'), 'antigüedad');
select t.passes('AN-2 inicio hace 29 dias esta dentro del limite: aceptado', format('select rpc_crear_solicitud(%L,%L,%L,now()-interval ''29 days'',now()-interval ''29 days''+interval ''2 hours'',%L,''x'')','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001'));
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
update configuracion_general set dias_maximos_antiguedad = 36500 where id = 1;
select t.ok('AN-3 fixture restaurado', t.q('select dias_maximos_antiguedad from configuracion_general where id=1')::int = 36500);
\echo '=== RESUMEN ==='
reset role; select set_config('request.jwt.uid','',false); select t.sesion('',null);
select t.resumen(191);
select 'FALLOS: '||coalesce(string_agg(label||' ['||coalesce(detail,'')||']', E'\n'),'ninguno') from t.res where not ok;
