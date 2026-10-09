/** SOFA · 2.2 · Vencimientos de tarifas contractuales y contratos (todos los clientes que el rol puede ver). */
import { h } from '../services/iter18.js';
import { mountExpiring } from './tarifario-import.js';

export async function render(root) {
  root.replaceChildren();
  const days = h('select', { id: 'vc-days' }, [30, 60, 90, 180].map((d) => h('option', { value: String(d), selected: d === 60 }, `${d} días`)));
  const box = h('div');
  root.append(h('h2', {}, 'Vencimientos de tarifas y contratos'),
    h('p', { class: 'i18-sub' }, 'Renegocie o recargue el tarifario antes de que venza: una tarifa vencida deja la reclamación «sin servicio contratado».'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'vc-days' }, 'Mostrar los que vencen en', days)), box);
  const draw = () => mountExpiring(box, { days: Number(days.value) });
  days.addEventListener('change', draw);
  await draw();
}
