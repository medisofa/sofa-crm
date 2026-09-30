/**
 * SOFA · Protección del arranque (script clásico, se carga antes que los módulos).
 * Si un archivo tiene un error (por ejemplo, una coma o comilla de más en
 * js/config.js), los módulos no se ejecutan y la pantalla quedaría en
 * "Cargando…". Este script detecta ese caso y muestra qué pasó.
 */
(function () {
  // Protección contra clickjacking: SOFA no se muestra dentro de un marco (iframe) de otro sitio
  try {
    if (window.top !== window.self) {
      document.documentElement.style.display = 'none';
      window.top.location = window.self.location.href;
      return;
    }
  } catch (e) { document.documentElement.style.display = 'none'; return; }
  var errors = [];
  function remember(msg, where) {
    if (errors.length < 5) errors.push((where ? where + ': ' : '') + msg);
  }
  window.addEventListener('error', function (e) {
    var t = e.target;
    if (t && t !== window && (t.src || t.href)) remember('no se pudo descargar', (t.src || t.href).split('/').slice(-2).join('/'));
    else if (e.message) remember(e.message, e.filename ? e.filename.split('/').slice(-2).join('/') + (e.lineno ? ' (línea ' + e.lineno + ')' : '') : '');
  }, true);
  window.addEventListener('unhandledrejection', function (e) { remember(String((e.reason && e.reason.message) || e.reason)); });

  function show() {
    var boot = document.querySelector('.boot');
    if (!boot) return; // la aplicación arrancó
    var configHint = errors.some(function (m) { return /config\.js/i.test(m); }) || !errors.length;
    var box = document.createElement('div');
    box.setAttribute('role', 'alert');
    box.style.cssText = 'max-width:560px;margin:40px auto;padding:20px;border:1px solid #DCE1E8;border-radius:10px;background:#fff;color:#172131;font:15px/1.5 system-ui,sans-serif';
    var h = document.createElement('h1'); h.style.cssText = 'font-size:19px;margin:0 0 8px'; h.textContent = 'SOFA no pudo iniciar';
    var p = document.createElement('p'); p.style.margin = '0 0 10px';
    p.textContent = configHint
      ? 'Lo más probable es un error de escritura en js/config.js: revisa que cada valor esté entre comillas simples rectas (\') y que cada línea termine en coma.'
      : 'Un archivo de la aplicación tiene un error o no se descargó. Vuelve a subir los archivos indicados.';
    box.appendChild(h); box.appendChild(p);
    if (errors.length) {
      var pre = document.createElement('pre');
      pre.style.cssText = 'white-space:pre-wrap;background:#F2F5F8;padding:10px;border-radius:6px;font-size:12.5px;margin:0 0 10px';
      pre.textContent = 'Detalle técnico:\n' + errors.join('\n');
      box.appendChild(pre);
    }
    var btn = document.createElement('button');
    btn.textContent = 'Reintentar'; btn.style.cssText = 'padding:9px 16px;border-radius:6px;border:0;background:#1A365D;color:#fff;font-weight:600;cursor:pointer';
    btn.onclick = function () { location.reload(); };
    box.appendChild(btn);
    boot.replaceWith(box);
  }
  setTimeout(show, 8000);
  window.addEventListener('load', function () { if (errors.length) setTimeout(show, 1500); });
})();
