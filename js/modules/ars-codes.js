/** SOFA · 2.1 · Iteración 31 · Códigos del prestador con cada ARS (las 21), en 6 estados con historial.
 *  Lo usan la ficha del cliente (pestaña «Códigos ARS») y «Mi ficha» del Médico.
 *  Todo pasa por funciones de la base (114): client_ars_matrix, set_ars_code_status y ars_code_history. */
import { rpc, h, fmtDate, note, guarded } from '../services/iter18.js';

export const STATUS = {
  sin_codigo: ['Sin código', 'st-none'], en_preparacion: ['Documentos en preparación', 'st-prep'], solicitado: ['Solicitado', 'st-req'],
  pendiente_respuesta: ['Pendiente de respuesta', 'st-wait'], codificado: ['Codificado', 'st-ok'], rechazado: ['Rechazado', 'st-bad']
};
const ORDER = ['codificado', 'pendiente_respuesta', 'solicitado', 'en_preparacion', 'rechazado', 'sin_codigo'];
const pill = (s) => h('span', { class: `ac-pill ${STATUS[s]?.[1] || ''}` }, STATUS[s]?.[0] || s);
const fmtTs = (iso) => (iso ? new Date(iso).toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' }) : '—');

export async function mountArsCodes(box, { orgId }) {
  let filter = ''; let provIdx = 0; let data;
  const head = h('div'); const body = h('div', { 'aria-live': 'polite' }); const pane = h('div', { 'aria-live': 'polite' });
  box.replaceChildren(head, body, pane);
  await load();

  async function load() {
    data = await guarded(body, () => rpc('client_ars_matrix', { p_org: orgId }));
    if (!data) return;
    if (!data.providers.length) { head.replaceChildren(); body.replaceChildren(note('Este cliente no tiene prestadores activos. Agregue al menos uno en la pestaña Resumen.')); return; }
    draw();
  }
  function draw() {
    const prov = data.providers[Math.min(provIdx, data.providers.length - 1)];
    const rows = prov.rows;
    const count = (s) => rows.filter((r) => r.status === s).length;
    const alerts = rows.filter((r) => r.alert).length;
    const provSel = data.providers.length > 1 ? h('label', { class: 'ac-prov' }, 'Prestador ',
      h('select', { onchange: (e) => { provIdx = Number(e.target.value); draw(); } }, data.providers.map((p, i) => h('option', { value: String(i), selected: i === provIdx }, p.name)))) : h('strong', {}, prov.name);
    head.replaceChildren(h('div', { class: 'ac-head' }, provSel,
      h('div', { class: 'ac-sum', role: 'group', 'aria-label': 'Filtrar por estado' },
        h('button', { type: 'button', class: 'ac-chip', 'aria-pressed': String(!filter), onclick: () => { filter = ''; draw(); } }, `Todas · ${rows.length}`),
        ORDER.map((s) => (count(s) ? h('button', { type: 'button', class: `ac-chip ${STATUS[s][1]}`, 'aria-pressed': String(filter === s), onclick: () => { filter = s; draw(); } }, `${STATUS[s][0]} · ${count(s)}`) : '')),
        alerts ? h('button', { type: 'button', class: 'ac-chip st-bad', 'aria-pressed': String(filter === 'alert'), onclick: () => { filter = 'alert'; draw(); } }, `⚠ Sin respuesta > ${data.alert_days} días · ${alerts}`) : '')),
      h('div', { class: 'ac-progress', title: `${count('codificado')} de ${rows.length} ARS con código` },
        h('div', { style: `width:${Math.round((count('codificado') / rows.length) * 100)}%` })),
      h('p', { class: 'i18-sub' }, `${count('codificado')} de ${rows.length} ARS con código. Sin código asignado, la ARS no paga.`));
    const list = rows.filter((r) => (!filter ? true : filter === 'alert' ? r.alert : r.status === filter));
    body.replaceChildren(h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table ac-table' },
      h('thead', {}, h('tr', {}, ['ARS', 'Estado', 'Código', 'N.º solicitud', 'Fecha', 'Tarifas', ''].map((t) => h('th', {}, t)))),
      h('tbody', {}, list.length ? list.map((r) => h('tr', { class: r.alert ? 'ac-alert' : '' },
        h('td', { 'data-l': 'ARS' }, h('strong', {}, r.ars)),
        h('td', { 'data-l': 'Estado' }, pill(r.status), r.alert ? h('div', { class: 'i18-sub' }, `⚠ ${r.days} días sin respuesta`) : r.days != null ? h('div', { class: 'i18-sub' }, `hace ${r.days} día(s)`) : '',
          r.status === 'rechazado' && r.rejection_reason ? h('div', { class: 'i18-sub' }, r.rejection_reason) : ''),
        h('td', { 'data-l': 'Código', class: 'ac-mono' }, r.code || '—'),
        h('td', { 'data-l': 'N.º solicitud' }, r.request_number || '—'),
        h('td', { 'data-l': 'Fecha' }, r.status === 'codificado' ? fmtDate(r.granted_on) : fmtDate(r.requested_on)),
        h('td', { 'data-l': 'Tarifas' }, r.tariffs ? `${r.tariffs} vigente${r.tariffs > 1 ? 's' : ''}` : '—'),
        h('td', { 'data-l': '' }, h('div', { class: 'i18-actions', style: 'margin:0' },
          data.can_edit ? h('button', { class: 'i18-btn i18-sec ac-sm', type: 'button', onclick: () => edit(prov, r) }, 'Actualizar') : '',
          r.days != null ? h('button', { class: 'i18-link', type: 'button', onclick: () => history(prov, r) }, 'Historial') : '',
          data.can_edit && r.status !== 'codificado' ? h('button', { class: 'i18-link', type: 'button', onclick: () => letter(prov, r) }, 'Carta') : ''))))
        : h('tr', {}, h('td', { colspan: '7', class: 'i18-empty' }, 'No hay ARS en este estado.'))))));
  }

  function edit(prov, r) {
    const st = h('select', { id: 'ac-st' }, Object.entries(STATUS).map(([k, [l]]) => h('option', { value: k, selected: k === r.status }, l)));
    const code = h('input', { id: 'ac-code', value: r.code || '', placeholder: 'Ej.: 12345' });
    const req = h('input', { id: 'ac-req', value: r.request_number || '', placeholder: 'Número de la solicitud ante la ARS' });
    const date = h('input', { id: 'ac-date', type: 'date', max: new Date().toISOString().slice(0, 10) });
    const nt = h('textarea', { id: 'ac-note', rows: '2', maxlength: '500', placeholder: 'Qué se hizo o qué respondió la ARS' });
    const msg = h('div', { 'aria-live': 'polite' });
    const save = h('button', { class: 'i18-btn', type: 'button' }, 'Guardar');
    const help = h('p', { class: 'i18-sub' });
    const sync = () => {
      help.textContent = ({ codificado: 'Escriba el código que asignó la ARS.', rechazado: 'Escriba el motivo del rechazo para saber qué corregir.',
        solicitado: 'La fecha es cuando se entregó la solicitud a la ARS.', pendiente_respuesta: 'La ARS recibió la solicitud y está en revisión.',
        en_preparacion: 'Se están reuniendo los documentos que pide la ARS.', sin_codigo: 'Aún no se ha iniciado la solicitud.' })[st.value];
    };
    st.addEventListener('change', sync); sync();
    save.addEventListener('click', async () => {
      save.disabled = true;
      try {
        await rpc('set_ars_code_status', { p_provider: prov.id, p_ars: r.ars_id, p_status: st.value, p_code: code.value || null,
          p_request_number: req.value || null, p_note: nt.value || null, p_date: date.value || null });
        pane.replaceChildren(note(`${r.ars}: guardado como «${STATUS[st.value][0]}».`, 'ok'));
        await load();
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    pane.replaceChildren(h('section', { class: 'i18-card i18-form ac-edit' },
      h('h4', { style: 'margin:0' }, `${r.ars} · ${prov.name}`),
      h('label', { for: 'ac-st' }, 'Estado', st), help,
      h('label', { for: 'ac-code' }, 'Código asignado', code), h('label', { for: 'ac-req' }, 'N.º de solicitud', req),
      h('label', { for: 'ac-date' }, 'Fecha (si no es hoy)', date), h('label', { for: 'ac-note' }, 'Nota', nt),
      h('div', { class: 'i18-actions' }, save, h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cancelar')), msg));
    pane.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    st.focus();
  }

  // 2.3 · Carta de solicitud de código, lista para imprimir y firmar
  async function letter(prov, r) {
    const d = await guarded(pane, () => rpc('ars_code_letter', { p_provider: prov.id, p_ars: r.ars_id }));
    if (!d) return;
    const today = new Date(d.today + 'T12:00:00').toLocaleDateString('es-DO', { day: 'numeric', month: 'long', year: 'numeric' });
    const o = d.organization; const pv = d.provider;
    const body = h('article', { class: 'sofa-print ac-letter' },
      h('p', { style: 'text-align:right' }, `${o.city || 'Santiago de los Caballeros'}, ${today}`),
      h('p', {}, 'Señores', h('br'), h('strong', {}, d.ars), h('br'), 'Departamento de Prestadores / Afiliación de Prestadores', h('br'), 'Su despacho.'),
      h('p', {}, h('strong', {}, 'Asunto: '), `Solicitud de código de prestador para ${pv.name}`),
      h('p', {}, 'Distinguidos señores:'),
      h('p', {}, `Por medio de la presente, ${o.name}${o.tax_id ? ` (RNC/Cédula ${o.tax_id})` : ''} solicita la asignación del código de prestador de servicios de salud para `,
        h('strong', {}, pv.name), `${pv.specialty ? `, especialidad ${pv.specialty}` : ''}${pv.exequatur ? `, exequátur n.º ${pv.exequatur}` : ''}${pv.tax_id ? `, cédula ${pv.tax_id}` : ''}, con el fin de brindar servicios a los afiliados de ${d.ars}.`),
      h('p', {}, 'Anexamos los documentos requeridos por su institución (copia de cédula y exequátur, título y especialidad, certificación del Colegio Médico, datos bancarios y demás formularios). Quedamos atentos a cualquier requisito adicional.'),
      h('p', {}, `Para seguimiento puede comunicarse con nosotros${o.phone ? ` al ${o.phone}` : ''}${o.email ? ` o al correo ${o.email}` : ''}.${d.operator ? ` La gestión está a cargo de ${d.operator} en representación del prestador.` : ''}`),
      d.request_number ? h('p', {}, `Referencia de solicitud: ${d.request_number}`) : '',
      h('p', {}, 'Atentamente,'), h('p', { style: 'margin-top:56px' }, '______________________________', h('br'), pv.name, h('br'), o.name, o.address ? [h('br'), o.address] : ''));
    pane.replaceChildren(h('section', { class: 'i18-card' },
      h('div', { class: 'hc-head' }, h('h4', { style: 'margin:0' }, `Carta de solicitud · ${r.ars}`),
        h('div', { class: 'i18-actions', style: 'margin:0' }, h('button', { class: 'i18-btn', type: 'button', onclick: () => window.print() }, 'Imprimir o guardar en PDF'),
          h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cerrar'))),
      h('p', { class: 'i18-sub' }, 'Revise el texto: cada ARS puede pedir requisitos propios. Después de entregarla, marque el código como «Solicitado» con el número que le den.'), body));
    pane.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  async function history(prov, r) {
    const ev = await guarded(pane, () => rpc('ars_code_history', { p_provider: prov.id, p_ars: r.ars_id }));
    if (!ev) return;
    pane.replaceChildren(h('section', { class: 'i18-card' },
      h('div', { class: 'hc-head' }, h('h4', { style: 'margin:0' }, `Historial · ${r.ars}`), h('button', { class: 'i18-link', type: 'button', onclick: () => pane.replaceChildren() }, 'Cerrar')),
      ev.length ? h('ol', { class: 'ac-timeline' }, ev.map((e) => h('li', {}, h('div', {}, pill(e.to), e.from ? h('span', { class: 'i18-sub' }, ` desde ${STATUS[e.from]?.[0] || e.from}`) : ''),
        h('div', { class: 'i18-sub' }, `${fmtTs(e.at)} · ${e.by || 'sistema'}`), e.note ? h('div', {}, e.note) : ''))) : note('Sin cambios registrados todavía (los anteriores a la versión 2.1 no tienen historial).')));
  }
}
