import { can } from './permissions.js';

// Una cuenta se identifica por user_id, nunca por nombre ni correo.
export function groupUserAccounts(rows = []) {
  const groups = new Map();
  rows.forEach((row, index) => {
    const key = row.user_id || `missing-id:${index}`;
    if (!groups.has(key)) groups.set(key, { key, user_id: row.user_id || null, memberships: [], emails: new Set() });
    const account = groups.get(key);
    if (row.email) account.emails.add(String(row.email).trim().toLowerCase());
    if (!account.full_name && row.full_name) account.full_name = row.full_name;
    if (row.last_sign_in_at && (!account.last_sign_in_at || new Date(row.last_sign_in_at) > new Date(account.last_sign_in_at))) account.last_sign_in_at = row.last_sign_in_at;
    const existing = account.memberships.find((m) => m.role_code === row.role_code && m.organization_id === row.organization_id);
    if (!existing) account.memberships.push({ ...row });
    else if (existing.is_active !== row.is_active || existing.status !== row.status || existing.access_readiness !== row.access_readiness) existing.conflict = true;
  });
  const accounts = [...groups.values()].map((account) => {
    const states = new Set(account.memberships.map((m) => m.is_active));
    return { ...account, email: account.emails.size === 1 ? [...account.emails][0] : '',
      emailConflict: account.emails.size > 1,
      is_active: states.size === 1 && !account.memberships.some((m) => m.conflict) && typeof [...states][0] === 'boolean' ? [...states][0] : null,
      protectedAdmin: account.memberships.some((m) => m.role_code === 'super_admin') };
  });
  const emailCounts = new Map();
  for (const account of accounts) for (const email of account.emails) emailCounts.set(email, (emailCounts.get(email) || 0) + 1);
  return accounts.map((account) => ({ ...account, sharedEmail: [...account.emails].some((email) => emailCounts.get(email) > 1) }));
}

/** Revalida la selección antes de cualquier acción. No sustituye autorización del servidor. */
export function resolveAccountAction(accounts, actor, request) {
  const account = accounts.find((u) => u.user_id && u.user_id === request.userId);
  if (!account || !actor?.userId || account.user_id === actor.userId ||
      (account.protectedAdmin && actor.role !== 'super_admin')) return null;
  const capabilities = { grant: 'users.invite', validate: 'users.invite', scope: 'capturers.assign',
    reset: 'users.reset', resend: 'users.invite', toggle: 'users.toggle', repair: 'users.toggle' };
  if (!capabilities[request.action] || !can(capabilities[request.action], actor.role)) return null;
  if (['grant', 'resend'].includes(request.action) && (!account.email || account.sharedEmail || account.emailConflict)) return null;
  if (request.action === 'toggle' && account.is_active === null) return null;
  if (request.action === 'repair') {
    if (actor.role !== 'super_admin') return null;
    const membership = account.memberships.find((m) => m.organization_id === request.orgId &&
      m.role_code === request.role && ['client','capturer'].includes(m.role_code) && m.is_active === true && !m.conflict);
    return membership ? { account, membership } : null;
  }
  if (['grant', 'scope', 'validate'].includes(request.action)) {
    const membership = account.memberships.find((m) => (m.role_code || '') === (request.role || '') &&
      (m.organization_id || '') === (request.orgId || ''));
    if (!membership || membership.conflict) return null;
    if (request.action === 'scope' && (membership.role_code !== 'capturer' || !membership.organization_id)) return null;
    return { account, membership };
  }
  return { account };
}

export function matchesAccount(account, { kind = '', status = '', q = '' } = {}) {
  const normalized = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const query = normalized(q).trim();
  if (query && !normalized(`${account.full_name} ${[...account.emails].join(' ')} ${account.user_id}`).includes(query)) return false;
  // Tipo y estado deben coincidir en el mismo acceso, no en dos membresías distintas.
  return account.memberships.some((m) => (!status || m.status === status) &&
    (!kind || (kind === 'sofa' ? m.kind === 'operator' : m.role_code === kind)));
}

export function mergeCapturerScope(current, editableProviders, chosen) {
  const editable = new Set(editableProviders);
  if (chosen.some((id) => !editable.has(id))) throw new Error('La selección contiene un médico ajeno al consultorio.');
  return [...new Set([...current.filter((id) => !editable.has(id)), ...chosen])];
}
