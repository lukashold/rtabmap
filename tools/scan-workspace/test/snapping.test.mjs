import test from 'node:test';
import assert from 'node:assert/strict';
import { BoxGeometry, BufferGeometry, Float32BufferAttribute, Group, InstancedMesh, Mesh, MeshBasicMaterial, OrthographicCamera, PerspectiveCamera, Plane, PlaneGeometry, Points, SkinnedMesh, Vector3 } from 'three';
import { buildSnapIndex, findSnap, visibleSnapPoint } from '../src/snapping.js';

const close = (actual, expected, tolerance = 1e-6) => assert.ok(actual.distanceTo(expected) < tolerance, `${actual.toArray()} != ${expected.toArray()}`);
const pixel = (point, camera, width = 800, height = 600) => { const p = point.clone().project(camera); return { x: (p.x + 1) * width / 2, y: (1 - p.y) * height / 2 }; };
const camera = () => { const c = new PerspectiveCamera(60, 4 / 3, .1, 100); c.updateMatrixWorld(); return c; };
const edgeIndex = (a, b) => ({ status: 'ready', corners: [], segments: [{ a, b }] });

test('coplanar indexed and non-indexed triangle diagonals are not eligible edges', () => {
  for (const geometry of [new PlaneGeometry(4, 3), new PlaneGeometry(4, 3).toNonIndexed()]) {
    const mesh = new Mesh(geometry), index = buildSnapIndex(mesh);
    assert.equal(index.status, 'ready');
    assert.equal(index.segments.length, 4);
    assert.equal(index.corners.length, 4);
    assert.ok(index.segments.every(({ a, b }) => a.x === b.x || a.y === b.y));
  }
  const subdivided = buildSnapIndex(new Mesh(new PlaneGeometry(4, 3, 4, 3)));
  assert.equal(subdivided.corners.length, 4, 'straight tessellation vertices are not corners');
  assert.ok(subdivided.segments.every(({ a, b }) => a.x === b.x || a.y === b.y));
});

test('a coplanar diagonal split across separate meshes is not mistaken for an object boundary', () => {
  const root = new Group();
  for (const vertices of [[0,0,0, 2,0,0, 2,2,0], [0,0,0, 2,2,0, 0,2,0]]) {
    const geometry = new BufferGeometry();
    geometry.setAttribute('position', new Float32BufferAttribute(vertices, 3)); root.add(new Mesh(geometry));
  }
  const index = buildSnapIndex(root);
  assert.equal(index.segments.length, 4);
  assert.equal(index.corners.length, 4);
  assert.ok(index.segments.every(({ a, b }) => a.x === b.x || a.y === b.y));
});

test('box extraction retains twelve sharp edges and eight corners without face diagonals', () => {
  const index = buildSnapIndex(new Mesh(new BoxGeometry(2, 3, 4)));
  assert.equal(index.segments.length, 12);
  assert.equal(index.corners.length, 8);
});

test('crease angle is evaluated after nested world transforms without mutating source positions', () => {
  const root = new Group(), parent = new Group(), mesh = new Mesh(new PlaneGeometry(2, 2));
  root.position.set(3, 4, -8); root.rotation.x = -.7;
  parent.rotation.y = .4; parent.scale.set(2, 3, .5); parent.position.set(1, 2, 3);
  root.add(parent); parent.add(mesh);
  const original = Array.from(mesh.geometry.attributes.position.array), index = buildSnapIndex(root);
  const expected = new Vector3(-1, 1, 0).applyMatrix4(mesh.matrixWorld);
  assert.ok(index.corners.some(corner => corner.point.distanceTo(expected) < 1e-6));
  assert.deepEqual(Array.from(mesh.geometry.attributes.position.array), original);
  const crease = new BufferGeometry();
  const height = Math.tan(10 * Math.PI / 180);
  crease.setAttribute('position', new Float32BufferAttribute([0,0,0, 1,0,0, 0,1,0, 1,0,0, 0,0,0, 0,-1,height], 3));
  const folded = new Mesh(crease);
  assert.equal(buildSnapIndex(folded).segments.length, 4, '10-degree crease is below threshold');
  folded.scale.z = 10;
  assert.equal(buildSnapIndex(folded).segments.length, 5, 'world-space stretch makes the crease sharp');
});

test('screen-space radius is in CSS pixels and perspective interpolation preserves world position', () => {
  const c = camera(), a = new Vector3(-1, 0, -2), b = new Vector3(1, 0, -6), index = edgeIndex(a, b);
  const pa = pixel(a, c), pb = pixel(b, c), pointer = { x: (pa.x + pb.x) / 2, y: pa.y + 11 };
  const result = findSnap(index, c, pointer, { width: 800, height: 600 });
  assert.equal(result.kind, 'edge');
  close(result.point, new Vector3(-.5, 0, -3));
  assert.ok(Math.abs(result.distancePx - 11) < 1e-6);
  assert.equal(findSnap(index, c, { ...pointer, y: pa.y + 13 }, { width: 800, height: 600 }), null);
  assert.equal(findSnap(index, c, pointer, { width: 800, height: 600 }, { radiusPx: 10 }), null);
  const projected = pixel(result.point, c);
  assert.ok(Math.abs(projected.x - pointer.x) < 1e-6);
});

test('orthographic corner priority, visibility rejection and clip plane respect the rendered view', () => {
  const c = new OrthographicCamera(-4, 4, 3, -3, .1, 100); c.updateMatrixWorld();
  const a = new Vector3(0, 0, -4), b = new Vector3(2, 0, -4), index = edgeIndex(a, b);
  index.corners = [{ point: a }];
  const pointer = pixel(a, c); pointer.x += 5;
  assert.equal(findSnap(index, c, pointer, { width: 800, height: 600 }).kind, 'vertex');
  assert.equal(findSnap(index, c, pointer, { width: 800, height: 600 }, { isVisible: () => false }), null);
  const clipped = findSnap(index, c, { x: 500, y: 300 }, { width: 800, height: 600 }, { clipPlane: new Plane(new Vector3(1, 0, 0), -1) });
  close(clipped.point, new Vector3(1, 0, -4));
  assert.equal(clipped.kind, 'edge', 'clipping does not invent a corner');
  assert.equal(findSnap(index, c, pointer, { width: 800, height: 600 }, { clipPlane: new Plane(new Vector3(1, 0, 0), -1) }), null);
});

test('behind-camera candidates are rejected and a segment crossing the near plane remains usable', () => {
  const c = camera(), viewport = { width: 800, height: 600 };
  assert.equal(findSnap(edgeIndex(new Vector3(0,0,2), new Vector3(1,0,2)), c, { x: 400, y: 300 }, viewport), null);
  const index = edgeIndex(new Vector3(0,0,.2), new Vector3(1,0,-4));
  const point = new Vector3(.5,0,-1.9), result = findSnap(index, c, pixel(point, c), viewport);
  close(result.point, point);
});

test('hard triangle and edge budgets return no partial index; point clouds remain unsupported', () => {
  const mesh = new Mesh(new BoxGeometry());
  for (const options of [{ maxTriangles: 1 }, { maxSegments: 5 }]) {
    const index = buildSnapIndex(mesh, options);
    assert.equal(index.status, 'limit'); assert.deepEqual(index.segments, []); assert.deepEqual(index.corners, []);
    assert.equal(findSnap(index, camera(), { x: 400, y: 300 }, { width: 800, height: 600 }), null);
  }
  assert.equal(buildSnapIndex(new Points(new BufferGeometry())).status, 'unsupported');
  assert.throws(() => buildSnapIndex(mesh, { maxTriangles: 0 }), RangeError);
  assert.throws(() => buildSnapIndex(mesh, { thresholdAngle: 0 }), RangeError);
});

test('model raycasting rejects hidden edges and respects hidden or roof-clipped occluders', () => {
  const root = new Group(), front = new Mesh(new PlaneGeometry(4, 4)), c = camera();
  front.position.z = -2; root.add(front); root.updateMatrixWorld(true);
  const behind = new Vector3(0, 0, -4);
  assert.equal(visibleSnapPoint(root, c, behind), false);
  assert.equal(visibleSnapPoint(root, c, new Vector3(0, 0, -2)), true);
  front.visible = false;
  assert.equal(visibleSnapPoint(root, c, behind), true);
  front.visible = true;
  assert.equal(visibleSnapPoint(root, c, behind, { clipPlane: new Plane(new Vector3(0, 0, -1), -3) }), true);
});

test('unsupported deformations, instances and partial triangle ranges never expose approximate snap points', () => {
  const geometry = new BoxGeometry(), morph = new Mesh(geometry.clone()), partial = new Mesh(geometry.clone());
  morph.geometry.morphAttributes.position = [geometry.attributes.position.clone()];
  partial.geometry.setDrawRange(0, 6);
  for (const model of [new SkinnedMesh(geometry), new InstancedMesh(geometry, new MeshBasicMaterial(), 2), morph, partial]) {
    const index = buildSnapIndex(model);
    assert.equal(index.status, 'unsupported'); assert.deepEqual(index.segments, []);
  }
});

test('dense projected edge clusters have a bounded occlusion budget', () => {
  const c = camera(), index = { status: 'ready', segments: [], corners: Array.from({ length: 200 }, (_, i) => ({ point: new Vector3(0,0,-2-i/100) })) };
  let calls = 0;
  assert.equal(findSnap(index, c, { x: 400, y: 300 }, { width: 800, height: 600 }, { isVisible: () => { calls++; return false; } }), null);
  assert.equal(calls, 32);
});
