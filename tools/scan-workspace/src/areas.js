// Floor, gross wall, opening and net wall areas from preserved RoomPlan surfaces.
//
// Requirement (KANTURA roadmap M2, written from the user's request and public
// product descriptions of opening deductions): floor area, gross wall area,
// assigned openings and net wall area are stored and shown separately. A door or
// window *note* never causes a deduction; only a detected door/window/opening
// surface that is assigned to a wall does. Overlapping openings are subtracted
// once (their union), openings that extend past a wall edge are clipped and
// flagged, and anything ambiguous stays visible instead of being guessed.
//
// Geometry convention (same as roomplan.js and the native exporter): each
// surface has a rigid, column-major 4×4 transform; local X is width, local Y is
// height, local Z is the surface normal. Dimensions are meters before the
// project scale is applied. The original surfaces are never modified.

export const SURFACE_KINDS = Object.freeze(['wall', 'door', 'window', 'opening', 'floor']);
export const OPENING_KINDS = Object.freeze(['door', 'window', 'opening']);
// Automatic assignment limits in model units (meters for RoomPlan).
export const ASSIGNMENT_LIMITS = Object.freeze({ plane: 0.2, edge: 0.05, parallel: 0.9, ambiguity: 0.02 });
export const AREA_ISSUES = Object.freeze(['missingHeight', 'degenerateWall', 'clipped', 'overlap', 'outsideWall', 'ambiguous', 'unassigned', 'notParallel', 'farFromWall', 'needsReview', 'excluded', 'missingWall']);

const EPS = 1e-9;
const finite = (v, limit = 100000) => Number.isFinite(v) && Math.abs(v) <= limit;
const vector = (v, n) => Array.isArray(v) && v.length === n && v.every(x => finite(x));
const column = (m, c) => [m[c * 4], m[c * 4 + 1], m[c * 4 + 2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const toWorld = (p, m) => [m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13], m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]];
// Rigid transform: local = Rᵀ (world − t).
const toLocal = (p, m) => { const d = [p[0] - m[12], p[1] - m[13], p[2] - m[14]]; return [dot(d, column(m, 0)), dot(d, column(m, 1)), dot(d, column(m, 2))]; };
const rectangle = (w, h) => [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]];
const shoelace = pts => Math.abs(pts.reduce((s, a, i) => { const b = pts[(i + 1) % pts.length]; return s + a[0] * b[1] - b[0] * a[1]; }, 0)) / 2;
const rectArea = r => Math.max(0, r[2] - r[0]) * Math.max(0, r[3] - r[1]);
const intersect = (a, b) => [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.min(a[2], b[2]), Math.min(a[3], b[3])];

function insidePolygon(p, polygon, tolerance) {
  // Points on (or within tolerance of) an edge count as inside.
  for (let i = 0; i < polygon.length; i++) {
    const a = polygon[i], b = polygon[(i + 1) % polygon.length], dx = b[0] - a[0], dy = b[1] - a[1], len = dx * dx + dy * dy;
    const t = len ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len)) : 0;
    if (Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy) <= tolerance) return true;
  }
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i], b = polygon[j];
    if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return inside;
}

/** Exact area of a union of axis-aligned rectangles [x0, y0, x1, y1]. */
export function unionArea(rects) {
  const live = rects.filter(r => rectArea(r) > EPS);
  const xs = [...new Set(live.flatMap(r => [r[0], r[2]]))].sort((a, b) => a - b);
  let area = 0;
  for (let i = 0; i + 1 < xs.length; i++) {
    const x0 = xs[i], x1 = xs[i + 1];
    const spans = live.filter(r => r[0] <= x0 && r[2] >= x1).map(r => [r[1], r[3]]).sort((a, b) => a[0] - b[0]);
    let covered = 0, start = -Infinity, end = -Infinity;
    for (const [s, e] of spans) { if (s > end) { covered += end - start > 0 ? end - start : 0; start = s; end = e; } else end = Math.max(end, e); }
    covered += end - start > 0 ? end - start : 0;
    area += covered * (x1 - x0);
  }
  return area;
}

function rigid(m) {
  if (!vector(m, 16) || Math.abs(m[3]) + Math.abs(m[7]) + Math.abs(m[11]) + Math.abs(m[15] - 1) > 1e-4) return false;
  for (let a = 0; a < 3; a++) for (let b = 0; b < 3; b++) if (Math.abs(dot(column(m, a), column(m, b)) - (a === b ? 1 : 0)) > 0.02) return false;
  return true;
}

/** Throws a plain Error when stored surfaces or manual assignments are malformed. */
export function validateAreaInputs(surfaces, assignments) {
  if (surfaces === undefined) { if (assignments !== undefined) throw new Error('areaInputs'); return; }
  if (!Array.isArray(surfaces) || surfaces.length > 150) throw new Error('areaInputs');
  const ids = new Map();
  for (const s of surfaces) {
    if (!s || typeof s.id !== 'string' || !s.id || s.id.length > 200 || ids.has(s.id) || !SURFACE_KINDS.includes(s.kind) || typeof s.label !== 'string' || s.label.length > 200 || !vector(s.dimensions, 3) || s.dimensions.some(v => v < 0) || !rigid(s.transform) || !['high', 'medium', 'low', 'unknown'].includes(s.confidence)) throw new Error('areaInputs');
    if (s.polygonCorners !== undefined && (!Array.isArray(s.polygonCorners) || s.polygonCorners.length < 3 || s.polygonCorners.length > 100 || !s.polygonCorners.every(v => vector(v, 3)))) throw new Error('areaInputs');
    ids.set(s.id, s.kind);
  }
  if (assignments === undefined) return;
  if (!assignments || typeof assignments !== 'object' || Array.isArray(assignments) || Object.keys(assignments).length > 150) throw new Error('areaInputs');
  for (const [opening, wall] of Object.entries(assignments)) {
    if (!OPENING_KINDS.includes(ids.get(opening)) || wall !== null && ids.get(wall) !== 'wall') throw new Error('areaInputs');
  }
}

function wallFrame(surface) {
  const [w, h] = surface.dimensions;
  const outline = surface.polygonCorners ? surface.polygonCorners.map(p => [p[0], p[1]]) : rectangle(w, h);
  const xs = outline.map(p => p[0]), ys = outline.map(p => p[1]);
  const bounds = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  const issues = [];
  let gross = null;
  if (surface.polygonCorners) {
    const planar = surface.polygonCorners.every(p => Math.abs(p[2]) <= 0.03);
    gross = planar ? shoelace(outline) : null;
    if (!planar || !(gross > EPS)) { gross = null; issues.push('degenerateWall'); }
  } else if (!(h > EPS)) issues.push('missingHeight');
  else if (!(w > EPS)) issues.push('degenerateWall');
  else gross = w * h;
  return { surface, outline, bounds, gross, rectangular: !surface.polygonCorners, issues };
}

/**
 * Compute floor and wall areas. Returns null when the project has no preserved
 * RoomPlan surfaces (for example a textured LiDAR mesh or an older archive).
 * All lengths are multiplied by `scale` and areas by `scale²`.
 */
export function areaSummary(surfaces, assignments = {}, scale = 1) {
  if (!Array.isArray(surfaces) || !surfaces.length) return null;
  validateAreaInputs(surfaces, assignments && Object.keys(assignments).length ? assignments : undefined);
  if (!Number.isFinite(scale) || scale <= 0) throw new Error('areaInputs');
  const s2 = scale * scale, manual = assignments || {};
  const walls = surfaces.filter(s => s.kind === 'wall').map(wallFrame);
  const byId = new Map(walls.map(w => [w.surface.id, w]));
  const placed = new Map(walls.map(w => [w.surface.id, []]));

  const openings = surfaces.filter(s => OPENING_KINDS.includes(s.kind)).map(surface => {
    const [w, h] = surface.dimensions, issues = [];
    const world = rectangle(w, h).map(([x, y]) => toWorld([x, y, 0], surface.transform));
    const center = toWorld([0, 0, 0], surface.transform), normal = column(surface.transform, 2);
    const rawArea = w * h;
    const result = { id: surface.id, kind: surface.kind, label: surface.label, area: rawArea * s2, wallId: null, assignment: 'none', deducted: 0, issues };
    if (!(rawArea > EPS)) { issues.push('degenerateWall'); return result; }

    let wall;
    if (Object.hasOwn(manual, surface.id)) {
      result.assignment = 'manual';
      if (manual[surface.id] === null) { issues.push('excluded'); return result; }
      wall = byId.get(manual[surface.id]);
      if (!wall) { issues.push('missingWall'); return result; }
      if (Math.abs(dot(normal, column(wall.surface.transform, 2))) < ASSIGNMENT_LIMITS.parallel) { result.wallId = wall.surface.id; issues.push('notParallel'); return result; }
      if (Math.abs(toLocal(center, wall.surface.transform)[2]) > ASSIGNMENT_LIMITS.plane) issues.push('farFromWall');
    } else {
      const candidates = walls.map(candidate => {
        const local = toLocal(center, candidate.surface.transform), b = candidate.bounds, e = ASSIGNMENT_LIMITS.edge;
        const fits = Math.abs(dot(normal, column(candidate.surface.transform, 2))) >= ASSIGNMENT_LIMITS.parallel && Math.abs(local[2]) <= ASSIGNMENT_LIMITS.plane && local[0] >= b[0] - e && local[0] <= b[2] + e && local[1] >= b[1] - e && local[1] <= b[3] + e;
        return fits ? { candidate, distance: Math.abs(local[2]) } : null;
      }).filter(Boolean).sort((a, b) => a.distance - b.distance);
      if (!candidates.length) { issues.push('unassigned'); return result; }
      if (candidates.length > 1 && candidates[1].distance - candidates[0].distance < ASSIGNMENT_LIMITS.ambiguity) { issues.push('ambiguous'); return result; }
      wall = candidates[0].candidate;
      result.assignment = 'auto';
    }
    result.wallId = wall.surface.id;
    const local = world.map(p => toLocal(p, wall.surface.transform));
    const raw = [Math.min(...local.map(p => p[0])), Math.min(...local.map(p => p[1])), Math.max(...local.map(p => p[0])), Math.max(...local.map(p => p[1]))];
    const clipped = intersect(raw, wall.bounds);
    if (rectArea(clipped) <= EPS) { issues.push('outsideWall'); return result; }
    if (rectArea(clipped) < rectArea(raw) - 1e-6) issues.push('clipped');
    if (wall.gross === null) { issues.push('needsReview'); return result; }
    if (!wall.rectangular) {
      const corners = [[clipped[0], clipped[1]], [clipped[2], clipped[1]], [clipped[2], clipped[3]], [clipped[0], clipped[3]]];
      if (!corners.every(p => insidePolygon(p, wall.outline, 1e-6))) { issues.push('needsReview'); return result; }
    }
    placed.get(wall.surface.id).push({ opening: result, rect: clipped });
    return result;
  });

  const wallRows = walls.map(wall => {
    const items = placed.get(wall.surface.id);
    for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) {
      if (rectArea(intersect(items[i].rect, items[j].rect)) > 1e-6) for (const item of [items[i], items[j]]) if (!item.opening.issues.includes('overlap')) item.opening.issues.push('overlap');
    }
    for (const item of items) item.opening.deducted = rectArea(item.rect) * s2;
    const openingArea = unionArea(items.map(item => item.rect)) * s2;
    const gross = wall.gross === null ? null : wall.gross * s2;
    return { id: wall.surface.id, label: wall.surface.label, width: wall.surface.dimensions[0] * scale, height: wall.surface.dimensions[1] * scale, gross, openingArea, net: gross === null ? null : Math.max(0, gross - openingArea), openings: items.map(item => item.opening.id), issues: wall.issues };
  });

  const floors = surfaces.filter(s => s.kind === 'floor').map(surface => {
    const planar = surface.polygonCorners?.every(p => Math.abs(p[2]) <= 0.03);
    const area = planar ? shoelace(surface.polygonCorners.map(p => [p[0], p[1]])) : 0;
    return { id: surface.id, label: surface.label, area: area > EPS ? area * s2 : null };
  });
  const known = wallRows.filter(w => w.gross !== null), sum = (rows, key) => rows.reduce((s, r) => s + (r[key] ?? 0), 0);
  const knownFloors = floors.filter(f => f.area !== null);
  return {
    floors,
    walls: wallRows,
    openings,
    totals: {
      floor: knownFloors.length ? sum(knownFloors, 'area') : null,
      gross: sum(known, 'gross'),
      openingArea: sum(known, 'openingArea'),
      net: sum(known, 'net'),
      // Incomplete means a total is missing parts, not that the scan is wrong.
      incomplete: known.length !== wallRows.length || knownFloors.length !== floors.length || !floors.length,
      unresolved: openings.filter(o => !o.deducted && !o.issues.includes('excluded')).length,
    },
  };
}

/** Surface records stored in a project, translated by the viewer normalization offset. */
export function storedSurfaces(surfaces, offset, labelFor) {
  return surfaces.map((s, i) => {
    const transform = [...s.transform];
    transform[12] -= offset[0]; transform[13] -= offset[1]; transform[14] -= offset[2];
    const stored = { id: s.id, kind: s.kind, label: labelFor(s, i), dimensions: [...s.dimensions], transform, confidence: s.confidence };
    if (s.polygonCorners) stored.polygonCorners = s.polygonCorners.map(p => [...p]);
    return stored;
  });
}

/** Rows for the wall/opening table, CSV or report; null values are unknown. */
export function areaRows(summary) {
  if (!summary) return [];
  return [
    ...summary.floors.map(f => ({ group: 'floor', label: f.label, area: f.area })),
    ...summary.walls.map(w => ({ group: 'wall', label: w.label, gross: w.gross, openingArea: w.openingArea, net: w.net, issues: w.issues })),
    ...summary.openings.map(o => ({ group: 'opening', kind: o.kind, label: o.label, area: o.area, deducted: o.deducted, wallId: o.wallId, assignment: o.assignment, issues: o.issues })),
  ];
}

/** World-space outline of a stored surface (for focusing the viewer on it). */
export function surfaceOutline(surface) {
  const local = surface.polygonCorners || rectangle(surface.dimensions[0], surface.dimensions[1]).map(([x, y]) => [x, y, 0]);
  return local.map(p => toWorld(p, surface.transform));
}
