/** SOFA · Horas libres según el horario del médico, sus citas y las horas no disponibles (respuesta de agenda_week). */
export const toMin = (t) => { const [h, m] = String(t).split(':').map(Number); return h * 60 + (m || 0); };
export const toHHMM = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
export const isoDow = (iso) => { const d = new Date(`${iso}T12:00:00`).getDay(); return d === 0 ? 7 : d; };

/** @returns {string[]} horas HH:MM libres ese día. ignoreId: la cita que se está moviendo no se estorba a sí misma. */
export function freeSlots(data, date, ignoreId = null) {
  const taken = [
    ...(data.appointments || []).filter((a) => a.date === date && a.time && a.id !== ignoreId && !['cancelada', 'no_asistio'].includes(a.status))
      .map((a) => [toMin(a.time), toMin(a.time) + (a.duration_min || 30)]),
    ...(data.busy || []).filter((b) => b.date === date).map((b) => [toMin(b.start), toMin(b.end)])
  ];
  const free = [];
  (data.schedule || []).filter((s) => s.weekday === isoDow(date)).forEach((s) => {
    for (let m = toMin(s.start); m + s.slot_min <= toMin(s.end); m += s.slot_min) {
      if (!taken.some(([from, to]) => m < to && m + s.slot_min > from)) free.push(toHHMM(m));
    }
  });
  return [...new Set(free)].sort();
}
