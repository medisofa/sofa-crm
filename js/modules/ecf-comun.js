/** SOFA · 3.1 · Pasos e-CF de un cliente (los usan el equipo SOFA y el Médico en «Mi cuenta con SOFA»). */
import { rpc, h, fmtDate, note } from '../services/iter18.js';

/** s = respuesta de ecf_client_status. onChange se llama después de marcar un paso. */
export function ecfSteps(s, onChange) {
  const out = h('div', { 'aria-live': 'polite' });
  const head = h('p', {}, s.status === 'listo'
    ? `Listo para facturar con e-CF desde el ${fmtDate(s.ready_on)}${s.provider ? ` · ${s.provider}` : ''}.`
    : `Obligado desde el ${fmtDate(s.required_from)} · ${s.days_left < 0 ? `venció hace ${-s.days_left} días` : `faltan ${s.days_left} días`}.`);
  const steps = h('ol', { class: 'ecf-steps' }, s.steps.map((st) => {
    const chk = h('input', { type: 'checkbox', id: `ecf-s-${st.code}`, checked: st.done, disabled: !s.can_edit || s.status === 'listo' });
    const provInput = st.code === 'proveedor' ? h('input', { type: 'text', 'aria-label': 'Proveedor', placeholder: 'Nombre del proveedor', value: s.provider || '', maxlength: '120',
      list: 'ecf-prov-list', disabled: !s.can_edit || st.done }) : null;
    chk.addEventListener('change', async () => {
      chk.disabled = true; out.replaceChildren();
      try {
        const r = await rpc('ecf_client_step_set', { p_org: s.organization_id, p_step: st.code, p_done: chk.checked, p_note: null, p_provider: provInput ? provInput.value.trim() || null : null });
        if (r.hint) out.replaceChildren(note(r.hint));
        if (onChange) await onChange();
      } catch (e) { chk.checked = !chk.checked; out.replaceChildren(note(e.message, 'error')); }
      finally { chk.disabled = !s.can_edit; }
    });
    return h('li', { class: st.done ? 'ecf-done' : '' }, h('label', { class: 'i18-chk', for: `ecf-s-${st.code}` }, chk, ' ', h('strong', {}, st.label)),
      h('div', { class: 'i18-sub' }, st.hint), provInput, st.done && st.done_on ? h('div', { class: 'i18-sub' }, `Hecho el ${fmtDate(st.done_on)}${st.by ? ` · ${st.by}` : ''}`) : null);
  }));
  const dl = h('datalist', { id: 'ecf-prov-list' }, (s.providers || []).map((p) => h('option', { value: p.name })));
  const blocked = s.blocked.length
    ? [h('h4', {}, `Lotes que quedarían bloqueados (${s.blocked.length})`), h('ul', {}, s.blocked.map((b) => h('li', {}, `${b.folio || 'Lote sin folio'} · ${b.ars || ''} · ${String(b.period || '').slice(0, 7)}: ${b.reasons.join('; ')}`)))]
    : [h('p', { class: 'i18-sub' }, 'Ningún lote abierto quedaría bloqueado.')];
  const recos = (s.providers || []).length ? h('p', { class: 'i18-sub' }, 'Proveedores que recomienda SOFA: ' + s.providers.map((p) => p.name + (p.website ? ` (${p.website})` : '')).join(' · ')) : null;
  return h('div', {}, head, steps, dl, recos, ...blocked, out,
    h('p', { class: 'i18-sub' }, 'Los pasos son orientativos: confirme los detalles con su proveedor de facturación electrónica y con la DGII.'));
}
