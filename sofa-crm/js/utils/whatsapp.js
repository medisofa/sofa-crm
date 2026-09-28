/** SOFA · Enlaces de WhatsApp (números dominicanos: 809/829/849 + 7 dígitos) */
export function waNumber(n) {
  let d = String(n || '').replace(/\D/g, '');
  if (d.length === 10) d = `1${d}`;
  return d.length >= 11 && d.length <= 15 ? d : '';
}
export const waLink = (n, text = '') => { const d = waNumber(n); return d ? `https://wa.me/${d}${text ? `?text=${encodeURIComponent(text)}` : ''}` : ''; };
export const phoneFmt = (n) => {
  const d = String(n || '').replace(/\D/g, '');
  const m = /^1?(\d{3})(\d{3})(\d{4})$/.exec(d);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : (n || '');
};
