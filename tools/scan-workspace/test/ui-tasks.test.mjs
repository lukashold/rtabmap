import test from 'node:test';
import assert from 'node:assert/strict';
import { createTaskRunner } from '../src/ui-tasks.js';

test('a pending file read prevents a second import or save from replacing its workspace', async () => {
  const states = [], runner = createTaskRunner(value => states.push(value));
  let finishRead, currentRoom = 'original', secondRead = false;
  const pendingRead = new Promise(resolve => finishRead = resolve);
  const first = runner.run(async () => { await pendingRead; currentRoom = 'first import'; });
  assert.equal(runner.busy, true);
  const second = await runner.run(async () => { secondRead = true; currentRoom = 'second import'; });
  assert.equal(second, false);
  assert.equal(secondRead, false);
  assert.equal(currentRoom, 'original');
  finishRead();
  assert.equal(await first, true);
  assert.equal(currentRoom, 'first import');
  assert.deepEqual(states, [true, false]);
  assert.equal(await runner.run(async () => { currentRoom = 'later import'; }), true);
  assert.equal(currentRoom, 'later import');
});

test('invalid archive and model parsing failures release the UI for a retry', async () => {
  const states = [], runner = createTaskRunner(value => states.push(value));
  await assert.rejects(runner.run(async () => { await Promise.resolve(); throw new Error('badArchive'); }), /badArchive/);
  assert.equal(runner.busy, false);
  let retried = false;
  await runner.run(async () => { retried = true; });
  assert.equal(retried, true);
  assert.deepEqual(states, [true, false, true, false]);
});
