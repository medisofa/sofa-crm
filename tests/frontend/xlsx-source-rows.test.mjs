import test from 'node:test';
import assert from 'node:assert/strict';
import { readDelimited, readTable } from '../../js/utils/xlsx-lite.js';

test('error references preserve physical CSV lines after blanks and quoted multiline descriptions', () => {
  const rows = readDelimited('Servicio;Descripción;Tarifa\r\n\r\nP1;"Primera\nsegunda";1500\r\n\r\nP2;Otro;2000\r\n');
  assert.deepEqual(rows.map((r) => r.sourceRow), [1, 3, 6]);
  assert.deepEqual(rows[1], ['P1', 'Primera\nsegunda', '1500']);
});

test('readTable preserves provenance while keeping the existing array API', async () => {
  const rows = await readTable({ name: 'tarifa.csv', size: 60, text: async () => '\uFEFFServicio;Tarifa\nP1;100\n\nP2;200' });
  assert.deepEqual(rows, [['Servicio', 'Tarifa'], ['P1', '100'], ['P2', '200']]);
  assert.equal(rows[2].sourceRow, 4);
  assert.equal(JSON.stringify(rows[2]), '["P2","200"]');
});
