-- ============================================================================
-- STUBS SOLO PARA PRUEBAS LOCALES (PostgreSQL local). NO se ejecuta en Supabase:
-- allí los roles y el schema `auth` ya existen. Simula lo mínimo que el esquema
-- necesita: roles anon/authenticated/service_role, auth.users, auth.uid()
-- (lee el GUC request.jwt.uid, que reemplaza al JWT) y los privilegios por
-- defecto de Supabase (tablas y FUNCIONES con acceso para anon/authenticated).
-- ============================================================================
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon')         then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.uid', true), '')::uuid;
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

grant usage on schema public to anon, authenticated, service_role;
-- Defaults de Supabase para objetos creados por el dueño del schema public:
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
