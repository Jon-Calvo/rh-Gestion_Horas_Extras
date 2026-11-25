import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { COOKIE_SESION, estadoSesion } from "@/lib/sesion";

// Refresca la sesión de Supabase y protege todas las rutas salvo /login.
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (list) => {
          list.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    },
  );

  const { data } = await supabase.auth.getClaims();
  const autenticado = !!data?.claims;
  const enLogin = request.nextUrl.pathname.startsWith("/login");

  // Duración de la sesión: sin cookie (se cerró el navegador, o sesión previa a esta función) o vencida => se cierra la sesión.
  if (autenticado && !request.nextUrl.pathname.startsWith("/api/salir") && estadoSesion(request.cookies.get(COOKIE_SESION)?.value) !== "ok") {
    const url = request.nextUrl.clone();
    url.pathname = "/api/salir"; url.search = "";
    return NextResponse.redirect(url);
  }
  if (!autenticado && !enLogin) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }
  if (autenticado && enLogin) {
    const url = request.nextUrl.clone();
    url.pathname = "/";
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)"],
};
