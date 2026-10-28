/**
 * SOFA · Bandera compartida de "Ver como" (modo soporte, solo lectura).
 * app.js la actualiza al entrar/salir; cualquier utilidad puede importarla
 * para bloquear exportar/imprimir sin tener que importar app.js (evita
 * dependencias circulares, ya que app.js importa muchos módulos).
 */
export const viewAsState = { active: false };
