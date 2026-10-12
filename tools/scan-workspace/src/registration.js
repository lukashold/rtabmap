// Landmark correspondence is supplied by the caller. This module neither finds
// matching rooms nor establishes survey accuracy. Coordinates and residuals are
// metres; a rigid transform never repairs scale differences or warped geometry.
export class RegistrationError extends Error {
  constructor(code) { super(code); this.name = 'RegistrationError'; this.code = code; }
}

const MAX_POINTS = 1000;
const MAX_COORDINATE = 1e9;
const sub = (a, b) => a.map((value, i) => value - b[i]);
const norm = point => Math.hypot(...point);
const dot = (a, b) => a.reduce((sum, value, i) => sum + value * b[i], 0);
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];

function validate(points) {
  if (!Array.isArray(points) || points.length < 3 || points.length > MAX_POINTS ||
      Array.from(points).some(point => !Array.isArray(point) || point.length !== 3 ||
        Array.from(point).some(value => !Number.isFinite(value) || Math.abs(value) > MAX_COORDINATE))) {
    throw new RegistrationError('invalidLandmarks');
  }
}

function centered(points) {
  // Translate first, so averaging a local set with a large origin loses less
  // precision than adding the large absolute coordinate once per landmark.
  const local = points.map(point => sub(point, points[0]));
  const offset = [0, 1, 2].map(axis => local.reduce((sum, point) => sum + point[axis] / points.length, 0));
  const center = points[0].map((value, axis) => value + offset[axis]);
  const vectors = local.map(point => sub(point, offset));
  const extent = Math.max(...vectors.map(norm));
  if (extent === 0) throw new RegistrationError('degenerateLandmarks');
  const normalized = vectors.map(point => point.map(value => value / extent));
  const longest = normalized.reduce((best, point) => norm(point) > norm(best) ? point : best);
  // A numerical conditioning check, not a physical accuracy tolerance. Planar
  // non-collinear points are valid; three points can define a proper 3D rotation.
  if (Math.max(...normalized.map(point => norm(cross(longest, point)))) < 1e-8) {
    throw new RegistrationError('degenerateLandmarks');
  }
  for (let i = 0; i < normalized.length; i++) for (let j = i + 1; j < normalized.length; j++) {
    if (norm(sub(normalized[i], normalized[j])) < 1e-12) throw new RegistrationError('duplicateLandmark');
  }
  return { center, normalized };
}

// Jacobi diagonalization of a real symmetric 4x4 matrix. Unlike power iteration,
// it selects the largest algebraic eigenvalue, including rotations near 180°.
function largestEigenvector(input) {
  const a = input.map(row => [...row]);
  const vectors = Array.from({ length: 4 }, (_, i) => Array.from({ length: 4 }, (_, j) => Number(i === j)));
  let converged = false;
  for (let iteration = 0; iteration < 100; iteration++) {
    let p = 0, q = 1;
    for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) {
      if (Math.abs(a[i][j]) > Math.abs(a[p][q])) { p = i; q = j; }
    }
    const magnitude = Math.max(...a.flat().map(Math.abs));
    if (Math.abs(a[p][q]) <= Math.max(magnitude * 1e-14, Number.MIN_VALUE)) { converged = true; break; }
    const angle = .5 * Math.atan2(2*a[p][q], a[q][q]-a[p][p]);
    const c = Math.cos(angle), s = Math.sin(angle);
    const app = a[p][p], aqq = a[q][q], apq = a[p][q];
    for (let k = 0; k < 4; k++) {
      if (k !== p && k !== q) {
        const akp = a[k][p], akq = a[k][q];
        a[k][p] = a[p][k] = c*akp-s*akq;
        a[k][q] = a[q][k] = s*akp+c*akq;
      }
      const vkp = vectors[k][p], vkq = vectors[k][q];
      vectors[k][p] = c*vkp-s*vkq;
      vectors[k][q] = s*vkp+c*vkq;
    }
    a[p][p] = c*c*app-2*s*c*apq+s*s*aqq;
    a[q][q] = s*s*app+2*s*c*apq+c*c*aqq;
    a[p][q] = a[q][p] = 0;
  }
  if (!converged) throw new RegistrationError('registrationNotConverged');
  const order = [0, 1, 2, 3].sort((i, j) => a[j][j]-a[i][i]);
  const magnitude = Math.max(...order.map(i => Math.abs(a[i][i])));
  if (magnitude === 0 || a[order[0]][order[0]]-a[order[1]][order[1]] <= magnitude*1e-12) {
    throw new RegistrationError('ambiguousRegistration');
  }
  const quaternion = vectors.map(row => row[order[0]]);
  const length = norm(quaternion);
  return quaternion.map(value => value / length);
}

/**
 * Least-squares proper rigid registration of ordered source/target landmarks.
 * `matrix` is a column-major 4x4 mapping source metres into target metres.
 * `residuals`, `rmse`, and returned `maxResidual` are distances in metres.
 * options.maxResidual is the caller's explicit acceptance threshold in metres;
 * it is returned as `threshold`. Every residual must meet it. With no threshold,
 * accepted is null and status is needs-review. No default physical tolerance is
 * invented. Even accepted means only that these supplied pairs meet that limit.
 * There is no outlier removal, correspondence search, scale fit or reflection.
 */
export function registerLandmarks(sourcePoints, targetPoints, options = {}) {
  validate(sourcePoints); validate(targetPoints);
  if (sourcePoints.length !== targetPoints.length) throw new RegistrationError('landmarkCountMismatch');
  if (options === null || typeof options !== 'object' || Array.isArray(options) ||
      options.maxResidual !== undefined && (!Number.isFinite(options.maxResidual) || options.maxResidual < 0 || options.maxResidual > MAX_COORDINATE)) {
    throw new RegistrationError('invalidRegistrationThreshold');
  }
  const source = centered(sourcePoints), target = centered(targetPoints);
  // Normalization improves numerical conditioning but does not fit or apply a
  // scale: a common positive covariance factor cannot change its optimal rotation.
  const covariance = Array.from({ length: 3 }, () => [0, 0, 0]);
  source.normalized.forEach((point, n) => {
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) covariance[i][j] += point[i] * target.normalized[n][j] / sourcePoints.length;
  });
  const [[xx, xy, xz], [yx, yy, yz], [zx, zy, zz]] = covariance;
  const [w, x, y, z] = largestEigenvector([
    [xx+yy+zz, yz-zy, zx-xz, xy-yx],
    [yz-zy, xx-yy-zz, xy+yx, zx+xz],
    [zx-xz, xy+yx, -xx+yy-zz, yz+zy],
    [xy-yx, zx+xz, yz+zy, -xx-yy+zz]
  ]);
  const rotation = [
    [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
    [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
    [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]
  ];
  const translation = target.center.map((value, axis) => value - dot(rotation[axis], source.center));
  const matrix = [
    rotation[0][0], rotation[1][0], rotation[2][0], 0,
    rotation[0][1], rotation[1][1], rotation[2][1], 0,
    rotation[0][2], rotation[1][2], rotation[2][2], 0,
    ...translation, 1
  ];
  const residuals = sourcePoints.map((point, index) => norm(rotation.map((row, axis) => dot(row, point) + translation[axis] - targetPoints[index][axis])));
  const rmse = Math.hypot(...residuals) / Math.sqrt(residuals.length);
  const maxResidual = Math.max(...residuals);
  const threshold = options.maxResidual ?? null;
  const accepted = threshold === null ? null : maxResidual <= threshold;
  if (![...matrix, ...residuals, rmse].every(Number.isFinite)) throw new RegistrationError('invalidRegistrationResult');
  return { matrix, residuals, rmse, maxResidual, threshold, accepted,
    status: accepted === null ? 'needs-review' : accepted ? 'accepted' : 'rejected',
    units: 'm', direction: 'source-to-target', scale: 1 };
}
