// Duración de la sesión. La cookie `he_sesion` se escribe al iniciar sesión con: "<inicio_ms>.<horas_máximas|0>.<cerrar_al_salir 1|0>".
// El proxy la revisa en cada pedido. Para un corte estricto del lado del servidor, Supabase ofrece además
// "Time-box user sessions" en Authentication → Sessions (plan Pro).
export const COOKIE_SESION = "he_sesion";
const CASI_SIN_LIMITE = 400 * 24 * 3600; // segundos: la cookie dura lo que dure la sesión de Supabase

export function valorCookieSesion(horasMax: number | null | undefined, cerrarAlSalir: boolean, ahora = Date.now()): string {
  return `${ahora}.${horasMax && horasMax > 0 ? Math.floor(horasMax) : 0}.${cerrarAlSalir ? 1 : 0}`;
}
/** Atributos de la cookie: sin Max-Age (cookie de sesión del navegador) si debe cerrarse al salir; si no, dura lo que la duración máxima. */
export function atributosCookieSesion(horasMax: number | null | undefined, cerrarAlSalir: boolean): string {
  if (cerrarAlSalir) return "";
  return `; Max-Age=${horasMax && horasMax > 0 ? Math.floor(horasMax) * 3600 : CASI_SIN_LIMITE}`;
}
export type EstadoSesion = "ok" | "sin_cookie" | "vencida";
export function estadoSesion(valor: string | undefined | null, ahora = Date.now()): EstadoSesion {
  if (!valor) return "sin_cookie";
  const m = /^(\d{10,16})\.(\d{1,4})\.([01])$/.exec(valor);
  if (!m) return "sin_cookie";
  const horas = Number(m[2]);
  return horas > 0 && ahora - Number(m[1]) > horas * 3600_000 ? "vencida" : "ok";
}
