/** SOFA · 5.3.0 · I63 · «Cola de correos» (Administración): estado de la cola, reintentar, cancelar, bitácora de envío, configuración y plantillas.
 *  Solo Super Admin y Administrador del operador; las plantillas las edita solo el Super Admin. El servidor vuelve a verificar el rol en cada función.
 *  El envío es SIMULADO mientras no se elija proveedor de correo y dominio remitente. */
import { rpc, h, note, kpi, fmtDate, guarded } from '../services/iter18.js';

const ESTADOS = ['pendiente', 'enviando', 'enviado', 'fallido', 'cancelado'];
const ETQ = { pendiente: 'Pendiente', enviando: 'Enviando', enviado: 'Enviado', fallido: 'Fallido', cancelado: 'Cancelado' };
const dt = (iso) => { if (!iso) return '—'; const d = new Date(iso); return Number.isNaN(d.getTime()) ? '—' : `${fmtDate(d.toISOString())} ${d.toLocaleTimeString('es-DO', { hour: '2-digit', minute: '2-digit' })}`; };

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const top = h('div', { 'aria-live': 'polite' });
  const cfg = h('div', { 'aria-live': 'polite' });
  const cfgMsg = h('div', { 'aria-live': 'polite' });
  const bar = h('div', { class: 'i18-bar cc-tabs', role: 'tablist' });
  const list = h('div', { 'aria-live': 'polite' });
  const det = h('div', { 'aria-live': 'polite' });
  const tpl = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap cc-wrap' }, h('h2', {}, 'Cola de correos'),
    h('p', { class: 'i18-sub' }, 'Los avisos por correo que SOFA tiene por enviar, los que ya salieron y los que fallaron. Aquí puede reintentar o cancelar.'), top, cfg, cfgMsg, bar, list, det,
    h('h3', {}, 'Plantillas de los avisos'), tpl));
  const isSuper = ctx.role === 'super_admin';
  let filtro = null; let page = 0; let cfgOpen = false; const PAGE = 25;

  async function loadTop() {
    try {
      const [s, st, o] = await Promise.all([rpc('email_settings_get'), rpc('email_queue_stats'), rpc('email_open_rate')]);
      const settings = s && typeof s === 'object' ? s : {};
      const stats = st && typeof st === 'object' ? st : {};
      const openings = o && typeof o === 'object' ? o : {};
      const est = stats.por_estado || {};
      top.replaceChildren(
        note(settings.nota_proveedor || 'Estado del proveedor no disponible.', 'warn'),
        h('div', { class: 'i18-kpis' }, kpi('Avisos', settings.enabled ? 'Encendidos' : 'Apagados', settings.enabled ? 'Los generadores encolan' : 'No se encola nada (salvo seguridad)'),
          kpi('Pendientes', String(est.pendiente || 0), stats.pendiente_mas_viejo_min != null ? `El más viejo espera ${stats.pendiente_mas_viejo_min} min` : 'Sin atraso'),
          kpi('Fallidos (24 h)', String(stats.fallidos_24h), stats.fallidos_24h ? 'Revise y reintente' : 'Ninguno'),
          kpi('Enviados (7 días)', String(stats.enviados_7d)),
          kpi('Médicos que abren el resumen', openings.medido ? `${openings.porcentaje} %` : 'Sin medición', openings.medido ? `Meta ${openings.meta} %` : 'Seguimiento de aperturas apagado')));
      drawCfg(settings);
    } catch (e) { top.replaceChildren(note(e.message, 'error')); }
  }

  function drawCfg(s) {
    const out = cfgMsg;
    const en = h('input', { type: 'checkbox', id: 'cc-enabled', checked: s.enabled });
    const tr = h('input', { type: 'checkbox', id: 'cc-track', checked: s.track_opens });
    const dias = h('input', { type: 'number', id: 'cc-dias', min: '1', max: '14', value: String(s.glosa_days_ahead) });
    const int = h('input', { type: 'number', id: 'cc-int', min: '1', max: '10', value: String(s.max_attempts) });
    const go = h('button', { class: 'i18-btn', type: 'button', id: 'cc-save' }, 'Guardar configuración');
    go.addEventListener('click', async () => {
      go.disabled = true; out.replaceChildren();
      try { await rpc('email_settings_set', { p_enabled: en.checked, p_track_opens: tr.checked, p_glosa_days: Number(dias.value), p_max_attempts: Number(int.value) }); await loadTop(); out.replaceChildren(note('Configuración guardada.', 'ok')); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    const gen = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'cc-gen' }, 'Generar avisos ahora');
    gen.addEventListener('click', async () => {
      gen.disabled = true; out.replaceChildren();
      try { const r = await rpc('email_generate_now'); await Promise.all([loadTop(), loadList()]); out.replaceChildren(note(`Se encolaron ${r.glosas_por_vencer} aviso(s) de glosas, ${r.pago_recibido} de pagos y ${r.resumen_semanal} resumen(es).`, 'ok')); }
      catch (e) { out.replaceChildren(note(e.message, 'error')); gen.disabled = false; }
    });
    const dts = h('details', { class: 'i18-card', open: cfgOpen }, h('summary', {}, 'Configuración de los avisos'),
      h('div', { class: 'i18-form' },
        h('label', { class: 'i18-chk' }, en, ' Avisos encendidos para este operador'),
        h('label', { class: 'i18-chk' }, tr, ' Medir aperturas del resumen (apagado por defecto por privacidad; nunca en avisos de seguridad)'),
        h('label', { for: 'cc-dias' }, 'Días de anticipación de «glosas por vencer»'), dias,
        h('label', { for: 'cc-int' }, 'Intentos de envío por correo'), int,
        h('div', { class: 'av-row' }, go, gen)));
    dts.addEventListener('toggle', () => { cfgOpen = dts.open; });
    cfg.replaceChildren(dts);
  }

  function drawTabs() {
    bar.replaceChildren(...[null, ...ESTADOS].map((e) => {
      const b = h('button', { class: `i18-btn i18-sec cc-tab${filtro === e ? ' cc-on' : ''}`, type: 'button', role: 'tab', 'aria-selected': filtro === e ? 'true' : 'false', id: `cc-tab-${e || 'todos'}` }, e ? ETQ[e] : 'Todos');
      b.addEventListener('click', () => { filtro = e; page = 0; drawTabs(); loadList(); });
      return b;
    }));
  }

  async function loadList() {
    const r = await guarded(list, () => rpc('email_queue_list', { p_status: filtro, p_limit: PAGE, p_offset: page * PAGE }));
    if (!r) return;
    const rows = (Array.isArray(r.rows) ? r.rows : []).map((m) => {
      const ver = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Ver correo para ${m.recipient_email}` }, 'Ver');
      ver.addEventListener('click', () => open(m.id));
      const acc = [ver];
      if (m.status === 'fallido') { const b = h('button', { class: 'i18-btn', type: 'button', 'data-act': 'reintentar' }, 'Reintentar'); b.addEventListener('click', () => act('email_queue_retry', m.id, b)); acc.push(b); }
      if (m.status === 'pendiente' || m.status === 'fallido') { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'data-act': 'cancelar' }, 'Cancelar'); b.addEventListener('click', () => act('email_queue_cancel', m.id, b)); acc.push(b); }
      return h('tr', {}, h('td', {}, dt(m.created_at)), h('td', {}, String(m.topic || 'Sin tema').replaceAll('_', ' ')), h('td', {}, m.recipient_email), h('td', {}, m.subject),
        h('td', {}, h('span', { class: `cc-st cc-${m.status}` }, ETQ[m.status] || m.status), m.last_error ? h('small', { class: 'i18-sub' }, ` · ${m.last_error}`) : null),
        h('td', { class: 'i18-r' }, `${m.attempts}/${m.max_attempts}`), h('td', { class: 'cc-acts' }, acc));
    });
    const total = Number(r.total) || 0;
    const pages = Math.max(1, Math.ceil(total / PAGE));
    const prev = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: page === 0 }, 'Anterior');
    const next = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: page + 1 >= pages }, 'Siguiente');
    prev.addEventListener('click', () => { page--; loadList(); }); next.addEventListener('click', () => { page++; loadList(); });
    list.replaceChildren(h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Creado', 'Aviso', 'Destinatario', 'Asunto', 'Estado', 'Intentos', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, rows.length ? rows : h('tr', {}, h('td', { colspan: '7', class: 'i18-empty' }, 'No hay correos con ese estado.'))))),
      h('div', { class: 'av-row' }, prev, h('span', { class: 'i18-sub' }, `Página ${page + 1} de ${pages} · ${total} correo(s)`), next));
  }

  async function act(fn, id, btn) {
    btn.disabled = true;
    try { await rpc(fn, { p_id: id }); await Promise.all([loadTop(), loadList()]); det.replaceChildren(); }
    catch (e) { det.replaceChildren(note(e.message, 'error')); btn.disabled = false; }
  }

  async function open(id) {
    const m = await guarded(det, () => rpc('email_queue_get', { p_id: id }));
    if (!m) return;
    const fr = h('iframe', { class: 'av-frame', title: 'Contenido del correo', sandbox: '', referrerpolicy: 'no-referrer' });
    fr.srcdoc = m.html;
    det.replaceChildren(h('section', { class: 'i18-card', id: 'cc-detail' }, h('h3', {}, 'Correo seleccionado'),
      h('p', {}, h('strong', {}, 'Para: '), m.recipient_email, ' · ', h('strong', {}, 'Asunto: '), m.subject, ' · ', h('strong', {}, 'Plantilla: '), `v${m.template_version}`),
      fr,
      h('h4', {}, 'Bitácora de envío'),
      h('ul', { class: 'cc-log' }, (Array.isArray(m.log) ? m.log : []).map((l) => h('li', {}, `${dt(l.at)} · ${l.event}${l.detail ? ' · ' + l.detail : ''}`)))));
  }

  async function loadTpl() {
    const t = await guarded(tpl, () => rpc('email_templates_list'));
    if (!t) return;
    const cards = (Array.isArray(t) ? t : []).map((x) => {
      const out = h('div', { 'aria-live': 'polite' });
      const body = [h('p', {}, h('strong', {}, 'Asunto: '), x.subject), h('p', { class: 'i18-sub' }, `Variables: ${(Array.isArray(x.variables) ? x.variables : []).map((v) => `{{${v}}}`).join(' ')}`), h('pre', { class: 'av-text' }, x.body_text)];
      if (isSuper && !x.is_active) {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Volver a esta versión');
        b.addEventListener('click', async () => { b.disabled = true; try { await rpc('email_template_activate', { p_code: x.code, p_version: x.version }); await loadTpl(); } catch (e) { out.replaceChildren(note(e.message, 'error')); b.disabled = false; } });
        body.push(b);
      }
      return h('details', { class: 'i18-card' }, h('summary', {}, `${String(x.code || 'Sin código').replaceAll('_', ' ')} · versión ${x.version}${x.is_active ? ' (activa)' : ''}`), ...body, out);
    });
    tpl.replaceChildren(isSuper ? null : note('Las plantillas las cambia solo el Super Admin porque afectan a todos los operadores.'), ...cards);
  }

  drawTabs();
  await Promise.all([loadTop(), loadList(), loadTpl()]);
}
export default render;
