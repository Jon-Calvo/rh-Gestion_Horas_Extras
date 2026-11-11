"use client";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Campo } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { useToast } from "@/components/ui/toast";
import { useRouter } from "next/navigation";
import { mensajeError } from "@/lib/errors";
import { NIVEL_LABEL, ROL_LABEL, type Nivel, type UsuarioPermisos } from "@/lib/types";
import type { Catalogos } from "@/lib/catalogos";

export interface UsuarioFila { id: string; nombre_completo: string; activo: boolean }
export interface RolFila { id: string; nombre: string; descripcion: string | null }
export interface ScopeFila { usuario_id: string; tipo_permiso: "VISIBILIDAD" | "APROBACION" | "MODIFICACION" | "REAPERTURA"; area_id: string | null; sector_id: string | null; proceso_id: string | null }

const TIPOS = [
  { tipo: "VISIBILIDAD" as const, campo: "visibilidad_nivel" as const, nombre: "Ver solicitudes" },
  { tipo: "APROBACION" as const, campo: "aprobacion_nivel" as const, nombre: "Aprobar / rechazar" },
  { tipo: "MODIFICACION" as const, campo: "modificacion_nivel" as const, nombre: "Crear y modificar" },
  { tipo: "REAPERTURA" as const, campo: "reapertura_nivel" as const, nombre: "Reabrir" },
];
const NIVELES: Nivel[] = ["NADA", "TODO", "AREA", "SECTOR", "PROCESO"];
const BOOLS: { k: keyof UsuarioPermisos; t: string; d: string }[] = [
  { k: "control_ingreso", t: "Control de ingreso", d: "Registrar y finalizar, dentro de su alcance de visibilidad." },
  { k: "puede_quitar_control_ingreso", t: "Quitar control de ingreso", d: "Solo si además está habilitado en la configuración general." },
  { k: "puede_ver_importes", t: "Ver importes", d: "Valores en dinero de las solicitudes." },
  { k: "puede_eliminar_cancelar", t: "Eliminar y cancelar", d: "Eliminar borradores y cancelar solicitudes." },
  { k: "puede_importar", t: "Gestionar empleados / importar", d: "Alta, edición e importación de empleados." },
  { k: "puede_exportar", t: "Exportar", d: "Descargar listados." },
];

export function UsuariosAdmin({ usuarios, usuarioRoles, roles, permisos, scopes, cat, yo }: { usuarios: UsuarioFila[]; usuarioRoles: { usuario_id: string; rol_id: string }[]; roles: RolFila[]; permisos: UsuarioPermisos[]; scopes: ScopeFila[]; cat: Catalogos; yo: string; puedeCrear: boolean }) {
  const [sel, setSel] = useState<string | null>(null);
  const [nuevo, setNuevo] = useState(false);
  const [q, setQ] = useState("");
  const rolNombre = useMemo(() => Object.fromEntries(roles.map((r) => [r.id, r.nombre])), [roles]);
  const filas = usuarios.filter((u) => !q || u.nombre_completo.toLowerCase().includes(q.toLowerCase()));
  return (
    <>
      <div className="flex gap-3 mb-4"><input className="input sm:max-w-xs" type="search" placeholder="Buscar usuario…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" /><div className="flex-1" /><button className="btn btn-primary" onClick={() => setNuevo(true)}>+ Nuevo usuario</button></div>
      <div className="card overflow-hidden"><div className="overflow-x-auto"><table className="tbl"><thead><tr><th>Usuario</th><th>Roles</th><th>Estado</th><th /></tr></thead>
        <tbody>{filas.map((u) => (
          <tr key={u.id}>
            <td className="font-medium">{u.nombre_completo}{u.id === yo && <span className="text-xs text-muted"> (vos)</span>}</td>
            <td><div className="flex flex-wrap gap-1">{usuarioRoles.filter((x) => x.usuario_id === u.id).map((x) => <Badge key={x.rol_id} tono={rolNombre[x.rol_id] === "DESARROLLADOR" ? "violeta" : "azul"}>{ROL_LABEL[rolNombre[x.rol_id]] ?? rolNombre[x.rol_id]}</Badge>)}</div></td>
            <td><Badge tono={u.activo ? "verde" : "gris"}>{u.activo ? "Activo" : "Inactivo"}</Badge></td>
            <td className="text-right"><button className="btn btn-secondary btn-sm" onClick={() => setSel(u.id)}>Gestionar</button></td>
          </tr>))}</tbody></table></div></div>
      <NuevoUsuario abierto={nuevo} roles={roles} onCerrar={() => setNuevo(false)} />
      {sel && <Editor key={sel} usuario={usuarios.find((u) => u.id === sel)!} roles={roles} rolesDe={usuarioRoles.filter((x) => x.usuario_id === sel).map((x) => x.rol_id)} permisos={permisos.find((p) => p.usuario_id === sel) ?? null} scopes={scopes.filter((x) => x.usuario_id === sel)} cat={cat} onCerrar={() => setSel(null)} />}
    </>
  );
}

function NuevoUsuario({ abierto, roles, onCerrar }: { abierto: boolean; roles: RolFila[]; onCerrar: () => void }) {
  const toast = useToast(); const router = useRouter();
  const [email, setEmail] = useState(""); const [nombre, setNombre] = useState(""); const [pass, setPass] = useState(""); const [rs, setRs] = useState<string[]>([]); const [ocupado, setOcupado] = useState(false);
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault(); setOcupado(true);
    const r = await fetch("/api/admin/usuarios", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, nombre, password: pass, roles: rs }) });
    const j = await r.json().catch(() => ({}));
    setOcupado(false);
    if (!r.ok) { toast("error", j.error ?? "No se pudo crear el usuario"); return; }
    toast("ok", "Usuario creado. Asignale permisos con «Gestionar»."); setEmail(""); setNombre(""); setPass(""); setRs([]); onCerrar(); router.refresh();
  };
  return (
    <Modal abierto={abierto} onCerrar={onCerrar} titulo="Nuevo usuario">
      <form onSubmit={enviar} className="space-y-4">
        <Campo etiqueta="Nombre completo"><input className="input" required value={nombre} onChange={(e) => setNombre(e.target.value)} /></Campo>
        <Campo etiqueta="Email"><input className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
        <Campo etiqueta="Contraseña inicial" ayuda="Mínimo 8 caracteres. Compartila por un canal seguro."><input className="input" type="text" minLength={8} required value={pass} onChange={(e) => setPass(e.target.value)} autoComplete="off" /></Campo>
        <fieldset><legend className="label">Roles</legend><div className="flex flex-wrap gap-2">{roles.filter((r) => r.nombre !== "DESARROLLADOR").map((r) => (
          <label key={r.id} className="inline-flex items-center gap-2 text-sm card px-3 py-1.5 cursor-pointer"><input type="checkbox" checked={rs.includes(r.nombre)} onChange={(e) => setRs(e.target.checked ? [...rs, r.nombre] : rs.filter((x) => x !== r.nombre))} />{ROL_LABEL[r.nombre] ?? r.nombre}</label>))}</div>
          <p className="text-xs text-muted mt-2">Los roles son etiquetas; lo que el usuario puede hacer sale de sus permisos.</p></fieldset>
        <div className="flex justify-end gap-2"><button type="button" className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado}>{ocupado ? <span className="spinner" /> : "Crear usuario"}</button></div>
      </form>
    </Modal>
  );
}

function Editor({ usuario, roles, rolesDe, permisos, scopes, cat, onCerrar }: { usuario: UsuarioFila; roles: RolFila[]; rolesDe: string[]; permisos: UsuarioPermisos | null; scopes: ScopeFila[]; cat: Catalogos; onCerrar: () => void }) {
  const toast = useToast(); const router = useRouter();
  const esDev = rolesDe.some((id) => roles.find((r) => r.id === id)?.nombre === "DESARROLLADOR");
  const [nombre, setNombre] = useState(usuario.nombre_completo);
  const [activo, setActivo] = useState(usuario.activo);
  const [rs, setRs] = useState<string[]>(rolesDe);
  const [p, setP] = useState<UsuarioPermisos>(permisos ?? { usuario_id: usuario.id, visibilidad_nivel: "NADA", aprobacion_nivel: "NADA", modificacion_nivel: "NADA", reapertura_nivel: "NADA", control_ingreso: false, puede_ver_importes: true, puede_eliminar_cancelar: false, puede_importar: false, puede_exportar: false, puede_quitar_control_ingreso: false });
  const [sc, setSc] = useState<Record<string, { area_id: string; sector_id: string; proceso_id: string }>>(() => Object.fromEntries(scopes.map((s) => [s.tipo_permiso, { area_id: s.area_id ?? "", sector_id: s.sector_id ?? "", proceso_id: s.proceso_id ?? "" }])));
  const [pass, setPass] = useState("");
  const [ocupado, setOcupado] = useState(false);

  const guardar = async () => {
    setOcupado(true);
    try {
      const sb = createClient();
      const paso = async (q: PromiseLike<{ error: { message: string } | null }>) => { const { error } = await q; if (error) throw new Error(error.message); };
      // Perfil
      await paso(sb.from("usuarios").update({ nombre_completo: nombre.trim(), activo }).eq("id", usuario.id));
      // Roles (el rol DESARROLLADOR no se asigna ni se quita desde la interfaz)
      const actuales = new Set(rolesDe), deseados = new Set(rs);
      const quitar = [...actuales].filter((x) => !deseados.has(x) && roles.find((r) => r.id === x)?.nombre !== "DESARROLLADOR");
      const agregar = [...deseados].filter((x) => !actuales.has(x));
      if (quitar.length) await paso(sb.from("usuario_roles").delete().eq("usuario_id", usuario.id).in("rol_id", quitar));
      if (agregar.length) await paso(sb.from("usuario_roles").insert(agregar.map((rol_id) => ({ usuario_id: usuario.id, rol_id }))));
      // Permisos y alcances
      if (!esDev) {
        await paso(sb.from("usuario_permisos").upsert({ ...p, usuario_id: usuario.id }, { onConflict: "usuario_id" }));
        for (const t of TIPOS) {
          const nivel = p[t.campo]; const v = sc[t.tipo];
          if (nivel === "AREA" || nivel === "SECTOR" || nivel === "PROCESO") {
            const fila = { usuario_id: usuario.id, tipo_permiso: t.tipo, area_id: nivel === "AREA" ? v?.area_id || null : null, sector_id: nivel === "SECTOR" ? v?.sector_id || null : null, proceso_id: nivel === "PROCESO" ? v?.proceso_id || null : null };
            const val = nivel === "AREA" ? fila.area_id : nivel === "SECTOR" ? fila.sector_id : fila.proceso_id;
            if (!val) throw new Error(`Elegí el ${nivel.toLowerCase()} para «${t.nombre}».`);
            await paso(sb.from("usuario_permiso_scopes").upsert(fila, { onConflict: "usuario_id,tipo_permiso" }));
          } else await paso(sb.from("usuario_permiso_scopes").delete().eq("usuario_id", usuario.id).eq("tipo_permiso", t.tipo));
        }
      }
      toast("ok", "Cambios guardados"); router.refresh(); onCerrar();
    } catch (e) { toast("error", mensajeError(e)); } finally { setOcupado(false); }
  };

  const resetPass = async () => {
    const r = await fetch("/api/admin/usuarios", { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ id: usuario.id, password: pass }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) toast("error", j.error ?? "No se pudo cambiar la contraseña"); else { toast("ok", "Contraseña actualizada"); setPass(""); }
  };

  return (
    <Modal abierto onCerrar={onCerrar} titulo={`Gestionar · ${usuario.nombre_completo}`} ancho>
      <div className="space-y-6">
        {esDev && <div className="text-sm rounded-lg px-3 py-2" style={{ background: "color-mix(in srgb, var(--accent) 14%, transparent)", color: "var(--accent)" }}>Usuario DESARROLLADOR: protegido por la base. Sus permisos y su estado no se pueden modificar desde acá.</div>}
        <section className="grid sm:grid-cols-2 gap-3 items-end">
          <Campo etiqueta="Nombre completo"><input className="input" value={nombre} onChange={(e) => setNombre(e.target.value)} /></Campo>
          <label className="flex items-center gap-2 text-sm min-h-10"><input type="checkbox" checked={activo} onChange={(e) => setActivo(e.target.checked)} /> Cuenta activa <span className="text-xs text-muted">(inactiva = no puede operar)</span></label>
        </section>
        <section><h3 className="font-semibold text-sm mb-2">Roles</h3><div className="flex flex-wrap gap-2">{roles.map((r) => (
          <label key={r.id} className="inline-flex items-center gap-2 text-sm card px-3 py-1.5" title={r.descripcion ?? undefined}><input type="checkbox" disabled={r.nombre === "DESARROLLADOR"} checked={rs.includes(r.id)} onChange={(e) => setRs(e.target.checked ? [...rs, r.id] : rs.filter((x) => x !== r.id))} />{ROL_LABEL[r.nombre] ?? r.nombre}</label>))}</div></section>
        {!esDev && <>
          <section><h3 className="font-semibold text-sm mb-1">Nivel y alcance por tipo de permiso</h3><p className="text-xs text-muted mb-3">«Todo» en visibilidad no da por sí solo permiso de aprobar, modificar ni reabrir: cada tipo se configura aparte.</p>
            <div className="space-y-3">{TIPOS.map((t) => { const nivel = p[t.campo]; const v = sc[t.tipo] ?? { area_id: "", sector_id: "", proceso_id: "" }; return (
              <div key={t.tipo} className="card p-3 grid sm:grid-cols-[11rem_9rem_1fr] gap-3 items-center">
                <div className="text-sm font-medium">{t.nombre}</div>
                <select className="input" value={nivel} onChange={(e) => setP({ ...p, [t.campo]: e.target.value as Nivel })} aria-label={`Nivel: ${t.nombre}`}>{NIVELES.map((n) => <option key={n} value={n}>{NIVEL_LABEL[n]}</option>)}</select>
                <div>
                  {nivel === "AREA" && <select className="input" value={v.area_id} onChange={(e) => setSc({ ...sc, [t.tipo]: { ...v, area_id: e.target.value } })}><option value="">Elegir área…</option>{cat.areas.map((a) => <option key={a.id} value={a.id}>{a.nombre}</option>)}</select>}
                  {nivel === "SECTOR" && <select className="input" value={v.sector_id} onChange={(e) => setSc({ ...sc, [t.tipo]: { ...v, sector_id: e.target.value } })}><option value="">Elegir sector…</option>{cat.sectores.map((s) => <option key={s.id} value={s.id}>{cat.areas.find((a) => a.id === s.area_id)?.nombre} · {s.nombre}</option>)}</select>}
                  {nivel === "PROCESO" && <select className="input" value={v.proceso_id} onChange={(e) => setSc({ ...sc, [t.tipo]: { ...v, proceso_id: e.target.value } })}><option value="">Elegir proceso…</option>{cat.procesos.map((x) => { const s = cat.sectores.find((s) => s.id === x.sector_id); return <option key={x.id} value={x.id}>{cat.areas.find((a) => a.id === s?.area_id)?.nombre} · {s?.nombre} · {x.nombre}</option>; })}</select>}
                  {(nivel === "TODO" || nivel === "NADA") && <span className="text-xs text-muted">{nivel === "TODO" ? "Sin restricción de alcance" : "Sin permiso"}</span>}
                </div>
              </div>); })}</div></section>
          <section><h3 className="font-semibold text-sm mb-2">Capacidades</h3><div className="grid sm:grid-cols-2 gap-2">{BOOLS.map((b) => (
            <label key={b.k} className="card p-3 flex gap-3 items-start cursor-pointer"><input type="checkbox" className="mt-1" checked={!!p[b.k]} onChange={(e) => setP({ ...p, [b.k]: e.target.checked })} /><span><span className="text-sm font-medium block">{b.t}</span><span className="text-xs text-muted">{b.d}</span></span></label>))}</div></section>
        </>}
        <section className="grid sm:grid-cols-[1fr_auto] gap-2 items-end"><Campo etiqueta="Restablecer contraseña" ayuda="Mínimo 8 caracteres."><input className="input" type="text" minLength={8} value={pass} onChange={(e) => setPass(e.target.value)} autoComplete="off" placeholder="Nueva contraseña" /></Campo><button className="btn btn-secondary" disabled={pass.length < 8} onClick={resetPass}>Cambiar contraseña</button></section>
        <div className="flex justify-end gap-2 pt-2 border-t"><button className="btn btn-secondary" onClick={onCerrar}>Cancelar</button><button className="btn btn-primary" disabled={ocupado} onClick={guardar}>{ocupado ? <span className="spinner" /> : "Guardar cambios"}</button></div>
      </div>
    </Modal>
  );
}
