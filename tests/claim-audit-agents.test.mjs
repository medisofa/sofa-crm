// Ejecutar: node --experimental-default-type=module --test tests/claim-audit-agents.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { preauditClaim } from '../js/services/claim-audit-agents.js';

const valid = { organization_id: 'synthetic-org', member_number: '000', service_date: '2026-10-20', authorization_number: 'AUTH-X', amount: 1200 };
const ctx = { isDemo: true, duplicateCandidates: [] };

test('no confunde revisión humana con aprobación automática', () => {
  const r = preauditClaim(valid, ctx);
  assert.equal(r.decision, 'human_review_required');
  assert.equal(r.requiresHumanReview, true);
  assert.equal(r.isDemo, true);
  assert.equal(r.externalVerified, false);
  assert.equal(r.checks.find(x => x.code === 'ars_coverage').status, 'pending');
});

test('bloquea campo NSS vacío', () => {
  const r = preauditClaim({ ...valid, member_number: '' }, ctx);
  assert.equal(r.decision, 'correction_required');
});

test('bloquea duplicado detectado por RPC', () => {
  const r = preauditClaim(valid, { ...ctx, duplicateCandidates: [{ blocks_radicacion: true }] });
  assert.equal(r.decision, 'correction_required');
  assert.equal(r.checks.find(x => x.code === 'duplicate').status, 'block');
});

test('si faltan resultados del detector, marca pendiente', () => {
  const r = preauditClaim(valid, { isDemo: false });
  assert.equal(r.checks.find(x => x.code === 'duplicate').status, 'pending');
});

test('no acepta fechas imposibles', () => {
  const r = preauditClaim({ ...valid, service_date: '2026-02-30' }, ctx);
  assert.equal(r.decision, 'correction_required');
});

test('se niega a operar sin tipo DEMO comprobado', () => {
  assert.throws(() => preauditClaim(valid, {}), /isDemo/);
});

test('no interpreta una respuesta arbitraria como evidencia oficial de la ARS', () => {
  const r = preauditClaim(valid, { ...ctx, arsCoverage: { verified: true, active: true, source: 'mock' } });
  assert.equal(r.externalVerified, false);
});
