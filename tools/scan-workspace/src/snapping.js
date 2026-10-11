import { BufferGeometry, EdgesGeometry, Float32BufferAttribute, Matrix4, Raycaster, Vector2, Vector3, Vector4 } from 'three';

export const SNAP_LIMITS = Object.freeze({ maxTriangles: 100000, maxSegments: 20000, thresholdAngle: 30, radiusPx: 12 });
const visible = object => { for (let current = object; current; current = current.parent) if (!current.visible) return false; return true; };

// Work in the same world coordinates that the viewer stores for measurements.
// Extract in world space so a non-uniform scale also affects the crease angle.
export function buildSnapIndex(root, options = {}) {
  const { maxTriangles, maxSegments, thresholdAngle } = { ...SNAP_LIMITS, ...options };
  if (!Number.isInteger(maxTriangles) || maxTriangles < 1 || !Number.isInteger(maxSegments) || maxSegments < 1 || !Number.isFinite(thresholdAngle) || thresholdAngle <= 0 || thresholdAngle > 180) throw new RangeError('Invalid snap limits');
  const empty = status => ({ status, segments: [], corners: [] });
  const meshes = [];
  let triangles = 0, unsupported = false;
  root.updateWorldMatrix(true, true);
  root.traverse(object => {
    if (!object.isMesh || !visible(object)) return;
    if (object.isSkinnedMesh || object.isInstancedMesh || Object.keys(object.geometry.morphAttributes).length || object.geometry.drawRange.start !== 0 || Number.isFinite(object.geometry.drawRange.count)) { unsupported = true; return; }
    const position = object.geometry.getAttribute('position');
    if (!position) return;
    const count = object.geometry.index?.count ?? position.count;
    if (count % 3) { unsupported = true; return; }
    triangles += count / 3;
    meshes.push(object);
  });
  if (unsupported) return empty('unsupported');
  if (triangles > maxTriangles) return empty('limit');
  const segments = [], corners = [];
  if (!triangles) return empty('unsupported');
  // Join visible static meshes before extracting edges. A material/object split
  // between two coplanar triangles must not turn their shared diagonal into an
  // apparent object boundary. Vertex positions are copied, never edited in place.
  const positions = new Float32Array(triangles * 9), point = new Vector3();
  let offset = 0;
  for (const object of meshes) {
    const attribute = object.geometry.getAttribute('position'), indices = object.geometry.index;
    for (let i = 0, count = indices?.count ?? attribute.count; i < count; i++) {
      point.fromBufferAttribute(attribute, indices ? indices.getX(i) : i).applyMatrix4(object.matrixWorld);
      if (!point.toArray().every(Number.isFinite)) return empty('unsupported');
      positions.set(point.toArray(), offset); offset += 3;
    }
  }
  const geometry = new BufferGeometry(); geometry.setAttribute('position', new Float32BufferAttribute(positions, 3));
  let edges;
  try {
    edges = new EdgesGeometry(geometry, thresholdAngle);
    const edgePositions = edges.getAttribute('position');
    if (edgePositions.count / 2 > maxSegments) return empty('limit');
    const vertices = new Map();
    const addVertex = (vertex, other) => {
      const key = vertex.toArray().map(value => value.toPrecision(12)).join(',');
      if (!vertices.has(key)) vertices.set(key, { point: vertex, directions: [] });
      vertices.get(key).directions.push(other.clone().sub(vertex).normalize());
    };
    for (let index = 0; index < edgePositions.count; index += 2) {
      const a = new Vector3().fromBufferAttribute(edgePositions, index), b = new Vector3().fromBufferAttribute(edgePositions, index + 1);
      if (!a.toArray().every(Number.isFinite) || !b.toArray().every(Number.isFinite) || a.equals(b)) continue;
      segments.push({ a, b }); addVertex(a, b); addVertex(b, a);
    }
    for (const { point, directions } of vertices.values()) {
      // A tessellation vertex along a straight boundary is not a corner.
      if (directions.length === 2 && directions[0].dot(directions[1]) < -Math.cos(Math.PI / 36)) continue;
      corners.push({ point, object: root });
    }
  } finally { edges?.dispose(); geometry.dispose(); }
  return { status: segments.length ? 'ready' : 'unsupported', segments, corners };
}

function intervalForPlanes(a, b, planes) {
  let start = 0, end = 1;
  for (const distance of planes) {
    const da = distance(a), db = distance(b);
    if (da < 0 && db < 0) return null;
    if (da < 0) start = Math.max(start, da / (da - db));
    if (db < 0) end = Math.min(end, da / (da - db));
  }
  return start > end ? null : [start, end];
}
const frustumPlanes = [p => p.w + p.x, p => p.w - p.x, p => p.w + p.y, p => p.w - p.y, p => p.w + p.z, p => p.w - p.z];

export function visibleSnapPoint(root, camera, point, { clipPlane, tolerance = 1e-6 } = {}) {
  const projected = point.clone().project(camera), ray = new Raycaster();
  ray.setFromCamera(new Vector2(projected.x, projected.y), camera);
  const targetDistance = ray.ray.origin.distanceTo(point);
  const hit = ray.intersectObject(root, true).find(item => {
    if (!item.object.isMesh || !visible(item.object) || (clipPlane && clipPlane.distanceToPoint(item.point) < -tolerance)) return false;
    const material = Array.isArray(item.object.material) ? item.object.material[item.face?.materialIndex ?? 0] : item.object.material;
    return material?.visible !== false && !(material?.transparent && material.opacity === 0);
  });
  return !hit || hit.distance >= targetDistance - tolerance;
}

// x/y and radius are CSS pixels, independent of canvas/device pixel ratio.
// isVisible can ray-test the few nearest candidates against the actual model.
export function findSnap(index, camera, pointer, viewport, options = {}) {
  const { radiusPx = SNAP_LIMITS.radiusPx, clipPlane, isVisible = () => true } = options;
  if (index?.status !== 'ready' || ![pointer.x, pointer.y, viewport.width, viewport.height, radiusPx].every(Number.isFinite) || viewport.width <= 0 || viewport.height <= 0 || radiusPx <= 0) return null;
  camera.updateMatrixWorld();
  const matrix = new Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
  const clip = point => new Vector4(point.x, point.y, point.z, 1).applyMatrix4(matrix);
  const screen = point => ({ x: (point.x / point.w + 1) * viewport.width / 2, y: (1 - point.y / point.w) * viewport.height / 2 });
  const candidates = [];
  const add = candidate => {
    if (candidate.distancePx > radiusPx) return;
    candidates.push(candidate);
    candidates.sort((a, b) => (a.kind === b.kind ? a.distancePx - b.distancePx : a.kind === 'vertex' ? -1 : 1));
    // Bound occlusion raycasts even in a dense projected edge cluster.
    if (candidates.length > 32) candidates.pop();
  };
  for (const { point, object } of index.corners) {
    if ((object && !visible(object)) || (clipPlane && clipPlane.distanceToPoint(point) < 0)) continue;
    const projected = clip(point);
    if (projected.w <= 0 || frustumPlanes.some(distance => distance(projected) < 0)) continue;
    const pixel = screen(projected);
    add({ kind: 'vertex', point: point.clone(), distancePx: Math.hypot(pixel.x - pointer.x, pixel.y - pointer.y) });
  }
  for (const segment of index.segments) {
    if (segment.object && !visible(segment.object)) continue;
    let a = segment.a.clone(), b = segment.b.clone();
    if (clipPlane) {
      const interval = intervalForPlanes(a, b, [point => clipPlane.distanceToPoint(point)]);
      if (!interval) continue;
      [a, b] = [a.clone().lerp(b, interval[0]), a.clone().lerp(b, interval[1])];
    }
    const interval = intervalForPlanes(clip(a), clip(b), frustumPlanes);
    if (!interval) continue;
    [a, b] = [a.clone().lerp(b, interval[0]), a.clone().lerp(b, interval[1])];
    const ca = clip(a), cb = clip(b);
    if (ca.w <= 0 || cb.w <= 0) continue;
    const pa = screen(ca), pb = screen(cb), dx = pb.x - pa.x, dy = pb.y - pa.y, lengthSquared = dx * dx + dy * dy;
    const s = lengthSquared ? Math.max(0, Math.min(1, ((pointer.x - pa.x) * dx + (pointer.y - pa.y) * dy) / lengthSquared)) : 0;
    // Interpolate with reciprocal depth: linear screen t is not world t.
    const t = s * ca.w / ((1 - s) * cb.w + s * ca.w);
    add({ kind: 'edge', point: a.lerp(b, t), distancePx: Math.hypot(pa.x + s * dx - pointer.x, pa.y + s * dy - pointer.y) });
  }
  return candidates.find(candidate => isVisible(candidate.point)) ?? null;
}
