// Conservative envelope checks, not a collision-free 3D route planner.
// Dimensions and clearances are metres. Returned yaw/tilt are DEGREES.
const EPS = 1e-9;
const RAD = Math.PI / 180;

export class TransportError extends Error {
  constructor(field) { super(`Invalid transport field: ${field}`); this.code = 'invalidTransport'; this.field = field; }
}

function finite(value, min, max, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) throw new TransportError(field);
  return value;
}

function angles(start, end, critical = []) {
  const lower = Math.min(start, end), upper = Math.max(start, end);
  const count = Math.max(1, Math.ceil((upper - lower) / (5 * RAD)));
  const result = Array.from({ length: count + 1 }, (_, i) => lower + (upper - lower) * i / count);
  for (const angle of critical) if (angle >= lower - EPS && angle <= upper + EPS) result.push(Math.min(upper, Math.max(lower, angle)));
  return [...new Set(result)].sort((a, b) => a - b);
}

// Extrema of a|cos(yaw)| + b|sin(yaw)|, including between display samples.
function yawCandidates(a, b, end) {
  const critical = [];
  const peak = Math.atan2(b, a);
  for (let k = -4; k <= 4; k++) critical.push(k * Math.PI / 2, peak + k * Math.PI, -peak + k * Math.PI);
  return angles(0, end, critical);
}

function projection(a, b, angle) { return a * Math.abs(Math.cos(angle)) + b * Math.abs(Math.sin(angle)); }
function maximumProjection(a, b, end) { return Math.max(...yawCandidates(a, b, end).map(angle => projection(a, b, angle))); }

function scenario(object, route, margin, sideways, tilt, id) {
  const width = sideways ? object.depth : object.width;
  const depth = sideways ? object.width : object.depth;
  const turn = route.turnDegrees * RAD;
  const hasTurn = Math.abs(turn) > EPS;
  // Tilt about the lateral axis: width unchanged, depth and height projected.
  const tiltAngles = angles(0, tilt, [Math.atan2(object.height, depth), Math.atan2(depth, object.height)]);
  const maxDepth = Math.max(...tiltAngles.map(a => projection(depth, object.height, a)));
  const maxHeight = Math.max(...tiltAngles.map(a => projection(object.height, depth, a)));
  const fixedDepth = projection(depth, object.height, tilt);
  const fixedHeight = projection(object.height, depth, tilt);
  const yawAngles = [...new Set([...yawCandidates(width, maxDepth, turn), ...yawCandidates(maxDepth, width, turn)])].sort((a, b) => a - b);
  const clearances = { corridorWidth: route.width - width - 2 * margin, ceiling: route.ceiling - maxHeight - 2 * margin };
  // A centred turn occupying this entire rectangular landing is sufficient.
  // It is not necessary: a translated turn may succeed when these bounds fail.
  if (hasTurn || tilt > EPS) {
    clearances.landingWidth = route.landingWidth - maximumProjection(width, maxDepth, turn) - 2 * margin;
    clearances.landingDepth = route.landingDepth - maximumProjection(maxDepth, width, turn) - 2 * margin;
  }
  const samples = [];
  for (const angle of yawAngles) samples.push({
    phase: 'turn', yaw: angle / RAD, tilt: tilt / RAD,
    width: projection(width, fixedDepth, angle), depth: projection(fixedDepth, width, angle), height: fixedHeight
  });
  if (tilt > EPS) for (const angle of tiltAngles) for (const yaw of hasTurn ? [0, turn] : [0]) samples.push({
    phase: 'tilt-transition', yaw: yaw / RAD, tilt: angle / RAD,
    width: projection(width, projection(depth, object.height, angle), yaw),
    depth: projection(projection(depth, object.height, angle), width, yaw), height: projection(object.height, depth, angle)
  });
  return {
    id, sideways, startingYaw: sideways ? 90 : 0, tilt: tilt / RAD,
    fits: Object.values(clearances).every(value => value >= -EPS),
    limitingClearances: clearances,
    minimumClearance: Math.min(...Object.values(clearances)),
    samples,
    envelope: { width: maximumProjection(width, maxDepth, turn), depth: maximumProjection(maxDepth, width, turn), height: maxHeight }
  };
}

/**
 * Assess a rectangular object along a simplified straight passage, stair slope
 * and centred landing turn. A margin applies to EACH side, including vertically.
 * rise/run may describe one step or a complete straight flight, consistently.
 * Possible = a sufficient rectangular envelope fits under these assumptions.
 * It does not establish a real route, safe handling, or permitted appliance tilt.
 */
export function assessTransport(input) {
  if (!input || typeof input !== 'object') throw new TransportError('input');
  const { object, route, margin = 0, allowTilt = false } = input;
  if (!object || !route) throw new TransportError('object/route');
  for (const field of ['width', 'depth', 'height']) finite(object[field], 0.001, 20, `object.${field}`);
  for (const field of ['width', 'ceiling', 'landingWidth', 'landingDepth', 'run']) finite(route[field], 0.001, 100, `route.${field}`);
  finite(route.rise, 0, 100, 'route.rise');
  finite(route.turnDegrees, -180, 180, 'route.turnDegrees');
  finite(margin, 0, 2, 'margin');
  if (typeof allowTilt !== 'boolean') throw new TransportError('allowTilt');
  const stairAngle = Math.atan2(route.rise, route.run);
  const scenarios = [scenario(object, route, margin, false, 0, 'upright'), scenario(object, route, margin, true, 0, 'upright-sideways')];
  if (allowTilt && stairAngle > EPS) scenarios.push(scenario(object, route, margin, false, stairAngle, 'stair-tilt'), scenario(object, route, margin, true, stairAngle, 'stair-tilt-sideways'));
  // Prefer the simplest fitting handling orientation, then the least deficit.
  const best = scenarios.find(item => item.fits) || [...scenarios].sort((a, b) => b.minimumClearance - a.minimumClearance)[0];
  const smallest = Math.min(object.width, object.depth, object.height);
  const reasons = [];
  if (smallest + 2 * margin > route.width + EPS) reasons.push('corridor_narrower_than_smallest_dimension');
  if (smallest + 2 * margin > route.ceiling + EPS) reasons.push('ceiling_lower_than_smallest_dimension');
  let verdict;
  if (reasons.length) verdict = 'blocked';
  else if (best.fits) { verdict = 'possible'; reasons.push(best.tilt ? 'tilted_envelope_fits' : 'upright_envelope_fits'); }
  else {
    verdict = 'uncertain'; reasons.push('no_tested_orientation_fits');
    if (best.limitingClearances.corridorWidth < -EPS) reasons.push('corridor_clearance_insufficient');
    if (best.limitingClearances.ceiling < -EPS) reasons.push('ceiling_clearance_insufficient');
    if ((best.limitingClearances.landingWidth ?? 0) < -EPS || (best.limitingClearances.landingDepth ?? 0) < -EPS) reasons.push('landing_requires_path_planning');
  }
  return {
    verdict, reasons, angleUnit: 'degrees', dimensionUnit: 'm', marginPerSide: margin,
    stairAngle: stairAngle / RAD, chosenScenario: best.id, startingYaw: best.startingYaw,
    samples: best.samples, limitingClearances: best.limitingClearances, scenarios,
    assumptions: ['rectangular_object', 'unobstructed_rectangular_passage', 'centred_turn_on_rectangular_landing', 'tilt_transitions_fit_landing', 'no_step_or_handrail_collision_test', 'no_carriers_or_equipment', 'verify_actual_route_and_manufacturer_transport_instructions']
  };
}
