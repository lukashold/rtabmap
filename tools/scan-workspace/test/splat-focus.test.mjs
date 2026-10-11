import test from 'node:test';
import assert from 'node:assert/strict';
import { PerspectiveCamera, Vector3 } from 'three';
import { splatSubjectBounds, MAX_SUBJECT_SAMPLES } from '../src/splat-focus.js';
import { SplatViewer } from '../src/splat-viewer.js';
import { decodeSplat } from '../src/splat-data.js';
import { uxDictionaries } from '../src/ux-i18n.js';
import { supportedLanguages } from '../locales/index.js';

function cloud(positions, scale = .01) {
  const bytes = new Uint8Array(positions.length * 32), view = new DataView(bytes.buffer);
  positions.forEach((position, index) => {
    position.forEach((value, axis) => view.setFloat32(index * 32 + axis * 4, value, true));
    for (let axis = 0; axis < 3; axis++) view.setFloat32(index * 32 + 12 + axis * 4, scale, true);
    bytes.set([150,200,160,255,255,128,128,128], index * 32 + 24);
  });
  return decodeSplat(bytes, 'fixture.splat');
}

function cameraHarness(data) {
  // Exercise the real camera actions without constructing a WebGL context.
  const viewer = Object.create(SplatViewer.prototype);
  Object.assign(viewer, { data, camera: new PerspectiveCamera(50, 1.5, .01, 1000),
    controls: { target: new Vector3(), update() {} }, engine: { forceRenderNextFrame() {} } });
  return viewer;
}

test('subject framing resists extreme positions and Gaussian sizes without changing any point or full bound', () => {
  const positions = Array.from({ length: 100 }, (_, index) => [(index % 10) / 10, Math.floor(index / 10) / 10, 2]);
  positions.push([-220,-172,-113], [190,241,298]);
  const data = cloud(positions, 1000), original = data.original.slice(), bounds = structuredClone(data.bounds);
  Object.freeze(data.bounds.min); Object.freeze(data.bounds.max); Object.freeze(data.bounds);
  const focus = splatSubjectBounds(data);
  assert.equal(focus.sampleCount, 102);
  assert.ok(focus.min[0] >= 0 && focus.max[0] <= .91);
  assert.ok(focus.min[1] >= 0 && focus.max[1] <= .91);
  assert.equal(focus.min[2], 2); assert.equal(focus.max[2], 2);
  const viewer = cameraHarness(data);
  viewer.fit(); const fullPosition = viewer.camera.position.toArray(), fullTarget = viewer.controls.target.toArray();
  const fullDistance = viewer.camera.position.distanceTo(viewer.controls.target);
  viewer.focusSubject();
  assert.ok(viewer.camera.position.distanceTo(viewer.controls.target) < fullDistance / 1000);
  assert.ok(viewer.controls.target.x >= 0 && viewer.controls.target.x <= .91);
  assert.ok(viewer.camera.far > 3000); // Large Gaussians remain inside the far extent.
  viewer.fit();
  assert.deepEqual(viewer.camera.position.toArray(), fullPosition);
  assert.deepEqual(viewer.controls.target.toArray(), fullTarget);
  assert.equal(data.count, positions.length); assert.equal(data.bytes, data.original);
  assert.deepEqual(data.original, original); assert.deepEqual(data.bounds, bounds);
});

test('subject sample storage remains capped and covers the whole record range', () => {
  const count = MAX_SUBJECT_SAMPLES * 10, bytes = new Uint8Array(count * 32), view = new DataView(bytes.buffer);
  for (let index = 0; index < count; index++) view.setFloat32(index * 32, index, true);
  const focus = splatSubjectBounds({ bytes, count });
  assert.equal(focus.sampleCount, 8192);
  assert.ok(Math.abs(focus.min[0] - (count - 1) * .05) < 2);
  assert.ok(Math.abs(focus.max[0] - (count - 1) * .95) < 2);
  assert.deepEqual(focus.min.slice(1), [0,0]);
});

test('small, coincident, offset-buffer and invalid clouds have safe deterministic framing', () => {
  for (const positions of [[[1,2,3]], [[1,2,3],[1,2,3]], [[0,0,0],[10,0,0]]]) {
    const data = cloud(positions), focus = splatSubjectBounds(data), viewer = cameraHarness(data);
    assert.ok([...focus.min, ...focus.max].every(Number.isFinite));
    viewer.focusSubject();
    assert.ok(viewer.camera.position.toArray().every(Number.isFinite));
    assert.ok(viewer.camera.near > 0 && viewer.camera.far > viewer.camera.near);
    const position = viewer.camera.position.toArray(); viewer.closed = true; viewer.focusSubject();
    assert.deepEqual(viewer.camera.position.toArray(), position);
  }
  const data = cloud([[1,2,3]]), backing = new Uint8Array(64); backing.set(data.bytes, 16);
  assert.deepEqual(splatSubjectBounds({bytes:backing.subarray(16,48),count:1}).min, [1,2,3]);
  for (const input of [null, {}, {bytes:new Uint8Array(),count:0}, {bytes:new Uint8Array(31),count:1}]) assert.equal(splatSubjectBounds(input), null);
  new DataView(data.bytes.buffer).setFloat32(0, NaN, true);
  assert.equal(splatSubjectBounds(data), null);
  assert.doesNotThrow(() => cameraHarness(data).focusSubject());
});

test('all fifteen languages name the explicit focus action and link back to the complete view', () => {
  for (const language of supportedLanguages) {
    const words = uxDictionaries[language];
    assert.ok(words.splatFocus?.trim(), language);
    assert.ok(words.splatFocusHelp?.includes('{all}'), language);
  }
});
