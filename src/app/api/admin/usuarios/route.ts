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

export async function PATCH(req: Request) {
  const g = await exigirAdmin(); if (g.error) return g.error;
  const admin = authAdmin();
  if (!admin) return NextResponse.json({ error: "Falta configurar SUPABASE_SERVICE_ROLE_KEY en el servidor." }, { status: 501 });
  const b = (await req.json().catch(() => null)) as { id?: string; password?: string } | null;
  if (!b?.id || !b.password || b.password.length < 8) return NextResponse.json({ error: "Indicá el usuario y una contraseña de al menos 8 caracteres." }, { status: 400 });
  // Debe ser un usuario que el administrador pueda ver (existe en public.usuarios).
  const { data: u } = await g.sb!.from("usuarios").select("id").eq("id", b.id).maybeSingle();
  if (!u) return NextResponse.json({ error: "Usuario inexistente" }, { status: 404 });
  const { error } = await admin.auth.admin.updateUserById(b.id, { password: b.password });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
