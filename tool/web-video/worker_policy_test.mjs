import {test} from 'node:test';
import assert from 'node:assert/strict';
import {editPlan, maximumEncodedBytes} from './worker.mjs';

for (const [preset, bitrate] of [['smaller', 1500000], ['balanced', 4000000]]) {
  test(`${preset}: video bitrate is independent of clip length`, () => {
    for (const duration of [5, 120, 1800, 3600]) {
      const plan = editPlan({preset}, 1920, 1080, duration);
      assert.equal(plan.bitrate, bitrate);
      assert.equal(plan.maximum, maximumEncodedBytes);
      assert.equal(plan.end, duration);
    }
  });
}
test('all qualities retain the common browser-memory guard, not 12/24 MiB caps', () => {
  assert.equal(maximumEncodedBytes, 128 * 1048576);
  const original = editPlan({optimize:false}, 1920, 1080, 600);
  assert.equal(original.bitrate, 8000000);
  assert.equal(original.maximum, maximumEncodedBytes);
});
test('decode, duration and invalid crop safety guards remain', () => {
  assert.throws(() => editPlan({}, 8000, 8000, 60));
  assert.throws(() => editPlan({}, 1920, 1080, 3601));
  assert.throws(() => editPlan({edit:{width:2}}, 1920, 1080, 60));
});
