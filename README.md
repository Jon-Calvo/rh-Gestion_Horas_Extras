# Horas Extras — Interfaz web (Next.js + Supabase + Vercel)

Interfaz para el esquema **Horas Extras V2.1**. Toda la lógica de negocio vive en la base (22 funciones `rpc_*`, RLS, triggers); la interfaz solo las invoca y muestra los mensajes de error de la base. Los botones que se ven según permisos son una ayuda visual: la autoridad es siempre la base.

## Pantallas
Ingreso · Panel · Solicitudes (lista, nueva, detalle con aprobación por empleado, control de ingreso, reemplazos, rectificación, cronología) · Aprobaciones · Control de ingreso · Empleados (+ importación xlsx/CSV) · Ranking · Usuarios y permisos · Catálogos · Configuración y apariencia · Auditoría. Modo claro / oscuro / según dispositivo; adaptado a PC, tablet y celular.

## Variables de entorno
| Variable | Dónde | Uso |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Vercel (todas) | Project URL de Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Vercel (todas) | Clave anon/publishable |
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel, **solo servidor** (sin prefijo NEXT_PUBLIC) | Crear usuarios y cambiar contraseñas desde «Usuarios». Opcional: sin ella el resto funciona y esa función avisa que falta configurarla. |

## Puesta en marcha local
```bash
cp .env.example .env.local   # completar valores
npm install
npm run dev
```

## Deploy en Vercel
1. Subí esta carpeta a un repositorio de GitHub (el `.gitignore` ya excluye `node_modules`, `.next` y `.env*`).
2. Vercel → *Add New Project* → importá el repo (Framework: Next.js, detectado solo).
3. En *Environment Variables* cargá las tres variables de arriba y desplegá.
4. Supabase → *Authentication → URL Configuration*: poné la URL de Vercel como *Site URL*.
5. Ingresá con el usuario DESARROLLADOR que creaste. Desde «Usuarios y permisos» das de alta al resto.

## Qué se verificó y qué no
- Verificado: `tsc` sin errores y `next build` exitoso; capturas de la pantalla de ingreso en claro/oscuro y en ancho de celular.
- **No verificado**: funcionamiento contra tu Supabase real (login, RPC, RLS, importación, alta de usuarios), ni el resto de las pantallas renderizadas con datos. Hacé una pasada con usuarios de prueba (admin, aprobador, control de ingreso, sin permisos, inactivo) antes de usarlo en producción.
- Los tipos de `src/lib/types.ts` están escritos a mano según el esquema; si cambia el esquema, actualizarlos.
