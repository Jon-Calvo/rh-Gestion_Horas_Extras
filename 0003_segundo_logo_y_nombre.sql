-- ============================================================================
-- Horas Extras — MIGRACIÓN 0003 (sobre V2.1 + 0002 ya instaladas)
--   Segundo logo y segundo nombre de empresa en configuracion_apariencia.
-- Solo agrega dos columnas opcionales (nullable). No toca datos ni políticas:
-- las políticas RLS y el trigger de auditoría existentes ya cubren la tabla completa.
-- Idempotente: se puede ejecutar más de una vez.
-- ============================================================================
begin;

do $chk$
begin
  if to_regclass('public.configuracion_apariencia') is null then
    raise exception 'Esta migración requiere la V2.1 instalada';
  end if;
end
$chk$;

alter table configuracion_apariencia add column if not exists logo_url_secundario text;
alter table configuracion_apariencia add column if not exists nombre_empresa_secundario text;

comment on column configuracion_apariencia.logo_url_secundario is 'Segundo logo (p. ej. el de la empresa que usa la app, si el primero es el del proyecto).';
comment on column configuracion_apariencia.nombre_empresa_secundario is 'Segundo nombre de empresa, opcional.';

commit;
