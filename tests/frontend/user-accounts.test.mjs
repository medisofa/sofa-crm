import test from 'node:test';
import assert from 'node:assert/strict';
import { groupUserAccounts, matchesAccount, resolveAccountAction, mergeCapturerScope } from '../../js/utils/user-accounts.js';

const membership = (extra = {}) => ({ user_id: 'a', email: 'a@example.test', full_name: 'Ana', role_code: 'client', organization_id: 'clinic-a', kind: 'client', is_active: true, status: 'activo', ...extra });

test('one account keeps separate roles and organizations and removes repeated membership rows', () => {
  const row = membership();
  const accounts = groupUserAccounts([row, { ...row }, membership({ organization_id: 'clinic-b', role_code: 'capturer' })]);
  assert.equal(accounts.length, 1);
  assert.equal(accounts[0].memberships.length, 2);
  assert.equal(accounts[0].is_active, true);
});

test('distinct user IDs with the same normalized email remain separate and flagged', () => {
  const accounts = groupUserAccounts([membership(), membership({ user_id: 'b', email: ' A@EXAMPLE.TEST ' })]);
  assert.equal(accounts.length, 2);
  assert.ok(accounts.every((a) => a.sharedEmail));
});

test('mixed status and contradictory membership data never imply a global activation state', () => {
  const mixed = groupUserAccounts([membership(), membership({ organization_id: 'clinic-b', is_active: false, status: 'desactivado' })])[0];
  assert.equal(mixed.is_active, null);
  const conflict = groupUserAccounts([membership(), membership({ is_active: false, status: 'desactivado' })])[0];
  assert.equal(conflict.memberships.length, 1);
  assert.equal(conflict.memberships[0].conflict, true);
  assert.equal(conflict.is_active, null);
});

test('filters match role and status on the same membership and search ignores accents', () => {
  const account = groupUserAccounts([membership({ full_name: 'Ángela' }), membership({ kind: 'operator', role_code: 'admin', organization_id: 'sofa', status: 'desactivado', is_active: false })])[0];
  assert.equal(matchesAccount(account, { kind: 'sofa', status: 'activo' }), false);
  assert.equal(matchesAccount(account, { kind: 'sofa', status: 'desactivado', q: 'angela' }), true);
  assert.equal(matchesAccount(account, { kind: 'client', status: 'activo' }), true);
});

test('super-admin protection considers all accesses and missing IDs are never merged', () => {
  const account = groupUserAccounts([membership(), membership({ role_code: 'super_admin', kind: 'operator', organization_id: 'sofa' })])[0];
  assert.equal(account.protectedAdmin, true);
  assert.equal(groupUserAccounts([membership({ user_id: null }), membership({ user_id: null })]).length, 2);
});

test('inconsistent account emails disable email-addressed actions', () => {
  const account = groupUserAccounts([membership(), membership({ email: 'other@example.test', organization_id: 'clinic-b' })])[0];
  assert.equal(account.emailConflict, true);
  assert.equal(account.email, '');
});

test('account actions reject self, unknown targets/actions and unauthorized actor roles', () => {
  const accounts = groupUserAccounts([membership()]);
  const actor = { userId: 'actor', role: 'super_admin' };
  const request = { action: 'toggle', userId: 'a' };
  assert.ok(resolveAccountAction(accounts, actor, request));
  assert.equal(resolveAccountAction(accounts, { ...actor, userId: 'a' }, request), null);
  assert.equal(resolveAccountAction(accounts, { ...actor, role: 'client' }, request), null);
  assert.equal(resolveAccountAction(accounts, { ...actor, role: 'admin' }, request), null);
  assert.equal(resolveAccountAction(accounts, actor, { ...request, action: 'delete' }), null);
  assert.equal(resolveAccountAction(accounts, actor, { ...request, userId: 'unknown' }), null);
});

test('email actions reject shared identities, while precise user/role/org selection is required', () => {
  const actor = { userId: 'actor', role: 'admin' };
  const shared = groupUserAccounts([membership(), membership({ user_id: 'b' })]);
  assert.equal(resolveAccountAction(shared, actor, { action: 'resend', userId: 'a' }), null);
  assert.equal(resolveAccountAction(shared, actor, { action: 'grant', userId: 'a', role: 'client', orgId: 'clinic-a' }), null);
  const accounts = groupUserAccounts([membership()]);
  assert.equal(resolveAccountAction(accounts, actor, { action: 'validate', userId: 'a', role: 'client', orgId: 'clinic-b' }), null);
  const chosen = resolveAccountAction(accounts, actor, { action: 'validate', userId: 'a', role: 'client', orgId: 'clinic-a' });
  assert.equal(chosen.membership.organization_id, 'clinic-a');
});

test('filtered memberships never weaken super-admin protection or ambiguous-state guards', () => {
  const accounts = groupUserAccounts([membership(), membership({ role_code: 'super_admin', organization_id: 'sofa', kind: 'operator', is_active: false })]);
  assert.equal(resolveAccountAction(accounts, { userId: 'actor', role: 'admin' }, { action: 'validate', userId: 'a', role: 'client', orgId: 'clinic-a' }), null);
  assert.equal(resolveAccountAction(accounts, { userId: 'actor', role: 'super_admin' }, { action: 'toggle', userId: 'a' }), null);
});

test('updating one consultorio preserves other provider scopes and rejects foreign choices', () => {
  assert.deepEqual(mergeCapturerScope(['old-a', 'keep-b'], ['old-a', 'new-a'], ['new-a']), ['keep-b', 'new-a']);
  assert.deepEqual(mergeCapturerScope(['old-a', 'keep-b'], ['old-a'], []), ['keep-b']);
  assert.throws(() => mergeCapturerScope(['keep-b'], ['new-a'], ['foreign-c']), /ajeno/);
});
