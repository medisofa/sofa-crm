/** SOFA · 5.17.0 · I73 · «Permisos y menús»: qué ve cada rol, y dónde.
 *
 *  LO QUE ESTA PANTALLA HACE Y LO QUE NO, porque la diferencia importa:
 *
 *    SÍ · decide qué módulos aparecen en la barra izquierda de cada rol y en qué grupo.
 *    NO · no otorga ni quita acceso a ninguna pantalla. Eso vive en dos sitios que esta
 *         pantalla no toca: la matriz del código y las políticas de la base de datos.
 *
 *  Un módulo escondido del menú sigue abriéndose por el buscador y por su enlace. Esconder
 *  no es prohibir: es ordenar. Por eso la columna de la derecha dice siempre qué puede ver
 *  el rol de verdad, para que nadie confunda una cosa con la otra.
 *
 *  El Super Admin no se configura a sí mismo, a propósito: es quien arregla los menús de los
 *  demás, y si pudiera esconderse «Usuarios y roles» se quedaría sin manera de volver atrás.
 */
import { rpc, h, note, guarded } from '../services/iter18.js';
import { ROLES, FAMILIES, FAMILIAS_ROL, rutasDelRol, canSee } from '../utils/permissions.js';

const famNombre = (key, rol) => {
  const f = (FAMILIAS_ROL[rol] || FAMILIES).find((x) => x.key === key);
  return f ? f.group : 'Sin grupo';
};
const cuando = (iso) => {
  if (!iso) return '';
  const d = new Date(iso);
  return isNaN(d) ? '' : d.toLocaleString('es-DO', { dateStyle: 'medium', timeStyle: 'short' });
};

export async function render(root, ctx = {}) {
  root.replaceChildren();
  if (!['super_admin', 'admin'].includes(ctx.role)) {
    root.append(h('div', { class: 'i18-wrap' }, note(
      'Esta pantalla es del Super Admin y del Administrador. Si crees que deberías verla, pide al Administrador que revise tu rol.', 'error')));
    return;
  }

  const cab = h('div', {});
  const cuerpo = h('div', { 'aria-live': 'polite' });
  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Permisos y menús'),
    h('p', { class: 'i18-sub' },
      'Aquí se decide qué módulos aparecen en el menú de cada rol y en qué grupo. '
      + 'Esconder un módulo no se lo prohíbe a nadie: sigue abriéndose desde el buscador. '
      + 'Los permisos de verdad —a qué datos llega cada rol— viven en la base de datos y se '
      + 'muestran aquí solo para consultarlos.'),
    cab, cuerpo));

  let datos = null;     // lo que devolvió role_menu_get()
  let rol = null;       // rol en edición
  let borrador = null;  // Map ruta → {en_menu, familia, orden}, sin guardar todavía
  // Guardar repinta la pantalla entera, y el repintado se llevaba por delante el «Guardado».
  // Este mensaje sobrevive un repintado y se muestra una sola vez.
  let pendiente = null;

  const sucio = () => {
    if (!borrador) return false;
    return rutasDelRol(rol).some((r) => (borrador.get(r.route).en_menu) !== r.en_menu);
  };

  async function cargar() {
    datos = await guarded(cuerpo, () => rpc('role_menu_get'));
    if (datos == null) return;
    pintarRoles();
    if (rol) await abrir(rol); else cuerpo.replaceChildren(bienvenida());
  }

  function bienvenida() {
    return h('div', { class: 'pm-vacio' },
      h('p', {}, 'Escoge un rol arriba para ver y ajustar su menú.'),
      h('p', { class: 'i18-sub' },
        'El número entre paréntesis es cuánta gente tiene ese rol hoy. '
        + 'Un rol sin gente se puede ajustar sin que nadie lo note.'));
  }

  /* ── La fila de roles ────────────────────────────────────────────────────── */
  function pintarRoles() {
    const fila = h('div', { class: 'i18-bar pm-roles', role: 'group', 'aria-label': 'Roles' });
    (datos.roles || []).forEach((r) => {
      const b = h('button', {
        class: 'i18-btn' + (rol === r.code ? '' : ' i18-sec') + (r.intocable ? ' pm-fijo' : ''),
        type: 'button', 'aria-pressed': rol === r.code ? 'true' : 'false',
        title: r.intocable ? 'El menú del Super Admin no se configura: siempre lo ve todo' : ''
      }, `${r.name} (${r.personas})`);
      b.addEventListener('click', async () => {
        if (sucio() && !confirm('Tienes cambios sin guardar en «' + nombreRol(rol) + '». ¿Los descartas?')) return;
        rol = r.code; borrador = null; pintarRoles(); await abrir(r.code);
      });
      fila.append(b);
    });
    cab.replaceChildren(fila);
  }

  const nombreRol = (code) => ((datos.roles || []).find((r) => r.code === code) || {}).name || code;
  const esIntocable = (code) => !!((datos.roles || []).find((r) => r.code === code) || {}).intocable;

  /* ── La pantalla de un rol ───────────────────────────────────────────────── */
  async function abrir(code) {
    const rutas = rutasDelRol(code);
    borrador = new Map(rutas.map((r) => [r.route, {
      en_menu: r.en_menu, familia: r.familia, orden: 100, obligatoria: r.obligatoria }]));

    const aviso = h('div', { 'aria-live': 'polite' });
    const decir = (t, k = 'ok') => aviso.replaceChildren(note(t, k));
    const decirDespues = (t, k = 'ok') => { pendiente = [t, k]; };

    const puede = datos.puede_editar === true && !esIntocable(code);
    const resumen = h('p', { class: 'i18-sub' });
    const listas = h('div', { class: 'pm-cols' });
    const pie = h('div', { class: 'i18-bar' });

    function contar() {
      const n = [...borrador.values()].filter((v) => v.en_menu).length;
      resumen.textContent = `${n} de ${rutas.length} módulos en el menú. `
        + `Los otros ${rutas.length - n} siguen abriéndose desde el buscador.`;
    }

    /* Dos columnas: lo que está en el menú, agrupado por familia, y lo que no. */
    function pintarListas() {
      const dentro = h('div', { class: 'pm-col' },
        h('h4', {}, 'En el menú'),
        h('p', { class: 'i18-sub' }, 'Lo que ve en la barra izquierda, por grupos.'));
      const fuera = h('div', { class: 'pm-col' },
        h('h4', {}, 'Solo por el buscador'),
        h('p', { class: 'i18-sub' }, 'Lo puede abrir, pero no le llena el menú del día a día.'));

      const porFamilia = {};
      rutas.forEach((r) => {
        const v = borrador.get(r.route);
        if (!v.en_menu) return;
        (porFamilia[r.familia || '_'] = porFamilia[r.familia || '_'] || []).push(r);
      });
      const orden = (FAMILIAS_ROL[code] || FAMILIES).map((f) => f.key);
      Object.keys(porFamilia)
        .sort((a, b) => (orden.indexOf(a) + 99) - (orden.indexOf(b) + 99))
        .forEach((k) => {
          dentro.append(h('div', { class: 'pm-fam' },
            h('div', { class: 'pm-fam-t' }, famNombre(k, code)),
            h('ul', { class: 'pm-lista' }, porFamilia[k].map((r) => chip(r, true)))));
        });
      if (!Object.keys(porFamilia).length) dentro.append(note('Su menú quedaría vacío.', 'error'));

      const afuera = rutas.filter((r) => !borrador.get(r.route).en_menu);
      fuera.append(h('ul', { class: 'pm-lista' }, afuera.length
        ? afuera.map((r) => chip(r, false))
        : h('li', { class: 'i18-sub' }, 'Nada escondido: ve todo su menú.')));

      listas.replaceChildren(dentro, fuera);
    }

    function chip(r, dentro) {
      const b = h('button', {
        class: 'pm-chip' + (r.obligatoria ? ' pm-chip-fijo' : ''),
        type: 'button',
        disabled: !puede || r.obligatoria,
        title: r.obligatoria
          ? 'No se puede quitar: sin esto no podría cambiar su clave ni su segundo paso'
          : (puede ? (dentro ? 'Quitar del menú' : 'Poner en el menú') : 'Solo el Super Admin cambia esto')
      }, h('span', { class: 'pm-sig' }, r.obligatoria ? '•' : (dentro ? '−' : '+')), ' ', r.label);
      if (puede && !r.obligatoria) {
        b.addEventListener('click', () => {
          const v = borrador.get(r.route);
          borrador.set(r.route, { ...v, en_menu: !v.en_menu });
          pintarListas(); contar(); pintarPie();
        });
      }
      return h('li', {}, b);
    }

    function pintarPie() {
      pie.replaceChildren();
      if (!puede) {
        pie.append(note(esIntocable(code)
          ? 'El menú del Super Admin no se configura, a propósito: es quien arregla los menús de los demás y tiene que poder llegar siempre a «Usuarios y roles».'
          : 'Solo el Super Admin cambia los menús. Tú puedes mirarlos.'));
        return;
      }
      const guardar = h('button', { class: 'i18-btn', type: 'button', disabled: !sucio() },
        sucio() ? 'Guardar los cambios' : 'Sin cambios que guardar');
      guardar.addEventListener('click', async () => {
        guardar.disabled = true;
        try {
          const items = rutas.map((r) => {
            const v = borrador.get(r.route);
            return { route: r.route, en_menu: v.en_menu, familia: v.familia, orden: v.orden };
          });
          await rpc('role_menu_save', { p_role: code, p_items: items,
            p_note: 'Desde «Permisos y menús»' });
          decirDespues('Guardado. Quien tenga el rol «' + nombreRol(code) + '» lo verá al recargar la página.');
          await cargar();
        } catch (e) { decir(e.message, 'error'); guardar.disabled = false; }
      });

      const deshacer = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Descartar lo que cambié');
      deshacer.addEventListener('click', () => abrir(code));

      const fabrica = h('button', { class: 'i18-btn i18-sec', type: 'button' }, 'Volver a como viene de fábrica');
      fabrica.addEventListener('click', async () => {
        if (!confirm('Esto borra la configuración guardada de «' + nombreRol(code)
          + '» y vuelve al menú que trae el sistema. ¿Seguimos?')) return;
        fabrica.disabled = true;
        try { await rpc('role_menu_reset', { p_role: code });
          decirDespues('Listo: «' + nombreRol(code) + '» volvió al menú de fábrica.'); await cargar(); }
        catch (e) { decir(e.message, 'error'); fabrica.disabled = false; }
      });

      pie.append(guardar, deshacer, fabrica);
    }

    cuerpo.replaceChildren(
      h('h3', {}, nombreRol(code)),
      resumen, aviso,
      note('Esconder un módulo no se lo prohíbe a nadie: sigue abriéndolo desde el buscador o por su enlace. '
         + 'Para cambiar a qué datos llega un rol hace falta una migración revisada, no esta pantalla.'),
      listas, pie,
      seguridadReal(code, rutas),
      historial(code, decirDespues));

    pintarListas(); contar(); pintarPie();
    if (pendiente) { decir(pendiente[0], pendiente[1]); pendiente = null; }
  }

  /* ── La columna de la verdad: qué puede ver el rol, según el sistema ─────── */
  function seguridadReal(code, rutas) {
    const dentro = rutas.filter((r) => canSee(r.route, code)).length;
    return h('details', { class: 'pm-real' },
      h('summary', {}, `Qué puede ver de verdad el rol «${nombreRol(code)}» (${dentro} módulos)`),
      h('p', { class: 'i18-sub' },
        'Esto NO se cambia desde aquí. Sale de la matriz de permisos del sistema y de las políticas '
        + 'de la base de datos, y es lo que de verdad decide a qué datos llega cada quien. '
        + 'Lo de arriba solo acomoda el menú dentro de esta lista.'),
      h('ul', { class: 'pm-lista pm-real-lista' },
        rutas.map((r) => h('li', {}, h('span', { class: 'pm-chip pm-chip-leer' }, r.label)))));
  }

  /* ── Historial y deshacer ────────────────────────────────────────────────── */
  function historial(code, decir) {
    const caja = h('details', { class: 'pm-hist' }, h('summary', {}, 'Historial de cambios'));
    caja.addEventListener('toggle', async () => {
      if (!caja.open || caja.dataset.cargado) return;
      caja.dataset.cargado = '1';
      const box = h('div', {}); caja.append(box);
      const ver = await guarded(box, () => rpc('role_menu_history', { p_role: code }));
      if (ver == null) return;
      if (!ver.length) { box.replaceChildren(note('Este rol nunca se ha cambiado.')); return; }
      box.replaceChildren(h('ul', { class: 'pm-lista pm-hist-lista' }, ver.map((v) => {
        const li = h('li', {},
          h('span', { class: 'i18-sub' }, cuando(v.cuando)), ' · ',
          (v.quien || 'alguien del equipo'), ' · ',
          (v.nota || 'sin nota'), ' · ',
          h('span', { class: 'i18-sub' }, `antes tenía ${v.rutas_antes} ajustes`));
        if (datos.puede_editar && !esIntocable(code)) {
          const b = h('button', { class: 'i18-btn i18-sec pm-mini', type: 'button' }, 'Volver aquí');
          b.addEventListener('click', async () => {
            if (!confirm('Esto deja «' + nombreRol(code) + '» como estaba en ese momento. ¿Seguimos?')) return;
            b.disabled = true;
            try { await rpc('role_menu_restore', { p_version: v.id });
              decir('Listo: «' + nombreRol(code) + '» volvió a como estaba el ' + cuando(v.cuando) + '.');
              await cargar(); }
            catch (e) { decir(e.message, 'error'); b.disabled = false; }
          });
          li.append(' ', b);
        }
        return li;
      })));
    });
    return caja;
  }

  await cargar();
}
