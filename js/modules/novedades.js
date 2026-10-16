/** SOFA · 5.5.0 · I65 · «Novedades»: la bitácora de versiones dentro de la app.
 *  Solo lectura. La ve cualquier usuario con sesión activa. Los datos salen de
 *  public.changelog_list() (versión, iteración y tema de cada migración registrada);
 *  nunca trae datos de pacientes ni del negocio. */
import { rpc, h, note, guarded } from '../services/iter18.js';

export async function render(root) {
  root.replaceChildren();
  const list = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap nov-wrap' },
    h('h2', {}, 'Novedades'),
    h('p', { class: 'i18-sub' }, 'Lo que ha cambiado en SOFA, de lo más reciente a lo más antiguo.'),
    list));

  const data = await guarded(list, () => rpc('changelog_list'));
  if (!data) return;
  const items = Array.isArray(data) ? data : [];
  if (!items.length) { list.replaceChildren(note('Aún no hay versiones registradas.', 'info')); return; }

  list.replaceChildren(h('ol', { class: 'nov-lista' },
    items.map((v) => h('li', { class: 'nov-item' },
      h('div', { class: 'nov-ver' }, `v${v.version || ''}${v.iteracion ? ' · ' + v.iteracion : ''}`),
      h('div', { class: 'nov-tema' }, v.tema || '')))));
}
