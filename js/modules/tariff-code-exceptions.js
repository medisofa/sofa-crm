/** Propose and explicitly authorize an ARS-only code association. No catalog write occurs here. */
import { rpc, h, note } from '../services/iter18.js';

export function codeExceptionEditor({ orgId, row, source, errors, setBusy, isBusy, onAuthorized, onInvalidate }) {
  const reason = h('textarea', { rows: '2', maxlength: '1000', placeholder: 'Ej.: el contrato de esta ARS asigna este código al servicio indicado.' });
  const systems = ['SIMON', 'CUPS'].map((system) => ({ system,
    input: h('input', { type: 'checkbox', checked: !!row[system.toLowerCase()] && errors.some((m) => m.includes(system)) })
  }));
  const result = h('div', { 'aria-live': 'polite' });
  const prepare = h('button', { class: 'i18-btn', type: 'button' }, 'Revisar propuesta de excepción');
  function invalidate() {
    onInvalidate();
    result.replaceChildren(note('La propuesta cambió. Revísela de nuevo antes de autorizar.'));
  }
  reason.addEventListener('input', invalidate);
  systems.forEach(({ input }) => input.addEventListener('change', invalidate));
  const snapshot = () => {
    const data = { ...row, source_file: source.file, source_line: source.line };
    delete data.code_authorization;
    return data;
  };
  prepare.addEventListener('click', async () => {
    if (isBusy()) return;
    const selected = systems.filter(({ input }) => input.checked).map(({ system }) => system);
    if (!selected.length) return result.replaceChildren(note('Seleccione SIMON, CUPS o ambos.', 'error'));
    if (reason.value.trim().length < 8) return result.replaceChildren(note('Explique el motivo con al menos 8 caracteres.', 'error'));
    const data = snapshot(); const text = reason.value.trim();
    setBusy(true);
    try {
      const proposal = await rpc('tariff_code_exception_prepare', { p_org: orgId, p_row: data, p_systems: selected, p_reason: text });
      const confirm = h('input', { type: 'checkbox' });
      const authorize = h('button', { class: 'i18-btn', type: 'button', disabled: true }, 'Autorizar excepción para esta ARS');
      confirm.addEventListener('change', () => { authorize.disabled = !confirm.checked; });
      authorize.addEventListener('click', async () => {
        if (isBusy() || !confirm.checked) return;
        if (JSON.stringify(snapshot()) !== JSON.stringify(data) || reason.value.trim() !== text) return invalidate();
        setBusy(true);
        try {
          const approval = await rpc('tariff_code_exception_authorize', {
            p_org: orgId, p_row: data, p_systems: selected, p_reason: text, p_expected: proposal
          });
          onAuthorized(approval);
          result.replaceChildren(note('Excepción autorizada. Pulse «Volver a validar correcciones» y después confirme el guardado. El código aún no se ha cambiado en el catálogo.', 'ok'));
        } catch (e) { result.append(note(e.message, 'error')); }
        finally { setBusy(false); }
      });
      result.replaceChildren(h('h5', {}, `Solo para ${proposal.ars_name}`),
        h('p', {}, `Servicio propuesto: ${proposal.service_code} · ${proposal.service_description}`),
        h('ul', {}, proposal.codes.map((code) => h('li', {},
          `${code.system} ${code.code}. Asociación actual en esta ARS: ${code.previous_description || 'sin asociación exclusiva'}. Catálogo general: ${code.general_description || 'sin código general'}. Nueva asociación: ${proposal.service_description}.`))),
        h('p', {}, `Motivo: ${proposal.reason}`),
        h('label', { class: 'ti-exception-confirm' }, confirm, `Autorizo esta asociación exclusiva para ${proposal.ars_name} y confirmo que verifiqué el contrato.`), authorize);
    } catch (e) { result.replaceChildren(note(e.message, 'error')); }
    finally { setBusy(false); }
  });
  return {
    element: h('details', { class: 'ti-code-exception' }, h('summary', {}, '¿Este código es exclusivo de la ARS? Proponer excepción'),
      h('p', {}, 'Use esta opción cuando el contrato de esta ARS asigne un SIMON o CUPS distinto del catálogo general. Se requiere Administración o Facturación con acceso al cliente. Las demás ARS conservan sus códigos.'),
      h('div', { class: 'i18-actions' }, systems.map(({ system, input }) => h('label', {}, input, ` ${system} exclusivo`))),
      h('label', { class: 'ti-exception-reason' }, 'Motivo y referencia del contrato', reason), prepare, result),
    invalidate
  };
}
