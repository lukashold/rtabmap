import test from 'node:test';
import assert from 'node:assert/strict';
import { Matrix4, Quaternion, Vector3 } from 'three';
import { registerLandmarks, RegistrationError } from '../src/registration.js';

const points = [[0, 0, 0], [4, 0, 0], [1, 3, 0], [.5, .8, 2], [2, -.6, .7]];
const near = (actual, expected, tolerance = 1e-9) => assert.ok(Math.abs(actual-expected) <= tolerance, `${actual} != ${expected}`);
const apply = (set, matrix) => set.map(point => new Vector3(...point).applyMatrix4(matrix).toArray());
const transform = (axis, angle, translation) => new Matrix4().compose(new Vector3(...translation), new Quaternion().setFromAxisAngle(new Vector3(...axis).normalize(), angle), new Vector3(1, 1, 1));
function properRigid(matrix) {
  const m = new Matrix4().fromArray(matrix);
  near(m.determinant(), 1);
  const columns = [0, 1, 2].map(i => new Vector3().setFromMatrixColumn(m, i));
  columns.forEach(column => near(column.length(), 1));
  near(columns[0].dot(columns[1]), 0); near(columns[0].dot(columns[2]), 0); near(columns[1].dot(columns[2]), 0);
  return m;
}

test('known 3D rotation and translation maps source to target in Three column-major order', () => {
  const known = transform([1, -2, 3], 1.17, [8.2, -3.4, .7]), target = apply(points, known);
  const before = structuredClone({ points, target });
  const result = registerLandmarks(points, target, { maxResidual: 1e-8 });
  result.matrix.forEach((value, index) => near(value, known.elements[index]));
  properRigid(result.matrix); near(result.rmse, 0);
  assert.equal(result.accepted, true); assert.equal(result.status, 'accepted');
  assert.equal(result.units, 'm'); assert.equal(result.direction, 'source-to-target'); assert.equal(result.scale, 1);
  assert.equal(result.residuals.length, points.length); assert.equal(result.threshold, 1e-8);
  assert.deepEqual({ points, target }, before);
});

test('three planar non-collinear pairs suffice, including a 180-degree rotation', () => {
  const source = [[0, 0, 0], [4, 0, 0], [.5, 2, 0]];
  const known = transform([1, 2, -.3], Math.PI, [-1, 5, 3]);
  const result = registerLandmarks(source, apply(source, known), { maxResidual: 1e-8 });
  assert.equal(result.accepted, true); properRigid(result.matrix);
  result.matrix.forEach((value, i) => near(value, known.elements[i]));
});

test('identity is retained but absent threshold stays explicitly unreviewed', () => {
  const result = registerLandmarks(points, points);
  properRigid(result.matrix); near(result.rmse, 0);
  assert.equal(result.accepted, null); assert.equal(result.threshold, null); assert.equal(result.status, 'needs-review');
});

test('noisy references report actual residuals and every point must satisfy the supplied threshold', () => {
  const target = apply(points, transform([.4, 1, -.2], -.42, [2, 0, -.9]));
  target[3][0] += .08;
  const result = registerLandmarks(points, target);
  assert.ok(result.rmse > .001 && result.maxResidual > result.rmse);
  const mapped = apply(points, properRigid(result.matrix));
  result.residuals.forEach((distance, i) => near(distance, new Vector3(...mapped[i]).distanceTo(new Vector3(...target[i]))));
  near(result.rmse, Math.sqrt(result.residuals.reduce((sum, value) => sum + value*value, 0)/points.length));
  // A threshold above RMSE but below the worst landmark must still reject.
  const threshold = (result.rmse+result.maxResidual)/2;
  assert.equal(registerLandmarks(points, target, { maxResidual: threshold }).accepted, false);
  assert.equal(registerLandmarks(points, target, { maxResidual: result.maxResidual+.000001 }).accepted, true);
});

test('mismatched landmark correspondence is not silently reordered or discarded', () => {
  const target = apply(points, transform([0, 1, 0], .7, [2, 1, 3]));
  [target[0], target[4]] = [target[4], target[0]];
  const result = registerLandmarks(points, target, { maxResidual: .01 });
  assert.equal(result.accepted, false); assert.equal(result.status, 'rejected');
  assert.ok(result.maxResidual > .1); assert.equal(result.residuals.length, points.length); properRigid(result.matrix);
});

test('an asymmetric non-planar reflection is not accepted or fitted with an improper rotation', () => {
  const reflected = points.map(([x, y, z]) => [-x+7, y-2, z+1]);
  const result = registerLandmarks(points, reflected, { maxResidual: .001 });
  assert.equal(result.accepted, false); assert.ok(result.rmse > .1); properRigid(result.matrix);
});

test('scale mismatch remains visible; the fitted transform never changes landmark distances', () => {
  const scaled = points.map(point => point.map(value => value*1.3));
  const result = registerLandmarks(points, apply(scaled, transform([2, 1, 3], .4, [5, 6, 7])), { maxResidual: .001 });
  assert.equal(result.accepted, false); assert.equal(result.scale, 1);
  const fitted = apply(points, properRigid(result.matrix));
  near(new Vector3(...fitted[0]).distanceTo(new Vector3(...fitted[1])), 4);
  assert.ok(result.maxResidual > .1);
});

test('duplicates, coincident and near-collinear anchors are rejected in either set', () => {
  const degenerate = [
    [[1, 2, 3], [1, 2, 3], [1, 2, 3]],
    [[0, 0, 0], [1, 2, 3], [2, 4, 6]],
    [[0, 0, 0], [1, 0, 0], [2, 1e-12, 0]],
    [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 1, 0]]
  ];
  for (const set of degenerate) {
    const valid = points.slice(0, set.length);
    assert.throws(() => registerLandmarks(set, valid), RegistrationError);
    assert.throws(() => registerLandmarks(valid, set), RegistrationError);
  }
});

test('finite dimensions, matching counts, bounded arrays and explicit thresholds are validated', () => {
  for (const input of [null, {}, [], Array(3), [[0, 0, 0], [1, 1, 1]], [...points, [0, 1]], [...points, [0, , 1]], Array(1001).fill([0, 0, 0])]) {
    assert.throws(() => registerLandmarks(input, points), RegistrationError);
  }
  for (const value of [NaN, Infinity, -Infinity, '1', 1e10, undefined]) {
    const bad = structuredClone(points); bad[1][2] = value;
    assert.throws(() => registerLandmarks(points, bad), RegistrationError);
  }
  assert.throws(() => registerLandmarks(points, points.slice(0, 3)), { code: 'landmarkCountMismatch' });
  for (const maxResidual of [NaN, Infinity, -1, '0.01', null, 1e10]) {
    assert.throws(() => registerLandmarks(points, points, { maxResidual }), { code: 'invalidRegistrationThreshold' });
  }
  for (const options of [null, [], 1, '']) assert.throws(() => registerLandmarks(points, points, options), RegistrationError);
});

test('non-collinear inputs with an ambiguous optimal rotation are not falsely accepted', () => {
  const regularTetrahedron = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]];
  const reflected = regularTetrahedron.map(([x, y, z]) => [-x, y, z]);
  assert.throws(() => registerLandmarks(regularTetrahedron, reflected, { maxResidual: 10 }), { code: 'ambiguousRegistration' });
});

test('a translated large origin retains useful local room geometry', () => {
  const source = points.map(([x, y, z]) => [x+1e7, y-2e7, z+3e7]);
  const target = apply(source, transform([1, 2, 3], .6, [2, 3, 4]));
  const result = registerLandmarks(source, target, { maxResidual: 1e-6 });
  assert.equal(result.accepted, true); assert.ok(result.matrix.every(Number.isFinite)); properRigid(result.matrix);
});
