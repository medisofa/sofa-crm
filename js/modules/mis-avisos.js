/** SOFA · 5.3.0 · I63 · «Mis avisos»: qué correos recibo y cada cuánto, con vista previa.
 *  Cada persona ve y cambia solo lo suyo. Por defecto solo llega lo esencial; puede apagar todo. El aviso de seguridad no se apaga.
 *  El servidor valida todo (rol, frecuencia, aviso de seguridad): ocultar un botón aquí no es un control. */
import { rpc, h, note, guarded } from '../services/iter18.js';

const FREQ = { inmediato: 'Al momento', diario: 'Una vez al día', semanal: 'Una vez por semana', quincenal: 'Cada dos semanas', mensual: 'Una vez al mes' };

export async function render(root) {
  root.replaceChildren();
  const status = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  const prev = h('div', { 'aria-live': 'polite', class: 'av-prev' });
  root.append(h('div', { class: 'i18-wrap av-wrap' }, h('h2', {}, 'Mis avisos'),
    h('p', { class: 'i18-sub' }, 'Elija qué avisos quiere recibir por correo y cada cuánto. Los correos solo traen conteos y montos: nunca datos de pacientes.'), status, list, prev));
  let data = null;

  async function load() {
    data = await guarded(list, () => rpc('email_my_preferences'));
    if (!data) return;
    draw();
  }

  async function save(topic, enabled, frequency, out) {
    try { await rpc('email_my_preference_set', { p_topic: topic, p_enabled: enabled, p_frequency: frequency ?? null }); await load(); status.replaceChildren(note('Cambio guardado.', 'ok')); }
    catch (e) { (out || status).replaceChildren(note(e.message, 'error')); await load().catch(() => {}); }
  }

  function draw() {
    status.replaceChildren();
    if (!data.avisos_activos) status.append(note('Los avisos por correo todavía no están encendidos para su cuenta de SOFA. Sus elecciones quedan guardadas y empezarán a llegar cuando se activen.', 'warn'));
    if (data.todo_apagado) status.append(note('Tiene todos los avisos apagados. Solo recibirá los avisos de seguridad de su cuenta.', 'info'));
    const rows = data.topics.map((t) => {
      const out = h('div', { 'aria-live': 'polite' });
      const chk = h('input', { type: 'checkbox', id: `av-on-${t.topic}`, checked: t.enabled, disabled: !t.can_disable, 'aria-describedby': `av-d-${t.topic}` });
      chk.addEventListener('change', () => save(t.topic, chk.checked, sel ? sel.value : null, out));
      const sel = t.frequencies.length > 1 ? h('select', { id: `av-f-${t.topic}`, 'aria-label': `Frecuencia de ${t.label}`, disabled: !t.enabled || !t.can_disable },
        t.frequencies.map((f) => h('option', { value: f, selected: f === t.frequency }, FREQ[f] || f))) : null;
      if (sel) sel.addEventListener('change', () => save(t.topic, true, sel.value, out));
      const vp = h('button', { class: 'i18-btn i18-sec', type: 'button', id: `av-v-${t.topic}` }, 'Ver ejemplo');
      vp.addEventListener('click', () => preview(t, vp));
      return h('section', { class: 'i18-card av-card' },
        h('div', { class: 'av-row' }, h('label', { class: 'i18-chk', for: `av-on-${t.topic}` }, chk, h('strong', {}, ` ${t.label}`)),
          t.can_disable ? null : h('span', { class: 'i18-sub' }, 'Siempre activo'), t.is_default ? h('span', { class: 'i18-sub' }, 'Valor por defecto') : null),
        h('p', { id: `av-d-${t.topic}`, class: 'i18-sub' }, t.description),
        h('div', { class: 'av-row' }, sel ? h('label', { for: `av-f-${t.topic}` }, 'Cada cuánto ', sel) : h('span', { class: 'i18-sub' }, FREQ[t.frequency] || t.frequency), vp), out);
    });
    const mute = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'av-mute' }, data.todo_apagado ? 'Volver a los avisos esenciales' : 'Apagar todos mis avisos');
    mute.addEventListener('click', async () => {
      mute.disabled = true;
      try { await rpc('email_my_mute_all', { p_mute: !data.todo_apagado }); await load(); }
      catch (e) { status.replaceChildren(note(e.message, 'error')); mute.disabled = false; }
    });
    list.replaceChildren(...rows, h('div', { class: 'av-row' }, mute, h('span', { class: 'i18-sub' }, 'Los avisos de seguridad no se pueden apagar: protegen su cuenta.')));
  }

  async function preview(t, btn) {
    btn.disabled = true;
    try {
      const r = await rpc('email_my_preview', { p_topic: t.topic });
      // El HTML lo arma y escapa el servidor; igual se muestra en un marco aislado (sin scripts, sin enlaces activos) con su versión en texto.
      const fr = h('iframe', { class: 'av-frame', title: `Vista previa: ${t.label}`, sandbox: '', referrerpolicy: 'no-referrer' });
      fr.srcdoc = r.html;
      prev.replaceChildren(h('section', { class: 'i18-card', id: 'av-preview' }, h('h3', {}, `Vista previa · ${t.label}`),
        r.ejemplo ? note('Todavía no hay movimiento para mostrar: esto es un ejemplo con datos inventados.', 'info') : note('Así se vería hoy con sus datos reales.', 'ok'),
        h('p', {}, h('strong', {}, 'Asunto: '), r.subject), fr,
        h('details', {}, h('summary', {}, 'Ver como texto simple'), h('pre', { class: 'av-text' }, r.text))));
      prev.scrollIntoView?.({ block: 'nearest' });
    } catch (e) { prev.replaceChildren(note(e.message, 'error')); }
    btn.disabled = false;
  }

  await load();
}
export default render;
