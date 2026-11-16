# Migración 0002 — bandas por día y observación de ingreso

Se ejecuta **una sola vez** en el SQL Editor de tu proyecto Supabase (el que ya tiene la V2.1), **antes** de publicar la versión nueva de la interfaz.

## Qué hace
1. `bandas_horarias`: agrega `dia_desde` y `dia_hasta` (1=lunes … 7=domingo). Las bandas existentes quedan en 1–7 (todos los días), o sea, **todo sigue calculando igual**.
2. El cálculo de horas y el control de superposición de bandas tienen en cuenta los días.
3. `solicitud_empleados.observacion_control_ingreso` y un parámetro opcional `p_observacion` en `rpc_registrar_control_ingreso` (la llamada anterior de 3 parámetros sigue funcionando).
4. `vista_solicitudes_resumen`: nuevas columnas de empleados y horas aprobados / rechazados / pendientes (las columnas existentes no cambian). `vista_solicitud_empleados_detalle`: expone la observación de ingreso.

## Reglas de días (decisiones que tomé; confirmalas)
- `dia_desde`..`dia_hasta` es un rango inclusivo. Si `dia_desde` > `dia_hasta` pasa por el domingo (ej. 6→2 = sáb, dom, lun, mar).
- Una banda que cruza medianoche **pertenece al día en que empieza**: «Extras nocturnas» lunes–viernes 22:00–06:00 cubre del lunes 22:00 al **sábado 06:00**. La madrugada del lunes (00:00–06:00) NO queda cubierta por esa banda: necesitás una banda de domingo 22:00–06:00 para cubrirla.
- Un horario que no cae en ninguna banda activa para su día **se sigue rechazando** con error explícito (ej. sábado 10:00 si no cargaste bandas de sábado). No inventé ninguna banda por omisión.
- Dos bandas activas no pueden superponerse en el mismo día y horario (incluyendo la cola de las que cruzan medianoche).
- Los feriados siguen aplicando `multiplicador_feriado` de la banda que corresponde al día de la semana de esa fecha.

## Cómo ejecutarla
1. Hacé un respaldo (*Database → Backups*) o verificá que tenés uno reciente.
2. SQL Editor → New query → pegá **todo** `0002_bandas_por_dia_y_observacion_ingreso.sql` → Run.
3. Verificá:
```sql
select descripcion, hora_desde, hora_hasta, dia_desde, dia_hasta from bandas_horarias order by hora_desde;   -- todas 1..7
select to_regprocedure('rpc_registrar_control_ingreso(uuid, estado_asistencia_empleado, timestamptz, text)');   -- no nulo
select count(*) from pg_proc where proname = 'rpc_registrar_control_ingreso';                                    -- 1
select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and has_function_privilege('anon', p.oid, 'execute')
  and not exists (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e');   -- 0
```
4. Entrá a la app → Catálogos → Bandas horarias y cargá tus bandas por día. **Primero** editá/desactivá las bandas viejas que se superpongan con las nuevas (el sistema te lo avisa con un error si se pisan).

Ejemplo de carga (descripciones y multiplicadores a tu criterio):
| Banda | Desde | Hasta | Día desde | Día hasta |
|---|---|---|---|---|
| Extras | 18:00 | 22:00 | 1 | 5 |
| Extras nocturnas | 22:00 | 06:00 | 1 | 5 |

## Qué se probó (PostgreSQL 16 local, NO Supabase)
Con `ejecutar_pruebas_locales.sh`: V2.1 + migración → `regresion_v2_1_final.sql` 191/191, `pruebas_control_ingreso_v2_1_final.sql` 53/53 y `pruebas_0002.sql` 47/47 (bandas por día, cruce de medianoche y de semana, superposición, feriado, sábado sin banda, observación, vistas, privilegios). Además: la migración se aplicó dos veces seguidas sin error y, sobre una base con datos, el recálculo de una solicitud existente dio el mismo resultado. Mutaciones ejecutadas: ignorar los días en el motor detiene la suite; no guardar la observación hace fallar 3 pruebas.
**No probado:** comportamiento en Supabase real (el SQL Editor ante un error a mitad de script, PostgREST con la nueva firma de la RPC, JWT reales). El script usa `begin/commit`, por lo que un error no debería dejar cambios parciales, pero no lo verifiqué allí.
La migración elimina **una** función: la firma anterior de `rpc_registrar_control_ingreso` de 3 parámetros (reemplazada por la de 4). No toca datos.
