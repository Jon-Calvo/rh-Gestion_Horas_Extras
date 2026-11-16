# Migración 0003 — segundo logo y segundo nombre

1. Supabase → SQL Editor → pegá el contenido de `0003_segundo_logo_y_nombre.sql` → Run.
2. Resultado esperado: "Success". Solo agrega dos columnas opcionales a `configuracion_apariencia`; no toca datos.
3. Es idempotente: si la ejecutás dos veces no pasa nada.
4. Después, en la web: Administración → Configuración → Apariencia, completá «Nombre 2» y «URL del logo 2».

Probada solo en PostgreSQL 16 local (6 pruebas propias + las 291 anteriores, todas PASS). No equivale a una verificación en Supabase real.
