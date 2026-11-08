/** SOFA · 5.29 · «Mi panel»: visión unificada del cliente: cobros ARS, habilitación MISPAS y cuenta SOFA.
 *  Tres RPCs en paralelo (client_account + collection_calendar + client_habilitation) para el médico
 *  que quiere un vistazo rápido de toda su relación con SOFA sin navegar entre tres pantallas.
 *  Reutiliza los RPCs ya usados por mi-dinero, mi-habilitacion y mi-cuenta-sofa sin agregar carga
 *  al servidor: las mismas funciones, combinadas en una sola pantalla de inicio. */
import { rpc, h, money, fmtDate, note, kpi, guarded } from '../services/iter18.js';
import { openPrint, fillPrint } from '../utils/print-doc.js';

const DIA = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/** '2026-10-24' → 'vie 24 oct' sin depender de la zona horaria local. */
function fechaCorta(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1, d));
  return `${DIA[f.getUTCDay()]} ${d} ${MES[m - 1]}`;
}

/** Días desde hoy hasta una fecha ISO (negativo = pasada). */
function diasHasta(iso) {
  if (!iso) return null;
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return Math.round((new Date(y, m - 1, d) - hoy) / 86400000);
}

export async function render(root, ctx = {}) {
  const org = ctx.membership?.organization_id;
  root.replaceChildren();
  const box = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mi panel'),
    h('p', { class: 'i18-sub' }, 'Su relación con SOFA de un vistazo: cobros de ARS, habilitación MISPAS y su cuenta.'),
    box));

  if (!org) {
    box.replaceChildren(note('No se encontró su consultorio. Cierre la sesión y vuelva a entrar.', 'error'));
    return;
  }

  // Tres RPCs en paralelo — solo client_account es bloqueante
  const [acct, cal, habs] = await Promise.all([
    guarded(box, () => rpc('client_account', { p_org: org })),
    rpc('collection_calendar', { p_org: org }).catch(() => null),
    rpc('client_habilitation', { p_org: org }).catch(() => null),
  ]);
  if (!acct) return;

  const s = acct.summary;
  const totals = cal?.totals ?? {};
  const totalARS = Number(totals.balance ?? 0);
  const atrasado = Number(totals.late_balance ?? 0);

  // ── Hero: lo primero que el médico quiere saber ──────────────────────────
  const hero = h('div', { class: 'md-hero' },
    h('div', { class: 'md-hero-l' }, 'Las ARS le deben'),
    h('div', { class: 'md-hero-v' }, money(totalARS)),
    atrasado > 0
      ? h('div', { class: 'md-hero-w' }, `⚠ ${money(atrasado)} ya pasó la fecha de pago`)
      : h('div', { class: 'md-hero-ok' }, 'Nada atrasado: todo está dentro de plazo.'));

  // ── KPIs ──────────────────────────────────────────────────────────────────
  const activos = acct.contracts.filter((c) => c.status === 'firmado').length;
  const kpis = h('div', { class: 'i18-kpis' },
    kpi('Cobros atrasados', money(atrasado), atrasado > 0 ? 'Contacte a su ARS' : 'Ninguno'),
    kpi('Saldo con SOFA', money(s.balance), s.overdue > 0 ? `${s.overdue_count} vencida(s)` : 'Al día'),
    kpi('Servicios activos', String(activos)),
    kpi('Casos abiertos', String(s.open_cases)));

  // ── Alertas críticas ──────────────────────────────────────────────────────
  const alertas = [];
  if (s.overdue > 0) {
    alertas.push(note(`Tiene ${s.overdue_count} factura(s) vencida(s) por ${money(s.overdue)}. Contacte a SOFA para regularizar.`, 'warn'));
  }
  if (habs) {
    for (const c of habs) {
      if ((c.counts?.critical_open ?? 0) > 0) alertas.push(note(`Habilitación "${c.name}": ${c.counts.critical_open} requisito(s) crítico(s) pendiente(s).`, 'warn'));
      if (c.sofa_reset_note) alertas.push(note(`Caso "${c.name}" fue reiniciado por SOFA: ${c.sofa_reset_note}`, 'warn'));
      if (c.license_days_left != null && c.license_days_left <= 30) alertas.push(note(`Licencia de "${c.name}": vence en ${c.license_days_left} día(s) (${fmtDate(c.license_valid_until)}).`, 'warn'));
    }
  }

  // ── Próximos cobros de ARS ────────────────────────────────────────────────
  const porArs = (cal?.by_ars ?? []).slice();
  const conFecha = porArs.filter((a) => a.next_expected).sort((a, b) => String(a.next_expected).localeCompare(String(b.next_expected)));
  const sinFecha = porArs.filter((a) => !a.next_expected && Number(a.balance) > 0);
  let arsSection = null;
  if (conFecha.length || sinFecha.length) {
    const filas = [];
    for (const a of conFecha.slice(0, 5)) {
      const d = diasHasta(a.next_expected);
      const tarde = d != null && d < 0;
      filas.push(h('li', { class: tarde ? 'mp-ars-row mp-tarde' : 'mp-ars-row' },
        h('span', { class: 'mp-ars-name' }, a.ars),
        tarde
          ? h('span', { class: 'i18-badge i18-atrasado' }, 'atrasado')
          : h('span', { class: 'mp-ars-fecha' }, d === 0 ? 'hoy' : d === 1 ? 'mañana' : fechaCorta(a.next_expected)),
        h('b', {}, money(a.balance))));
    }
    for (const a of sinFecha.slice(0, 2)) {
      filas.push(h('li', { class: 'mp-ars-row mp-tarde' },
        h('span', { class: 'mp-ars-name' }, a.ars),
        h('span', { class: 'i18-badge i18-atrasado' }, 'sin fecha'),
        h('b', {}, money(a.balance))));
    }
    arsSection = h('section', { class: 'i18-card' },
      h('h3', {}, 'Próximos cobros de ARS'),
      h('ul', { class: 'mp-ars-lista' }, ...filas),
      h('a', { class: 'i18-btn i18-sec', href: '#/calendario-cobros' }, 'Ver calendario →'));
  }

  // ── Habilitación MISPAS ───────────────────────────────────────────────────
  let habSection = null;
  if (habs?.length) {
    habSection = h('section', { class: 'i18-card' },
      h('h3', {}, 'Habilitación MISPAS'),
      ...habs.map((c) => {
        const pctVal = c.counts?.applicable ? Math.round(100 * (c.counts.verde || 0) / c.counts.applicable) : 0;
        return h('div', { class: 'mp-hab-row' },
          h('div', { class: 'mp-hab-name' },
            h('span', {}, c.name),
            h('span', { class: `i18-badge ${c.stage === 'habilitado' ? 'i18-proximo' : 'i18-esta_semana'}` }, c.stage_label || c.stage || '—')),
          h('p', { class: 'i18-sub', style: 'text-align:right;margin:3px 0' }, `${pctVal}%`),
          h('div', { class: 'ac-progress', 'aria-hidden': 'true' }, h('div', { style: `width:${pctVal}%` })),
          h('p', { class: 'i18-sub', style: 'margin:4px 0 0' }, `${c.counts?.verde || 0}/${c.counts?.applicable || 0} en verde${c.counts?.critical_open ? ` · ${c.counts.critical_open} crítico(s)` : ''}`));
      }),
      h('a', { class: 'i18-btn i18-sec', href: '#/mi-habilitacion' }, 'Ver detalle →'));
  }

  // ── Solicitudes abiertas ──────────────────────────────────────────────────
  const casosRecientes = acct.cases.slice(0, 3);
  let casosSection = null;
  if (casosRecientes.length) {
    casosSection = h('section', { class: 'i18-card' },
      h('h3', {}, 'Mis solicitudes recientes'),
      ...casosRecientes.map((c) =>
        h('div', { class: 'mp-caso-row i18-bar' },
          h('span', {}, `${c.folio} · ${c.title}`),
          h('span', { class: 'i18-badge i18-esta_semana' }, c.status_label || c.status))),
      h('a', { class: 'i18-btn i18-sec', href: '#/mi-cuenta-sofa' }, 'Ver todas las solicitudes →'));
  }

  // ── Accesos rápidos ───────────────────────────────────────────────────────
  const btnResumen = h('button', { class: 'i18-btn i18-sec', type: 'button', title: 'Genera un PDF con su balance ARS, cuenta SOFA, habilitación y solicitudes.' }, '📄 Descargar resumen');
  btnResumen.addEventListener('click', () => {
    const w = openPrint();
    if (!w) { box.prepend(note('El navegador bloqueó la ventana. Permita ventanas emergentes de SOFA.', 'error')); return; }
    const fecha = new Date().toLocaleDateString('es-DO', { year: 'numeric', month: 'long', day: 'numeric' });
    const blocks = [
      { h: 'Balance ARS' },
      { big: money(totalARS) },
      atrasado > 0 ? { warn: `${money(atrasado)} ya superó la fecha de pago.` } : { p: 'Ningún cobro atrasado. Todo dentro de plazo.' },
    ];
    if (conFecha.length || sinFecha.length) {
      blocks.push({ h: 'Próximos cobros de ARS' });
      blocks.push({ table: { head: ['ARS', 'Fecha esperada', 'Saldo'], rows: [...conFecha.slice(0, 10), ...sinFecha].map((a) => [a.ars, a.next_expected ? fechaCorta(a.next_expected) : 'sin fecha', money(a.balance)]), right: [2] } });
    }
    blocks.push({ h: 'Mi cuenta con SOFA' });
    blocks.push({ table: { head: ['Fact. vencidas', 'Monto vencido', 'Saldo total', 'Casos abiertos', 'Servicios activos'], rows: [[s.overdue_count > 0 ? String(s.overdue_count) : '—', money(s.overdue), money(s.balance), String(s.open_cases), String(activos)]], right: [1, 2] } });
    if (habs?.length) {
      blocks.push({ h: 'Habilitación MISPAS' });
      blocks.push({ table: { head: ['Caso', 'Etapa', 'Avance', 'Críticos pendientes'], rows: habs.map((c) => { const pct = c.counts?.applicable ? Math.round(100 * (c.counts.verde || 0) / c.counts.applicable) : 0; return [c.name, c.stage_label || c.stage || '—', `${pct}% (${c.counts?.verde || 0}/${c.counts?.applicable || 0})`, String(c.counts?.critical_open || 0)]; }) } });
    }
    if (casosRecientes.length) {
      blocks.push({ h: 'Mis solicitudes recientes' });
      blocks.push({ table: { head: ['Folio', 'Solicitud', 'Estado'], rows: casosRecientes.map((c) => [c.folio || '—', c.title, c.status_label || c.status || '—']) } });
    }
    fillPrint(w, 'Mi panel SOFA', `Generado el ${fecha}`, blocks);
  });
  const accesos = h('div', { class: 'i18-bar mp-links' },
    h('a', { class: 'i18-btn i18-sec', href: '#/mi-dinero' }, 'Mi dinero'),
    h('a', { class: 'i18-btn i18-sec', href: '#/mi-cuenta-sofa' }, 'Mi cuenta'),
    h('a', { class: 'i18-btn i18-sec', href: '#/mi-habilitacion' }, 'Mi habilitación'),
    h('a', { class: 'i18-btn i18-sec', href: '#/calendario-cobros' }, 'Cobros ARS'),
    btnResumen);

  // ── Ensamblaje ────────────────────────────────────────────────────────────
  const gridItems = [arsSection, habSection].filter(Boolean);
  const grid = gridItems.length === 2
    ? h('div', { class: 'mp-grid' }, ...gridItems)
    : gridItems.length === 1 ? gridItems[0] : null;

  const sections = [hero, kpis,
    alertas.length ? h('div', { class: 'mp-alertas' }, ...alertas) : null,
    grid, casosSection, accesos].filter(Boolean);
  box.replaceChildren(...sections);
}
export default render;
