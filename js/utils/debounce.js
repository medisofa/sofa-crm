/** Retrasa la ejecución de fn hasta que pasen ms milisegundos sin que vuelva a llamarse. */
export const debounce = (fn, ms = 300) => {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
};
