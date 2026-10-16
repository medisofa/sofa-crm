/* SOFA · 4.7.0 · SEG-31 · Bloqueo de marcos (clickjacking) desde el arranque.
 * Script clásico y externo ('self'): la política CSP no permite scripts en línea.
 * La página nace oculta (<style id="anti-marcos"> en el <head>). Solo se muestra si NO está dentro de un marco;
 * si está enmarcada se queda oculta e intenta sacar la ventana del marco. Si este archivo no carga, la página sigue oculta (falla cerrado). */
(function () {
  var libre = false;
  try { libre = window.top === window.self; } catch (e) { libre = false; }
  if (libre) {
    var e = document.getElementById('anti-marcos');
    if (e && e.parentNode) e.parentNode.removeChild(e);
    return;
  }
  try { window.top.location = window.self.location; } catch (e) { /* otro origen o marco con sandbox: se queda oculta */ }
})();
