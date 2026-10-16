/** SOFA · 5.1 · I61 · «Calidad de captura»: indicador por secretaria (meta menos de 2 % de reclamaciones devueltas por error de captura) y reglas de calidad del dato.
 *  La secretaria ve solo lo suyo; Administración y Operaciones ven a todas; solo Super Admin y Administrador editan las reglas y solo el Super Admin enciende el bloqueo.
 *  El servidor vuelve a verificar el rol en cada función; ocultar partes de la pantalla no es un control. */
import { h, note, kpi, guarded, fmtDate, todayIso } from '../services/iter18.js';
import * as dq from '../services/calidad-dato.js';

const KIND = { dx_requerido: 'El servicio exige diagnóstico', dx_permitidos: 'Solo estos diagnósticos', dx_excluidos: 'Estos diagnósticos no se aceptan' };
const MODE = { advertir: 'Advertir', bloquear: 'Bloquear' };
const STATUS = { activa: 'Activa', inactiva: 'Inactiva' };
const pct = (n) => `${Number(n ?? 0).toLocaleString('es-DO', { maximumFractionDigits: 2 })} %`;
const sel = (id, map, value, attrs = {}) => h('select', { id, ...attrs }, Object.entries(map).map(([k, v]) => h('option', { value: k, selected: k === value }, v)));
const primerDiaMes = () => `${todayIso().slice(0, 7)}-01`;

export async function render(root, ctx = {}) {
  root.replaceChildren();
  const role = ctx.role;
  const soloMia = role === 'capturer';
  const veTodo = ['super_admin', 'admin', 'operations'].includes(role);
  const box = h('div', { class: 'cq-ind', 'aria-live': 'polite' });
  const cfg = h('div', { class: 'cq-cfg', 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap cq-wrap' },
    h('h2', {}, soloMia ? 'Mi calidad de captura' : 'Calidad de captura'),
    h('p', { class: 'i18-sub' }, soloMia
      ? 'Cuántas de las reclamaciones que usted capturó fueron devueltas o glosadas por un error de captura. La meta es menos de 2 %. Aquí solo ve lo suyo.'
      : 'Indicador por secretaria (meta: menos de 2 % de reclamaciones devueltas por error de captura) y reglas que detienen el error al escribirlo: cédula, NSS y diagnóstico contra el servicio.'),
    box, veTodo ? cfg : null));

  // ── Indicador ──
  const desde = h('input', { id: 'cq-desde', type: 'date', value: primerDiaMes() });
  const hasta = h('input', { id: 'cq-hasta', type: 'date', value: todayIso() });
  const cli = h('select', { id: 'cq-cli' }, h('option', { value: '' }, 'Todos los clientes'));
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Ver indicador');
  const out = h('div', { 'aria-live': 'polite' });
  const bar = h('div', { class: 'i18-bar cq-filtro' }, h('label', { for: 'cq-desde' }, 'Desde'), desde, h('label', { for: 'cq-hasta' }, 'Hasta'), hasta, !soloMia ? cli : null, go);
  box.append(bar, out);
  if (!soloMia) dq.opcionesClientes().then((c) => c.forEach((x) => cli.append(h('option', { value: x.id }, x.trade_name || x.legal_name)))).catch(() => {});

  async function cargarIndicador() {
    const d = await guarded(out, () => dq.indicadorSecretarias(desde.value, hasta.value, cli.value || null));
    if (!d) return;
    const t = d.total || {};
    const cumple = t.cumple_meta;
    const kpis = h('div', { class: 'i18-kpis' },
      kpi(soloMia ? 'Mi error de captura' : 'Error de captura del grupo', pct(t.pct_error), cumple ? `Cumple la meta (menos de ${pct(d.meta_pct)})` : `Sobre la meta de ${pct(d.meta_pct)}`),
      kpi('Reclamaciones capturadas', String(t.capturadas ?? 0)), kpi('Devueltas o glosadas por captura', String(t.con_error ?? 0)));
    const filas = d.filas || [];
    const tabla = h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table cq-tabla' },
      h('thead', {}, h('tr', {}, ['Secretaria', 'Capturadas', 'Devueltas', 'Glosadas por captura', '% error', 'Meta'].map((x, i) => h('th', { class: i > 0 && i < 5 ? 'i18-r' : '' }, x)))),
      h('tbody', {}, filas.length ? filas.map((f) => h('tr', {}, h('td', {}, f.nombre), h('td', { class: 'i18-r' }, String(f.capturadas)), h('td', { class: 'i18-r' }, String(f.devueltas)),
        h('td', { class: 'i18-r' }, String(f.glosadas_por_captura)), h('td', { class: 'i18-r' }, pct(f.pct_error)),
        h('td', {}, h('span', { class: `cq-pill ${f.cumple_meta ? 'cq-ok' : 'cq-mal'}` }, f.cumple_meta ? 'Cumple' : 'Por mejorar'))))
        : h('tr', {}, h('td', { colspan: '6', class: 'i18-empty' }, 'No hay reclamaciones capturadas en este período.')))));
    const tend = (d.tendencia || []).length ? h('div', { class: 'cq-tend' }, h('h3', {}, 'Últimos 6 meses'),
      h('ul', { class: 'cq-lista' }, d.tendencia.map((m) => h('li', {}, h('span', { class: 'cq-mes' }, m.mes),
        h('meter', { class: `cq-meter ${Number(m.pct_error) < Number(d.meta_pct) ? 'cq-ok' : 'cq-mal'}`, min: '0', max: '10', value: String(Math.min(Number(m.pct_error), 10)), 'aria-label': `${m.mes}: ${pct(m.pct_error)}` }),
        h('span', {}, ` ${pct(m.pct_error)} · ${m.con_error} de ${m.capturadas}`))))) : null;
    out.replaceChildren(kpis, tabla, h('p', { class: 'i18-sub' }, `Período del ${fmtDate(d.desde)} al ${fmtDate(d.hasta)}. Cuenta las reclamaciones devueltas y las glosadas por un motivo marcado como error de captura.`),
      soloMia ? note('Cómo bajarlo: revise la cédula, el NSS y el diagnóstico contra el documento antes de guardar. Los avisos que aparecen bajo cada casilla dicen qué corregir.', 'info') : null, tend);
  }
  go.addEventListener('click', cargarIndicador);
  await cargarIndicador();
  if (!veTodo) return;

  // ── Configuración ──
  let ov = null; let arsOpts = []; let srvOpts = [];
  async function cargar() {
    ov = await guarded(cfg, () => dq.configuracion());
    if (!ov) return;
    try { [arsOpts, srvOpts] = await Promise.all([dq.opcionesArs(), dq.opcionesServicios()]); } catch (_) { arsOpts = []; srvOpts = []; }
    pintar();
  }
  const aviso = h('div', { 'aria-live': 'polite' });
  const accion = async (fn) => { aviso.replaceChildren(); try { await fn(); await cargar(); } catch (e) { aviso.replaceChildren(note(e.message, 'error')); } };

  function pintar() {
    const ed = ov.puede_editar;
    // interruptor y meta
    const sw = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ov.puede_activar }, ov.enforce ? 'Volver a solo advertir' : 'Activar el bloqueo');
    sw.addEventListener('click', () => {
      const motivo = window.prompt(ov.enforce ? 'Motivo para APAGAR el bloqueo (mínimo 10 caracteres):' : 'Motivo para ACTIVAR el bloqueo (mínimo 10 caracteres). Desde ese momento las reglas en modo «Bloquear» impedirán guardar datos incorrectos:');
      if (motivo == null) return;
      accion(() => dq.interruptor(!ov.enforce, motivo));
    });
    const meta = h('input', { id: 'cq-meta', type: 'number', min: '0.1', max: '100', step: '0.1', value: String(ov.target_pct), disabled: !ed });
    const gm = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ed }, 'Guardar meta');
    gm.addEventListener('click', () => accion(() => dq.guardarMeta(Number(meta.value))));
    const estado = h('section', { class: 'i18-card' }, h('h3', {}, 'Bloqueo de las reglas'),
      h('div', { class: 'i18-kpis' }, kpi('Bloqueo', ov.enforce ? 'ACTIVO' : 'Apagado', ov.enforce ? 'Las reglas en modo «Bloquear» impiden guardar' : 'Todo se queda en advertencia (no se bloquea nada)'),
        kpi('Meta de error de captura', pct(ov.target_pct))),
      ov.puede_activar ? sw : note('Solo el Super Admin enciende o apaga el bloqueo.'),
      h('div', { class: 'i18-bar' }, h('label', { for: 'cq-meta' }, 'Meta (% máximo de error)'), meta, gm));

    // comprobaciones básicas
    const cks = ov.checks.map((c) => {
      const m = sel(`cq-ck-m-${c.code}`, MODE, c.mode, { disabled: !ed }); const s = sel(`cq-ck-s-${c.code}`, STATUS, c.status, { disabled: !ed });
      const b = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ed }, 'Guardar');
      b.addEventListener('click', () => accion(() => dq.guardarComprobacion(c.code, m.value, s.value)));
      return h('tr', {}, h('td', {}, c.label), h('td', {}, m), h('td', {}, s), h('td', {}, b));
    });
    const checks = h('section', { class: 'i18-card' }, h('h3', {}, 'Comprobaciones básicas'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Comprobación', 'Modo', 'Estado', ''].map((x) => h('th', {}, x)))), h('tbody', {}, cks))),
      h('p', { class: 'i18-sub' }, 'La cédula con un largo distinto de 11 números se bloquea siempre (la base de datos no la acepta). El dígito verificador, el NSS y el formato del diagnóstico siguen el modo elegido.'));

    // formatos de NSS
    const nss = ov.nss_formats.map((f) => {
      const b = f.ars_id ? h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ed }, 'Quitar') : null;
      b?.addEventListener('click', () => accion(() => dq.borrarFormatoNss(f.ars_id)));
      return h('tr', {}, h('td', {}, f.ars || 'General (todas las ARS)'), h('td', { class: 'i18-r' }, `${f.min_len} a ${f.max_len}`), h('td', {}, f.digits_only ? 'Solo números' : 'Letras y números'), h('td', {}, f.example || '—'), h('td', {}, b));
    });
    const fa = h('select', { id: 'cq-nss-ars' }, h('option', { value: '' }, 'General (todas las ARS)'), arsOpts.map((a) => h('option', { value: a.id }, a.name)));
    const fmin = h('input', { id: 'cq-nss-min', type: 'number', min: '3', max: '30', value: '6' }); const fmax = h('input', { id: 'cq-nss-max', type: 'number', min: '3', max: '30', value: '15' });
    const fdig = h('input', { id: 'cq-nss-dig', type: 'checkbox' }); const fex = h('input', { id: 'cq-nss-ex', type: 'text', maxlength: '60', placeholder: 'Ejemplo ficticio' });
    const fb = h('button', { class: 'i18-btn', type: 'button', disabled: !ed }, 'Guardar formato');
    fb.addEventListener('click', () => accion(() => dq.guardarFormatoNss({ ars_id: fa.value || null, min_len: Number(fmin.value), max_len: Number(fmax.value), digits_only: fdig.checked, example: fex.value })));
    const formatos = h('section', { class: 'i18-card' }, h('h3', {}, 'Formato del NSS'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['ARS', 'Largo', 'Caracteres', 'Ejemplo', ''].map((x) => h('th', {}, x)))), h('tbody', {}, nss))),
      ed ? h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, 'Agregar o cambiar un formato'), h('label', { for: 'cq-nss-ars' }, 'ARS'), fa, h('label', { for: 'cq-nss-min' }, 'Largo mínimo'), fmin,
        h('label', { for: 'cq-nss-max' }, 'Largo máximo'), fmax, h('label', { class: 'i18-chk' }, fdig, ' Solo números'), h('label', { for: 'cq-nss-ex' }, 'Ejemplo'), fex, h('div', {}, fb)) : null);

    // reglas diagnóstico–procedimiento
    const filasR = ov.rules.map((r) => {
      const e = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ed }, 'Editar'); e.addEventListener('click', () => formulario(r));
      const x = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: !ed }, 'Borrar');
      x.addEventListener('click', () => { if (window.confirm(`¿Borrar la regla «${r.name}»? No se puede deshacer.`)) accion(() => dq.borrarRegla(r.id)); });
      return h('tr', {}, h('td', {}, r.name, r.is_example ? h('small', { class: 'i18-sub' }, ' · ejemplo ficticio') : null), h('td', {}, r.ars || 'Todas'), h('td', {}, r.procedure || 'Todos'),
        h('td', {}, KIND[r.kind] || r.kind), h('td', {}, (r.dx_prefixes || []).join(', ') || '—'), h('td', {}, MODE[r.mode]), h('td', {}, h('span', { class: `cq-pill ${r.status === 'activa' ? 'cq-ok' : 'cq-off'}` }, STATUS[r.status])), h('td', {}, e, ' ', x));
    });
    const formBox = h('div', { 'aria-live': 'polite' });
    function formulario(r = null) {
      const nm = h('input', { id: 'cq-r-nombre', type: 'text', maxlength: '140', value: r?.name || '' });
      const ars = h('select', { id: 'cq-r-ars' }, h('option', { value: '' }, 'Todas las ARS'), arsOpts.map((a) => h('option', { value: a.id, selected: a.id === r?.ars_id }, a.name)));
      const sv = h('select', { id: 'cq-r-srv' }, h('option', { value: '' }, 'Todos los servicios'), srvOpts.map((p) => h('option', { value: p.id, selected: p.id === r?.procedure_id }, `${p.internal_code} · ${p.description}`)));
      const kd = sel('cq-r-tipo', KIND, r?.kind || 'dx_requerido'); const pf = h('input', { id: 'cq-r-pref', type: 'text', maxlength: '120', value: (r?.dx_prefixes || []).join(', '), placeholder: 'Ej.: I10, E11, O' });
      const md = sel('cq-r-modo', MODE, r?.mode || 'advertir'); const st = sel('cq-r-estado', STATUS, r?.status || 'inactiva');
      const ms = h('input', { id: 'cq-r-msg', type: 'text', maxlength: '400', value: r?.message || '', placeholder: 'Opcional: mensaje que verá la secretaria (diga qué hacer)' });
      const sv2 = h('button', { class: 'i18-btn', type: 'button' }, r ? 'Guardar cambios' : 'Crear regla'); const cn = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Cancelar');
      cn.addEventListener('click', () => formBox.replaceChildren());
      sv2.addEventListener('click', () => accion(() => dq.guardarRegla({ id: r?.id, name: nm.value, ars_id: ars.value || null, procedure_id: sv.value || null, kind: kd.value,
        dx_prefixes: pf.value.split(/[,;\s]+/).filter(Boolean), mode: md.value, status: st.value, message: ms.value })));
      formBox.replaceChildren(h('fieldset', { class: 'i18-fs i18-form' }, h('legend', {}, r ? 'Editar regla' : 'Nueva regla'),
        h('label', { for: 'cq-r-nombre' }, 'Nombre'), nm, h('label', { for: 'cq-r-ars' }, 'ARS'), ars, h('label', { for: 'cq-r-srv' }, 'Servicio'), sv, h('label', { for: 'cq-r-tipo' }, 'Qué revisa'), kd,
        h('label', { for: 'cq-r-pref' }, 'Prefijos de diagnóstico (CIE-10)'), pf, h('label', { for: 'cq-r-modo' }, 'Modo'), md, h('label', { for: 'cq-r-estado' }, 'Estado'), st,
        h('label', { for: 'cq-r-msg' }, 'Mensaje'), ms, h('div', {}, sv2, ' ', cn)));
      nm.focus();
    }
    const nueva = h('button', { class: 'i18-btn', type: 'button', disabled: !ed }, 'Nueva regla'); nueva.addEventListener('click', () => formulario());
    const reglas = h('section', { class: 'i18-card' }, h('h3', {}, 'Reglas diagnóstico–servicio por ARS'),
      h('p', { class: 'i18-sub' }, 'Cada regla puede aplicar a una ARS y a un servicio, o a todos. Una regla «Bloquear» solo impide guardar cuando el bloqueo global está activo; mientras tanto avisa. Los ejemplos vienen inactivos: edítelos antes de activarlos.'),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' }, h('thead', {}, h('tr', {}, ['Regla', 'ARS', 'Servicio', 'Qué revisa', 'Prefijos', 'Modo', 'Estado', ''].map((x) => h('th', {}, x)))),
        h('tbody', {}, filasR.length ? filasR : h('tr', {}, h('td', { colspan: '8', class: 'i18-empty' }, 'No hay reglas.'))))), nueva, formBox);

    // motivos que cuentan como error de captura
    const mot = h('ul', { class: 'cq-lista' }, ov.error_reasons.map((m) => {
      const c = h('input', { type: 'checkbox', checked: m.is_capture_error, disabled: !ed, 'aria-label': m.name });
      c.addEventListener('change', () => accion(() => dq.marcarMotivo(m.code, c.checked)));
      return h('li', {}, h('label', { class: 'i18-chk' }, c, ` ${m.name}`));
    }));
    const motivos = h('section', { class: 'i18-card' }, h('h3', {}, 'Qué cuenta como error de captura'),
      h('p', { class: 'i18-sub' }, 'Además de las reclamaciones devueltas, el indicador cuenta las glosadas por los motivos marcados aquí.'), mot);
    cfg.replaceChildren(h('h2', {}, 'Reglas de calidad'), estado, checks, formatos, reglas, motivos, aviso);
  }
  await cargar();
}
export default render;
