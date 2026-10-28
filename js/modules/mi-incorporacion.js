/** SOFA · 2.1 · Iteración 30 · «Mi incorporación»: lo único que ve el usuario con rol Prospecto.
 *  Muestra el avance de su oportunidad con SOFA y de su habilitación MISPAS. Al convertirse en cliente pasa a Médico.
 *  28/10/2026: el checklist de habilitación deja de ser solo lectura — el prospecto puede marcar
 *  cada requisito como entregado, con una nota de qué envió y cómo (habilitation_item_submit).
 *  Documentos adjuntos: pendiente (requiere decidir cómo guardar el archivo de alguien sin
 *  organización todavía; por ahora la entrega se registra como nota, igual que ya hace Mi habilitación). */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';

// 4.7.0: todas las etapas que puede devolver prospect_portal tienen su texto en español (antes «prospecto» salía tal cual)
const STAGE = { prospecto: 'Primer contacto', nuevo: 'Nuevo', contactado: 'Contactado', reunion: 'Presentación', evaluacion: 'Seguimiento', propuesta: 'Propuesta enviada', negociacion: 'Negociación',
  acuerdo: 'Acuerdo', contratado: 'Contratado', implementacion: 'Implementación', cliente: 'Activo', ganado: 'Aprobado', perdido: 'Cerrado' };
const HAB = { diagnostico: 'Diagnóstico de brechas', correccion: 'Corrección', ensamblaje: 'Ensamblaje del expediente', depositado: 'Depositado en DGHA', inspeccion: 'Inspección', habilitado: 'Habilitado', cancelado: 'Cancelado' };
const ITEM_STATUS = { pendiente: ['Sin evaluar', ''], verde: ['Verde · listo', 'i18-proximo'], amarillo: ['Amarillo · corregible', 'i18-esta_semana'], rojo: ['Rojo · requiere obra', 'i18-atrasado'], no_aplica: ['No aplica', ''] };

function checklistCard(c, onSubmitted) {
  const counts = c.counts || {};
  const card = h('section', { class: 'i18-card', 'aria-label': `Checklist de ${c.name}` },
    h('div', { class: 'i18-sub' }, `${c.name} · ${c.type}${c.kind === 'renovacion' ? ' · Renovación' : ''}`),
    h('div', {}, h('span', { class: 'i18-badge i18-esta_semana' }, HAB[c.stage] || c.stage_label || c.stage)),
    h('p', { class: 'i18-sub' }, `${counts.verde || 0} de ${counts.applicable || 0} requisitos en verde${counts.critical_open ? ` · ${counts.critical_open} crítico(s) pendiente(s)` : ''}`));

  for (const a of (c.areas || [])) {
    card.append(h('h4', { style: 'margin:14px 0 4px' }, a.area));
    for (const i of (a.items || [])) {
      const [label, cls] = ITEM_STATUS[i.status] || [i.status, ''];
      const row = h('div', { class: 'i18-card', style: 'margin:6px 0;padding:10px 12px' },
        h('div', {}, i.requirement, i.critical ? h('span', { class: 'i18-badge i18-atrasado', style: 'margin-left:6px' }, 'Crítico') : null),
        i.hint ? h('div', { class: 'i18-sub' }, `Evidencia: ${i.hint}`) : null,
        h('div', { class: `i18-badge ${cls}`.trim() }, label));
      if (i.client_note) {
        row.append(h('div', { class: 'i18-sub' }, `Ya informado: «${i.client_note}»${i.submitted_at ? ` (${fmtDate(i.submitted_at)})` : ''} — en revisión por SOFA.`));
      } else if (i.can_submit) {
        const input = h('input', { type: 'text', maxlength: '500', placeholder: 'Ej.: copia del exequátur enviada por WhatsApp hoy', 'aria-label': `Nota de entrega para ${i.requirement}` });
        const btn = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Marcar como entregado');
        btn.addEventListener('click', async () => {
          const val = input.value.trim();
          if (val.length < 5) { input.focus(); row.append(note('Cuente qué entregó y cómo (al menos 5 caracteres).', 'error')); return; }
          btn.disabled = true;
          try { await rpc('habilitation_item_submit', { p_item: i.id, p_note: val }); await onSubmitted(); }
          catch (err) { btn.disabled = false; row.append(note(err.message || 'No se pudo registrar la entrega.', 'error')); }
        });
        row.append(h('div', { class: 'i18-actions' }, input, btn));
      }
      card.append(row);
    }
  }
  return card;
}

export async function render(root) {
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('h2', {}, 'Mi incorporación a SOFA'), box);
  const d = await guarded(box, () => rpc('prospect_portal'));
  if (!d) return;

  const draw = async () => {
    box.replaceChildren();
    box.append(
      note(`Bienvenido${d.contact ? `, ${d.contact}` : ''}. Aquí verá el avance de su incorporación. Cuando firme y quede como cliente, su usuario pasará a «Médico» con acceso a su consultorio completo.`),
      h('section', { class: 'i18-card' }, h('h3', {}, d.company), h('p', { class: 'i18-sub' }, [d.specialty, d.owner ? `Su asesor en SOFA: ${d.owner}` : null].filter(Boolean).join(' · '))),
      h('h3', {}, 'Servicios en proceso'),
      d.opportunities.length ? h('div', { class: 'i18-list' }, d.opportunities.map((o) => h('div', { class: 'i18-card' },
        h('strong', {}, o.service || 'Servicio'), h('div', {}, 'Etapa: ', h('span', { class: 'i18-badge i18-esta_semana' }, STAGE[o.stage] || o.stage)),
        o.next_action ? h('div', { class: 'i18-sub' }, `Próximo paso: ${o.next_action}${o.next_action_date ? ` (${fmtDate(o.next_action_date)})` : ''}`) : '')))
        : note('Todavía no hay servicios en proceso. Su asesor lo registrará después de la primera reunión.'),
      h('h3', {}, 'Habilitación MISPAS'));

    const cases = await guarded(box, () => rpc('prospect_habilitation'));
    if (!cases || !cases.length) {
      box.append(d.habilitation.length
        ? h('div', { class: 'i18-list' }, d.habilitation.map((x) => h('div', { class: 'i18-card' },
            h('strong', {}, x.name), h('div', {}, `${HAB[x.stage] || x.stage || 'Sin etapa'} · ${x.ready_pct ?? 0}% listo`),
            h('div', { class: 'ac-progress' }, h('div', { style: `width:${Math.max(0, Math.min(100, x.ready_pct || 0))}%` })),
            x.target_date ? h('div', { class: 'i18-sub' }, `Meta: ${fmtDate(x.target_date)}`) : '')))
        : note('Sin caso de habilitación abierto.'));
      return;
    }
    for (const c of cases) box.append(checklistCard(c, draw));
  };

  await draw();
}
