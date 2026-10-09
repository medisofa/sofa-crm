/** SOFA · 2.1 · Iteración 30 · «Mi incorporación»: lo único que ve el usuario con rol Prospecto.
 *  Muestra el avance de su oportunidad con SOFA y de su habilitación MISPAS. Al convertirse en cliente pasa a Médico. */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';

const STAGE = { nuevo: 'Nuevo', contactado: 'Contactado', reunion: 'Reunión', propuesta: 'Propuesta enviada', negociacion: 'Negociación', ganado: 'Aprobado', perdido: 'Cerrado' };

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Mi incorporación a SOFA'), box);
  const d = await guarded(box, () => rpc('prospect_portal'));
  if (!d) return;
  box.replaceChildren(
    note(`Bienvenido${d.contact ? `, ${d.contact}` : ''}. Aquí verá el avance de su incorporación. Cuando firme y quede como cliente, su usuario pasará a «Médico» con acceso a su consultorio completo.`),
    h('section', { class: 'i18-card' }, h('h3', {}, d.company), h('p', { class: 'i18-sub' }, [d.specialty, d.owner ? `Su asesor en SOFA: ${d.owner}` : null].filter(Boolean).join(' · '))),
    h('h3', {}, 'Servicios en proceso'),
    d.opportunities.length ? h('div', { class: 'i18-list' }, d.opportunities.map((o) => h('div', { class: 'i18-card' },
      h('strong', {}, o.service || 'Servicio'), h('div', {}, 'Etapa: ', h('span', { class: 'i18-badge i18-esta_semana' }, STAGE[o.stage] || o.stage)),
      o.next_action ? h('div', { class: 'i18-sub' }, `Próximo paso: ${o.next_action}${o.next_action_date ? ` (${fmtDate(o.next_action_date)})` : ''}`) : '')))
      : note('Todavía no hay servicios en proceso. Su asesor lo registrará después de la primera reunión.'),
    h('h3', {}, 'Habilitación MISPAS'),
    d.habilitation.length ? h('div', { class: 'i18-list' }, d.habilitation.map((x) => h('div', { class: 'i18-card' },
      h('strong', {}, x.name), h('div', {}, `${x.stage || ''} · ${x.ready_pct ?? 0}% listo`),
      h('div', { class: 'ac-progress' }, h('div', { style: `width:${Math.max(0, Math.min(100, x.ready_pct || 0))}%` })),
      x.target_date ? h('div', { class: 'i18-sub' }, `Meta: ${fmtDate(x.target_date)}`) : '')))
      : note('Sin caso de habilitación abierto.'));
}
