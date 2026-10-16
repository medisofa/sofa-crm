/**
 * SOFA · Panel «Fotografiar documento» de la Captura rápida (4.5.2).
 * Foto (cámara trasera, teléfono o archivo del escáner) → varias páginas → lectura en el dispositivo → la persona
 * confirma o corrige CADA dato → «Usar estos datos» prellena el formulario sin pisar lo ya escrito.
 * Las fotos se suben DESPUÉS de crear la reclamación (register_captured_document + confirm_document_ocr).
 * Nada leído llega a la reclamación sin esa confirmación. La lectura corre en este dispositivo (ver ocr-motor.js).
 */
import { html, render as paint, $ } from '../utils/dom.js';
import { toast, friendlyError, opt, confirmDialog } from '../utils/ui.js';
import { camaraEnVivoDisponible, iniciarCamara, procesarFoto, aBitmap, dibujar, subirCaptura, confirmarLectura } from '../services/camera.js';
import { extraerCampos, paraRegistrar, CAMPOS, UMBRAL } from '../services/ocr-reglas.js';
import { leerTexto, liberarMotor, motorDisponible } from '../services/ocr-motor.js';

/** Tipo de documento en pantalla -> código de document_types */
export const TIPOS = {
  autorizacion: ['Autorización de la ARS', 'autorizacion'],
  receta: ['Receta u orden médica', 'indicacion'],
  carnet: ['Carnet del afiliado', 'copia_carnet'],
  cedula: ['Cédula', 'copia_carnet'],
  factura: ['Factura', 'factura_ncf']
};
const ETIQ = { cedula: 'Cédula', numero_autorizacion: 'No. de autorización', fecha: 'Fecha', afiliado: 'Afiliado (nombre)', ars: 'ARS', procedimiento: 'Procedimiento' };
const MAX_PAGINAS = 10;

const nivel = (c) => (c >= 0.85 ? ['alta', 'ok'] : c >= UMBRAL ? ['media', 'warn'] : ['baja · revisar', 'bad']);
const pct = (c) => `${Math.round(c * 100)} %`;
const norm = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const mensaje = (err) => (err?.code === '23505' && /cargado/i.test(err.message || '') ? err.message : friendlyError(err));

/**
 * @param {object} o
 * @param {HTMLElement} o.host        contenedor donde se pinta el botón y el resumen de lo pendiente
 * @param {(id:string)=>HTMLElement} o.el   buscador de campos del formulario de capture.js
 * @param {()=>Array} o.ars           lista de ARS [{id,name}]
 * @param {()=>Array} o.services      servicios contratados cargados [{procedure_id,name}]
 */
export function initCamara({ host, el, ars, services }) {
  /** Fotos y lectura que esperan a que se cree la reclamación */
  let pend = null; // {tipo, pages:[{blob,sha256,url,origen}], ocr, confirmados}

  const limpiarPend = () => { pend?.pages.forEach((p) => URL.revokeObjectURL(p.url)); pend = null; pintarHost(); };

  function pintarHost() {
    paint(host, html`<div class="cam-bar">
      <button type="button" class="btn" id="camOpen">📷 Fotografiar documento</button>
      ${pend ? html`<span class="cam-pend" role="status">${pend.pages.length} ${pend.pages.length === 1 ? 'página lista' : 'páginas listas'} (${TIPOS[pend.tipo][0]}) · se suben al guardar
        <button type="button" class="btn sm" id="camDrop">Quitar</button></span>` : ''}
      ${pend ? html`<span class="cam-thumbs">${pend.pages.map((p, i) => html`<img class="cam-th" src="${p.url}" alt="Página ${i + 1}">`)}</span>` : ''}
    </div>`);
    $('#camOpen', host).addEventListener('click', abrir);
    $('#camDrop', host)?.addEventListener('click', limpiarPend);
  }

  // ------------------------------------------------------------------ panel
  async function abrir() {
    if (pend && !(await confirmDialog('Reemplazar fotos pendientes', 'Ya hay fotos esperando a guardarse con la reclamación. Si sigues, se reemplazan por las nuevas.', 'Reemplazar'))) return;
    const S = { tipo: pend?.tipo || 'autorizacion', pages: [], cur: null, leido: null, vals: {}, conf: {}, ok: {}, camara: null, leyendo: false };
    const d = document.createElement('dialog');
    d.className = 'dlg cam-dlg'; d.setAttribute('aria-labelledby', 'camT');
    paint(d, html`<div class="dh" id="camT">Fotografiar documento</div>
      <div class="db cam-body">
        <p class="small muted">La foto se reduce y se limpia en este dispositivo. La lectura del texto también ocurre aquí: la imagen no sale a ningún servicio externo. No se guarda copia en la galería.</p>
        <div class="cam-grid">
          <section aria-label="Foto">
            <div class="field"><label for="cam_tipo">Tipo de documento</label>
              <select id="cam_tipo">${Object.entries(TIPOS).map(([k, v]) => opt(k, v[0], S.tipo))}</select></div>
            <div class="toolbar cam-src" style="margin:0 0 8px;gap:6px">
              <button type="button" class="btn" id="cam_live">Abrir cámara</button>
              <label class="btn" style="cursor:pointer">Tomar foto con el teléfono<input type="file" id="cam_cap" accept="image/*" capture="environment" hidden></label>
              <label class="btn" style="cursor:pointer">Elegir imagen o escaneo<input type="file" id="cam_file" accept="image/jpeg,image/png,image/webp" hidden></label>
            </div>
            <div id="cam_msg" aria-live="polite"></div>
            <div id="cam_stage"></div>
            <div id="cam_pages"></div>
          </section>
          <section aria-label="Datos leídos">
            <div class="toolbar" style="margin:0 0 8px"><button type="button" class="btn primary" id="cam_read" disabled>Leer datos de las páginas</button>
              <span class="small muted" id="cam_prog" aria-live="polite"></span></div>
            <div id="cam_fields"><p class="small muted">Agrega al menos una página y toca «Leer datos». También puedes escribir los datos a mano y confirmarlos.</p></div>
          </section>
        </div>
        <div class="fd-msg" id="cam_err" aria-live="assertive"></div>
      </div>
      <div class="df"><button type="button" class="btn" id="cam_cancel">Cancelar</button>
        <button type="button" class="btn" id="cam_only" disabled>Adjuntar solo las fotos</button>
        <button type="button" class="btn primary" id="cam_use" disabled>Usar estos datos</button></div>`);
    document.body.appendChild(d);
    const q = (s) => $(s, d);
    const err = (m) => paint(q('#cam_err'), m ? html`<div class="note bad" role="alert">${m}</div>` : html``);
    const msg = (m, k = 'info') => paint(q('#cam_msg'), m ? html`<div class="note ${k}" role="status">${m}</div>` : html``);

    const cerrarCamara = () => { S.camara?.detener(); S.camara = null; };
    const soltarActual = () => { cerrarCamara(); if (S.cur?.bitmap?.close) S.cur.bitmap.close(); S.cur = null; paint(q('#cam_stage'), html``); };
    const cerrar = () => { soltarActual(); S.pages.forEach((p) => URL.revokeObjectURL(p.url)); liberarMotor(); d.close(); d.remove(); };

    // ---------------------------------------------------------- páginas
    function pintarPaginas() {
      paint(q('#cam_pages'), S.pages.length ? html`<div class="cam-strip" aria-label="Páginas tomadas">${S.pages.map((p, i) => html`<figure class="cam-pg">
        <img src="${p.url}" alt="Página ${i + 1}"><figcaption>Pág. ${i + 1} <button type="button" class="btn sm" data-del="${i}" aria-label="Quitar página ${i + 1}">Quitar</button></figcaption></figure>`)}</div>
        <p class="small muted">${S.pages.length} de ${MAX_PAGINAS} páginas.</p>` : html``);
      q('#cam_pages').querySelectorAll('[data-del]').forEach((b) => b.addEventListener('click', () => {
        const [p] = S.pages.splice(Number(b.dataset.del), 1); URL.revokeObjectURL(p.url); invalidarLectura(); pintarPaginas();
      }));
      q('#cam_read').disabled = !S.pages.length || S.leyendo;
      q('#cam_only').disabled = !S.pages.length;
    }
    function invalidarLectura() { S.leido = null; S.vals = {}; S.conf = {}; S.ok = {}; pintarCampos(); }

    // ---------------------------------------------------------- foto actual: rotar y recortar
    async function mostrarActual(fuente, origen) {
      soltarActual();
      let bitmap;
      try { bitmap = await aBitmap(fuente); } catch (e) { err(e.message); return; }
      S.cur = { fuente, bitmap, origen, rot: 0, c: { t: 0, b: 0, l: 0, r: 0 } };
      paint(q('#cam_stage'), html`<div class="cam-prev"><canvas id="cam_cv" aria-label="Vista previa de la foto"></canvas></div>
        <div class="toolbar" style="margin:6px 0;gap:6px">
          <button type="button" class="btn sm" id="cam_rl">↺ Girar izquierda</button><button type="button" class="btn sm" id="cam_rr">↻ Girar derecha</button></div>
        <details class="cam-crop"><summary>Recortar bordes</summary>
          ${[['t', 'Arriba'], ['b', 'Abajo'], ['l', 'Izquierda'], ['r', 'Derecha']].map(([k, l]) => html`<label class="cam-rng">${l}<input type="range" min="0" max="40" value="0" data-crop="${k}" aria-label="Recortar ${l.toLowerCase()}"></label>`)}</details>
        <div class="toolbar" style="margin:8px 0;gap:6px"><button type="button" class="btn primary" id="cam_add">Agregar esta página</button><button type="button" class="btn" id="cam_discard">Descartar foto</button></div>`);
      const redraw = () => {
        const { rot, c } = S.cur;
        const cv = dibujar(S.cur.bitmap, { rotacion: rot, recorte: { x: c.l / 100, y: c.t / 100, w: 1 - (c.l + c.r) / 100, h: 1 - (c.t + c.b) / 100 }, maxLado: 640 });
        const dst = q('#cam_cv'); dst.width = cv.width; dst.height = cv.height; dst.getContext('2d').drawImage(cv, 0, 0);
      };
      redraw();
      q('#cam_rl').addEventListener('click', () => { S.cur.rot -= 90; redraw(); });
      q('#cam_rr').addEventListener('click', () => { S.cur.rot += 90; redraw(); });
      d.querySelectorAll('[data-crop]').forEach((r) => r.addEventListener('input', () => {
        S.cur.c[r.dataset.crop] = Number(r.value);
        // nunca deja menos de 20 % de la imagen
        if (S.cur.c.l + S.cur.c.r > 80) { S.cur.c[r.dataset.crop] = 80 - (r.dataset.crop === 'l' ? S.cur.c.r : S.cur.c.l); r.value = S.cur.c[r.dataset.crop]; }
        if (S.cur.c.t + S.cur.c.b > 80) { S.cur.c[r.dataset.crop] = 80 - (r.dataset.crop === 't' ? S.cur.c.b : S.cur.c.t); r.value = S.cur.c[r.dataset.crop]; }
        redraw();
      }));
      q('#cam_discard').addEventListener('click', () => { soltarActual(); });
      q('#cam_add').addEventListener('click', async () => {
        if (S.pages.length >= MAX_PAGINAS) { err(`Máximo ${MAX_PAGINAS} páginas por documento. Quita alguna o guarda este grupo y fotografía el resto aparte.`); return; }
        err('');
        try {
          const { rot, c, fuente: f, origen: o } = S.cur;
          const foto = await procesarFoto(f, { rotacion: rot, recorte: { x: c.l / 100, y: c.t / 100, w: 1 - (c.l + c.r) / 100, h: 1 - (c.t + c.b) / 100 } });
          if (S.pages.some((p) => p.sha256 === foto.sha256)) { err('Esa página ya está en la lista. Toma otra foto o quita la repetida.'); return; }
          S.pages.push({ blob: foto.blob, sha256: foto.sha256, url: URL.createObjectURL(foto.blob), origen: o });
          soltarActual(); invalidarLectura(); pintarPaginas();
          msg(`Página ${S.pages.length} agregada. Puedes tomar otra o tocar «Leer datos».`, 'ok');
        } catch (e) { err(mensaje(e)); }
      });
    }

    // ---------------------------------------------------------- orígenes de la foto
    q('#cam_tipo').addEventListener('change', (e) => { S.tipo = e.target.value; });
    q('#cam_cap').addEventListener('change', (e) => { const f = e.target.files[0]; e.target.value = ''; if (f) { err(''); mostrarActual(f, 'camara'); } });
    q('#cam_file').addEventListener('change', (e) => { const f = e.target.files[0]; e.target.value = ''; if (f) { err(''); mostrarActual(f, 'escaner'); } });
    q('#cam_live').addEventListener('click', async () => {
      err(''); soltarActual();
      if (!camaraEnVivoDisponible()) { err('La cámara en vivo no está disponible aquí. Usa «Tomar foto con el teléfono» o «Elegir imagen o escaneo».'); return; }
      paint(q('#cam_stage'), html`<div class="cam-prev"><video id="cam_vid" aria-label="Cámara" playsinline muted></video></div>
        <div class="toolbar" style="margin:6px 0;gap:6px"><button type="button" class="btn primary" id="cam_shot">Tomar foto</button><button type="button" class="btn" id="cam_stop">Cerrar cámara</button></div>`);
      try { S.camara = await iniciarCamara(q('#cam_vid')); } catch (e) { paint(q('#cam_stage'), html``); err(e.message); return; }
      q('#cam_stop').addEventListener('click', soltarActual);
      q('#cam_shot').addEventListener('click', () => {
        try { const cv = S.camara.foto(); cerrarCamara(); mostrarActual(cv, 'camara'); } catch (e) { err(e.message); }
      });
    });

    // ---------------------------------------------------------- lectura
    q('#cam_read').addEventListener('click', async () => {
      err(''); S.leyendo = true; q('#cam_read').disabled = true;
      try {
        if (!motorDisponible()) throw new Error('Este navegador no puede leer el texto de la foto. Escribe los datos a mano y confírmalos.');
        let texto = '';
        for (let i = 0; i < S.pages.length; i += 1) {
          paint(q('#cam_prog'), html`Leyendo página ${i + 1} de ${S.pages.length}…`);
          const r = await leerTexto(S.pages[i].blob, { onProgreso: (st, p) => paint(q('#cam_prog'), html`Página ${i + 1}/${S.pages.length}: ${st} ${Math.round(p * 100)} %`) });
          texto += `${r.texto}\n\n`;
        }
        S.leido = extraerCampos(texto, { ars: ars() });
        S.vals = {}; S.conf = {}; S.ok = {};
        CAMPOS.forEach((k) => { const c = S.leido[k]; S.conf[k] = c.confianza; S.vals[k] = c.valor && c.confianza >= UMBRAL ? c.valor : ''; });
        paint(q('#cam_prog'), html`Lectura terminada.`);
        pintarCampos();
      } catch (e) { paint(q('#cam_prog'), html``); err(e.message); }
      finally { S.leyendo = false; q('#cam_read').disabled = !S.pages.length; }
    });

    // ---------------------------------------------------------- campos con confianza y confirmación
    function listo() {
      const llenos = CAMPOS.filter((k) => (S.vals[k] || '').trim());
      return { llenos, todos: llenos.length > 0 && llenos.every((k) => S.ok[k]) };
    }
    function refrescarBotones() {
      const { llenos, todos } = listo();
      q('#cam_use').disabled = !todos;
      const f = q('#cam_fields .cam-hint'); if (f) f.textContent = llenos.length ? (todos ? 'Todo confirmado.' : `Falta confirmar: ${llenos.filter((k) => !S.ok[k]).map((k) => ETIQ[k]).join(', ')}.`) : 'Escribe al menos un dato.';
    }
    function campoInput(k) {
      if (k === 'ars') return html`<select id="cf_${k}" data-k="${k}"><option value="">— sin definir —</option>${ars().map((a) => opt(a.name, a.name, S.vals[k]))}</select>`;
      if (k === 'fecha') return html`<input id="cf_${k}" data-k="${k}" type="date" value="${S.vals[k] || ''}">`;
      return html`<input id="cf_${k}" data-k="${k}" type="text" maxlength="120" value="${S.vals[k] || ''}" autocomplete="off" ${k === 'cedula' ? 'inputmode="numeric"' : ''}>`;
    }
    function pintarCampos() {
      if (!S.pages.length && !S.leido) { paint(q('#cam_fields'), html`<p class="small muted">Agrega al menos una página y toca «Leer datos». También puedes escribir los datos a mano y confirmarlos.</p>`); q('#cam_use').disabled = true; return; }
      paint(q('#cam_fields'), html`<p class="small muted">Revisa cada dato contra la foto. Los de confianza baja no se rellenan solos. Marca «Confirmo» en cada uno que vayas a usar.</p>
        <div class="cam-rows">${CAMPOS.map((k) => {
          const c = S.leido?.[k]; const [nv, cl] = nivel(S.conf[k] ?? 0);
          return html`<div class="cam-row ${c?.valor && c.confianza < UMBRAL ? 'dudoso' : ''}">
            <label for="cf_${k}">${ETIQ[k]}</label>
            ${campoInput(k)}
            <div class="small cam-meta">${c?.valor ? html`<span class="pill ${cl}">${nv} · ${pct(c.confianza)}</span>` : html`<span class="pill">${S.leido ? 'no encontrado' : 'a mano'}</span>`}
              ${c?.valor && c.confianza < UMBRAL ? html` Leído: «${c.valor}» <button type="button" class="btn sm" data-take="${k}">Usar esta lectura</button>` : ''}</div>
            <label class="check small"><input type="checkbox" data-ok="${k}" ${S.ok[k] ? 'checked' : ''}> Confirmo este dato</label></div>`;
        })}</div><p class="small cam-hint" aria-live="polite"></p>`);
      q('#cam_fields').querySelectorAll('[data-k]').forEach((i) => i.addEventListener('input', () => { S.vals[i.dataset.k] = i.value; S.ok[i.dataset.k] = false; const cb = q(`[data-ok="${i.dataset.k}"]`); if (cb) cb.checked = false; refrescarBotones(); }));
      q('#cam_fields').querySelectorAll('[data-ok]').forEach((cb) => cb.addEventListener('change', () => { S.ok[cb.dataset.ok] = cb.checked; refrescarBotones(); }));
      q('#cam_fields').querySelectorAll('[data-take]').forEach((b) => b.addEventListener('click', () => {
        const k = b.dataset.take; S.vals[k] = S.leido[k].valor; S.ok[k] = false; pintarCampos();
      }));
      refrescarBotones();
    }

    // ---------------------------------------------------------- aplicar al formulario
    function aplicar() {
      const hechos = []; const omitidos = [];
      const poner = (id, valor, etiqueta, evento = 'input') => {
        const inp = el(id); if (!inp || !valor) return;
        if (inp.value && inp.value !== valor) { omitidos.push(etiqueta); return; }
        if (inp.value === valor) return;
        inp.value = valor; inp.dispatchEvent(new Event(evento, { bubbles: true })); hechos.push(etiqueta);
      };
      poner('c_auth', S.vals.numero_autorizacion?.trim(), 'autorización');
      poner('c_authdate', S.vals.fecha?.trim(), 'fecha de autorización', 'change');
      poner('c_pat', S.vals.afiliado?.trim(), 'paciente');
      poner('c_doc', S.vals.cedula?.trim(), 'cédula');
      const a = ars().find((x) => x.name === S.vals.ars);
      if (S.vals.ars && !a) omitidos.push('ARS (no está en la lista)');
      else if (a) { const sel = el('c_ars'); if (sel.value && sel.value !== a.id) omitidos.push('ARS'); else if (sel.value !== a.id) { sel.value = a.id; sel.dispatchEvent(new Event('change', { bubbles: true })); hechos.push('ARS'); } }
      if (S.vals.procedimiento) {
        const p = norm(S.vals.procedimiento); const srv = el('c_srv');
        const hit = !srv.disabled && !srv.value ? services().filter((s) => { const n = norm(s.name); return n && (p.includes(n) || n.includes(p)); }) : [];
        if (srv.value) omitidos.push('procedimiento');
        else if (hit.length === 1) { srv.value = hit[0].procedure_id; srv.dispatchEvent(new Event('change', { bubbles: true })); hechos.push('procedimiento'); }
        else omitidos.push('procedimiento (elígelo del contrato)');
      }
      return { hechos, omitidos };
    }
    function guardarPend(conLectura) {
      limpiarPend();
      const confirmados = {}; CAMPOS.forEach((k) => { const v = (S.vals[k] || '').trim(); if (v) confirmados[k] = v; });
      const ocr = conLectura && S.leido ? paraRegistrar(S.leido) : null;
      pend = { tipo: S.tipo, pages: S.pages.map((p) => ({ ...p })), ocr, confirmados: conLectura ? confirmados : null };
      S.pages = []; // las páginas pasan a pend; cerrar() ya no libera sus URLs
    }
    q('#cam_use').addEventListener('click', () => {
      const { hechos, omitidos } = aplicar();
      guardarPend(true); cerrar(); pintarHost();
      toast(`Datos usados: ${hechos.join(', ') || 'ninguno nuevo'}.${omitidos.length ? ` Sin cambiar porque ya tenían datos o no coinciden: ${omitidos.join(', ')}.` : ''} Revisa el formulario y guarda: las fotos se suben con la reclamación.`, omitidos.length ? '' : 'ok');
    });
    q('#cam_only').addEventListener('click', () => {
      guardarPend(false); cerrar(); pintarHost();
      toast('Fotos listas: se suben al expediente cuando guardes la reclamación.', 'ok');
    });
    q('#cam_cancel').addEventListener('click', cerrar);
    d.addEventListener('cancel', (e) => { e.preventDefault(); cerrar(); });

    pintarPaginas();
    d.showModal();
    q('#cam_live').focus();
  }

  // ------------------------------------------------------------------ subida tras crear la reclamación
  /**
   * Sube las páginas pendientes. Devuelve {subidas, fallas:[mensaje]}. No lanza: la reclamación ya existe.
   * Siempre vacía lo pendiente; lo que falle se sube desde el expediente de la reclamación.
   * @param {{id:string, submission_id:string}} claim resultado de capture_claim
   */
  async function subirPendientes(claim, orgId) {
    if (!pend) return { subidas: 0, fallas: [] };
    const p = pend; const fallas = []; let subidas = 0; let primero = null;
    const [etiq, codigo] = TIPOS[p.tipo];
    for (let i = 0; i < p.pages.length; i += 1) {
      const pg = p.pages[i];
      try {
        const id = await subirCaptura({
          orgId, submissionId: claim.submission_id, lineId: claim.id, docType: codigo, blob: pg.blob, sha256: pg.sha256, origen: pg.origen,
          nombre: `${etiq}-pag${i + 1}de${p.pages.length}`, ocr: i === 0 ? p.ocr : null
        });
        subidas += 1; if (i === 0) primero = id;
      } catch (e) { fallas.push(`Página ${i + 1}: ${mensaje(e)}`); }
    }
    if (primero && p.ocr && p.confirmados) {
      try {
        const campos = {};
        Object.keys(p.ocr).forEach((k) => { campos[k] = p.confirmados[k] || ''; });          // lo leído y rechazado queda como vacío (manual)
        Object.keys(p.confirmados).forEach((k) => { if (!(k in campos)) campos[k] = p.confirmados[k]; }); // lo escrito a mano
        await confirmarLectura(primero, campos);
      } catch (e) { fallas.push(`Confirmación de lo leído: ${mensaje(e)}`); }
    }
    // lo que no subió no se arrastra a la siguiente reclamación: se sube desde el expediente de ésta
    limpiarPend();
    return { subidas, fallas };
  }

  pintarHost();
  return { abrir, subirPendientes, limpiar: limpiarPend, hayPendientes: () => !!pend };
}
