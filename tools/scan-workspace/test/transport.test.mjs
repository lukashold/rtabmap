import test from 'node:test';
import assert from 'node:assert/strict';
import { assessTransport, TransportError } from '../src/transport.js';

const input = (changes = {}) => ({ object: { width: .6, depth: .8, height: 2 }, route: { width: .75, ceiling: 2.4, landingWidth: 2, landingDepth: 2, rise: .17, run: .28, turnDegrees: 90 }, margin: .01, allowTilt: false, ...changes });
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-8, `${a} != ${b}`);

test('generous route has a sufficient upright envelope and per-side margin', () => {
  const result = assessTransport(input());
  assert.equal(result.verdict, 'possible'); assert.equal(result.chosenScenario, 'upright');
  near(result.limitingClearances.corridorWidth, .13); near(result.limitingClearances.landingWidth, .98);
  assert.equal(result.angleUnit, 'degrees'); assert.equal(result.dimensionUnit, 'm');
});
test('sideways handling can fit the straight passage', () => {
  const result = assessTransport(input({ object: { width: .9, depth: .5, height: 2 } }));
  assert.equal(result.verdict, 'possible'); assert.equal(result.chosenScenario, 'upright-sideways'); assert.equal(result.startingYaw, 90);
});
test('failed centred turn stays uncertain because translated paths are untested', () => {
  const data = input(); data.route.landingWidth = .9; data.route.landingDepth = .9;
  const result = assessTransport(data);
  assert.equal(result.verdict, 'uncertain'); assert.ok(result.reasons.includes('landing_requires_path_planning'));
});
test('continuous turn maximum catches collisions between regular samples', () => {
  const data = input({ margin: 0 }); data.route.landingWidth = .99999;
  const result = assessTransport(data);
  assert.equal(result.verdict, 'uncertain'); near(result.limitingClearances.landingWidth, -.00001);
});
test('minimum object dimension proves a mandatory passage too narrow', () => {
  const data = input({ allowTilt: true }); data.route.width = .61;
  const result = assessTransport(data);
  assert.equal(result.verdict, 'blocked'); assert.ok(result.reasons.includes('corridor_narrower_than_smallest_dimension'));
});
test('orientation-independent ceiling bound may also prove blocked', () => {
  const data = input(); data.route.ceiling = .59;
  assert.equal(assessTransport(data).verdict, 'blocked');
});
test('height failure alone does not prove orientation-independent impossibility', () => {
  const data = input(); data.route.ceiling = 1.9;
  assert.equal(assessTransport(data).verdict, 'uncertain');
});
test('tilted sample dimensions use slope atan(rise/run), and transitions are included', () => {
  const data = input({ allowTilt: true }); data.route.rise = .28;
  const result = assessTransport(data); near(result.stairAngle, 45);
  const tilted = result.scenarios.find(s => s.id === 'stair-tilt');
  const first = tilted.samples.find(s => s.phase === 'turn' && s.yaw === 0);
  near(first.width, .6); near(first.depth, 2.8 / Math.sqrt(2)); near(first.height, 2.8 / Math.sqrt(2));
  assert.ok(tilted.samples.some(s => s.phase === 'tilt-transition' && s.tilt === 0));
  // Continuous transition has a height maximum above both endpoint poses.
  near(tilted.envelope.height, Math.hypot(.8, 2));
});
test('turn direction does not change required bounding dimensions', () => {
  const left = input(); left.route.turnDegrees = -90;
  const a = assessTransport(left), b = assessTransport(input());
  assert.deepEqual(a.limitingClearances, b.limitingClearances);
  assert.ok(a.samples.some(s => s.yaw < 0));
});
test('a straight upright passage does not require an unused landing', () => {
  const data = input(); data.route.turnDegrees = 0; data.route.landingWidth = .1; data.route.landingDepth = .1;
  const result = assessTransport(data); assert.equal(result.verdict, 'possible');
  assert.deepEqual(Object.keys(result.limitingClearances), ['corridorWidth', 'ceiling']);
});
test('input validation rejects nonfinite, zero, string and out-of-bound values', () => {
  for (const value of [NaN, Infinity, 0, -.1, 101, '0.6']) {
    const data = input(); data.route.width = value;
    assert.throws(() => assessTransport(data), TransportError);
  }
  assert.throws(() => assessTransport(input({ margin: -.01 })), TransportError);
  assert.throws(() => assessTransport(input({ allowTilt: 'yes' })), TransportError);
  const data = input(); data.route.turnDegrees = 181; assert.throws(() => assessTransport(data), TransportError);
});
test('assessment is pure and all returned numeric dimensions remain finite', () => {
  const data = input({ allowTilt: true }), before = structuredClone(data);
  const result = assessTransport(data); assert.deepEqual(data, before);
  for (const scenario of result.scenarios) for (const sample of scenario.samples) for (const field of ['width','depth','height','yaw','tilt']) assert.ok(Number.isFinite(sample[field]));
});
