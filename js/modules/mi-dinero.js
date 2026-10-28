/** SOFA · 5.22.0 · Médico · «Mi dinero».
 *  Responde UNA pregunta: cuánto me deben y cuándo me pagan. Todo lo demás baja de jerarquía.
 *  Antes eran 19 cifras del mismo tamaño y ninguna fecha; la fecha esperada por ARS ya estaba
 *  calculada en collection_calendar (migración 066) y no se le enseñaba a nadie.
 *  Sigue sin inventar nada: account_statement y collection_calendar, las dos ya probadas. */
import { rpc, h, money, pct, num, kpi, note, guarded, clientOptions, clientName, monthNow, monthToDate } from '../services/iter18.js';

const DIA = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/** '2026-10-24' → 'vie 24 oct'. Se arma a mano para no depender de la zona horaria del navegador. */
function fechaCorta(iso) {
  if (!iso) return null;
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  const f = new Date(Date.UTC(y, m - 1, d));
  return `${DIA[f.getUTCDay()]} ${d} ${MES[m - 1]}`;
}
const diasDesdeHoy = (iso) => {
  if (!iso) return null;
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return Math.round((new Date(y, m - 1, d) - hoy) / 86400000);
};

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const clientSel = h('select', { 'aria-label': 'Consultorio' });
  const clientLbl = h('label', {}, 'Consultorio ', clientSel);
  const monthIn = h('input', { type: 'month', value: monthNow(), max: monthNow(), 'aria-label': 'Mes' });
  const barra = h('div', { class: 'i18-bar' }, clientLbl, h('label', {}, 'Mes ', monthIn));

  async function load() {
    if (!clientSel.value) { out.replaceChildren(note('No hay consultorios disponibles para tu usuario.')); return; }
    const org = clientSel.value, period = monthToDate(monthIn.value);
    const [st, cc] = await Promise.all([
      guarded(out, () => rpc('account_statement', { p_org: org, p_period: period })),
      rpc('collection_calendar', { p_org: org }).catch(() => null),
    ]);
    if (!st) return;
    out.replaceChildren(vista(st, cc, monthIn.value));
  }
  clientSel.addEventListener('change', load);
  monthIn.addEventListener('change', load);

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Mi dinero'),
    h('p', { class: 'i18-sub' }, 'Cuánto le deben las ARS, cuándo lo cobra, y cómo va el mes.'),
    barra, out));
  try {
    const cl = await clientOptions();
    cl.forEach((c) => clientSel.append(h('option', { value: c.id }, clientName(c))));
    // Con un solo consultorio no se le pide al médico que se escoja a sí mismo de una lista de uno.
    if (cl.length < 2) clientLbl.hidden = true;
    await load();
  } catch (e) { out.replaceChildren(note(e.message, 'error')); }
}

function tendencia(ahora, antes) {
  ahora = Number(ahora); antes = Number(antes);
  if (!(antes > 0)) return 'sin mes anterior';
  return `${ahora >= antes ? '▲' : '▼'} ${pct(Math.abs((ahora - antes) / antes * 100))} contra el mes pasado`;
}

/** 'oct 2026' para dejar dicho, en cada tarjeta, de qué período habla. */
function etiquetaMes(ym) {
  if (!ym) return '';
  const [y, m] = ym.split('-').map(Number);
  return `${MES[m - 1]} ${y}`;
}

function vista(st, cc, ym) {
  const p = st.production || {}, caja = st.cash || {}, hon = st.fees || {}, r = st.roi || {}, g = st.glosas || {}, ant = st.previous || {};
  const t = (cc && cc.totals) || {};
  const mes = etiquetaMes(ym);

  // ── Lo primero y lo más grande: cuánto le deben ──────────────────────────────────────────
  const debido = cc ? Number(t.balance || 0) : null;
  const atrasado = Number(t.late_balance || 0);
  const heroe = cc
    ? h('div', { class: 'md-hero' },
        h('div', { class: 'md-hero-l' }, 'Las ARS le deben'),
        h('div', { class: 'md-hero-v' }, money(debido)),
        atrasado > 0
          ? h('div', { class: 'md-hero-w' }, `${money(atrasado)} ya pasó de la fecha en que debían pagarle · ${num(t.late_lotes)} envío(s)`)
          : h('div', { class: 'md-hero-ok' }, 'Nada atrasado: todo está dentro de su plazo.'))
    : note('El calendario de cobros no está disponible ahora. Las cifras del mes sí.', 'info');

  // ── Y enseguida lo que nunca se le había dicho: cuándo ───────────────────────────────────
  const porArs = ((cc && cc.by_ars) || []).slice();
  const conFecha = porArs.filter((a) => a.next_expected).sort((a, b) => String(a.next_expected).localeCompare(String(b.next_expected)));
  const sinFecha = porArs.filter((a) => !a.next_expected && Number(a.balance) > 0);
  const filas = [];
  for (const a of conFecha.slice(0, 3)) {
    const d = diasDesdeHoy(a.next_expected);
    const cuando = d === 0 ? 'hoy' : d === 1 ? 'mañana' : fechaCorta(a.next_expected);
    filas.push(h('li', { class: 'md-fila' },
      h('span', {}, h('b', {}, a.ars), ' · ', h('span', { class: 'md-cuando' }, cuando)),
      h('b', { class: 'md-monto' }, money(a.balance))));
  }
  for (const a of sinFecha.slice(0, 2)) {
    filas.push(h('li', { class: 'md-fila md-tarde' },
      h('span', {}, h('b', {}, a.ars), ' · ', h('span', { class: 'md-cuando' }, 'atrasado, sin fecha')),
      h('b', { class: 'md-monto' }, money(a.balance))));
  }
  // Lo que no entró arriba se agrupa en una línea, en vez de alargar la lista.
  const mostradas = new Set([...conFecha.slice(0, 3), ...sinFecha.slice(0, 2)]);
  const resto = porArs.filter((a) => !mostradas.has(a));
  if (resto.length) {
    const suma = resto.reduce((acc, a) => acc + Number(a.balance || 0), 0);
    filas.push(h('li', { class: 'md-fila md-resto' },
      h('span', {}, resto.length === 1 ? `Otra ARS (${resto[0].ars})` : `Otras ${resto.length} ARS`),
      h('b', { class: 'md-monto' }, money(suma))));
  }

  const verPdf = h('a', { class: 'i18-btn', href: '#/estado-cuenta' }, 'Ver mi estado de cuenta (PDF)');
  const verCal = h('a', { class: 'i18-btn i18-sec', href: '#/calendario-cobros' }, 'Ver todas las fechas');

  // ── Lo demás, debajo y plegado: está, pero no compite ────────────────────────────────────
  const detalle = h('details', { class: 'i18-card' },
    h('summary', {}, h('strong', {}, `Cómo va ${mes}`), ' · lo cobrado, lo reclamado y las glosas'),
    h('div', { class: 'i18-kpis' },
      kpi(`Cobrado en ${mes}`, money(caja.collected), `${num(caja.payments)} pago(s) · ${tendencia(caja.collected, ant.collected)}`),
      kpi(`Reclamado en ${mes}`, money(p.claimed), `${num(p.lines)} servicio(s) · ${tendencia(p.claimed, ant.claimed)}`),
      kpi(`Glosado en ${mes}`, money(g.glosado), g.rate_pct != null ? `${pct(g.rate_pct)} de lo reclamado ese mes` : ''),
      kpi(`Recuperado en ${mes}`, money(g.recovered), 'de glosas que se pelearon'),
      kpi(`Perdido en ${mes}`, money(g.accepted), 'glosas que no se recuperaron'),
      kpi(`Honorarios de SOFA en ${mes}`, money(hon.accrued), r.fee_pct_of_collected != null ? `${pct(r.fee_pct_of_collected)} de lo cobrado` : 'sin honorarios ese mes')),
    h('div', { class: 'i18-bar' },
      h('a', { class: 'i18-btn i18-sec', href: '#/mis-glosas' }, 'Trabajar mis glosas'),
      h('a', { class: 'i18-btn i18-sec', href: '#/rentabilidad' }, 'Ver qué ARS me conviene')));

  // ── El retorno, al final, como cierre y no como competencia ──────────────────────────────
  const cierre = r.return_x != null
    ? h('p', { class: 'md-cierre' }, `En ${mes} SOFA le cobró `, h('b', {}, money(hon.accrued)),
        ' y le cobró a las ARS ', h('b', {}, money(caja.collected)), '. Por cada peso que le pagó, ',
        h('b', {}, `${r.return_x}×`), '.')
    : null;

  return h('div', {}, heroe,
    filas.length ? h('ul', { class: 'md-lista' }, filas) : null,
    filas.length ? h('p', { class: 'i18-sub md-nota' }, 'La fecha sale de lo que esa ARS tardó en pagarle a usted en los últimos lotes. Es una estimación con su propio historial, no una promesa de la ARS.') : null,
    h('div', { class: 'i18-bar' }, verPdf, verCal),
    detalle, cierre);
}
export default render;
