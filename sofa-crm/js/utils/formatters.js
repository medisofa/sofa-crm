/** SOFA · Formatos para República Dominicana */
const MONEY = new Intl.NumberFormat('es-DO', { style: 'currency', currency: 'DOP', currencyDisplay: 'code', maximumFractionDigits: 2 });
const NUM = new Intl.NumberFormat('es-DO');
export const money = (n) => (n == null || n === '' ? '—' : MONEY.format(Number(n)).replace('DOP', 'RD$'));
export const num = (n) => (n == null ? '—' : NUM.format(Number(n)));
export function date(d) {
  if (!d) return '—';
  const s = String(d).slice(0, 10).split('-');
  return s.length === 3 ? `${s[2]}/${s[1]}/${s[0]}` : String(d);
}
export function dateTime(ts) {
  if (!ts) return '—';
  const d = new Date(ts);
  return isNaN(d) ? '—' : d.toLocaleString('es-DO', { dateStyle: 'short', timeStyle: 'short' });
}
const MES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
export const period = (p) => { if (!p) return '—'; const [y, m] = String(p).split('-'); return `${MES[Number(m) - 1]} ${y}`; };
/** Fecha de hoy en República Dominicana (igual que la base de datos), sin importar la zona del dispositivo */
const RD_DATE = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Santo_Domingo', year: 'numeric', month: '2-digit', day: '2-digit' });
export const todayISO = () => RD_DATE.format(new Date());
/** Suma meses a un 'AAAA-MM' */
export const addMonths = (ym, n) => { let [y, m] = ym.split('-').map(Number); m += n; while (m > 12) { m -= 12; y += 1; } while (m < 1) { m += 12; y -= 1; } return `${y}-${String(m).padStart(2, '0')}`; };
/** ¿El rango de PostgreSQL "[2026-01-01,)" contiene la fecha ISO dada? */
export function rangeContains(range, iso) {
  const m = /^([\[(])([^,]*),([^\])]*)([\])])$/.exec(String(range || '').trim());
  if (!m) return false;
  const [, lb, lo, hi, ub] = m;
  const okLo = !lo || (lb === '[' ? iso >= lo : iso > lo);
  const okHi = !hi || (ub === ']' ? iso <= hi : iso < hi);
  return okLo && okHi;
}
export const initials = (name) => String(name || '?').trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
