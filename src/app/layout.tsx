import type { Metadata, Viewport } from "next";
import "./globals.css";
import { getApariencia } from "@/lib/session";
import { ToastProvider } from "@/components/ui/toast";

export const metadata: Metadata = { title: { default: "Horas Extras", template: "%s · Horas Extras" }, description: "Gestión de solicitudes de horas extras" };
export const viewport: Viewport = {
  width: "device-width", initialScale: 1,
  themeColor: [{ media: "(prefers-color-scheme: light)", color: "#f6f7fb" }, { media: "(prefers-color-scheme: dark)", color: "#0b1020" }],
};

// Aplica el tema antes de pintar (evita el destello). 'sistema' sigue al dispositivo.
const THEME_SCRIPT = `(function(){try{var t=localStorage.getItem('theme');if(!t||t==='sistema'){t=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';}document.documentElement.setAttribute('data-theme',t==='dark'?'dark':'light');}catch(e){}})();`;

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  let ap = null;
  try { ap = await getApariencia(); } catch { /* sin sesión o sin config: se usan los valores por defecto */ }
  const vars: Record<string, string> = {};
  if (ap) {
    vars["--primary"] = ap.color_primario; vars["--primary-hover"] = ap.color_primario_hover; vars["--accent"] = ap.color_acento;
    vars["--success"] = ap.color_exito; vars["--warning"] = ap.color_advertencia; vars["--danger"] = ap.color_error;
  }
  return (
    <html lang="es-AR" suppressHydrationWarning style={vars as React.CSSProperties} data-tema-defecto={ap?.tema_predeterminado ?? "SISTEMA"}>
      <head><script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} /></head>
      <body className="min-h-dvh antialiased"><ToastProvider>{children}</ToastProvider></body>
    </html>
  );
}
