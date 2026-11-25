"use client";

/** Abre el diálogo de impresión del navegador: elegir «Guardar como PDF» como destino. El nombre sugerido del archivo sale del título. */
export function BotonPdf({ nombreArchivo }: { nombreArchivo: string }) {
  const imprimir = () => {
    const anterior = document.title;
    document.title = nombreArchivo;
    const volver = () => { document.title = anterior; window.removeEventListener("afterprint", volver); };
    window.addEventListener("afterprint", volver);
    window.print();
  };
  return <button type="button" className="btn btn-secondary no-print" onClick={imprimir} title="Se abre la ventana de impresión: elegí «Guardar como PDF»">⬇ Exportar PDF</button>;
}
