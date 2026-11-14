/** Supabase/PostgREST devuelve como máximo 1000 filas por consulta (configurable en el proyecto). Esta función pagina hasta traer todo. */
export async function fetchAll<T>(pagina: (desde: number, hasta: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>, max = 20000): Promise<T[]> {
  const salida: T[] = [];
  const tam = 1000;
  for (let desde = 0; desde < max; desde += tam) {
    const { data, error } = await pagina(desde, desde + tam - 1);
    if (error) throw new Error(error.message);
    salida.push(...(data ?? []));
    if (!data || data.length < tam) break;
  }
  return salida;
}
