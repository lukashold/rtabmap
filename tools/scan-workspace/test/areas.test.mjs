import test from 'node:test';
import assert from 'node:assert/strict';
import { areaSummary, unionArea, validateAreaInputs } from '../src/areas.js';
import { roomPlanBundle } from '../src/roomplan.js';
import { validateProject, MeasureError } from '../src/measure.js';
import { packageBuilding, readFiles } from '../src/files.js';

// Column-major rigid transform: local X → world `x`, local Y → world up, local Z → normal.
function frame(center, xAxis) {
  const x = xAxis, y = [0, 1, 0], z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]];
  return [...x, 0, ...y, 0, ...z, 0, ...center, 1];
}
const floorFrame = center => [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, ...center, 1];
let n = 0;
const surface = (kind, dimensions, transform, extra = {}) => ({ id: `${kind}-${++n}`, kind, label: `${kind} ${n}`, dimensions, transform, confidence: 'high', ...extra });

// 4 m (x) × 5 m (z) room, 2.5 m high, floor at y = 0.
function room({ door = true, window = true } = {}) {
  const h = 2.5;
  const walls = [
    surface('wall', [4, h, 0], frame([0, h / 2, -2.5], [1, 0, 0])),
    surface('wall', [5, h, 0], frame([2, h / 2, 0], [0, 0, 1])),
    surface('wall', [4, h, 0], frame([0, h / 2, 2.5], [-1, 0, 0])),
    surface('wall', [5, h, 0], frame([-2, h / 2, 0], [0, 0, -1])),
  ];
  const floor = surface('floor', [4, 5, 0], floorFrame([0, 0, 0]), { polygonCorners: [[-2, -2.5, 0], [2, -2.5, 0], [2, 2.5, 0], [-2, 2.5, 0]] });
  const extras = [];
  // 0.8 × 2.5 = 2 m² door in the first wall, 1 × 1.5 = 1.5 m² window in the second.
  if (door) extras.push(surface('door', [0.8, 2.5, 0.04], frame([0.5, 1.25, -2.49], [1, 0, 0])));
  if (window) extras.push(surface('window', [1, 1.5, 0.04], frame([2.01, 1.4, 1], [0, 0, 1])));
  return [...walls, floor, ...extras];
}
const close = (actual, expected, label) => assert.ok(Math.abs(actual - expected) < 1e-9, `${label}: ${actual} ≠ ${expected}`);

test('roadmap acceptance: 4 × 5 m room, 2.5 m high, door 2 m² and window 1.5 m² → 20 / 45 / 41.5 m²', () => {
  const summary = areaSummary(room());
  close(summary.totals.floor, 20, 'floor');
  close(summary.totals.gross, 45, 'gross');
  close(summary.totals.openingArea, 3.5, 'openings');
  close(summary.totals.net, 41.5, 'net');
  assert.equal(summary.totals.incomplete, false);
  assert.equal(summary.totals.unresolved, 0);
  const [door, window] = summary.openings;
  assert.equal(door.wallId, summary.walls[0].id);
  assert.equal(window.wallId, summary.walls[1].id);
  assert.deepEqual([door.assignment, window.assignment], ['auto', 'auto']);
  close(summary.walls[0].net, 8, 'wall with door');
  close(summary.walls[1].net, 11, 'wall with window');
  close(summary.walls[2].net, 10, 'untouched wall');
});

test('a calibrated scale multiplies areas by the squared factor', () => {
  const summary = areaSummary(room(), {}, 2);
  close(summary.totals.floor, 80, 'floor');
  close(summary.totals.net, 166, 'net');
  close(summary.walls[0].width, 8, 'width');
});

test('overlapping openings are subtracted once and both are flagged', () => {
  const surfaces = room({ door: false, window: false });
  surfaces.push(surface('window', [1, 1, 0], frame([0, 1.5, -2.5], [1, 0, 0])));
  surfaces.push(surface('window', [1, 1, 0], frame([0.5, 1.5, -2.5], [1, 0, 0])));
  const summary = areaSummary(surfaces);
  close(summary.walls[0].openingArea, 1.5, 'union of two 1 m² windows overlapping by 0.5 m²');
  close(summary.walls[0].net, 8.5, 'net');
  assert.ok(summary.openings.every(o => o.issues.includes('overlap')));
});

test('an opening past the wall edge is clipped to the wall and flagged', () => {
  const surfaces = room({ door: false, window: false });
  // 1 m wide, centred 0.25 m inside the 2 m edge: half of it is outside.
  surfaces.push(surface('door', [1, 2, 0], frame([1.75, 1, -2.5], [1, 0, 0])));
  const summary = areaSummary(surfaces);
  const [door] = summary.openings;
  assert.ok(door.issues.includes('clipped'));
  close(door.area, 2, 'original area is kept');
  close(door.deducted, 1.5, 'only the part inside the wall is deducted');
  close(summary.walls[0].net, 8.5, 'net');
});

test('an opening away from every wall stays unassigned and is not deducted', () => {
  const surfaces = room({ door: false, window: false });
  surfaces.push(surface('door', [0.8, 2, 0], frame([0, 1, 0], [1, 0, 0])));
  const summary = areaSummary(surfaces);
  assert.deepEqual(summary.openings[0].issues, ['unassigned']);
  assert.equal(summary.openings[0].deducted, 0);
  close(summary.totals.net, 45, 'nothing subtracted');
  assert.equal(summary.totals.unresolved, 1);
});

test('two equally close parallel walls are ambiguous instead of guessed', () => {
  const walls = [surface('wall', [4, 2.5, 0], frame([0, 1.25, -0.05], [1, 0, 0])), surface('wall', [4, 2.5, 0], frame([0, 1.25, 0.05], [1, 0, 0]))];
  const door = surface('door', [1, 2, 0], frame([0, 1, 0], [1, 0, 0]));
  const summary = areaSummary([...walls, door]);
  assert.deepEqual(summary.openings[0].issues, ['ambiguous']);
  assert.equal(summary.openings[0].wallId, null);
});

test('manual assignment overrides the automatic choice and can exclude an opening', () => {
  const surfaces = room();
  const [, wall2] = surfaces;
  const door = surfaces.find(s => s.kind === 'door'), window = surfaces.find(s => s.kind === 'window');
  const excluded = areaSummary(surfaces, { [door.id]: null });
  assert.deepEqual(excluded.openings[0].issues, ['excluded']);
  assert.equal(excluded.openings[0].assignment, 'manual');
  close(excluded.totals.net, 43.5, 'door no longer deducted');
  assert.equal(excluded.totals.unresolved, 0, 'an explicit exclusion is resolved');
  // The window is parallel to wall 4 but 4 m away: it is deducted there but flagged.
  const moved = areaSummary(surfaces, { [window.id]: surfaces[3].id });
  assert.ok(moved.openings[1].issues.includes('farFromWall'));
  // Assigning the door to a perpendicular wall is rejected visibly.
  const wrong = areaSummary(surfaces, { [door.id]: wall2.id });
  assert.deepEqual(wrong.openings[0].issues, ['notParallel']);
  assert.equal(wrong.openings[0].deducted, 0);
});

test('a wall without height has no gross area and makes the total incomplete', () => {
  const surfaces = room({ window: false });
  surfaces[1] = { ...surfaces[1], dimensions: [5, 0, 0] };
  const summary = areaSummary(surfaces);
  assert.equal(summary.walls[1].gross, null);
  assert.deepEqual(summary.walls[1].issues, ['missingHeight']);
  assert.equal(summary.totals.incomplete, true);
  close(summary.totals.gross, 32.5, 'only known walls are summed');
});

test('L-shaped floor and non-rectangular wall use their polygons; doubtful openings need review', () => {
  const lFloor = surface('floor', [4, 4, 0], floorFrame([0, 0, 0]), { polygonCorners: [[0, 0, 0], [4, 0, 0], [4, 2, 0], [2, 2, 0], [2, 4, 0], [0, 4, 0]] });
  // Gable wall: 4 m wide, 2 m eaves, 3 m ridge → 10 m².
  const gable = surface('wall', [4, 3, 0], frame([0, 1.5, 0], [1, 0, 0]), { polygonCorners: [[-2, -1.5, 0], [2, -1.5, 0], [2, 0.5, 0], [0, 1.5, 0], [-2, 0.5, 0]] });
  const inside = surface('window', [1, 1, 0], frame([0, 1.5, 0], [1, 0, 0]));
  // Upper corner reaches above the sloped roof line.
  const corner = surface('window', [1, 1, 0], frame([1.5, 2.1, 0], [1, 0, 0]));
  const summary = areaSummary([lFloor, gable, inside, corner]);
  close(summary.floors[0].area, 12, 'L floor');
  close(summary.walls[0].gross, 10, 'gable wall');
  close(summary.walls[0].openingArea, 1, 'only the window inside the outline is deducted');
  assert.ok(summary.openings[1].issues.includes('needsReview'));
});

test('a degenerate floor outline has unknown area, not zero', () => {
  const line = surface('floor', [3, 3, 0], floorFrame([0, 0, 0]), { polygonCorners: [[0, 0, 0], [1, 1, 0], [2, 2, 0]] });
  const summary = areaSummary([line, surface('wall', [2, 2, 0], frame([0, 1, 0], [1, 0, 0]))]);
  assert.equal(summary.floors[0].area, null);
  assert.equal(summary.totals.floor, null);
  assert.equal(summary.totals.incomplete, true);
});

test('union area handles nested, disjoint and touching rectangles exactly', () => {
  close(unionArea([[0, 0, 2, 2], [0.5, 0.5, 1, 1]]), 4, 'nested');
  close(unionArea([[0, 0, 1, 1], [2, 2, 3, 3]]), 2, 'disjoint');
  close(unionArea([[0, 0, 1, 1], [1, 0, 2, 1]]), 2, 'touching');
  close(unionArea([[0, 0, 2, 1], [1, 0, 3, 1], [0, 0.5, 3, 2]]), 6, 'three overlapping: 3 m² below y = 1 plus 3 m² above');
});

test('malformed stored surfaces and assignments are rejected', () => {
  const surfaces = room();
  const door = surfaces.find(s => s.kind === 'door');
  assert.throws(() => validateAreaInputs(surfaces, { [door.id]: door.id }));
  assert.throws(() => validateAreaInputs(surfaces, { missing: null }));
  assert.throws(() => validateAreaInputs([{ ...surfaces[0], transform: surfaces[0].transform.map((v, i) => i === 0 ? 2 : v) }]));
  assert.throws(() => validateAreaInputs(undefined, {}));
  assert.doesNotThrow(() => validateAreaInputs(surfaces, { [door.id]: surfaces[0].id }));
  const project = { version: 1, name: 'x', scale: 1, upAxis: 'y', measurements: [], roomSurfaces: surfaces, openingAssignments: { [door.id]: 'nope' } };
  assert.throws(() => validateProject(project), MeasureError);
});

test('RoomPlan import preserves surfaces; areas survive building archive save and reopen', async () => {
  const toPlan = s => ({ id: s.id, kind: s.kind, dimensions: s.dimensions, transform: s.transform, confidence: s.confidence, ...(s.polygonCorners ? { polygonCorners: s.polygonCorners } : {}) });
  const data = { format: 'kantura-room-plan', version: 1, units: 'm', coordinateSystem: { upAxis: 'y', handedness: 'right', matrixOrder: 'column-major' }, name: 'Testraum', surfaces: room().map(toPlan) };
  const bundle = roomPlanBundle(data, { wall: 'Wand', door: 'Tür', window: 'Fenster' });
  assert.equal(bundle.project.roomSurfaces.length, 7);
  assert.equal(bundle.project.roomSurfaces[0].label, 'Wand 1');
  const before = areaSummary(bundle.project.roomSurfaces);
  close(before.totals.net, 41.5, 'net after normalization');
  const door = bundle.project.roomSurfaces.find(s => s.kind === 'door');
  bundle.project.openingAssignments = { [door.id]: null };
  const archive = await packageBuilding({ name: 'Haus', activeRoom: 'r1', rooms: [{ id: 'r1', floor: '0', bundle, project: bundle.project }] });
  const file = new File([await archive.arrayBuffer()], 'Haus.kantura-building.zip');
  const reopened = await readFiles([file]);
  const project = reopened.building.rooms[0].project;
  assert.deepEqual(project.openingAssignments, { [door.id]: null });
  close(areaSummary(project.roomSurfaces, project.openingAssignments).totals.net, 43.5, 'manual exclusion survives');
});
