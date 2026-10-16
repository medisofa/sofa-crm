/** SOFA · 4.6 · Iteración 56 · Puesta en marcha asistida por cliente (go-live).
 *  Equipo SOFA (Super Admin, Administrador, Operaciones): lista con responsable, fecha y evidencia, carga inicial desde Excel o CSV
 *  (pacientes, citas y cuentas por cobrar viejas) con validación por fila, reporte descargable y asistente «Pasar a real».
 *  Médico: ve su avance en solo lectura. El servidor vuelve a verificar el rol en cada función; ocultar botones no es un control. */
import { rpc, h, fmtDate, note, kpi, guarded, downloadCsv, providerOptions, todayIso } from '../services/iter18.js';
import { readTable, excelDate, detectColumns } from '../utils/xlsx-lite.js';

const MODE = { prueba: 'En prueba', real: 'Real' };
const ST = { pendiente: 'Pendiente', en_curso: 'En curso', completado: 'Completado', no_aplica: 'No aplica' };
const OWNER = { sofa: 'SOFA', medico: 'Médico', secretaria: 'Secretaria', otro: 'Otro' };
const KIND = { pacientes: 'Pacientes', citas: 'Citas', cuentas: 'Cuentas por cobrar viejas (reclamaciones pendientes)' };

/** Encabezados que se reconocen por tipo de carga (sin tildes ni mayúsculas) */
const ALIASES = {
  pacientes: {
    documento: ['documento', 'cedula', 'cedula pasaporte', 'identificacion', 'pasaporte'], nombre: ['nombre', 'paciente', 'nombre completo'],
    fecha_nacimiento: ['fecha nacimiento', 'fecha de nacimiento', 'nacimiento'], sexo: ['sexo', 'genero'], telefono: ['telefono', 'celular', 'tel', 'whatsapp'],
    email: ['email', 'correo', 'correo electronico'], ars: ['ars', 'aseguradora', 'seguro'], afiliado: ['afiliado', 'nss', 'numero afiliado']
  },
  citas: {
    documento: ['documento', 'cedula', 'cedula pasaporte', 'identificacion'], nombre: ['nombre', 'paciente', 'nombre completo'], fecha: ['fecha', 'fecha cita', 'fecha de la cita'],
    hora: ['hora', 'hora cita'], ars: ['ars', 'aseguradora', 'seguro'], afiliado: ['afiliado', 'nss', 'numero afiliado'], motivo: ['motivo', 'razon', 'servicio'],
    estado: ['estado', 'status'], telefono: ['telefono', 'celular', 'tel']
  },
  cuentas: {
    ars: ['ars', 'aseguradora'], servicio: ['servicio', 'codigo', 'procedimiento', 'concepto'], simon: ['simon'], cups: ['cups'], fecha: ['fecha', 'fecha servicio', 'fecha del servicio'],
    paciente: ['paciente', 'nombre', 'nombre afiliado'], nss: ['nss', 'afiliado', 'numero afiliado'], autorizacion: ['autorizacion', 'aprobacion'], cedula: ['cedula', 'documento'],
    monto: ['monto', 'valor', 'total'], cantidad: ['cantidad', 'cant'], modo: ['modo', 'modalidad']
  }
};
const REQUIRED = { pacientes: ['nombre'], citas: ['nombre', 'fecha'], cuentas: ['ars', 'fecha', 'paciente', 'nss'] };
const SAMPLE = {
  pacientes: [['documento', 'nombre', 'fecha_nacimiento', 'sexo', 'telefono', 'email', 'ars', 'afiliado'], ['', 'Paciente Ejemplo Uno', '15/03/1985', 'F', '8095550101', 'ejemplo@correo.test', '', '']],
  citas: [['documento', 'nombre', 'fecha', 'hora', 'ars', 'afiliado', 'motivo', 'estado'], ['', 'Paciente Ejemplo Uno', '10/09/2026', '09:30', '', '', 'Control', 'atendida']],
  cuentas: [['ars', 'servicio', 'fecha', 'paciente', 'nss', 'autorizacion', 'cedula', 'monto', 'cantidad', 'modo'], ['Nombre de la ARS', 'Código interno del servicio', '10/09/2026', 'Afiliado Ejemplo Dos', 'NSS-0001', 'AUT-0001', '', '1500', '1', '']]
};

/** Hora de Excel (fracción del día) o texto → HH:MM */
function cellTime(v) {
  const s = String(v ?? '').trim();
  if (/^0?\.\d+$|^0$|^1$/.test(s) || /^\d\.\d+$/.test(s)) { const n = Number(s); if (n >= 0 && n < 1) { const m = Math.round(n * 1440); return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`; } }
  return s;
}

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const client = ctx.role === 'client';
  const isSuper = ctx.role === 'super_admin';
  const top = h('div', { 'aria-live': 'polite' });
  const detail = h('div', { 'aria-live': 'polite', id: 'gl-detail' });
  root.append(h('div', { class: 'i18-wrap gl-wrap' }, h('h2', {}, client ? 'Mi puesta en marcha con SOFA' : 'Puesta en marcha de clientes'),
    h('p', { class: 'i18-sub' }, client
      ? 'Los pasos para que su consultorio pase de prueba a trabajo real con SOFA. Aquí solo ve su avance; el equipo de SOFA lo va completando con usted.'
      : 'Lista por cliente con responsable, fecha y evidencia; carga inicial desde Excel; y el asistente «Pasar a real», que solo abre cuando todo lo obligatorio está cumplido.'),
    top, detail));

  if (client) { await drawClient(null); return; }
  await drawOverview();

  async function drawOverview() {
    const [ov, ind] = await Promise.all([guarded(top, () => rpc('golive_overview')), rpc('golive_indicador').catch(() => null)]);
    if (!ov) return;
    const prueba = ov.filter((c) => c.mode === 'prueba');
    top.replaceChildren(
      h('div', { class: 'i18-kpis' }, kpi('Clientes en prueba', String(prueba.length), 'Todavía no pasan a real'),
        kpi('Días de la firma a la primera reclamación radicada', ind && ind.avg_days != null ? `${ind.avg_days} (promedio)` : '—', ind ? `${ind.clients_with_claim} cliente(s) con reclamación · ${ind.clients_without_claim} sin radicar` : null),
        kpi('Con pasos atrasados', String(prueba.filter((c) => c.late > 0).length), 'Entre los clientes en prueba')),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {}, ['Cliente', 'Modo', 'Firma', 'Obligatorios', 'Atrasados', 'Próximo vencimiento', 'Días a la 1.ª reclamación', ''].map((x) => h('th', {}, x)))),
        h('tbody', {}, ov.length ? ov.map((c) => {
          const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'data-org': c.org }, 'Abrir');
          b.addEventListener('click', () => drawClient(c.org));
          return h('tr', {}, h('td', {}, c.client), h('td', {}, h('span', { class: `gl-pill gl-${c.mode}` }, MODE[c.mode] || c.mode)), h('td', {}, fmtDate(c.signed_on)),
            h('td', {}, c.has_list ? `${c.mandatory_done} de ${c.mandatory_total}` : 'Cliente anterior'), h('td', { class: c.late ? 'gl-late' : '' }, c.has_list ? String(c.late) : '—'),
            h('td', {}, c.next_due ? fmtDate(c.next_due) : '—'), h('td', {}, c.days_to_first_claim == null ? 'Sin radicar' : String(c.days_to_first_claim)), h('td', {}, b));
        }) : h('tr', {}, h('td', { colspan: '8', class: 'i18-empty' }, 'No hay clientes.'))))));
  }

  async function drawClient(org) {
    const d = await guarded(detail, () => (org ? rpc('golive_checklist', { p_org: org }) : rpc('golive_mine')));
    if (!d) return;
    const ro = d.read_only; const o = d.org;
    const reload = () => drawClient(client ? null : o);
    const parts = [];
    parts.push(h('h3', {}, `${d.client} · `, h('span', { class: `gl-pill gl-${d.mode}` }, MODE[d.mode] || d.mode)));
    parts.push(h('div', { class: 'i18-kpis' }, kpi('Avance de lo obligatorio', d.pct == null ? 'Sin lista' : `${d.mandatory_done} de ${d.mandatory_total}`, d.pct == null ? 'Cliente anterior a la lista' : `${d.pct} %`),
      kpi('Firma del contrato', fmtDate(d.signed_on)), kpi('Primera reclamación radicada', d.first_claim_on ? fmtDate(d.first_claim_on) : 'Todavía no', d.days_to_first_claim != null ? `${d.days_to_first_claim} días después de la firma` : null),
      d.mode === 'real' ? kpi('Pasó a real', fmtDate(d.real_since)) : kpi('Tope de carga hacia atrás', `${d.months_back} meses`)));
    if (!d.has_list) parts.push(note('Este cliente es anterior a la puesta en marcha asistida y ya trabaja en real. No tiene lista.'));
    if (d.has_list) {
      parts.push(h('h4', {}, 'Lista de puesta en marcha'));
      parts.push(stepsTable(d, ro, o, reload));
    }
    if (!ro && d.has_list) {
      parts.push(configForm(d, o, reload));
      if (d.mode === 'prueba') parts.push(loadPanel(d, o, reload));
    }
    parts.push(loadsTable(d));
    if (d.has_list) parts.push(assistant(d, ro, o, reload));
    if (!ro && d.log.length) {
      parts.push(h('h4', {}, 'Bitácora'));
      parts.push(h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Cuándo', 'Quién', 'Acción', 'Detalle'].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.log.map((l) => h('tr', {}, h('td', {}, fmtDate(l.at)), h('td', {}, l.by || '—'), h('td', {}, l.action), h('td', {}, l.detail || '—')))))));
    }
    detail.replaceChildren(...parts);
    detail.scrollIntoView?.({ block: 'nearest' });
  }

  function stepsTable(d, ro, o, reload) {
    const out = h('div', { 'aria-live': 'polite', id: 'gl-step-out' });
    const rows = d.steps.map((s) => {
      const state = s.source === 'automatico' ? 'Cumplido solo' : (ST[s.status] || s.status);
      const cls = s.done ? 'gl-ok' : (s.late ? 'gl-late' : '');
      const cells = [h('td', {}, s.label, s.mandatory ? null : h('small', { class: 'i18-sub' }, ' (opcional)'), s.description ? h('div', { class: 'i18-sub' }, s.description) : null),
        h('td', {}, OWNER[s.owner_role] || s.owner_role, s.owner_label ? h('div', { class: 'i18-sub' }, s.owner_label) : null),
        h('td', { class: s.late ? 'gl-late' : '' }, fmtDate(s.due_on), s.late ? h('div', {}, 'Atrasado') : null),
        h('td', { class: cls }, state), h('td', {}, s.evidence || '—')];
      if (!ro) {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button', 'data-step': s.code }, 'Actualizar');
        b.addEventListener('click', () => editStep(s, o, out, reload));
        cells.push(h('td', {}, b));
      }
      return h('tr', {}, cells);
    });
    return h('div', {}, h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table', id: 'gl-steps' },
      h('thead', {}, h('tr', {}, ['Paso', 'Responsable', 'Fecha límite', 'Estado', 'Evidencia', ro ? null : ''].filter((x) => x !== null).map((x) => h('th', {}, x)))),
      h('tbody', {}, rows))), out);
  }

  function editStep(s, o, out, reload) {
    const st = h('select', { id: 'gl-st' }, Object.entries(ST).filter(([k]) => !(s.mandatory && k === 'no_aplica')).map(([k, v]) => h('option', { value: k, selected: k === s.status }, v)));
    const ev = h('textarea', { id: 'gl-ev', rows: '2', maxlength: '400', style: 'width:100%', placeholder: 'Evidencia: quién lo hizo, cuándo o dónde queda el soporte (mínimo 5 letras)' });
    ev.value = s.evidence || '';
    const due = h('input', { id: 'gl-due', type: 'date', value: s.due_on || '' });
    const ow = h('select', { id: 'gl-ow' }, Object.entries(OWNER).map(([k, v]) => h('option', { value: k, selected: k === s.owner_role }, v)));
    const ol = h('input', { id: 'gl-ol', type: 'text', maxlength: '80', placeholder: 'Nombre de la persona (opcional)', value: s.owner_label || '' });
    const save = h('button', { class: 'i18-btn', type: 'button', id: 'gl-save' }, 'Guardar paso');
    const cancel = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Cancelar');
    const msg = h('div', { 'aria-live': 'polite' });
    cancel.addEventListener('click', () => out.replaceChildren());
    save.addEventListener('click', async () => {
      save.disabled = true; msg.replaceChildren();
      try {
        await rpc('golive_step_update', { p_org: o, p_step: s.code, p_status: st.value, p_evidence: ev.value, p_due: due.value || null, p_owner_role: ow.value, p_owner_label: ol.value });
        await reload();
      } catch (e) { msg.replaceChildren(note(e.message, 'error')); save.disabled = false; }
    });
    out.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, s.label),
      h('label', { for: 'gl-st' }, 'Estado'), st, h('label', { for: 'gl-ev' }, 'Evidencia'), ev, h('label', { for: 'gl-due' }, 'Fecha límite'), due,
      h('label', { for: 'gl-ow' }, 'Responsable'), ow, h('label', { for: 'gl-ol' }, 'Nombre del responsable'), ol, h('div', { class: 'i18-actions' }, save, cancel), msg));
    out.scrollIntoView?.({ block: 'nearest' });
  }

  function configForm(d, o, reload) {
    const signed = h('input', { id: 'gl-signed', type: 'date', value: d.signed_on || '', max: todayIso() });
    const months = h('input', { id: 'gl-months', type: 'number', min: '1', max: '60', value: String(d.months_back) });
    const go = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Guardar configuración');
    const msg = h('div', { 'aria-live': 'polite' });
    go.addEventListener('click', async () => {
      go.disabled = true; msg.replaceChildren();
      try { await rpc('golive_config_set', { p_org: o, p_signed_on: signed.value || null, p_months_back: months.value ? Number(months.value) : null }); await reload(); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    return h('details', { class: 'i18-card' }, h('summary', {}, 'Configuración del cliente (fecha de firma y tope de meses de la carga)'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'gl-signed' }, 'Fecha de firma', signed), h('label', { for: 'gl-months' }, 'Tope de meses hacia atrás (1 a 60)', months), go), msg);
  }

  function loadPanel(d, o, reload) {
    const kind = h('select', { id: 'gl-kind' }, Object.entries(KIND).map(([k, v]) => h('option', { value: k }, v)));
    const prov = h('select', { id: 'gl-prov' }, h('option', { value: '' }, 'Elija el médico…'));
    const file = h('input', { id: 'gl-file', type: 'file', accept: '.xlsx,.csv,.txt' });
    const src = h('input', { id: 'gl-src', type: 'text', maxlength: '80', placeholder: 'Ej.: Excel del consultorio', value: 'Excel del consultorio' });
    const go = h('button', { class: 'i18-btn', type: 'button', id: 'gl-review' }, 'Revisar el archivo');
    const tpl = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar plantilla');
    const out = h('div', { 'aria-live': 'polite', id: 'gl-load-out' });
    providerOptions().then((ps) => { for (const p of ps.filter((x) => x.organization_id === o)) prov.append(h('option', { value: p.id }, p.full_name)); if (prov.options.length === 2) prov.selectedIndex = 1; }).catch(() => {});
    const needsProv = () => kind.value !== 'pacientes';
    tpl.addEventListener('click', () => downloadCsv(`plantilla_${kind.value}.csv`, SAMPLE[kind.value]));
    let rows = null; let fname = '';
    go.addEventListener('click', async () => {
      out.replaceChildren();
      if (!file.files[0]) return out.replaceChildren(note('Elija el archivo de Excel o CSV.', 'error'));
      if (needsProv() && !prov.value) return out.replaceChildren(note('Elija el médico al que pertenece el archivo (un archivo por médico).', 'error'));
      go.disabled = true;
      try {
        const t = await readTable(file.files[0]); fname = file.files[0].name;
        if (t.length < 2) throw new Error('El archivo no tiene filas debajo de los encabezados. La primera fila debe tener los nombres de las columnas.');
        const map = detectColumns(t[0], ALIASES[kind.value]);
        const miss = REQUIRED[kind.value].filter((k) => map[k] == null);
        if (kind.value === 'cuentas' && map.servicio == null && map.simon == null && map.cups == null) miss.push('servicio');
        if (miss.length) throw new Error(`No se reconocieron las columnas: ${miss.join(', ')}. Descargue la plantilla y use esos encabezados.`);
        rows = t.slice(1).map((r) => Object.fromEntries(Object.entries(map).map(([k, i]) => [k, k.startsWith('fecha') ? excelDate(r[i]) : (k === 'hora' ? cellTime(r[i]) : (r[i] ?? ''))])));
        const rep = await rpc('golive_load', { p_org: o, p_kind: kind.value, p_rows: rows, p_commit: false, p_file: fname, p_provider: needsProv() ? prov.value : null, p_source: src.value });
        preview(rep);
      } catch (e) { out.replaceChildren(note(e.message, 'error')); } finally { go.disabled = false; }
    });
    function summary(rep) {
      return h('div', { class: 'gl-sum' }, h('span', { class: 'gl-pill gl-real' }, `${rep.accepted} aceptadas`), h('span', { class: `gl-pill ${rep.rejected ? 'gl-late-pill' : 'gl-prueba'}` }, `${rep.rejected} rechazadas`),
        h('span', { class: 'i18-sub' }, `de ${rep.total} filas · tope: ${rep.months_back} meses hacia atrás (desde el ${fmtDate(rep.since)})`));
    }
    function rowsTable(rep, only) {
      const list = rep.rows.filter((r) => !only || r.status === only);
      return list.length ? h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table', id: 'gl-rows' },
        h('thead', {}, h('tr', {}, ['Fila', 'Estado', 'Documento', 'Nombre', 'Motivo'].map((x) => h('th', {}, x)))),
        h('tbody', {}, list.slice(0, 200).map((r) => h('tr', { class: r.status === 'rechazada' ? 'gl-rej' : '' }, h('td', {}, String(r.row)), h('td', {}, r.status === 'aceptada' ? 'Aceptada' : 'Rechazada'),
          h('td', {}, r.doc || '—'), h('td', {}, r.name || '—'), h('td', {}, (r.reasons || []).join(' · ') || '—')))))) : null;
    }
    const csv = (rep) => downloadCsv(`reporte_carga_${kind.value}_${todayIso()}.csv`, [['Fila', 'Estado', 'Motivo', 'Documento', 'Nombre']].concat(rep.rows.map((r) => [r.row, r.status === 'aceptada' ? 'Aceptada' : 'Rechazada', (r.reasons || []).join(' · '), r.doc || '', r.name || ''])));
    function preview(rep) {
      const dl = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar reporte (CSV)');
      dl.addEventListener('click', () => csv(rep));
      const commit = h('button', { class: 'i18-btn', type: 'button', id: 'gl-commit', disabled: rep.accepted === 0 }, `Cargar las ${rep.accepted} filas aceptadas`);
      commit.addEventListener('click', async () => {
        if (!window.confirm(`Se cargarán ${rep.accepted} filas. Las ${rep.rejected} rechazadas NO se cargan y quedan en el reporte. ¿Continuar?`)) return;
        commit.disabled = true;
        try {
          const r = await rpc('golive_load', { p_org: o, p_kind: kind.value, p_rows: rows, p_commit: true, p_file: fname, p_provider: needsProv() ? prov.value : null, p_source: src.value });
          const dl2 = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descargar reporte (CSV)'); dl2.addEventListener('click', () => csv(r));
          out.replaceChildren(note(`Listo: ${r.accepted} filas cargadas y ${r.rejected} rechazadas. El reporte quedó guardado.`, 'ok'), summary(r), rowsTable(r, 'rechazada'), h('div', { class: 'i18-actions' }, dl2));
          setTimeout(reload, 1800);
        } catch (e) { out.replaceChildren(note(e.message, 'error')); }
      });
      out.replaceChildren(note('Vista previa: todavía no se guardó nada.'), summary(rep), rowsTable(rep), rep.rows.length > 200 ? h('p', { class: 'i18-sub' }, `Se muestran 200 de ${rep.rows.length} filas; el CSV trae todas.`) : null, h('div', { class: 'i18-actions' }, commit, dl));
    }
    return h('section', { class: 'i18-card gl-load' }, h('h4', { style: 'margin-top:0' }, 'Carga inicial desde Excel o CSV'),
      note('Una fila por registro. Se valida fila por fila: cédula con dígito verificador, sin duplicados y dentro del tope de meses. Las filas rechazadas no se cargan y el reporte dice por qué. Nada se guarda hasta que confirme.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'gl-kind' }, 'Qué se carga', kind), h('label', { for: 'gl-prov' }, 'Médico (citas y cuentas)', prov), h('label', { for: 'gl-src' }, 'Sistema de origen', src),
        h('label', { for: 'gl-file' }, 'Archivo (.xlsx o .csv)', file)), h('div', { class: 'i18-actions' }, go, tpl), out);
  }

  function loadsTable(d) {
    if (!d.loads.length) return h('p', { class: 'i18-sub' }, 'Todavía no hay cargas iniciales confirmadas.');
    return h('div', {}, h('h4', {}, 'Cargas iniciales hechas'), h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table', id: 'gl-loads' },
      h('thead', {}, h('tr', {}, ['Fecha', 'Qué', 'Archivo', 'Filas', 'Aceptadas', 'Rechazadas', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, d.loads.map((l) => {
        const b = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Reporte (CSV)');
        b.addEventListener('click', async () => {
          try {
            const r = await rpc('golive_load_report', { p_batch: l.id });
            downloadCsv(`reporte_carga_${l.kind}_${String(l.at).slice(0, 10)}.csv`, [['Fila', 'Estado', 'Motivo', 'Documento', 'Nombre']].concat(r.rows.map((x) => [x.row, x.status === 'aceptada' ? 'Aceptada' : 'Rechazada', (x.reasons || []).join(' · '), x.doc || '', x.name || ''])));
          } catch (e) { b.after(note(e.message, 'error')); }
        });
        return h('tr', {}, h('td', {}, fmtDate(l.at)), h('td', {}, KIND[l.kind] || l.kind), h('td', {}, l.file || '—'), h('td', {}, String(l.total)), h('td', {}, String(l.accepted)),
          h('td', { class: l.rejected ? 'gl-late' : '' }, String(l.rejected)), h('td', {}, b));
      })))));
  }

  /** Asistente «Pasar a real»: 1) lista obligatoria, 2) cargas, 3) confirmar. El médico solo lo ve. */
  function assistant(d, ro, o, reload) {
    const miss = d.missing || [];
    const accepted = d.loads.reduce((a, l) => a + l.accepted, 0); const rejected = d.loads.reduce((a, l) => a + l.rejected, 0);
    const s1 = h('li', { class: miss.length ? 'gl-bad' : 'gl-good' }, h('strong', {}, '1. Lista obligatoria'), ' · ',
      miss.length ? `faltan ${miss.length}: ${miss.join('; ')}` : 'los 9 pasos obligatorios están cumplidos');
    const s2 = h('li', {}, h('strong', {}, '2. Cargas iniciales'), ' · ', d.loads.length ? `${accepted} filas cargadas y ${rejected} rechazadas en ${d.loads.length} carga(s); revise los reportes con el médico` : 'sin cargas (el cliente arranca sin datos anteriores, si así lo confirmó el médico)');
    const head = h('h4', {}, d.mode === 'real' ? 'Estado: el cliente ya trabaja en real' : 'Pasar a real');
    const box = h('section', { class: 'i18-card gl-assist', id: 'gl-assist' }, head, h('ol', { class: 'gl-ol' }, s1, s2));
    if (d.mode === 'real') {
      box.append(h('p', {}, `Pasó a real el ${fmtDate(d.real_since)}.`));
      if (isSuper && !ro) {
        const why = h('input', { type: 'text', id: 'gl-back-why', maxlength: '200', placeholder: 'Motivo (mínimo 10 letras)' }); const bb = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Devolver a prueba'); const msg = h('div', { 'aria-live': 'polite' });
        bb.addEventListener('click', async () => { try { await rpc('golive_go_back', { p_org: o, p_reason: why.value }); await reload(); } catch (e) { msg.replaceChildren(note(e.message, 'error')); } });
        box.append(h('div', { class: 'i18-bar' }, h('label', { for: 'gl-back-why' }, 'Solo el Super Admin', why), bb), msg);
      }
      return box;
    }
    if (ro) { box.append(note(d.ready ? 'Todo está listo. El equipo de SOFA hará el paso a real con usted.' : 'Cuando todo lo obligatorio esté cumplido, el equipo de SOFA pasará su consultorio a real.')); return box; }
    const word = h('input', { type: 'text', id: 'gl-word', autocomplete: 'off', placeholder: 'Escriba PASAR A REAL', disabled: !d.ready });
    const nt = h('input', { type: 'text', id: 'gl-note', maxlength: '200', placeholder: 'Nota (opcional)', disabled: !d.ready });
    const go = h('button', { class: 'i18-btn', type: 'button', id: 'gl-go', disabled: !d.ready }, 'Pasar a real');
    const msg = h('div', { 'aria-live': 'polite', id: 'gl-go-out' });
    word.addEventListener('input', () => { go.disabled = !d.ready || word.value.trim() !== 'PASAR A REAL'; });
    go.disabled = true;
    go.addEventListener('click', async () => {
      go.disabled = true;
      try { await rpc('golive_go_real', { p_org: o, p_confirm: word.value, p_note: nt.value || null }); await reload(); }
      catch (e) { msg.replaceChildren(note(e.message, 'error')); go.disabled = false; }
    });
    box.append(h('p', { class: 'gl-ol-3' }, h('strong', {}, '3. Confirmar'), d.ready ? ' · todo listo: escriba PASAR A REAL para confirmar. Queda en la bitácora.' : ' · se habilita cuando la lista obligatoria esté completa.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'gl-word' }, 'Confirmación', word), h('label', { for: 'gl-note' }, 'Nota', nt), go), msg);
    return box;
  }
}
export default render;
