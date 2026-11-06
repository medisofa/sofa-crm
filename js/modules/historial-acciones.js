/** SOFA · 5.28.1 · Historial de acciones del sistema: consulta del audit_log para admin y super_admin.
 *  La tabla audit_log es append-only (protegida por trigger); aquí solo se lee. */
import { sb } from '../supabase.js';
import { h, fmtDate, note, guarded } from '../services/iter18.js';

const TABLE_LABELS = {
  submissions: 'Radicaciones', glosas: 'Glosas', payments: 'Pagos', clients: 'Clientes',
  users: 'Usuarios', tariffs: 'Tarifarios', appointments: 'Citas', invoices: 'Facturas',
  claims: 'Reclamaciones', providers: 'Médicos', organizations: 'Organizaciones',
  contracts: 'Contratos', habilitation_cases: 'Habilitaciones'
};
const OP_LABELS = { INSERT: 'Creación', UPDATE: 'Modificación', DELETE: 'Eliminación' };
const OP_COLORS = { INSERT: 'var(--ok)', UPDATE: 'var(--warn)', DELETE: 'var(--bad)' };

function fmtChanges(op, oldV, newV) {
  if (!oldV && !newV) return '—';
  if (op === 'INSERT') return newV ? Object.keys(newV).slice(0, 3).join(', ') + (Object.keys(newV).length > 3 ? '…' : '') : '—';
  if (op === 'DELETE') return 'Registro eliminado';
  if (op === 'UPDATE' && oldV && newV) {
    const changed = Object.keys(newV).filter((k) => JSON.stringify(newV[k]) !== JSON.stringify(oldV[k]));
    return changed.length ? changed.slice(0, 3).join(', ') + (changed.length > 3 ? ` … (+${changed.length - 3})` : '') : 'Sin cambios de datos';
  }
  return '—';
}

function fmtDateTime(iso) {
  if (!iso) return '—';
  return fmtDate(iso) + ' ' + iso.slice(11, 16);
}

function exportCsv(rows, userNames) {
  const header = ['Fecha y hora', 'Usuario', 'Tabla', 'Registro', 'Operación', 'Campos afectados'];
  const lines = rows.map((r) => [
    fmtDateTime(r.created_at),
    r.user_id ? (userNames[r.user_id] || r.user_id.slice(0, 8)) : '—',
    TABLE_LABELS[r.table_name] || r.table_name,
    r.record_id ? String(r.record_id).slice(0, 8) : '—',
    OP_LABELS[r.operation] || r.operation,
    fmtChanges(r.operation, r.old_values, r.new_values)
  ].map((v) => `"${String(v).replace(/"/g, '""')}"`).join(','));
  const blob = new Blob(['﻿' + [header.join(','), ...lines].join('\r\n')], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = `historial-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click(); setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/** Carga nombres de usuario para los user_ids únicos del lote. */
async function loadUserNames(userIds) {
  const ids = [...new Set(userIds)].filter(Boolean);
  if (!ids.length) return {};
  try {
    const { data } = await sb().from('profiles').select('id, full_name').in('id', ids);
    if (!data) return {};
    return Object.fromEntries(data.map((p) => [p.id, p.full_name || p.id.slice(0, 8)]));
  } catch { return {}; }
}

export async function render(root) {
  root.replaceChildren();
  const out = h('div', { 'aria-live': 'polite' });
  const tableFilter = h('select', { id: 'ha-tabla' },
    h('option', { value: '' }, 'Todas las tablas'),
    Object.entries(TABLE_LABELS).map(([v, l]) => h('option', { value: v }, l)));
  const opFilter = h('select', { id: 'ha-op' },
    h('option', { value: '' }, 'Todas las operaciones'),
    Object.entries(OP_LABELS).map(([v, l]) => h('option', { value: v }, l)));
  const fromFilter = h('input', { id: 'ha-from', type: 'date', value: new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10) });
  const toFilter = h('input', { id: 'ha-to', type: 'date', value: new Date().toISOString().slice(0, 10) });
  const go = h('button', { class: 'i18-btn', type: 'button' }, 'Buscar');
  const exportBtn = h('button', { class: 'i18-btn i18-sec', type: 'button', disabled: true }, 'Exportar CSV');

  root.append(h('div', { class: 'i18-wrap' },
    h('h2', {}, 'Historial de acciones'),
    h('p', { class: 'i18-sub' }, 'Registro de cambios en el sistema. Solo visible para administradores. Solo lectura — no se puede editar ni eliminar.'),
    h('div', { class: 'i18-form', style: 'display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end;margin-bottom:16px' },
      h('label', { for: 'ha-tabla' }, 'Tabla', tableFilter),
      h('label', { for: 'ha-op' }, 'Operación', opFilter),
      h('label', { for: 'ha-from' }, 'Desde', fromFilter),
      h('label', { for: 'ha-to' }, 'Hasta', toFilter),
      go, exportBtn),
    out));

  async function load() {
    const d = await guarded(out, async () => {
      let q = sb().from('audit_log')
        .select('id, user_id, table_name, record_id, operation, old_values, new_values, created_at')
        .order('created_at', { ascending: false })
        .limit(200);
      if (tableFilter.value) q = q.eq('table_name', tableFilter.value);
      if (opFilter.value) q = q.eq('operation', opFilter.value);
      if (fromFilter.value) q = q.gte('created_at', fromFilter.value + 'T00:00:00');
      if (toFilter.value) q = q.lte('created_at', toFilter.value + 'T23:59:59');
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return data || [];
    });
    if (d == null) return;
    if (!d.length) { out.replaceChildren(note('No hay registros para los filtros seleccionados.')); return; }

    const userNames = await loadUserNames(d.map((r) => r.user_id));
    exportBtn.disabled = false;
    exportBtn.onclick = () => exportCsv(d, userNames);

    out.replaceChildren(
      h('p', { style: 'font-size:13px;color:var(--ink-2);margin-bottom:8px' }, `${d.length} registro(s)${d.length === 200 ? ' (límite: 200)' : ''}`),
      h('div', { class: 'i18-table-wrap' }, h('table', { class: 'i18-table' },
        h('thead', {}, h('tr', {},
          ['Fecha y hora', 'Usuario', 'Tabla', 'Registro', 'Operación', 'Campos afectados'].map((x) => h('th', {}, x)))),
        h('tbody', {}, d.map((row) => h('tr', {},
          h('td', { style: 'white-space:nowrap' }, fmtDateTime(row.created_at)),
          h('td', { style: 'max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap', title: row.user_id || '' },
            row.user_id ? (userNames[row.user_id] || row.user_id.slice(0, 8) + '…') : '—'),
          h('td', {}, TABLE_LABELS[row.table_name] || row.table_name),
          h('td', { style: 'font-family:monospace;font-size:12px' }, row.record_id ? String(row.record_id).slice(0, 8) + '…' : '—'),
          h('td', {}, h('span', { style: `font-size:12px;font-weight:600;color:${OP_COLORS[row.operation] || 'inherit'}` }, OP_LABELS[row.operation] || row.operation)),
          h('td', { style: 'font-size:12px;color:var(--ink-2)' }, fmtChanges(row.operation, row.old_values, row.new_values))))))));
  }

  go.addEventListener('click', load);
  await load();
}
export default render;
