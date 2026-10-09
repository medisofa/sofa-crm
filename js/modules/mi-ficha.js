/** SOFA · 2.1 · «Mi ficha» del Médico: la ficha de su propio consultorio (códigos ARS, tarifario, documentos, usuarios). */
export async function render(main, ctx) {
  const m = await import('./client.js');
  return m.render(main, { ...ctx, arg: ctx.membership?.organization_id });
}
