/** SOFA · 2.6 · Iteración 36 · Revisión del sistema (solo Super Admin).
 *  1) Carga cada módulo del menú y avisa si alguno no abre (archivo faltante o con error).
 *  2) Muestra qué familias y módulos ve cada rol, para revisar los permisos de un vistazo.
 *  3) Indica cómo correr todas las pruebas de la base de datos en un solo paso. */
import { h, note, rpc } from '../services/iter18.js';
import { MODULES } from '../router.js';
import { ROLES, visibleNav, allRoutes } from '../utils/permissions.js';
import { APP_VERSION } from '../version.js';

const QA_SQL = 'select * from app.qa_run_all();';

export async function render(root) {
  root.replaceChildren();
  const modBox = h('div', { 'aria-live': 'polite' }, note('Revisando los módulos…'));
  const roleBox = h('div');
  const accBox = h('div', { 'aria-live': 'polite' });
  const copy = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Copiar');
  copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(QA_SQL); copy.textContent = 'Copiado'; } catch (_) { copy.textContent = 'Selecciónelo y cópielo a mano'; } });
  root.append(h('h2', {}, 'Revisión del sistema'),
    h('p', { class: 'i18-sub' }, `Versión ${APP_VERSION}. Use esta pantalla después de cada entrega: si algo sale en rojo, no siga y avise.`),
    h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, '1. Pruebas de la base de datos'),
      h('p', {}, 'Abra Supabase › SQL Editor, pegue esta línea y pulse «Run». Cada fila es una suite; todas deben decir «TODO OK».'),
      h('div', { class: 'i18-bar' }, h('code', { class: 'rv-code' }, QA_SQL), copy)),
    h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, '2. Módulos de la aplicación'), modBox),
    h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, '3. Qué ve cada rol'), roleBox),
    h('section', { class: 'i18-card' }, h('h3', { style: 'margin-top:0' }, '4. Cuentas de acceso'), accBox));
  drawAccounts(accBox);

  drawRoles(roleBox);
  const routes = allRoutes().filter((r) => r.ready);
  const res = await Promise.all(routes.map(async (r) => {
    const file = MODULES[r.route];
    if (!file) return { r, ok: false, why: 'La ruta no tiene archivo asignado en router.js' };
    try { const m = await import(`./${file}`); return typeof m.render === 'function' ? { r, ok: true, file } : { r, ok: false, file, why: 'El archivo no exporta render()' }; }
    catch (e) { return { r, ok: false, file, why: e.message || 'No carga' }; }
  }));
  const bad = res.filter((x) => !x.ok);
  modBox.replaceChildren(
    note(bad.length ? `${bad.length} de ${res.length} módulos no abren. Suba a GitHub los archivos indicados (carpeta js/modules) y recargue.` : `Los ${res.length} módulos abren correctamente.`, bad.length ? 'error' : 'ok'),
    h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
      h('thead', {}, h('tr', {}, ['Módulo', 'Ruta', 'Archivo', 'Estado'].map((x) => h('th', {}, x)))),
      h('tbody', {}, [...bad, ...res.filter((x) => x.ok)].map((x) => h('tr', {}, h('td', {}, x.r.label), h('td', {}, h('a', { href: `#/${x.r.route}` }, `#/${x.r.route}`)),
        h('td', {}, x.file || '—'), h('td', {}, x.ok ? h('span', { class: 'ac-pill st-ok' }, 'Abre') : h('span', { class: 'ac-pill st-bad', title: x.why }, `No abre: ${x.why}`))))))));
}

/** 2.6.1 · Cuentas con datos de acceso incompletos (creadas por SQL) o sin rol: impiden entrar o restablecer la clave */
async function drawAccounts(box) {
  box.replaceChildren(note('Revisando las cuentas…'));
  try {
    const l = await rpc('auth_users_health');
    box.replaceChildren(l.length ? h('div', {}, note(`${l.length} cuenta(s) con problemas. Corríjalas antes de entregar claves.`, 'error'),
      h('ul', {}, l.map((u) => h('li', {}, h('strong', {}, u.email), ': ', u.problems.join(' · '))))) : note('Todas las cuentas tienen sus datos de acceso completos y un rol activo.', 'ok'));
  } catch (e) { box.replaceChildren(note(`No se pudo revisar: ${e.message}. ¿Aplicó la migración 126?`, 'error')); }
}

function drawRoles(box) {
  const roles = Object.keys(ROLES);
  const sel = h('select', { id: 'rv-role' }, roles.map((k) => h('option', { value: k }, ROLES[k].name || k)));
  const out = h('div');
  const draw = () => {
    const g = visibleNav(sel.value);
    out.replaceChildren(g.length ? h('div', { class: 'rv-fams' }, g.map((f) => h('div', { class: 'i18-card rv-fam' }, h('strong', {}, f.group),
      h('ul', {}, f.items.map((i) => h('li', {}, i.label)))))) : note('Este rol no ve ningún módulo.'),
      h('p', { class: 'i18-sub' }, `${g.reduce((a, f) => a + f.items.length, 0)} módulos en ${g.length} familias.`));
  };
  sel.addEventListener('change', draw); draw();
  box.replaceChildren(h('div', { class: 'i18-bar' }, h('label', { for: 'rv-role' }, 'Rol', sel)), out);
}
