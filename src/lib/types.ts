// Tipos escritos a mano según 0001_schema_inicial_consolidado_v2_1_SUPABASE.sql.
export type Nivel = "TODO" | "AREA" | "SECTOR" | "PROCESO" | "NADA";
export type Situacion = "BORRADOR" | "EN_APROBACION" | "APROBADA" | "RECHAZADA" | "FINALIZADA" | "CANCELADA" | "ELIMINADA";
export type EstadoAprobacion = "PENDIENTE_APROBACION" | "APROBADO" | "RECHAZADO";
export type EstadoAsistencia = "NO_APLICA" | "PENDIENTE_INGRESO" | "INGRESO_REGISTRADO" | "YA_ESTABA_EN_PLANTA" | "NO_PRESENTADO";
export type EstadoRegistro = "ACTIVO" | "REEMPLAZADO" | "CANCELADO";
export type TemaApp = "CLARO" | "OSCURO" | "SISTEMA";

export interface Area { id: string; nombre: string; activo: boolean }
export interface Sector { id: string; area_id: string; nombre: string; activo: boolean }
export interface Proceso { id: string; sector_id: string; nombre: string; activo: boolean }
export interface Motivo { id: string; motivo: string; tipo: "PRODUCTIVO" | "IMPRODUCTIVO"; requiere_aprobacion: boolean; activo: boolean }
export interface CategoriaTipo { id: string; codigo: string; descripcion: string | null; activo: boolean }
export interface Categoria { id: string; categoria_tipo_id: string; valor_hora: number; moneda: string; vigente_desde: string; vigente_hasta: string | null }
export interface BandaHoraria { id: string; descripcion: string; hora_desde: string; hora_hasta: string; multiplicador: number; multiplicador_feriado: number | null; activo: boolean }
export interface Feriado { id: string; fecha: string; descripcion: string | null }
export interface IbConfig { id: string; descripcion: string; activo: boolean }
export interface BandaRanking {
  id: string; descripcion: string; ranking_inferior: number; ranking_superior: number | null; color: string;
  aplica_a_solicitud: boolean; aplica_a_real: boolean; bloqueo_seleccion: "PERMITIDO" | "ADVERTENCIA" | "BLOQUEADO"; activo: boolean;
}

export interface ConfigGeneral {
  id: number; dias_maximos_antiguedad: number; emails_activos: boolean; ranking_periodo: "MENSUAL" | "TRIMESTRAL" | "ANUAL";
  control_ingreso_permite_eliminar: boolean; nivel_auditoria_negocio: "DESACTIVADA" | "BASICA" | "COMPLETA";
  retencion_auditoria_meses: number | null; zona_horaria: string; ultimo_reseteo_ranking: string | null;
}
export interface ConfigApariencia {
  id: number; nombre_empresa: string | null; logo_url: string | null; color_primario: string; color_primario_hover: string;
  color_secundario: string; color_acento: string; color_exito: string; color_advertencia: string; color_error: string; tema_predeterminado: TemaApp;
}

export interface SolicitudResumen {
  id: string; numero: string | null; situacion: Situacion; solicitante_id: string; solicitante_nombre: string;
  area_id: string; area_nombre: string; sector_id: string; sector_nombre: string; proceso_id: string; proceso_nombre: string;
  motivo_id: string; motivo_nombre: string; motivo_tipo: string; fecha_hora_inicio: string; fecha_hora_fin: string;
  observacion: string | null; moneda: string | null; fecha_hora_solicitud: string; cantidad_empleados: number; total_horas_solicitud: number;
  total_importe_solicitud: number | null; importe_aprobado: number | null; importe_rechazado: number | null; importe_pendiente: number | null;
}
export interface EmpleadoDetalle {
  solicitud_empleado_id: string; solicitud_id: string; empleado_id: string; legajo: string; nombre_completo: string;
  ib_descripcion: string | null; ranking_horas_al_momento: number | null; estado_aprobacion: EstadoAprobacion;
  estado_asistencia: EstadoAsistencia; estado_registro: EstadoRegistro; motivo_rechazo: string | null; total_horas: number;
  total_importe: number | null; fecha_hora_aprobacion: string | null; usuario_aprobacion_id: string | null;
  fecha_hora_ingreso: string | null; usuario_control_ingreso_id: string | null; reemplaza_a: string | null;
  reemplaza_a_legajo: string | null; reemplaza_a_nombre: string | null;
}
export interface EmpleadoResumen {
  id: string; legajo: string; nombre_completo: string; categoria_codigo: string; area_id: string | null; area_nombre: string | null;
  sector_id: string | null; sector_nombre: string | null; proceso_id: string | null; proceso_nombre: string | null;
  estado: "ACTIVO" | "INACTIVO"; ranking_horas: number; ranking_horas_real: number | null; ib_id: string | null; ib_descripcion: string | null;
  fecha_alta: string; fecha_baja: string | null;
}
export interface DetalleCalculo {
  id: string; solicitud_empleado_id: string; fecha: string; banda_horaria_id: string; horas: number; valor_hora: number;
  moneda: string; multiplicador: number; importe: number; es_feriado: boolean;
}
export interface PermisosScope { puede_ver: boolean; puede_modificar: boolean; puede_aprobar: boolean; puede_reabrir: boolean; puede_control_ingreso: boolean }
export interface AuditoriaNegocio {
  id: string; fecha_hora: string; usuario_id: string | null; origen: string; nivel: string; modulo: string; entidad_tipo: string;
  entidad_id: string | null; evento: string; estado_anterior: string | null; estado_nuevo: string | null; datos: Record<string, unknown> | null;
}
export interface UsuarioPermisos {
  usuario_id: string; visibilidad_nivel: Nivel; aprobacion_nivel: Nivel; modificacion_nivel: Nivel; reapertura_nivel: Nivel;
  control_ingreso: boolean; puede_ver_importes: boolean; puede_eliminar_cancelar: boolean; puede_importar: boolean;
  puede_exportar: boolean; puede_quitar_control_ingreso: boolean;
}

export const SITUACION_LABEL: Record<Situacion, string> = {
  BORRADOR: "Borrador", EN_APROBACION: "En aprobación", APROBADA: "Aprobada", RECHAZADA: "Rechazada",
  FINALIZADA: "Finalizada", CANCELADA: "Cancelada", ELIMINADA: "Eliminada",
};
export const APROBACION_LABEL: Record<EstadoAprobacion, string> = { PENDIENTE_APROBACION: "Pendiente", APROBADO: "Aprobado", RECHAZADO: "Rechazado" };
export const ASISTENCIA_LABEL: Record<EstadoAsistencia, string> = {
  NO_APLICA: "—", PENDIENTE_INGRESO: "Pendiente de ingreso", INGRESO_REGISTRADO: "Ingresó", YA_ESTABA_EN_PLANTA: "Ya estaba en planta", NO_PRESENTADO: "No se presentó",
};
export const NIVEL_LABEL: Record<Nivel, string> = { TODO: "Todo", AREA: "Área", SECTOR: "Sector", PROCESO: "Proceso", NADA: "Ninguno" };
export const ROL_LABEL: Record<string, string> = {
  DESARROLLADOR: "Desarrollador", ADMIN: "Administrador", RRHH: "RRHH", RESPONSABLE: "Responsable",
  APROBADOR: "Aprobador", CONTROL_INGRESO: "Control de ingreso", CONSULTA: "Consulta",
};
