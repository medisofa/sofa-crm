/** SOFA · Horas por usuario (migración 276). Solo llamadas a la base. */
import { rpc } from './iter18.js';

/** Latido de conexión: usage_ping(p_active). */
export const usagePing = (active) => rpc('usage_ping', { p_active: !!active });
/** Reporte semanal (solo Super Admin / Administrador): usage_hours_report(p_from, p_to) → { since, rows }. */
export const usageHoursReport = (from, to) => rpc('usage_hours_report', { p_from: from, p_to: to });
