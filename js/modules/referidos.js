/** SOFA · 4.4 · Iteración 54 · Casos de éxito con números y referidos.
 *  Médico: recomendar a un colega y ver sus recomendaciones.
 *  Equipo comercial: casos de éxito (solo publicables con consentimiento escrito) y tablero de referidos. */
import { rpc, h, money, fmtDate, note, guarded, clientOptions, clientName } from '../services/iter18.js';

const ST = { borrador: 'Borrador', interno: 'Interno (anónimo)', publicable: 'Publicable', retirado: 'Retirado' };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (ctx.role === 'client') return clientView(root, ctx.membership?.organization_id);
  const cases = h('div', { 'aria-live': 'polite' });
  const refs = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Casos de éxito y referidos'),
    h('p', { class: 'i18-sub' }, 'Resultados con nombre y número venden mejor que cualquier anuncio. Solo se publica con el consentimiento escrito del cliente.'), cases, refs));
  const sel = h('select', { id: 'ce-org' }, h('option', { value: '' }, 'Elija un cliente'));
  try { (await clientOptions()).forEach((c) => sel.append(h('option', { value: c.id }, clientName(c)))); } catch (_) { /* opcional */ }
  const sug = h('div', { 'aria-live': 'polite' });
  sel.addEventListener('change', () => suggest(sel.value));

  async function loadCases() {
    const list = await guarded(cases, () => rpc('success_cases_list'));
    if (!list) return;
    cases.replaceChildren(h('h3', {}, 'Nuevo caso'), h('div', { class: 'i18-bar' }, h('label', { for: 'ce-org' }, 'Cliente', sel)), sug,
      h('h3', {}, `Casos (${list.length})`), list.length ? h('div', { class: 'i18-list' }, list.map((c) => h('div', { class: 'i18-card' },
        h('strong', {}, `${c.title} · ${c.client}`), h('div', { class: 'i18-sub' }, `${ST[c.status]}${c.consent_by ? ` · consentimiento de ${c.consent_by} el ${fmtDate(c.consent_on)}` : ''}`),
        c.story ? h('p', {}, c.story) : null, c.quote ? h('blockquote', {}, `«${c.quote}»`) : null))) : note('Sin casos todavía.'));
  }

  async function suggest(org) {
    if (!org) { sug.replaceChildren(); return; }
    const d = await guarded(sug, () => rpc('success_case_suggest', { p_org: org }));
    if (!d) return;
    const m = d.metrics || {};
    const title = h('input', { type: 'text', id: 'ce-title', maxlength: '160', value: d.headline ? d.headline.split('.')[0] : '' });
    const story = h('textarea', { id: 'ce-story', rows: '4', style: 'width:100%' }, d.headline || '');
    const quote = h('input', { type: 'text', id: 'ce-quote', maxlength: '300', placeholder: 'Frase del cliente (opcional)' });
    const st = h('select', { id: 'ce-st' }, Object.entries(ST).filter(([k]) => k !== 'retirado').map(([v, t]) => h('option', { value: v }, t)));
    const cby = h('input', { type: 'text', id: 'ce-cby', maxlength: '120', placeholder: 'Quién autorizó' });
    const con = h('input', { type: 'date', id: 'ce-con' });
    const cnote = h('input', { type: 'text', id: 'ce-cnote', maxlength: '200', placeholder: 'Ej.: correo del 09/10' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar caso');
    const out = h('div', { 'aria-live': 'polite' });
    save.addEventListener('click', async () => {
      try { await rpc('success_case_save', { p_id: null, p_org: org, p_title: title.value, p_story: story.value, p_quote: quote.value || null, p_status: st.value, p_consent_by: cby.value || null, p_consent_on: con.value || null, p_consent_note: cnote.value || null }); sel.value = ''; sug.replaceChildren(); loadCases(); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); }
    });
    sug.replaceChildren(h('div', { class: 'i18-card' },
      h('p', {}, `Con SOFA desde ${fmtDate(m.since)} (${m.months_with_sofa ?? 0} meses). Antes: glosa ${m.before?.glosa_pct ?? '—'} %, ${m.before?.dso ?? '—'} días. Ahora: glosa ${m.now?.glosa_pct ?? '—'} %, ${m.now?.dso ?? '—'} días. Recuperado en glosas: ${money(m.recovered_total)}.`),
      d.hint ? note(d.hint) : null,
      h('div', { class: 'i18-form' }, h('label', { for: 'ce-title' }, 'Título'), title, h('label', { for: 'ce-story' }, 'Historia'), story, h('label', { for: 'ce-quote' }, 'Frase'), quote,
        h('label', { for: 'ce-st' }, 'Estado'), st, h('label', { for: 'ce-cby' }, 'Consentimiento: quién'), cby, h('label', { for: 'ce-con' }, 'Consentimiento: fecha'), con,
        h('label', { for: 'ce-cnote' }, 'Consentimiento: dónde consta'), cnote, h('div', {}, save), out)));
  }

  async function loadRefs() {
    const d = await guarded(refs, () => rpc('referrals_board'));
    if (!d) return;
    const tbl = (head, rows) => h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, head.map((x) => h('th', {}, x)))), h('tbody', {}, rows.map((r) => h('tr', {}, r.map((x) => h('td', {}, x)))))));
    refs.replaceChildren(h('h3', {}, 'Referidos'),
      d.clients.length ? tbl(['Cliente que refirió', 'Referidos', 'Ya clientes'], d.clients.map((c) => [c.client, String(c.referrals), String(c.converted)])) : note('Ningún cliente ha referido todavía.'),
      d.partners.length ? tbl(['Aliado', 'Tipo', 'Referidos', 'Ya clientes', 'Comisión'], d.partners.map((p) => [p.partner, p.type, String(p.referrals), String(p.converted), `${p.commission_rate} %`])) : null,
      d.recent.length ? [h('h4', {}, 'Últimos'), h('ul', {}, d.recent.map((r) => h('li', {}, `${fmtDate(r.created_at)} · ${r.name}${r.specialty ? ` (${r.specialty})` : ''} · por ${r.by || '—'}${r.converted ? ' · ya es cliente' : ''}`)))] : null);
  }

  try {
    await loadCases();
  } catch (_) { /* el equipo sin permiso verá el mensaje */ }
  if (['super_admin', 'admin', 'assistant'].includes(ctx.role)) await loadRefs();
}

async function clientView(root, org) {
  const name = h('input', { type: 'text', id: 'rf-name', maxlength: '120' });
  const phone = h('input', { type: 'tel', id: 'rf-phone', maxlength: '20', inputmode: 'tel' });
  const spec = h('input', { type: 'text', id: 'rf-spec', maxlength: '80' });
  const nt = h('input', { type: 'text', id: 'rf-note', maxlength: '200' });
  const send = h('button', { class: 'i18-btn', type: 'button' }, 'Recomendar');
  const out = h('div', { 'aria-live': 'polite' });
  const list = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, 'Recomendar a un colega'),
    h('p', { class: 'i18-sub' }, '¿Conoce a un médico o centro que pierde dinero con las ARS? Déjenos su contacto: lo llamamos en 24 horas y le decimos que viene de su parte.'),
    h('div', { class: 'i18-form' }, h('label', { for: 'rf-name' }, 'Nombre'), name, h('label', { for: 'rf-phone' }, 'Teléfono o WhatsApp'), phone,
      h('label', { for: 'rf-spec' }, 'Especialidad (opcional)'), spec, h('label', { for: 'rf-note' }, 'Comentario (opcional)'), nt, h('div', {}, send), out), list));
  const load = async () => {
    const d = await guarded(list, () => rpc('my_referrals', { p_org: org }));
    if (!d) return;
    list.replaceChildren(h('h3', {}, 'Sus recomendaciones'), d.length ? h('ul', {}, d.map((r) => h('li', {}, `${fmtDate(r.created_at)} · ${r.name}${r.specialty ? ` (${r.specialty})` : ''} · ${r.status}`))) : note('Todavía no ha recomendado a nadie.'));
  };
  send.addEventListener('click', async () => {
    send.disabled = true; out.replaceChildren();
    try { await rpc('client_referral_add', { p_org: org, p_name: name.value, p_phone: phone.value, p_specialty: spec.value || null, p_note: nt.value || null }); name.value = ''; phone.value = ''; spec.value = ''; nt.value = ''; out.replaceChildren(note('¡Gracias! SOFA lo contactará pronto.')); await load(); }
    catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { send.disabled = false; }
  });
  await load();
}
export default render;
