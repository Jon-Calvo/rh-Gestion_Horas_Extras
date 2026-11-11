// Los mensajes de las RPC (raise exception) ya están en español y son claros para el usuario.
export function mensajeError(e: unknown): string {
  if (!e) return "Error desconocido";
  const err = e as { message?: string; details?: string };
  const m = err.message ?? String(e);
  if (/JWT|not authenticated|PGRST30/i.test(m)) return "Tu sesión venció. Volvé a iniciar sesión.";
  return m;
}
