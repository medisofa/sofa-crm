/** SOFA · 5.0.0 · I60 · Reconsideración de glosas: el paquete completo para responder a la ARS dentro del plazo.
 *  Carta por motivo (solo con plantillas APROBADAS por el Super Admin o el Administrador), índice de soportes verificado contra lo adjunto, seguimiento
 *  (preparada, enviada, aceptada, rechazada, monto recuperado) e indicador de % recuperado. El PDF se arma en el navegador (js/utils/print-doc.js).
 *  Equipo (Super Admin, Administrador, Glosas) prepara y envía; Facturación solo consulta; el Médico ve el ESTADO de lo suyo.
 *  Todas las reglas las aplica la base de datos y vuelve a verificar el rol en cada función. */
import { rpc, h, money, pct, fmtDate, note, kpi, table, guarded } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const STATUS = { preparada: 'Preparada, sin enviar', enviada: 'Enviada a la ARS', aceptada: 'Aceptada por la ARS', rechazada: 'Rechazada por la ARS', anulada: 'Anulada' };
const LIGHT = { rojo: 'Vencido o vence hoy', amarillo: 'Vence pronto', verde: 'A tiempo' };
const localIso = (add = 0) => { const d = new Date(); d.setDate(d.getDate() + add); return d.toLocaleDateString('en-CA'); };
const days = (n) => (n == null ? '—' : n <= 0 ? 'Venció' : `${n} día${n === 1 ? '' : 's'} hábil${n === 1 ? '' : 'es'}`);
const badge = (s) => h('span', { class: `rc-badge rc-${s}` }, STATUS[s] || s);

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const medico = ctx.role === 'client';
  const tabsBar = h('div', { class: 'i18-tabs rc-tabs', role: 'tablist', 'aria-label': 'Secciones de reconsideración' });
  const panel = h('div', { class: 'rc-panel', role: 'tabpanel', 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' }, h('h2', {}, medico ? 'Mis reconsideraciones de glosas' : 'Reconsideración de glosas'),
    h('p', { class: 'i18-sub' }, medico ? 'Aquí ve en qué etapa está cada reclamación que SOFA presentó a la ARS por sus glosas y cuánto dinero se ha recuperado.'
      : 'Cada glosa se responde con un expediente completo: carta aprobada, soportes verificados y envío dentro del plazo. Después se registra qué decidió la ARS.'), tabsBar, panel));
  const SECTIONS = medico ? [['seguimiento', 'Estado de mis glosas']]
    : [['seguimiento', 'Seguimiento'], ['indicador', 'Indicador'], ['plantillas', 'Plantillas de carta'], ['soportes', 'Soportes por motivo']];
  const VIEW = { seguimiento, indicador, plantillas, soportes };
  let current = 'seguimiento'; let statusFilter = '';

  function tabs() {
    tabsBar.replaceChildren(...SECTIONS.map(([k, label]) => {
      const b = h('button', { class: 'i18-tab', type: 'button', role: 'tab', id: `rc-tab-${k}`, 'aria-selected': k === current ? 'true' : 'false', 'aria-controls': 'rc-panel' }, label);
      b.addEventListener('click', () => { current = k; tabs(); show(); });
      return b;
    }));
  }
  function show() { panel.replaceChildren(); panel.id = 'rc-panel'; panel.setAttribute('aria-labelledby', `rc-tab-${current}`); return VIEW[current](); }
  const flash = (box, msg, kind = 'ok') => box.replaceChildren(note(msg, kind));

  // ── Seguimiento ────────────────────────────────────────────────────────────────────────────────────────────────────
  async function seguimiento() {
    const box = h('div', { 'aria-live': 'polite' }); const out = h('div', { id: 'rc-out', 'aria-live': 'polite' }); panel.append(out, box);
    const d = await guarded(box, () => rpc('recon_list', { p_org: null, p_status: statusFilter || null }));
    if (!d) return;
    const rows = d.rows; const blocks = [];
    const cnt = (s) => rows.filter((r) => r.status === s).length;
    const rec = rows.reduce((a, r) => a + Number(r.recovered_amount || 0), 0);
    blocks.push(h('div', { class: 'i18-kpis' }, kpi('Preparadas, sin enviar', String(cnt('preparada')), `${rows.filter((r) => r.light === 'rojo').length} con plazo vencido o que vence hoy`), kpi('Enviadas, esperando a la ARS', String(cnt('enviada'))),
      kpi('Aceptadas', String(cnt('aceptada'))), kpi('Rechazadas', String(cnt('rechazada'))), kpi('Monto recuperado', money(rec))));
    const sel = h('select', { id: 'rc-status', 'aria-label': 'Filtrar por estado' }, h('option', { value: '' }, 'Todos los estados'), Object.entries(STATUS).map(([k, v]) => h('option', { value: k, selected: k === statusFilter }, v)));
    sel.addEventListener('change', () => { statusFilter = sel.value; show(); });
    blocks.push(h('div', { class: 'i18-bar' }, h('label', { for: 'rc-status' }, 'Estado', sel)));
    const cols = [
      { label: 'Glosa', get: (r) => h('div', {}, h('strong', {}, r.glosa_folio || '—'), h('small', { class: 'i18-sub' }, `Ronda ${r.round}`)) },
      ...(medico ? [] : [{ label: 'Cliente', get: (r) => r.client }]),
      { label: 'ARS', get: (r) => r.ars || '—' },
      { label: 'Motivo', get: (r) => r.reason },
      { label: 'Estado', get: (r) => h('div', {}, badge(r.status), r.status === 'enviada' ? h('small', { class: 'i18-sub' }, `Enviada el ${fmtDate(r.sent_on)}${r.sent_late ? ' (fuera de plazo)' : ''}`) : null) },
      { label: 'Plazo', get: (r) => (r.light ? h('span', { class: `rc-light rc-l-${r.light}` }, `${LIGHT[r.light]} · ${days(r.days_left)}`) : r.status === 'preparada' ? '—' : fmtDate(r.resolved_on || r.sent_on)) },
      { label: 'Reclamado', right: true, get: (r) => money(r.amount_claimed) },
      { label: 'Recuperado', right: true, get: (r) => (r.status === 'aceptada' ? money(r.recovered_amount) : '—') }
    ];
    if (!medico) cols.push({ label: '', get: (r) => { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Abrir el paquete de ${r.glosa_folio || 'la glosa'}, ronda ${r.round}` }, 'Abrir'); b.addEventListener('click', () => detalle(r.id)); return b; } });
    blocks.push(rows.length ? table(cols, rows) : note(statusFilter ? 'No hay paquetes en ese estado.' : medico ? 'Todavía no hay reconsideraciones de sus glosas.' : 'Todavía no hay paquetes. Prepare el primero desde «Glosas abiertas sin paquete».', 'info'));
    if (!medico) {
      blocks.push(h('h3', {}, 'Glosas abiertas sin paquete'));
      blocks.push(d.without_package.length ? table([
        { label: 'Glosa', get: (g) => g.glosa_folio || '—' }, { label: 'Cliente', get: (g) => g.client }, { label: 'ARS', get: (g) => g.ars || '—' }, { label: 'Estado de la glosa', get: (g) => g.status_label },
        { label: 'Notificada', get: (g) => fmtDate(g.notified_on) }, { label: 'Vence (7 días hábiles)', get: (g) => h('div', {}, fmtDate(g.due_on), h('small', { class: g.days_left <= 0 ? 'rc-over' : 'i18-sub' }, days(g.days_left))) },
        { label: 'Glosado', right: true, get: (g) => money(g.amount) }, { label: 'Rondas', right: true, get: (g) => String(g.rounds) },
        { label: '', get: (g) => {
          if (!d.can_edit) return h('small', { class: 'i18-sub' }, 'Solo lectura');
          const b = h('button', { class: 'i18-btn', type: 'button', 'aria-label': `Preparar paquete de ${g.glosa_folio || 'la glosa'}` }, 'Preparar paquete');
          b.addEventListener('click', async () => { b.disabled = true; try { const r = await rpc('recon_prepare', { p_glosa: g.glosa_id }); await detalle(r.id, r.missing_supports); } catch (e) { flash(out, e.message, 'error'); b.disabled = false; } });
          return b; } }
      ], d.without_package) : note('Todas las glosas abiertas ya tienen su paquete en curso.', 'ok'));
    }
    box.replaceChildren(...blocks);
  }

  // ── Detalle del paquete ────────────────────────────────────────────────────────────────────────────────────────────
  async function detalle(id, missingHint) {
    panel.replaceChildren(); const out = h('div', { id: 'rc-out', 'aria-live': 'polite' }); const box = h('div', { 'aria-live': 'polite' }); panel.append(out, box);
    const d = await guarded(box, () => rpc('recon_get', { p_id: id }));
    if (!d) { panel.prepend(back()); return; }
    const editor = d.role === 'editor'; const prep = d.status === 'preparada'; const sent = d.status === 'enviada';
    const letter = h('textarea', { id: 'rc-letter', rows: '16', maxlength: '12000', 'aria-label': 'Texto de la carta', disabled: !(editor && prep) }); letter.value = d.letter_text;
    const supRows = d.supports || [];
    const missing = prep ? (d.missing || []) : [];
    const late = d.due_on && prep && localIso() > d.due_on;
    const head = h('div', { class: 'i18-card' }, h('div', { class: 'rc-head' }, h('h3', {}, `Glosa ${d.glosa_folio || ''} · Ronda ${d.round}`), badge(d.status)),
      h('div', { class: 'i18-kpis' }, kpi('Cliente', d.client || '—', d.provider || ''), kpi('ARS', d.ars || '—', d.ars_reference ? `Referencia ${d.ars_reference}` : 'Sin referencia de la ARS'), kpi('Motivo principal', d.reason || '—'),
        kpi('Monto reclamado', money(d.amount_claimed), d.status === 'aceptada' ? `Recuperado ${money(d.recovered_amount)}` : ''),
        kpi('Plazo', fmtDate(d.due_on), prep ? days(d.days_left) : d.sent_late ? 'Se envió fuera de plazo' : d.sent_on ? 'Enviada a tiempo' : '')),
      h('p', { class: 'i18-sub' }, [`Preparada el ${fmtDate(d.prepared_on)}${d.prepared_by ? ` por ${d.prepared_by}` : ''}`, d.sent_on ? `enviada el ${fmtDate(d.sent_on)}${d.sent_by ? ` por ${d.sent_by}` : ''}${d.sent_reference ? ` (ref. ${d.sent_reference})` : ''}` : null,
        d.resolved_on ? `resultado el ${fmtDate(d.resolved_on)}${d.resolved_by ? ` por ${d.resolved_by}` : ''}` : null, d.cancelled_on ? `anulada el ${fmtDate(d.cancelled_on)}` : null].filter(Boolean).join(' · ') + '.'));
    const notes = [];
    if (missing.length) notes.push(note(`Faltan soportes obligatorios: ${missing.join(', ')}. Adjúntelos a la reclamación (Reclamaciones › Documentos) y vuelva a abrir este paquete para verificarlos.`, 'warn'));
    else if (prep) notes.push(note('Todos los soportes obligatorios están adjuntos.', 'ok'));
    if (late) notes.push(note('El plazo ya venció: para enviar tendrá que escribir el motivo del retraso (queda registrado).', 'warn'));
    if (d.late_reason) notes.push(note(`Motivo del envío tardío: ${d.late_reason}`, 'info'));
    if (d.missing_reason) notes.push(note(`Enviada sin todos los soportes obligatorios. Motivo: ${d.missing_reason}`, 'info'));
    if (d.result_note) notes.push(note(`Resultado: ${d.result_note}`, d.status === 'rechazada' ? 'warn' : 'info'));
    if (d.cancel_reason) notes.push(note(`Motivo de la anulación: ${d.cancel_reason}`, 'info'));
    if (missingHint && missingHint.length && !missing.length) notes.push(note(`Faltaban: ${missingHint.join(', ')}.`, 'info'));
    const supTable = supRows.length ? table([
      { label: 'Soporte', get: (s) => s.name }, { label: 'Requisito', get: (s) => (s.requirement === 'obligatorio' ? 'Obligatorio' : 'Recomendado') },
      { label: 'Estado', get: (s) => h('span', { class: s.present ? 'rc-ok' : s.requirement === 'obligatorio' ? 'rc-over' : 'rc-none' }, s.present ? `Adjunto (${s.files})` : s.requirement === 'obligatorio' ? 'Falta' : 'No adjunto') }
    ], supRows) : note('Este motivo no tiene soportes requeridos. Defínalos en «Soportes por motivo».', 'info');
    const items = table([{ label: 'Motivo', get: (i) => i.reason }, { label: 'Glosado', right: true, get: (i) => money(i.amount) }, { label: 'Aceptado por el médico', right: true, get: (i) => money(i.accepted) }, { label: 'Recuperado', right: true, get: (i) => money(i.recovered) }], d.items || []);

    const actions = h('div', { class: 'i18-bar' });
    const printBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'rc-print' }, 'Imprimir o guardar el paquete en PDF');
    printBtn.addEventListener('click', () => {
      const w = openPrint();
      if (!w) { flash(out, 'El navegador bloqueó la ventana del PDF. Permita las ventanas emergentes de SOFA y vuelva a pulsar el botón.', 'error'); return; }
      fillPrint(w, `Reconsideración de la glosa ${d.glosa_folio || ''} · Ronda ${d.round}`, `${d.client || ''} · ${d.ars || ''} · plazo ${fmtDate(d.due_on)}`, [
        ...(missing.length ? [{ warn: `Faltan soportes obligatorios: ${missing.join(', ')}.` }] : []),
        { h: 'Carta de reconsideración' }, { pre: letter.value },
        { h: 'Índice de soportes anexos' }, supRows.length ? { table: { head: ['N.º', 'Soporte', 'Requisito', 'Estado'], right: [0], rows: supRows.map((s, i) => [String(i + 1), s.name, s.requirement === 'obligatorio' ? 'Obligatorio' : 'Recomendado', s.present ? `Adjunto (${s.files})` : 'No adjunto']) } } : { p: 'Sin soportes requeridos para este motivo.' },
        { h: 'Servicios glosados' }, { table: { head: ['Motivo', 'Glosado'], right: [1], rows: (d.items || []).map((i) => [i.reason, money(i.amount)]) } }]);
    });
    actions.append(printBtn);
    const forms = [];
    if (editor && prep) {
      const save = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'rc-save' }, 'Guardar cambios de la carta');
      save.addEventListener('click', async () => { save.disabled = true; try { await rpc('recon_letter_edit', { p_id: d.id, p_text: letter.value }); flash(out, 'Carta guardada.'); } catch (e) { flash(out, e.message, 'error'); } save.disabled = false; });
      actions.prepend(save);
      const on = h('input', { id: 'rc-sent-on', type: 'date', value: localIso(), max: localIso() });
      const ref = h('input', { id: 'rc-ref', type: 'text', maxlength: '120', placeholder: 'N.º de recibo o correo (opcional)' });
      const lateR = h('input', { id: 'rc-late', type: 'text', placeholder: 'Por qué se envía fuera de plazo', 'aria-label': 'Motivo del retraso' });
      const missR = h('input', { id: 'rc-miss', type: 'text', placeholder: 'Por qué se envía sin esos soportes', 'aria-label': 'Motivo de los soportes faltantes' });
      const go = h('button', { class: 'i18-btn', type: 'button', id: 'rc-send' }, 'Registrar el envío a la ARS');
      go.addEventListener('click', async () => {
        go.disabled = true;
        try { const r = await rpc('recon_send', { p_id: d.id, p_sent_on: on.value || null, p_reference: ref.value || null, p_late_reason: lateR.value || null, p_missing_reason: missR.value || null }); await detalle(d.id); flash(document.getElementById('rc-out'), `Envío registrado${r.late ? ' (fuera de plazo, con su motivo)' : ''}. La glosa quedó como «Apelada» y corre el plazo de respuesta de la ARS.`); }
        catch (e) { flash(out, e.message, 'error'); go.disabled = false; }
      });
      forms.push(h('div', { class: 'i18-card' }, h('h3', {}, 'Enviar a la ARS'), h('p', { class: 'i18-sub' }, 'Imprima el PDF, entréguelo a la ARS y registre aquí la fecha real de entrega. Se registra la apelación de la glosa.'),
        h('div', { class: 'i18-bar' }, h('label', { for: 'rc-sent-on' }, 'Fecha de entrega', on), h('label', { for: 'rc-ref' }, 'Referencia', ref),
          late ? h('label', { for: 'rc-late' }, 'Motivo del retraso', lateR) : null, missing.length ? h('label', { for: 'rc-miss' }, 'Motivo de los soportes faltantes', missR) : null, go)));
      const why = h('input', { id: 'rc-cancel-why', type: 'text', placeholder: 'Por qué se anula (mínimo 10 caracteres)', 'aria-label': 'Motivo de la anulación' });
      const del = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'rc-cancel' }, 'Anular el paquete');
      del.addEventListener('click', async () => { del.disabled = true; try { await rpc('recon_cancel', { p_id: d.id, p_reason: why.value }); await detalle(d.id); } catch (e) { flash(out, e.message, 'error'); del.disabled = false; } });
      forms.push(h('div', { class: 'i18-card' }, h('h3', {}, 'Anular'), h('div', { class: 'i18-bar' }, h('label', { for: 'rc-cancel-why' }, 'Motivo', why), del)));
    }
    if (editor && sent) {
      const res = h('select', { id: 'rc-outcome' }, h('option', { value: 'aceptada' }, 'Aceptada por la ARS'), h('option', { value: 'rechazada' }, 'Rechazada por la ARS'));
      const amt = h('input', { id: 'rc-recovered', type: 'number', min: '0', step: '0.01', max: String(d.amount_claimed), placeholder: `Hasta ${money(d.amount_claimed)}` });
      const on = h('input', { id: 'rc-res-on', type: 'date', value: localIso(), max: localIso(), min: d.sent_on || undefined });
      const nt = h('input', { id: 'rc-res-note', type: 'text', maxlength: '500', placeholder: 'Qué respondió la ARS (obligatorio si la rechaza)' });
      const go = h('button', { class: 'i18-btn', type: 'button', id: 'rc-result' }, 'Registrar resultado');
      go.addEventListener('click', async () => {
        go.disabled = true;
        try {
          const r = await rpc('recon_result', { p_id: d.id, p_outcome: res.value, p_recovered: Number(amt.value || 0), p_on: on.value || null, p_note: nt.value || null });
          await detalle(d.id); flash(document.getElementById('rc-out'), `Resultado registrado: ${STATUS[r.status].toLowerCase()}. ${r.next || ''}`.trim(), r.next ? 'warn' : 'ok');
        } catch (e) { flash(out, e.message, 'error'); go.disabled = false; }
      });
      forms.push(h('div', { class: 'i18-card' }, h('h3', {}, 'Resultado de la ARS'), h('p', { class: 'i18-sub' }, 'Registre qué decidió la ARS. Si aceptó, escriba el monto que recuperó; si rechazó, explique por qué: ese dato alimenta la causa raíz.'),
        h('div', { class: 'i18-bar' }, h('label', { for: 'rc-outcome' }, 'Resultado', res), h('label', { for: 'rc-recovered' }, 'Monto recuperado (RD$)', amt), h('label', { for: 'rc-res-on' }, 'Fecha', on), h('label', { for: 'rc-res-note' }, 'Nota', nt), go)));
    }
    box.replaceChildren(head, ...notes, h('h3', {}, 'Carta'), letter, h('h3', {}, 'Índice de soportes'), supTable, h('h3', {}, 'Servicios glosados'), items, actions, ...forms);
    panel.prepend(back());
  }
  function back() { const b = h('button', { class: 'i18-btn i18-sec', type: 'button', id: 'rc-back' }, '← Volver al seguimiento'); b.addEventListener('click', () => { current = 'seguimiento'; tabs(); show(); }); return b; }

  // ── Indicador ──────────────────────────────────────────────────────────────────────────────────────────────────────
  async function indicador() {
    const from = h('input', { id: 'rc-from', type: 'date', value: localIso(-180) }); const to = h('input', { id: 'rc-to', type: 'date', value: localIso() });
    const go = h('button', { class: 'i18-btn', type: 'button' }, 'Consultar'); const res = h('div', { 'aria-live': 'polite' });
    panel.append(h('p', { class: 'i18-sub' }, '% recuperado = monto recuperado ÷ monto recuperable (lo reclamado en los paquetes enviados en el período). Los paquetes anulados no cuentan.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'rc-from' }, 'Desde', from), h('label', { for: 'rc-to' }, 'Hasta', to), go), res);
    async function load() {
      const d = await guarded(res, () => rpc('recon_indicator', { p_org: null, p_from: from.value || null, p_to: to.value || null }));
      if (!d) return;
      const t = d.totals;
      res.replaceChildren(h('div', { class: 'i18-kpis' }, kpi('% recuperado', pct(t.pct_recovered), `${money(t.recovered)} de ${money(t.claimed)}`), kpi('% recuperado de lo ya resuelto', pct(t.pct_recovered_resolved), 'Sin contar lo que la ARS aún no responde'),
        kpi('Paquetes enviados', String(t.sent), `${t.accepted} aceptados · ${t.rejected} rechazados · ${t.pending} esperando`), kpi('Enviados a tiempo', pct(t.pct_on_time), `${t.late} fuera de plazo`)),
        h('h3', {}, 'Por ARS'), d.by_ars.length ? table([{ label: 'ARS', get: (x) => x.ars }, { label: 'Enviados', right: true, get: (x) => String(x.sent) }, { label: 'Reclamado', right: true, get: (x) => money(x.claimed) }, { label: 'Recuperado', right: true, get: (x) => money(x.recovered) }, { label: '%', right: true, get: (x) => pct(x.pct) }], d.by_ars) : note('Sin paquetes enviados en el período.', 'info'),
        h('h3', {}, 'Por motivo de glosa'), d.by_reason.length ? table([{ label: 'Motivo', get: (x) => x.reason }, { label: 'Enviados', right: true, get: (x) => String(x.sent) }, { label: 'Reclamado', right: true, get: (x) => money(x.claimed) }, { label: 'Recuperado', right: true, get: (x) => money(x.recovered) }, { label: '%', right: true, get: (x) => pct(x.pct) }], d.by_reason) : note('Sin datos.', 'info'),
        h('h3', {}, 'Por mes'), d.by_month.length ? table([{ label: 'Mes', get: (x) => x.month }, { label: 'Enviados', right: true, get: (x) => String(x.sent) }, { label: 'Reclamado', right: true, get: (x) => money(x.claimed) }, { label: 'Recuperado', right: true, get: (x) => money(x.recovered) }, { label: '%', right: true, get: (x) => pct(x.pct) }], d.by_month) : note('Sin datos.', 'info'));
    }
    go.addEventListener('click', load); await load();
  }

  // ── Plantillas de carta ────────────────────────────────────────────────────────────────────────────────────────────
  async function plantillas() {
    const box = h('div', { 'aria-live': 'polite' }); const out = h('div', { id: 'rc-out', 'aria-live': 'polite' }); panel.append(out, box);
    const d = await guarded(box, () => rpc('recon_templates_list'));
    if (!d) return;
    const approved = d.templates.filter((t) => t.status === 'aprobada').length;
    const sinAprobar = d.reasons.filter((r) => !r.approved).length;
    const blocks = [note(approved ? `${approved} plantilla(s) aprobada(s). Faltan motivos sin plantilla aprobada: ${sinAprobar}.` : 'Ninguna plantilla está aprobada todavía: no se puede preparar ningún paquete. El Super Admin o el Administrador debe revisar y aprobar cada carta.', approved ? 'info' : 'warn')];
    let editing = null;
    const form = h('div', { class: 'i18-card', id: 'rc-tpl-form' });
    const reason = h('select', { id: 'rc-t-reason' }, h('option', { value: '' }, 'Elija el motivo…'), d.reasons.map((r) => h('option', { value: r.code }, r.name)));
    const ars = h('select', { id: 'rc-t-ars' }, h('option', { value: '' }, 'Todas las ARS'), d.ars.map((a) => h('option', { value: a.id }, a.name)));
    const title = h('input', { id: 'rc-t-title', type: 'text', maxlength: '150', placeholder: 'Título de la plantilla' });
    const body = h('textarea', { id: 'rc-t-body', rows: '12', maxlength: '8000', 'aria-label': 'Texto de la plantilla' });
    const save = h('button', { class: 'i18-btn', type: 'button', id: 'rc-t-save' }, 'Guardar como borrador');
    const clear = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Nueva plantilla');
    function load(t) { editing = t ? t.id : null; reason.value = t ? t.reason_code : ''; ars.value = t && t.ars_id ? t.ars_id : ''; title.value = t ? t.title : ''; body.value = t ? t.body : ''; form.scrollIntoView?.({ block: 'nearest' }); }
    clear.addEventListener('click', () => load(null));
    save.addEventListener('click', async () => {
      save.disabled = true;
      try { const r = await rpc('recon_template_save', { p_id: editing, p_reason: reason.value || null, p_ars: ars.value || null, p_title: title.value, p_body: body.value }); await show(); flash(document.getElementById('rc-out'), r.returned_to_draft ? 'Plantilla guardada. Estaba aprobada y volvió a borrador: hay que aprobarla de nuevo.' : 'Plantilla guardada como borrador. Pida su aprobación para usarla.'); }
      catch (e) { flash(out, e.message, 'error'); save.disabled = false; }
    });
    if (d.can_edit) {
      form.append(h('h3', {}, 'Editar o crear plantilla'), h('p', { class: 'i18-sub' }, `Marcas que se reemplazan con los datos de la glosa: ${d.placeholders.map((x) => `{{${x}}}`).join(' ')}. Cada cambio devuelve la plantilla a borrador.`),
        h('div', { class: 'i18-bar' }, h('label', { for: 'rc-t-reason' }, 'Motivo', reason), h('label', { for: 'rc-t-ars' }, 'ARS', ars), h('label', { for: 'rc-t-title' }, 'Título', title)), h('label', { for: 'rc-t-body' }, 'Carta', body), h('div', { class: 'i18-bar' }, save, clear));
      blocks.push(form);
    } else blocks.push(note('Su rol consulta las plantillas; no las edita.', 'info'));
    blocks.push(table([
      { label: 'Motivo', get: (t) => t.reason }, { label: 'ARS', get: (t) => t.ars || 'Todas' },
      { label: 'Título', get: (t) => h('div', {}, h('strong', {}, t.title), h('small', { class: 'i18-sub' }, `Versión ${t.version} · usada ${t.used} vez/veces`)) },
      { label: 'Estado', get: (t) => h('div', {}, h('span', { class: `rc-badge ${t.status === 'aprobada' ? 'rc-aceptada' : 'rc-preparada'}` }, t.status === 'aprobada' ? 'Aprobada' : 'Borrador'), t.status === 'aprobada' ? h('small', { class: 'i18-sub' }, `${fmtDate(t.approved_on)}${t.approved_by ? ` · ${t.approved_by}` : ''}`) : null) },
      { label: '', get: (t) => {
        const wrap = h('div', { class: 'rc-actions' });
        const act = (label, fn, cls = 'i18-sec') => { const b = h('button', { class: `i18-btn ${cls}`, type: 'button', 'aria-label': `${label}: ${t.title}` }, label); b.addEventListener('click', async () => { b.disabled = true; try { await fn(); await show(); } catch (e) { flash(document.getElementById('rc-out'), e.message, 'error'); b.disabled = false; } }); wrap.append(b); };
        const ver = h('button', { class: 'i18-btn i18-sec', type: 'button' }, d.can_edit ? 'Editar' : 'Ver'); ver.addEventListener('click', () => { if (d.can_edit) load(t); else flash(out, t.body, 'info'); }); wrap.append(ver);
        if (d.can_approve && t.status === 'borrador') act('Aprobar', () => rpc('recon_template_approve', { p_id: t.id }), '');
        if (d.can_approve && t.status === 'aprobada') act('Quitar aprobación', () => rpc('recon_template_unapprove', { p_id: t.id }));
        if (d.can_edit && t.status === 'borrador' && !t.used) act('Borrar', () => rpc('recon_template_delete', { p_id: t.id }));
        return wrap; } }
    ], d.templates));
    box.replaceChildren(...blocks);
  }

  // ── Soportes por motivo ────────────────────────────────────────────────────────────────────────────────────────────
  async function soportes() {
    const box = h('div', { 'aria-live': 'polite' }); const out = h('div', { id: 'rc-out', 'aria-live': 'polite' }); panel.append(out, box);
    const d = await guarded(box, () => rpc('recon_supports_list', { p_reason: null }));
    if (!d) return;
    const reasons = []; d.supports.forEach((s) => { if (!reasons.find((r) => r.code === s.reason_code)) reasons.push({ code: s.reason_code, name: s.reason }); });
    const blocks = [h('p', { class: 'i18-sub' }, 'Qué documentos acompañan la reconsideración de cada motivo. Los obligatorios se verifican contra lo adjunto a la reclamación antes de enviar.')];
    if (d.can_edit) {
      const rs = await rpc('recon_templates_list').catch(() => null);
      const reason = h('select', { id: 'rc-s-reason' }, h('option', { value: '' }, 'Elija el motivo…'), (rs ? rs.reasons : reasons).map((r) => h('option', { value: r.code }, r.name)));
      const doc = h('select', { id: 'rc-s-doc' }, h('option', { value: '' }, 'Elija el documento…'), d.document_types.map((x) => h('option', { value: x.code }, x.name)));
      const req = h('select', { id: 'rc-s-req' }, h('option', { value: 'obligatorio' }, 'Obligatorio'), h('option', { value: 'recomendado' }, 'Recomendado'));
      const nt = h('input', { id: 'rc-s-note', type: 'text', maxlength: '300', placeholder: 'Nota (opcional)' });
      const go = h('button', { class: 'i18-btn', type: 'button', id: 'rc-s-save' }, 'Agregar o actualizar');
      go.addEventListener('click', async () => { go.disabled = true; try { await rpc('recon_support_save', { p_reason: reason.value || null, p_document: doc.value || null, p_requirement: req.value, p_note: nt.value || null }); await show(); flash(document.getElementById('rc-out'), 'Soporte guardado.'); } catch (e) { flash(out, e.message, 'error'); go.disabled = false; } });
      blocks.push(h('div', { class: 'i18-card' }, h('div', { class: 'i18-bar' }, h('label', { for: 'rc-s-reason' }, 'Motivo', reason), h('label', { for: 'rc-s-doc' }, 'Documento', doc), h('label', { for: 'rc-s-req' }, 'Requisito', req), h('label', { for: 'rc-s-note' }, 'Nota', nt), go)));
    }
    blocks.push(d.supports.length ? table([
      { label: 'Motivo', get: (s) => s.reason }, { label: 'Documento', get: (s) => s.document }, { label: 'Requisito', get: (s) => (s.requirement === 'obligatorio' ? 'Obligatorio' : 'Recomendado') }, { label: 'Nota', get: (s) => s.note || '—' },
      { label: '', get: (s) => { if (!d.can_edit) return ''; const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'aria-label': `Quitar ${s.document} de ${s.reason}` }, 'Quitar'); b.addEventListener('click', async () => { b.disabled = true; try { await rpc('recon_support_remove', { p_reason: s.reason_code, p_document: s.document_type_code }); await show(); } catch (e) { flash(document.getElementById('rc-out'), e.message, 'error'); b.disabled = false; } }); return b; } }
    ], d.supports) : note('No hay soportes definidos.', 'warn'));
    box.replaceChildren(...blocks);
  }

  tabs(); await show();
}
export default render;
