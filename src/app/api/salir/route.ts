import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { COOKIE_SESION } from "@/lib/sesion";

export const dynamic = "force-dynamic";

// Cierra la sesión (vencida o terminada al cerrar el navegador) y vuelve al ingreso.
export async function GET(request: NextRequest) {
  const sb = await createClient();
  await sb.auth.signOut();
  const url = request.nextUrl.clone();
  url.pathname = "/login"; url.search = "?m=sesion";
  const res = NextResponse.redirect(url);
  res.cookies.set(COOKIE_SESION, "", { path: "/", maxAge: 0 });
  return res;
}
