import { NextResponse } from "next/server";
import { createClient as createAdminClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

// Alta de usuarios y reseteo de contraseña. Requiere SUPABASE_SERVICE_ROLE_KEY (solo servidor).
// La autorización real es doble: acá se exige fn_es_admin() y, además, la base (RLS/triggers) valida cada escritura.

async function exigirAdmin() {
  const sb = await createClient();
  const { data: u } = await sb.auth.getUser();
  if (!u.user) return { error: NextResponse.json({ error: "No autenticado" }, { status: 401 }) };
  const { data: esAdmin } = await sb.rpc("fn_es_admin");
  if (esAdmin !== true) return { error: NextResponse.json({ error: "Solo administradores" }, { status: 403 }) };
  return { sb };
}
// Un administrador común no puede tocar las credenciales (e-mail / contraseña) de un DESARROLLADOR: sería una vía para tomar su cuenta.
async function protegido(sb: Awaited<ReturnType<typeof createClient>>, objetivo: string): Promise<boolean> {
  const { data: soyDev } = await sb.rpc("fn_es_desarrollador");
  if (soyDev === true) return false;
  const { data: roles } = await sb.from("usuario_roles").select("roles(nombre)").eq("usuario_id", objetivo);
  return (roles ?? []).some((r) => (r as unknown as { roles: { nombre: string } | null }).roles?.nombre === "DESARROLLADOR");
}
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function authAdmin() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createAdminClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export async function POST(req: Request) {
  const g = await exigirAdmin(); if (g.error) return g.error;
  const admin = authAdmin();
  if (!admin) return NextResponse.json({ error: "Falta configurar SUPABASE_SERVICE_ROLE_KEY en el servidor." }, { status: 501 });
  const b = (await req.json().catch(() => null)) as { email?: string; password?: string; nombre?: string; roles?: string[] } | null;
  const email = b?.email?.trim().toLowerCase(), nombre = b?.nombre?.trim(), password = b?.password;
  if (!email || !nombre || !password || password.length < 8) return NextResponse.json({ error: "Email, nombre y una contraseña de al menos 8 caracteres son obligatorios." }, { status: 400 });

  const { data: nuevo, error: e1 } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (e1 || !nuevo.user) return NextResponse.json({ error: e1?.message ?? "No se pudo crear el usuario" }, { status: 400 });
  const id = nuevo.user.id;

  const deshacer = async (msg: string) => { await admin.auth.admin.deleteUser(id); return NextResponse.json({ error: msg }, { status: 400 }); };
  const { error: e2 } = await g.sb!.from("usuarios").insert({ id, nombre_completo: nombre, activo: true });
  if (e2) return deshacer(e2.message);
  const { error: e3 } = await g.sb!.from("usuario_permisos").insert({ usuario_id: id });
  if (e3) return deshacer(e3.message);
  const roles = (b?.roles ?? []).filter((r) => r !== "DESARROLLADOR");
  if (roles.length) {
    const { data: rr } = await g.sb!.from("roles").select("id, nombre").in("nombre", roles);
    const { error: e4 } = await g.sb!.from("usuario_roles").insert((rr ?? []).map((r: { id: string }) => ({ usuario_id: id, rol_id: r.id })));
    if (e4) return deshacer(e4.message);
  }
  return NextResponse.json({ id });
}

export async function GET(req: Request) {
  const g = await exigirAdmin(); if (g.error) return g.error;
  const admin = authAdmin();
  if (!admin) return NextResponse.json({ error: "Falta configurar SUPABASE_SERVICE_ROLE_KEY en el servidor." }, { status: 501 });
  const id = new URL(req.url).searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Falta el usuario" }, { status: 400 });
  const { data: u } = await g.sb!.from("usuarios").select("id").eq("id", id).maybeSingle();
  if (!u) return NextResponse.json({ error: "Usuario inexistente" }, { status: 404 });
  const { data, error } = await admin.auth.admin.getUserById(id);
  if (error || !data.user) return NextResponse.json({ error: error?.message ?? "No se encontró la cuenta de acceso" }, { status: 404 });
  return NextResponse.json({ email: data.user.email ?? "", protegido: await protegido(g.sb!, id) });
}

export async function PATCH(req: Request) {
  const g = await exigirAdmin(); if (g.error) return g.error;
  const admin = authAdmin();
  if (!admin) return NextResponse.json({ error: "Falta configurar SUPABASE_SERVICE_ROLE_KEY en el servidor." }, { status: 501 });
  const b = (await req.json().catch(() => null)) as { id?: string; password?: string; email?: string } | null;
  if (!b?.id || (b.password === undefined && b.email === undefined)) return NextResponse.json({ error: "Indicá el usuario y qué cambiar." }, { status: 400 });
  if (b.password !== undefined && b.password.length < 8) return NextResponse.json({ error: "La contraseña debe tener al menos 8 caracteres." }, { status: 400 });
  const email = b.email?.trim().toLowerCase();
  if (b.email !== undefined && (!email || !EMAIL.test(email))) return NextResponse.json({ error: "El e-mail no es válido." }, { status: 400 });
  // Debe ser un usuario que el administrador pueda ver (existe en public.usuarios).
  const { data: u } = await g.sb!.from("usuarios").select("id").eq("id", b.id).maybeSingle();
  if (!u) return NextResponse.json({ error: "Usuario inexistente" }, { status: 404 });
  if (await protegido(g.sb!, b.id)) return NextResponse.json({ error: "Solo un usuario DESARROLLADOR puede cambiar el e-mail o la contraseña de otro DESARROLLADOR." }, { status: 403 });
  const cambios: { password?: string; email?: string; email_confirm?: boolean } = {};
  if (b.password !== undefined) cambios.password = b.password;
  if (email) { cambios.email = email; cambios.email_confirm = true; }
  const { error } = await admin.auth.admin.updateUserById(b.id, cambios);
  if (error) return NextResponse.json({ error: /already|registered|exists/i.test(error.message) ? "Ya existe otra cuenta con ese e-mail." : error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
