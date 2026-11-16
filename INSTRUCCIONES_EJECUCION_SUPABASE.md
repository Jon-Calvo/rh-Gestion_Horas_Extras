# Instrucciones de ejecución en Supabase — Horas Extras V2.1

> El esquema se ejecuta **una sola vez**, en un **proyecto Supabase nuevo y limpio**. Estas instrucciones no se probaron contra Supabase real (solo contra PostgreSQL 16 local); ver `INFORME_FINAL_V2_1.md`, sección "Limitaciones".

## 1. Requisitos previos

- Un proyecto Supabase **nuevo**, sin tablas propias en el schema `public`. No lo ejecutes sobre el proyecto operativo de la versión anterior.
- Acceso al **SQL Editor** del proyecto (corre como el rol `postgres`).
- Las extensiones `pgcrypto` y `btree_gist` deben poder activarse (el script ejecuta `create extension if not exists`). Si el proyecto las rechaza, activalas antes en *Database → Extensions* y volvé a empezar con un proyecto limpio.
- Un usuario creado en *Authentication → Users* (será el administrador inicial; ver paso 4).
- Haber corrido `ejecutar_pruebas_locales.sh` en tu máquina con PostgreSQL local y ver `TODAS LAS SUITES OK` (opcional pero recomendado; no toca Supabase).

## 2. Instalar el esquema

1. Abrí *SQL Editor → New query*.
2. Pegá **todo** el contenido de `0001_schema_inicial_consolidado_v2_1_SUPABASE.sql` y ejecutalo con *Run* **una vez**.
3. No ejecutes ningún otro archivo de este paquete en Supabase. `regresion_v2_1_final.sql`, `pruebas_control_ingreso_v2_1_final.sql`, `ejecutar_pruebas_locales.sh` y `local_stubs/` son **solo para PostgreSQL local**.

El archivo no contiene `DROP` ni `TRUNCATE`.

## 3. Verificar que la instalación terminó bien

Ejecutá estas consultas (SQL Editor). Resultados esperados, medidos en PostgreSQL 16 local:

```sql
-- 29 tablas, sin ninguna sin RLS
select count(*) as tablas from information_schema.tables where table_schema='public' and table_type='BASE TABLE';
select relname from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity;   -- 0 filas

-- 7 roles
select count(*) from roles;                                                                    -- 7

-- tabla de rectificaciones y función de usuario activo presentes
select to_regclass('public.ranking_rectificaciones'), to_regprocedure('public.fn_usuario_activo()');  -- ambos no nulos

-- anon no ejecuta ninguna función de public
select count(*) from pg_proc where pronamespace='public'::regnamespace and has_function_privilege('anon', oid, 'execute');   -- 0

-- las funciones SECURITY DEFINER propias tienen search_path fijo
select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%');          -- 0
```

Si alguna no coincide, **no sigas**: ver el apartado 7.

## 4. Crear o verificar el administrador inicial

El esquema no siembra usuarios (`usuarios.id` referencia a `auth.users`).

1. En *Authentication → Users* creá el usuario (o usá uno existente).
2. En el SQL Editor, reemplazá el email y ejecutá:

```sql
begin;
insert into usuarios (id, nombre_completo, activo)
select id, 'Administrador inicial', true from auth.users where email = 'TU_EMAIL@dominio.com';
insert into usuario_roles (usuario_id, rol_id)
select u.id, r.id from auth.users u cross join roles r
where u.email = 'TU_EMAIL@dominio.com' and r.nombre = 'DESARROLLADOR';
commit;
```

Esto da el rol `DESARROLLADOR` (protegido: no se puede quitar, desactivar ni eliminar; `fn_es_admin()` lo reconoce). Se probó el mismo SQL en PostgreSQL local. Para un administrador común usá el rol `ADMIN` en lugar de `DESARROLLADOR`.

Verificar (debe devolver 1 fila):

```sql
select u.id, u.nombre_completo, u.activo, r.nombre
from usuarios u join usuario_roles ur on ur.usuario_id = u.id join roles r on r.id = ur.rol_id
where r.nombre in ('DESARROLLADOR','ADMIN');
```

## 5. Comprobar autenticación, permisos y RLS

Con la aplicación (o con el cliente Supabase) iniciando sesión con el administrador:

- Un `select` sobre `usuarios` debe devolver filas (administrador) y una sesión **sin** login (anon) no debe leer nada, salvo `configuracion_apariencia`, que es de lectura pública a propósito.
- Un usuario común sin permisos debe ver 0 solicitudes y no poder escribir tablas maestras.
- Un usuario con `usuarios.activo = false` no debe poder ejecutar ninguna operación autenticada (cualquier `rpc_*` devuelve "Usuario inactivo o sin sesión válida").
- Control de Ingreso: un usuario con `control_ingreso = true` y visibilidad `TODO` opera entre áreas; con visibilidad limitada a un área, solo en esa área; no puede aprobar, modificar, reabrir ni crear por tener ese permiso.

Estas comprobaciones **con tokens reales de Supabase no se ejecutaron** en esta entrega; las suites locales simulan la sesión con una variable de configuración (`request.jwt.uid`). Verificalas vos con usuarios de prueba reales en la primera puesta en marcha.

Para probar permisos desde el SQL Editor simulando a un usuario (el rol `postgres` no aplica RLS, hay que cambiar de rol dentro de una transacción). **Este fragmento no se probó en Supabase**: depende de cómo `auth.uid()` lee el JWT en tu proyecto; si no devuelve el UUID, usá usuarios reales desde la aplicación.

```sql
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_DEL_USUARIO>","role":"authenticated"}', true);
set local role authenticated;
select fn_usuario_activo(), fn_es_admin();      -- auth.uid() de Supabase lee request.jwt.claims
select count(*) from solicitudes;
rollback;
```

## 6. Ejecutar las pruebas sin contaminar la base operativa

- Las pruebas **nunca** se ejecutan en el proyecto Supabase. Corren en tu computadora con PostgreSQL 16 local:

  ```bash
  bash ejecutar_pruebas_locales.sh
  ```

  Cada suite usa una base temporal nueva (`horas_extras_test_<hex>`) que el script crea y borra. Conecta **solo por socket UNIX local**, ignora `PGHOST`/`DATABASE_URL`, se niega a correr si el servidor parece Supabase y nunca ejecuta `DROP SCHEMA`.
- Necesita un usuario del servidor local con permiso para crear bases (`LOCAL_PG_USER=postgres`, por ejemplo) y, si el socket no está en `/var/run/postgresql`, `LOCAL_PG_SOCKET_DIR=/ruta/absoluta`.
- Salida esperada: `total=191 PASS=191 FAIL=0` y `total=53 PASS=53 FAIL=0`, y la línea final `TODAS LAS SUITES OK (PostgreSQL local; NO equivale a verificar Supabase real)`.
- Si necesitás datos de prueba en Supabase, usá un **segundo proyecto desechable**, nunca el operativo.

## 7. Qué hacer ante un error

- **No vuelvas a pegar el script completo ni ejecutes partes sueltas** sobre un proyecto donde ya falló: el estado puede haber quedado parcial (no verifiqué cómo trata el SQL Editor de Supabase un script multi-sentencia que falla a mitad).
- Copiá el mensaje de error **completo** y la línea indicada.
- Reproducí el problema primero en local con `ejecutar_pruebas_locales.sh` (se detiene en el primer error real y muestra cuál).
- Descartá ese proyecto (o restablecelo) y empezá de nuevo en un proyecto limpio con el SQL corregido. No hay migraciones parciales ni parches separados.
