"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Icon } from "./icons";

export interface NavItem { href: string; label: string; icon: string; grupo: string }
type Tema = "claro" | "oscuro" | "sistema";

function aplicarTema(t: Tema) {
  const oscuro = t === "oscuro" || (t === "sistema" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.setAttribute("data-theme", oscuro ? "dark" : "light");
}

export function ThemeToggle() {
  const [tema, setTema] = useState<Tema>("sistema");
  useEffect(() => {
    try {
      const t = localStorage.getItem("theme") as Tema | null;
      if (t === "claro" || t === "oscuro" || t === "sistema") setTema(t);
      else {
        const d = document.documentElement.getAttribute("data-tema-defecto");
        setTema(d === "CLARO" ? "claro" : d === "OSCURO" ? "oscuro" : "sistema");
      }
    } catch { /* almacenamiento no disponible */ }
  }, []);
  useEffect(() => {
    aplicarTema(tema);
    if (tema !== "sistema") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const h = () => aplicarTema("sistema");
    mq.addEventListener("change", h);
    return () => mq.removeEventListener("change", h);
  }, [tema]);
  const elegir = (t: Tema) => { setTema(t); try { localStorage.setItem("theme", t); } catch { /* ignorar */ } };
  const opciones: { v: Tema; icon: string; label: string }[] = [{ v: "claro", icon: "sun", label: "Claro" }, { v: "sistema", icon: "cog", label: "Sistema" }, { v: "oscuro", icon: "moon", label: "Oscuro" }];
  return (
    <div className="inline-flex rounded-xl border p-0.5 bg-surface-2" role="radiogroup" aria-label="Tema">
      {opciones.map((o) => (
        <button key={o.v} role="radio" aria-checked={tema === o.v} title={o.label} onClick={() => elegir(o.v)}
          className={`h-8 w-8 grid place-items-center rounded-lg transition ${tema === o.v ? "bg-surface shadow text-primary" : "text-muted hover:text-fg"}`}>
          <Icon name={o.icon} size={15} />
        </button>
      ))}
    </div>
  );
}

export function AppShell({ nav, nombre, roles, empresa, logoUrl, children }: { nav: NavItem[]; nombre: string; roles: string[]; empresa: string; logoUrl: string | null; children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [colapsado, setColapsado] = useState(false);
  useEffect(() => setAbierto(false), [pathname]);
  useEffect(() => { try { setColapsado(localStorage.getItem("nav-colapsado") === "1"); } catch { /* ignorar */ } }, []);
  const toggleColapsado = () => setColapsado((c) => { try { localStorage.setItem("nav-colapsado", c ? "0" : "1"); } catch { /* ignorar */ } return !c; });

  const salir = async () => { await createClient().auth.signOut(); router.replace("/login"); router.refresh(); };
  const activo = (href: string) => (href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(href + "/"));
  const grupos = Array.from(new Set(nav.map((n) => n.grupo)));
  const iniciales = nombre.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase()).join("");

  const Menu = (
    <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-5" aria-label="Principal">
      {grupos.map((g) => (
        <div key={g}>
          {g && !colapsado && <div className="px-3 mb-1.5 text-[0.68rem] font-semibold uppercase tracking-wider text-muted">{g}</div>}
          <ul className="space-y-0.5">
            {nav.filter((n) => n.grupo === g).map((n) => (
              <li key={n.href}>
                <Link href={n.href} title={colapsado ? n.label : undefined} aria-current={activo(n.href) ? "page" : undefined}
                  className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition ${activo(n.href) ? "bg-primary text-white shadow-sm" : "text-muted hover:bg-surface-2 hover:text-fg"} ${colapsado ? "justify-center" : ""}`}>
                  <Icon name={n.icon} /><span className={colapsado ? "sr-only" : ""}>{n.label}</span>
                </Link>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
  const Marca = (
    <div className={`flex items-center gap-2.5 px-4 h-16 border-b ${colapsado ? "justify-center" : ""}`}>
      {logoUrl ? /* eslint-disable-next-line @next/next/no-img-element */ <img src={logoUrl} alt="" className="h-8 w-8 rounded-lg object-contain" /> : <div className="h-8 w-8 rounded-lg bg-primary text-white grid place-items-center font-bold text-sm">HE</div>}
      {!colapsado && <div className="leading-tight min-w-0"><div className="font-bold text-sm truncate">{empresa}</div><div className="text-[0.7rem] text-muted">Horas extras</div></div>}
    </div>
  );

  return (
    <div className="min-h-dvh">
      <aside className={`hidden lg:flex fixed inset-y-0 left-0 z-30 flex-col bg-surface border-r transition-[width] ${colapsado ? "w-[4.5rem]" : "w-64"}`}>
        {Marca}{Menu}
        <button onClick={toggleColapsado} className="m-3 btn btn-ghost btn-sm justify-center" aria-label={colapsado ? "Expandir menú" : "Contraer menú"}>
          <span className={`transition ${colapsado ? "rotate-180" : ""}`}><Icon name="chevron" size={16} /></span>{!colapsado && "Contraer"}
        </button>
      </aside>

      {abierto && <div className="lg:hidden fixed inset-0 z-40 bg-black/50" onClick={() => setAbierto(false)} aria-hidden />}
      <aside className={`lg:hidden fixed inset-y-0 left-0 z-50 w-72 max-w-[85vw] flex flex-col bg-surface border-r transition-transform ${abierto ? "translate-x-0" : "-translate-x-full"}`} aria-hidden={!abierto}>
        {Marca}{Menu}
      </aside>

      <div className={`transition-[padding] ${colapsado ? "lg:pl-[4.5rem]" : "lg:pl-64"}`}>
        <header className="sticky top-0 z-20 h-16 flex items-center gap-3 px-4 sm:px-6 bg-bg/85 backdrop-blur border-b">
          <button className="lg:hidden btn btn-ghost btn-sm" onClick={() => setAbierto(true)} aria-label="Abrir menú"><Icon name="menu" size={20} /></button>
          <div className="flex-1" />
          <ThemeToggle />
          <div className="flex items-center gap-2.5 pl-2 border-l">
            <div className="h-8 w-8 rounded-full bg-accent/20 text-accent grid place-items-center text-xs font-bold">{iniciales || "?"}</div>
            <div className="hidden sm:block leading-tight max-w-44">
              <div className="text-sm font-semibold truncate">{nombre}</div>
              <div className="text-[0.7rem] text-muted truncate">{roles.join(" · ") || "Sin rol"}</div>
            </div>
            <button onClick={salir} className="btn btn-ghost btn-sm" title="Cerrar sesión" aria-label="Cerrar sesión"><Icon name="logout" /></button>
          </div>
        </header>
        <main className="p-4 sm:p-6 max-w-[1500px] mx-auto fade-in">{children}</main>
      </div>
    </div>
  );
}
