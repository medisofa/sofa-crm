/** SOFA · 5.5.0 · I65 · «Novedades»: la bitácora de versiones dentro de la app.
 *  Solo lectura. La ve cualquier usuario con sesión activa. Los datos salen de
 *  public.changelog_list() (versión, iteración y tema de cada migración registrada);
 *  nunca trae datos de pacientes ni del negocio. */
import { rpc, h, note, guarded } from '../services/iter18.js';
import { APP_VERSION } from '../version.js';

export async function render(root) {
  root.replaceChildren();
  const list = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap nov-wrap' },
    h('h2', {}, 'Novedades'),
    h('p', { class: 'i18-sub' }, 'Lo que ha cambiado en SOFA, de lo más reciente a lo más antiguo.'),
    h('div', { class: 'nov-current' },
      h('span', { class: 'nov-badge' }, `v${APP_VERSION}`),
      ' versión en uso ahora mismo'),
    list));

  const data = await guarded(list, () => rpc('changelog_list'));
  if (!data) return;
  const items = Array.isArray(data) ? data : [];
  if (!items.length) { list.replaceChildren(note('Aún no hay versiones registradas.', 'info')); return; }

  /* Agrupa por serie menor: "5.17.0" → grupo "5.17" */
  const groups = new Map();
  items.forEach((v) => {
    const p = String(v.version || '').split('.');
    const g = p.length >= 2 ? `${p[0]}.${p[1]}` : String(v.version || '');
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g).push(v);
  });

  let isFirst = true;
  const groupEls = [...groups.entries()].map(([grp, entries]) => {
    const isLatest = isFirst;
    isFirst = false;
    return h('div', { class: `nov-group${isLatest ? ' nov-group-latest' : ''}` },
      h('div', { class: 'nov-group-t' }, `Serie ${grp}`),
      h('ol', { class: 'nov-lista' },
        entries.map((v, vi) => {
          const current = isLatest && vi === 0;
          return h('li', { class: `nov-item${current ? ' nov-item-current' : ''}` },
            h('div', { class: 'nov-top' },
              h('span', { class: 'nov-ver' }, `v${v.version || ''}`),
              v.iteracion ? h('span', { class: 'nov-iter' }, v.iteracion) : '',
              current ? h('span', { class: 'nov-tag' }, 'Actual') : ''),
            h('div', { class: 'nov-tema' }, v.tema || ''));
        })));
  });

  list.replaceChildren(...groupEls);
}
