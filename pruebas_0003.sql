\set ON_ERROR_STOP on
\pset pager off
\pset tuples_only on
create schema t;
create table t.res(n serial, label text, ok boolean, detail text);
create function t.ok(p_label text, p_cond boolean, p_detail text default null) returns void language plpgsql as $f$
begin insert into t.res(label,ok,detail) values (p_label, coalesce(p_cond,false), p_detail);
 raise notice '% : %', case when coalesce(p_cond,false) then 'PASS' else 'FAIL' end, p_label; end $f$;
create function t.resumen(p_esperado int) returns void language plpgsql as $f$
declare tot int; ps int; fl int; begin select count(*), count(*) filter (where ok), count(*) filter (where not ok) into tot, ps, fl from t.res;
 raise notice 'RESUMEN total=% PASS=% FAIL=% esperado=%', tot, ps, fl, p_esperado; end $f$;

select t.ok('M3-1 existen las dos columnas nuevas, tipo text y nullable',
  (select count(*) from information_schema.columns where table_name='configuracion_apariencia' and column_name in ('logo_url_secundario','nombre_empresa_secundario') and data_type='text' and is_nullable='YES') = 2);
select t.ok('M3-2 la fila singleton existente quedó con ambos valores en NULL',
  (select logo_url_secundario is null and nombre_empresa_secundario is null from configuracion_apariencia where id=1));
update configuracion_apariencia set logo_url_secundario='https://ej.com/l2.png', nombre_empresa_secundario='Empresa 2' where id=1;
select t.ok('M3-3 se pueden guardar y leer', (select logo_url_secundario||'|'||nombre_empresa_secundario from configuracion_apariencia where id=1) = 'https://ej.com/l2.png|Empresa 2');
select t.ok('M3-4 el trigger de auditoría registró el cambio con las columnas nuevas',
  (select count(*) from auditoria where tabla='configuracion_apariencia' and datos_nuevos ? 'logo_url_secundario' and datos_nuevos->>'nombre_empresa_secundario'='Empresa 2') = 1);
select t.ok('M3-5 las políticas RLS de la tabla siguen siendo las mismas (select anon/authenticated + write admin)',
  (select count(*) from pg_policies where tablename='configuracion_apariencia') = 2);
\i /dev/null
-- idempotencia
\i 0003_segundo_logo_y_nombre.sql
select t.ok('M3-6 la migración se puede volver a ejecutar sin error y conserva los datos', (select nombre_empresa_secundario from configuracion_apariencia where id=1) = 'Empresa 2');
select t.resumen(6);
