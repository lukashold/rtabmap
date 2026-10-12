import test from 'node:test';
import assert from 'node:assert/strict';
import { WGS84, validateGeodeticPoint, geodeticToECEF, ecefToENU, geodeticToENU, enuToViewer, georeferencePoint } from '../src/georeference.js';

const point = (latitude, longitude, height = 0) => ({ latitude, longitude, height, verticalDatum: 'ellipsoidal' });
const near = (actual, expected, tolerance = 1e-8) => {
  assert.equal(actual.length, expected.length);
  actual.forEach((value, i) => assert.ok(Math.abs(value - expected[i]) <= tolerance, `${actual} != ${expected} within ${tolerance} m`));
};

test('WGS84 equator and both poles agree with independent ellipsoid axis lengths', () => {
  assert.equal(WGS84.semiMajorAxisMeters, 6378137);
  assert.equal(WGS84.inverseFlattening, 298.257223563);
  const polarRadius = 6356752.314245179;
  near(geodeticToECEF(point(0, 0)), [6378137, 0, 0]);
  near(geodeticToECEF(point(0, 90)), [0, 6378137, 0]);
  near(geodeticToECEF(point(0, -90)), [0, -6378137, 0]);
  near(geodeticToECEF(point(90, 123, 7)), [0, 0, polarRadius + 7]);
  near(geodeticToECEF(point(-90, -47, -9)), [0, 0, -polarRadius + 9]);
});

test('published PROJ non-cardinal conversion examples agree within their rounded precision', () => {
  // Primary PROJ examples use GRS80 (sub-millimetre difference here from WGS84).
  // https://proj.org/en/stable/operations/conversions/cart.html
  near(geodeticToECEF(point(45.3935192042, 17.7562015132, 133.12)),
    [4272922.1553, 1368283.0597, 4518261.3501], .001);
  // https://proj.org/en/stable/operations/conversions/topocentric.html
  near(geodeticToENU(point(53.80939444, 2.12955, 73), point(55, 5, 200)),
    [-189013.869, -128642.040, -4220.171], .001);
});

test('the mandatory origin is zero and metre offsets use the correct viewer handedness', () => {
  const origin = point(0, 0);
  near(geodeticToENU(origin, origin), [0, 0, 0]);
  // At Greenwich/equator, ECEF X is up, Y is east, Z is north.
  near(ecefToENU([6378140, 1, 2], origin), [1, 2, 3]);
  assert.deepEqual(enuToViewer([1, 2, 3]), [1, 3, -2]);
  const result = georeferencePoint(origin, origin);
  assert.deepEqual(result.position, [0, 0, 0]);
  assert.deepEqual(result.axes, { x: 'east', y: 'up', z: '-north' });
  for (const origin of [undefined, null]) {
    assert.throws(() => ecefToENU([6378137, 0, 0], origin), { code: 'missingOrigin' });
    assert.throws(() => geodeticToENU(point(0, 0), origin), { code: 'missingOrigin' });
    assert.throws(() => georeferencePoint(point(0, 0), origin), { code: 'missingOrigin' });
  }
});

test('known one-metre equatorial angular offsets and ellipsoidal height retain axis meaning', () => {
  const origin = point(0, 0);
  // One metre of equatorial longitude and meridional latitude respectively.
  near(geodeticToENU(point(0, 0.000008983152841195214), origin), [1, 0, 0], 1e-7);
  near(geodeticToENU(point(0.00000904369477050382, 0), origin), [0, 1, 0], 1e-7);
  for (const [latitude, longitude] of [[45, 16], [-32, 151], [90, 40], [-90, -95]]) {
    near(geodeticToENU(point(latitude, longitude, 456.45), point(latitude, longitude, 333)), [0, 0, 123.45], 2e-9);
  }
});

test('the antimeridian stays continuous rather than producing a world-width offset', () => {
  near(geodeticToENU(point(0, -180), point(0, 180)), [0, 0, 0]);
  near(geodeticToENU(point(0, -179.999), point(0, 179.999)), [222.6389815, 0, -0.0038858], .000001);
  near(geodeticToENU(point(0, 179.999), point(0, -179.999)), [-222.6389815, 0, -0.0038858], .000001);
});

test('explicit pole longitude fixes the local tangent orientation', () => {
  const b = 6356752.314245179;
  near(ecefToENU([2, 3, b + 4], point(90, 0)), [3, -2, 4]);
  near(ecefToENU([2, 3, b + 4], point(90, 90)), [-2, -3, 4]);
  near(ecefToENU([2, 3, -b - 4], point(-90, 0)), [3, 2, 4]);
});

test('unsupported height datums, absent numeric heights and invalid ranges never get inferred or clamped', () => {
  for (const verticalDatum of [undefined, null, 'MSL', 'orthometric', 'EGM96', 'EXIF', 'unknown']) {
    assert.throws(() => geodeticToECEF({ ...point(48, 16, 200), verticalDatum }), { code: 'unsupportedVerticalDatum' });
    assert.throws(() => geodeticToENU(point(48, 16, 200), { ...point(48, 16, 200), verticalDatum }), { code: 'unsupportedVerticalDatum' });
  }
  for (const change of [{ latitude: 90.1 }, { latitude: -90.1 }, { longitude: 180.1 }, { longitude: -180.1 },
    { height: undefined }, { height: -12001 }, { height: 100001 }, { height: NaN }, { height: Infinity },
    { latitude: NaN }, { longitude: Infinity }, { latitude: '48' }, { height: '200' }]) {
    assert.throws(() => geodeticToECEF({ ...point(48, 16, 200), ...change }), { code: 'invalidGeodetic' });
  }
  for (const invalid of [null, [], '48,16,200']) assert.throws(() => validateGeodeticPoint(invalid), { code: 'invalidGeodetic' });
  assert.equal(validateGeodeticPoint(point(0, 0, -12000)).height, -12000);
  assert.equal(validateGeodeticPoint(point(0, 0, 100000)).height, 100000);
});

test('uncertainty metadata stays detached and unverified without manufacturing combined precision', () => {
  const target = { ...point(48, 16, 200), uncertainty: { horizontalMeters: 2.4, verticalMeters: 5 } };
  const origin = { ...point(48, 16, 199), uncertainty: { horizontalMeters: .4 } };
  const before = JSON.stringify({ target, origin });
  const result = georeferencePoint(target, origin);
  assert.equal(JSON.stringify({ target, origin }), before);
  assert.deepEqual(result.point.uncertainty, target.uncertainty);
  assert.deepEqual(result.origin.uncertainty, origin.uncertainty);
  assert.equal(result.qualityStatus, 'unverified');
  assert.equal(result.scaleStatus, 'unverified');
  assert.equal(result.metricAccuracyValidated, false);
  result.point.uncertainty.horizontalMeters = 900;
  result.origin.height = 0;
  assert.equal(JSON.stringify({ target, origin }), before);
  assert.equal(georeferencePoint(point(0, 0), point(0, 0)).point.uncertainty, undefined);
  for (const uncertainty of [null, [], {}, { horizontalMeters: -1 }, { verticalMeters: Infinity },
    { horizontalMeters: '1' }, { horizontalMeters: 1e8 }, { confidence: 95 }]) {
    assert.throws(() => georeferencePoint({ ...target, uncertainty }, origin), { code: 'invalidUncertainty' });
  }
});

test('ECEF and ENU vectors must be three finite bounded numeric components', () => {
  for (const invalid of [null, [1, 2], [1, 2, 3, 4], [1, NaN, 3], [Infinity, 0, 0], ['1', 2, 3], [1e10, 0, 0]]) {
    assert.throws(() => ecefToENU(invalid, point(0, 0)), { code: 'invalidECEF' });
    assert.throws(() => enuToViewer(invalid), { code: 'invalidENU' });
  }
});
