/**
 * Coordinate conversion only: no scan alignment, datum inference or accuracy approval.
 * WGS84 constants: https://earth-info.nga.mil/index.php?dir=wgs84&action=wgs84
 * Geodetic/ECEF: https://gssc.esa.int/navipedia/index.php/Ellipsoidal_and_Cartesian_Coordinates_Conversion
 * ENU basis: https://gssc.esa.int/navipedia/index.php/Transformations_between_ECEF_and_ENU_coordinates
 */
export const WGS84 = Object.freeze({ semiMajorAxisMeters: 6378137, inverseFlattening: 298.257223563 });
const flattening = 1 / WGS84.inverseFlattening;
const eccentricitySquared = flattening * (2 - flattening);
const radians = degrees => degrees * Math.PI / 180;
const finiteRange = (value, minimum, maximum) => Number.isFinite(value) && value >= minimum && value <= maximum;

export class GeoreferenceError extends Error {
  constructor(code) { super(code); this.name = 'GeoreferenceError'; this.code = code; }
}
const fail = code => { throw new GeoreferenceError(code); };

/**
 * Degrees and metres, with explicitly declared ellipsoidal height. Supported
 * height range is terrestrial/UAV (-12 km to +100 km), not satellite orbits.
 * Unknown, orthometric/MSL and EXIF heights are never converted implicitly.
 * Uncertainty values are supplied estimates, not confidence intervals or bounds
 * established here. Both point and origin estimates remain separate.
 */
export function validateGeodeticPoint(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('invalidGeodetic');
  if (value.verticalDatum !== 'ellipsoidal') fail('unsupportedVerticalDatum');
  if (!finiteRange(value.latitude, -90, 90) || !finiteRange(value.longitude, -180, 180)
      || !finiteRange(value.height, -12000, 100000)) fail('invalidGeodetic');
  const point = { latitude: value.latitude, longitude: value.longitude, height: value.height, verticalDatum: 'ellipsoidal' };
  if (value.uncertainty !== undefined) {
    const uncertainty = value.uncertainty;
    const keys = uncertainty && typeof uncertainty === 'object' && !Array.isArray(uncertainty) ? Object.keys(uncertainty) : [];
    if (!keys.length || keys.some(key => !['horizontalMeters', 'verticalMeters'].includes(key)
        || !finiteRange(uncertainty[key], 0, 1e7))) fail('invalidUncertainty');
    point.uncertainty = Object.fromEntries(keys.map(key => [key, uncertainty[key]]));
  }
  return point;
}

function originPoint(value) {
  if (value === undefined || value === null) fail('missingOrigin');
  return validateGeodeticPoint(value);
}
function vector(value, code) {
  if (!Array.isArray(value) || value.length !== 3 || value.some(component => !finiteRange(component, -1e9, 1e9))) fail(code);
  return value;
}
function ecef(point) {
  const latitude = radians(point.latitude), longitude = radians(point.longitude);
  const sinLatitude = Math.sin(latitude), cosLatitude = Math.cos(latitude);
  const radius = WGS84.semiMajorAxisMeters / Math.sqrt(1 - eccentricitySquared * sinLatitude * sinLatitude);
  return [(radius + point.height) * cosLatitude * Math.cos(longitude),
    (radius + point.height) * cosLatitude * Math.sin(longitude),
    (radius * (1 - eccentricitySquared) + point.height) * sinLatitude];
}
function localENU(position, origin) {
  const base = ecef(origin), [dx, dy, dz] = position.map((value, i) => value - base[i]);
  const latitude = radians(origin.latitude), longitude = radians(origin.longitude);
  const sinLatitude = Math.sin(latitude), cosLatitude = Math.cos(latitude);
  const sinLongitude = Math.sin(longitude), cosLongitude = Math.cos(longitude);
  // At either pole, the supplied origin longitude explicitly fixes the otherwise
  // ambiguous east/north orientation. Up is the ellipsoid normal, not a radius.
  return [-sinLongitude * dx + cosLongitude * dy,
    -sinLatitude * cosLongitude * dx - sinLatitude * sinLongitude * dy + cosLatitude * dz,
    cosLatitude * cosLongitude * dx + cosLatitude * sinLongitude * dy + sinLatitude * dz];
}

/** WGS84 geodetic point -> Earth-centred, Earth-fixed [X, Y, Z] in metres. */
export function geodeticToECEF(point) { return ecef(validateGeodeticPoint(point)); }

/** ECEF [X, Y, Z] -> [east, north, up] in metres at the mandatory origin. */
export function ecefToENU(position, origin) {
  return localENU(vector(position, 'invalidECEF'), originPoint(origin));
}

/** ENU is a local tangent frame; it is not a flat-map/geodesic distance model. */
export function geodeticToENU(point, origin) {
  return localENU(ecef(validateGeodeticPoint(point)), originPoint(origin));
}

/** Right-handed viewer Y-up convention: x=east, y=up, z=-north. */
export function enuToViewer(enu) {
  const [east, north, up] = vector(enu, 'invalidENU');
  return [east, up, north === 0 ? 0 : -north];
}

/**
 * Detached data for a future explicit control-point workflow. This does not
 * change model coordinates, calibrate a scan, or propagate unknown covariance.
 */
export function georeferencePoint(value, originValue) {
  const point = validateGeodeticPoint(value), origin = originPoint(originValue);
  const positionECEF = ecef(point), enu = localENU(positionECEF, origin);
  return { datum: 'WGS84', verticalDatum: 'ellipsoidal', unit: 'metre',
    point, origin, ecef: positionECEF, enu, position: enuToViewer(enu),
    axes: { x: 'east', y: 'up', z: '-north' },
    qualityStatus: 'unverified', scaleStatus: 'unverified', metricAccuracyValidated: false };
}
