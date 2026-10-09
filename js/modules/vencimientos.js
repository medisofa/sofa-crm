/** SOFA · 2.2 · 2.6.1 · Renegociación de tarifarios (solo personal SOFA). Las ARS contratan por tiempo indefinido:
 *  cada tarifario se revisa a los 2 años de su última vigencia para ofrecer al cliente el servicio de renegociación. */
import { h } from '../services/iter18.js';
import { mountExpiring } from './tarifario-import.js';

export async function render(root) {
  root.replaceChildren();
  const days = h('select', { id: 'vc-days' }, [30, 60, 90, 120, 180, 365].map((d) => h('option', { value: String(d), selected: d === 120 }, `${d} días`)));
  const box = h('div');
  root.append(h('h2', {}, 'Renegociación de tarifarios'),
    h('p', { class: 'i18-sub' }, 'Tarifarios que cumplen 2 años o contratos que vencen: oportunidad para ofrecer al cliente el servicio SOFA de renegociación. Solo lo ve el equipo SOFA.'),
    h('div', { class: 'i18-bar' }, h('label', { for: 'vc-days' }, 'Mostrar los que llegan a revisión en', days)), box);
  const draw = () => mountExpiring(box, { days: Number(days.value) });
  days.addEventListener('change', draw);
  await draw();
}
