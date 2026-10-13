import Foundation

// Stair and basement-access scans: an ARKit LiDAR mesh plus the walked path.
// RoomPlan models one storey per room, so stairs going down need their own
// capture. Everything here is Foundation-only so it is tested on CI.

struct StairVec: Equatable {
    var x: Double, y: Double, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    static func + (a: StairVec, b: StairVec) -> StairVec { .init(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: StairVec, b: StairVec) -> StairVec { .init(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: StairVec, s: Double) -> StairVec { .init(a.x * s, a.y * s, a.z * s) }
    func dot(_ b: StairVec) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: StairVec) -> StairVec { .init(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { sqrt(dot(self)) }
    var normalized: StairVec { let l = length; return l > 1e-12 ? self * (1 / l) : .init(0, 0, 0) }
    var array: [Double] { [x, y, z] }
}

/// Mesh vertices (with normals) and triangles in world coordinates, y up, metres.
/// Stored as `mesh.bin`: "KSM1", UInt32 vertex count, UInt32 triangle count,
/// Float32 positions, Float32 normals, UInt32 indices (little endian).
struct StairMesh: Equatable {
    var positions: [Float] = []
    var normals: [Float] = []
    var faces: [UInt32] = []
    static let fileName = "mesh.bin"
    static let maxVertices = 1_500_000

    enum MeshError: Error { case invalid }
    var vertexCount: Int { positions.count / 3 }
    func position(_ i: Int) -> StairVec { .init(Double(positions[3 * i]), Double(positions[3 * i + 1]), Double(positions[3 * i + 2])) }
    func normalY(_ i: Int) -> Double { Double(normals[3 * i + 1]) }

    func encoded() -> Data {
        var data = Data("KSM1".utf8)
        func put<T: FixedWidthInteger>(_ v: T) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        put(UInt32(vertexCount)); put(UInt32(faces.count / 3))
        for v in positions { put(v.bitPattern) }
        for v in normals { put(v.bitPattern) }
        for v in faces { put(v) }
        return data
    }

    init() {}
    init(positions: [Float], normals: [Float], faces: [UInt32]) {
        self.positions = positions; self.normals = normals; self.faces = faces
    }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0..<4] == [0x4B, 0x53, 0x4D, 0x31] else { throw MeshError.invalid }
        func u32(_ o: Int) -> UInt32 { UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24 }
        let n = Int(u32(4)), m = Int(u32(8))
        guard n <= Self.maxVertices, m <= 4 * Self.maxVertices, bytes.count == 12 + 24 * n + 12 * m else { throw MeshError.invalid }
        var o = 12
        positions = (0..<3 * n).map { i in Float(bitPattern: u32(o + 4 * i)) }; o += 12 * n
        normals = (0..<3 * n).map { i in Float(bitPattern: u32(o + 4 * i)) }; o += 12 * n
        faces = (0..<3 * m).map { i in u32(o + 4 * i) }
        guard positions.allSatisfy(\.isFinite), normals.allSatisfy(\.isFinite), faces.allSatisfy({ Int($0) < n }) else { throw MeshError.invalid }
    }

    /// Keep what lies within `radius` (horizontally) of the walked path.
    func cropped(near path: [StairVec], radius: Double) -> StairMesh {
        guard !path.isEmpty else { return self }
        let grid = StairPointGrid(xs: path.map(\.x), zs: path.map(\.z), cell: max(radius, 0.25))
        var map = [Int32](repeating: -1, count: vertexCount)
        var out = StairMesh()
        for i in 0..<vertexCount {
            let p = position(i)
            var keep = false
            grid.near(x: p.x, z: p.z, radius: radius) { k in
                if !keep, hypot(path[k].x - p.x, path[k].z - p.z) <= radius { keep = true }
            }
            if keep {
                map[i] = Int32(out.vertexCount)
                out.positions += positions[3 * i..<3 * i + 3]
                out.normals += normals[3 * i..<3 * i + 3]
            }
        }
        var f = 0
        while f + 2 < faces.count {
            let a = map[Int(faces[f])], b = map[Int(faces[f + 1])], c = map[Int(faces[f + 2])]
            if a >= 0, b >= 0, c >= 0 { out.faces += [UInt32(a), UInt32(b), UInt32(c)] }
            f += 3
        }
        return out
    }

    /// Wavefront OBJ for CAD and 3D tools (metres, y up).
    func obj() -> String {
        var s = "# KANTURA stair scan, metres, y up\n"
        s.reserveCapacity(vertexCount * 40 + faces.count * 8)
        for i in 0..<vertexCount { s += String(format: "v %.4f %.4f %.4f\n", positions[3 * i], positions[3 * i + 1], positions[3 * i + 2]) }
        for i in 0..<vertexCount { s += String(format: "vn %.3f %.3f %.3f\n", normals[3 * i], normals[3 * i + 1], normals[3 * i + 2]) }
        var f = 0
        while f + 2 < faces.count { s += "f \(faces[f] + 1)//\(faces[f] + 1) \(faces[f + 1] + 1)//\(faces[f + 1] + 1) \(faces[f + 2] + 1)//\(faces[f + 2] + 1)\n"; f += 3 }
        return s
    }
}

/// Horizontal (x/z) bucket grid for neighbourhood queries.
struct StairPointGrid {
    let cell: Double
    private var buckets: [Int64: [Int32]] = [:]
    init(xs: [Double], zs: [Double], cell: Double) {
        self.cell = cell
        for i in 0..<xs.count { buckets[Self.key(Int(Foundation.floor(xs[i] / cell)), Int(Foundation.floor(zs[i] / cell))), default: []].append(Int32(i)) }
    }
    private static func key(_ i: Int, _ j: Int) -> Int64 { Int64(i) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: j))) }
    func near(x: Double, z: Double, radius: Double, _ body: (Int) -> Void) {
        for i in Int(Foundation.floor((x - radius) / cell))...Int(Foundation.floor((x + radius) / cell)) {
            for j in Int(Foundation.floor((z - radius) / cell))...Int(Foundation.floor((z + radius) / cell)) {
                if let list = buckets[Self.key(i, j)] { for k in list { body(Int(k)) } }
            }
        }
    }
}

/// What the walk tells about the stair: per-station floor, clear width and
/// headroom along the centre line, and the summary numbers.
struct StairProfile: Codable, Equatable {
    struct Station: Codable, Equatable {
        var distance: Double          // horizontal distance along the centre line
        var x: Double, z: Double      // centre line position
        var floor: Double             // tread / floor height under the centre line
        var ceiling: Double?          // lowest overhead surface
        var left: Double?, right: Double?  // free distance to the side walls (or handrail)
        var heading: Double           // walking direction, radians (atan2(x, -z))
        var smoothedWidth: Double? = nil  // median width over ±15 cm
        var width: Double? { left != nil && right != nil ? left! + right! : nil }
        var headroom: Double? { ceiling.map { $0 - floor } }
    }
    var stations: [Station]
    var length: Double
    var drop: Double
    var risers: Int
    var riser: Double?
    var going: Double?
    var slopeDegrees: Double?
    var turnDegrees: Double
    var minWidth: Double?
    var minWidthAt: Double?
    var minHeadroom: Double?
    var minHeadroomAt: Double?
    /// 2: path cleaning and robust steps/turn/width (older scans are re-analysed).
    var analysis: Int? = StairAnalyzer.version
}

enum StairAnalyzer {
    static let version = 2
    enum AnalysisError: Error { case tooShort, noFloor }

    /// Resample the camera path every `step` metres (3D arc length) and smooth it.
    static func resample(_ path: [StairVec], step: Double = 0.05, window: Double = 0.4) -> [StairVec] {
        guard path.count >= 2 else { return path }
        var d = [0.0]
        for i in 1..<path.count { d.append(d[i - 1] + (path[i] - path[i - 1]).length) }
        let total = d.last!
        guard total >= step else { return [path[0]] }
        var out: [StairVec] = []
        var lo = 0, hi = 0, j = 0
        var sum = StairVec(0, 0, 0)
        var count = 0
        for k in 0...Int(total / step) {
            let s = Double(k) * step
            while hi < path.count && d[hi] <= s + window / 2 { sum = sum + path[hi]; count += 1; hi += 1 }
            while lo < hi && d[lo] < s - window / 2 { sum = sum - path[lo]; count -= 1; lo += 1 }
            if count > 0 { out.append(sum * (1 / Double(count))) } else {
                while j < d.count - 2 && d[j + 1] < s { j += 1 }
                let t = (s - d[j]) / max(1e-9, d[j + 1] - d[j])
                out.append(path[j] + (path[j + 1] - path[j]) * t)
            }
        }
        return out
    }

    /// Real walks are messy: looking around at the top, swinging the phone to the
    /// walls, a step back. Keep the stretch around the height change and pull the
    /// path tight so only forward progress remains.
    static func cleanPath(_ path: [StairVec]) -> [StairVec] {
        guard path.count >= 3 else { return path }
        func flat(_ a: StairVec, _ b: StairVec) -> Double { hypot(a.x - b.x, a.z - b.z) }
        let n = path.count, k = max(1, n / 10)
        let ys = path.map(\.y)
        let top = ys.prefix(k).sorted()[k / 2], bottom = ys.suffix(k).sorted()[k / 2]
        var first = 0, last = n - 1
        if abs(top - bottom) >= 0.3 {
            let down = bottom < top
            if let f = ys.firstIndex(where: { down ? $0 < top - 0.12 : $0 > top + 0.12 }),
               let l = ys.lastIndex(where: { down ? $0 > bottom + 0.12 : $0 < bottom - 0.12 }), l > f { first = f; last = l }
        }
        var s = first, e = last
        while s > 0 && flat(path[s - 1], path[first]) <= 1.3 { s -= 1 }
        while e < n - 1 && flat(path[e + 1], path[last]) <= 1.3 { e += 1 }
        var kept = [path[s]]
        for p in path[(s + 1)...e] {
            if flat(p, kept.last!) < 0.15 { continue }
            // Going back: retract instead of adding a U-turn.
            while kept.count >= 2 {
                let a = kept[kept.count - 2], b = kept[kept.count - 1]
                let v1 = (b.x - a.x, b.z - a.z), v2 = (p.x - b.x, p.z - b.z)
                let c = (v1.0 * v2.0 + v1.1 * v2.1) / (hypot(v1.0, v1.1) * hypot(v2.0, v2.1) + 1e-9)
                if c < -0.2 { kept.removeLast() } else { break }
            }
            if flat(p, kept.last!) >= 0.15 { kept.append(p) }
        }
        return kept
    }

    private static func kthLowest(_ v: [Double], _ k: Int) -> Double? { v.isEmpty ? nil : v.sorted()[min(k, v.count - 1)] }
    private static func kthHighest(_ v: [Double], _ k: Int) -> Double? { v.isEmpty ? nil : v.sorted(by: >)[min(k, v.count - 1)] }

    /// - Parameters:
    ///   - mesh: vertices and normals (faces are not needed)
    ///   - path: camera positions in walking order
    static func analyze(mesh: StairMesh, path: [StairVec]) throws -> StairProfile {
        let cams = resample(cleanPath(path))
        guard cams.count >= 8 else { throw AnalysisError.tooShort }
        let n = mesh.vertexCount
        let xs = (0..<n).map { Double(mesh.positions[3 * $0]) }, zs = (0..<n).map { Double(mesh.positions[3 * $0 + 2]) }
        let grid = StairPointGrid(xs: xs, zs: zs, cell: 0.25)
        let count = cams.count

        // Walking direction over ±25 cm.
        var forward: [StairVec] = []
        for i in 0..<count {
            let a = cams[max(0, i - 5)], b = cams[min(count - 1, i + 5)]
            var t = StairVec(b.x - a.x, 0, b.z - a.z).normalized
            if t.length == 0 { t = forward.last ?? StairVec(0, 0, -1) }
            forward.append(t)
        }

        func column(_ x: Double, _ z: Double, _ r: Double, _ accept: (StairVec, Double) -> Bool) -> [Double] {
            var ys: [Double] = []
            grid.near(x: x, z: z, radius: r) { k in
                let p = mesh.position(k)
                if hypot(p.x - x, p.z - z) <= r, accept(p, mesh.normalY(k)) { ys.append(p.y) }
            }
            return ys
        }

        // 1. Floor under the camera: highest upward-facing surface below the phone.
        var floors: [Double?] = cams.map { c in kthHighest(column(c.x, c.z, 0.12) { p, ny in ny > 0.7 && p.y < c.y - 0.7 }, 2) }
        guard floors.contains(where: { $0 != nil }) else { throw AnalysisError.noFloor }
        fill(&floors)

        // 2. Side walls perpendicular to the walk → centre line and clear width.
        var centres: [StairVec] = [], lefts: [Double?] = [], rights: [Double?] = []
        for i in 0..<count {
            let c = cams[i], t = forward[i], side = StairVec(-t.z, 0, t.x), f = floors[i]!
            var left: [Double] = [], right: [Double] = []
            grid.near(x: c.x, z: c.z, radius: 2.5) { k in
                let p = mesh.position(k)
                let dx = p.x - c.x, dz = p.z - c.z, dy = p.y - f
                guard abs(dx * t.x + dz * t.z) <= 0.04, dy >= 0.25, dy <= 1.7 else { return }
                let nx = Double(mesh.normals[3 * k]), nz = Double(mesh.normals[3 * k + 2])
                guard abs(nx * side.x + nz * side.z) >= 0.5 else { return }   // a wall facing sideways, not a riser
                let l = dx * side.x + dz * side.z
                if l > 0.03 { left.append(l) } else if l < -0.03 { right.append(-l) }
            }
            let l = kthLowest(left, 2), r = kthLowest(right, 2)
            let offset = (l != nil && r != nil) ? (l! - r!) / 2 : 0
            centres.append(StairVec(c.x + side.x * offset, 0, c.z + side.z * offset))
            lefts.append(l.map { $0 - offset }); rights.append(r.map { $0 + offset })
        }

        // 3. Floor and ceiling at the centre line.
        var stations: [StairProfile.Station] = []
        var distance = 0.0
        for i in 0..<count {
            let c = centres[i], cam = cams[i]
            if i > 0 { distance += hypot(c.x - centres[i - 1].x, c.z - centres[i - 1].z) }
            let floor = kthHighest(column(c.x, c.z, 0.06) { p, ny in ny > 0.7 && p.y < cam.y - 0.7 }, 2) ?? floors[i]!
            let ceiling = kthLowest(column(c.x, c.z, 0.08) { p, ny in ny < -0.5 && p.y > floor + 0.6 }, 2)
            let t = forward[i]
            stations.append(.init(distance: distance, x: c.x, z: c.z, floor: floor, ceiling: ceiling, left: lefts[i], right: rights[i], heading: atan2(t.x, -t.z)))
        }

        // 4. Steps: runs of floor changes, merged when closer than 12 cm, that go the
        // overall way (down or up) and have a plausible height (8–30 cm).
        var runs: [(total: Double, at: Double, from: Int, to: Int)] = []
        var i = 1
        while i < count {
            if abs(stations[i].floor - stations[i - 1].floor) < 0.02 { i += 1; continue }
            var j = i, total = 0.0
            while j < count && abs(stations[j].floor - stations[j - 1].floor) >= 0.02 { total += stations[j].floor - stations[j - 1].floor; j += 1 }
            let at = (stations[i - 1].distance + stations[j - 1].distance) / 2
            if let last = runs.last, at - last.at < 0.12 {
                runs[runs.count - 1] = (last.total + total, (last.at + at) / 2, last.from, j - 1)
            } else { runs.append((total, at, i - 1, j - 1)) }
            i = j
        }
        let sign: Double = stations[count - 1].floor >= stations[0].floor ? 1 : -1
        let steps = runs.filter { $0.total * sign >= 0.08 && abs($0.total) <= 0.30 }
        let jumps = steps.map { abs($0.total) }
        let median: ([Double]) -> Double? = { v in v.isEmpty ? nil : v.sorted()[v.count / 2] }
        // Going: straight distance between neighbouring risers on the centre line.
        let mids = steps.map { r in ((stations[r.from].x + stations[r.to].x) / 2, (stations[r.from].z + stations[r.to].z) / 2) }
        let goings = zip(mids, mids.dropFirst()).map { hypot($1.0 - $0.0, $1.1 - $0.1) }
        var slope: Double?
        var turn = 0.0
        if steps.count >= 2 {
            let a = steps.first!.from, b = steps.last!.to
            if stations[b].distance > stations[a].distance {
                slope = atan(abs(stations[b].floor - stations[a].floor) / (stations[b].distance - stations[a].distance)) * 180 / .pi
            }
            // 5. Turn: direction of the first and last 60 cm of the flight.
            func at(_ d: Double) -> StairProfile.Station { stations.min { abs($0.distance - d) < abs($1.distance - d) }! }
            func heading(_ p: StairProfile.Station, _ q: StairProfile.Station) -> Double { atan2(q.x - p.x, -(q.z - p.z)) }
            let d0 = stations[a].distance, d1 = stations[b].distance
            var d = heading(at(d1 - 0.6), at(d1)) - heading(at(d0), at(d0 + 0.6))
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            turn = d * 180 / .pi
        }

        // Clear width: median over ±15 cm so one swing of the phone does not count.
        for k in 0..<count {
            let near = stations.filter { abs($0.distance - stations[k].distance) <= 0.15 }.compactMap(\.width)
            stations[k].smoothedWidth = median(near)
        }
        let widths = stations.compactMap { s in s.smoothedWidth.map { ($0, s.distance) } }
        let heads = stations.compactMap { s in s.headroom.map { ($0, s.distance) } }
        // Height difference between the first and last 50 cm (robust to single spikes);
        // step count from that and the typical riser, so a missed or doubled edge
        // does not change the result.
        let startLevel = median(stations.filter { $0.distance <= 0.5 }.map(\.floor)) ?? stations[0].floor
        let endLevel = median(stations.filter { $0.distance >= distance - 0.5 }.map(\.floor)) ?? stations[count - 1].floor
        let drop = abs(endLevel - startLevel)
        var risers = jumps.count, riser = median(jumps)
        if let typical = riser, typical > 0.05, jumps.count >= 2 {
            risers = max(1, Int((drop / typical).rounded()))
            riser = drop / Double(risers)
        }
        return StairProfile(stations: stations, length: distance, drop: drop,
                            risers: risers, riser: riser, going: median(goings), slopeDegrees: slope,
                            turnDegrees: turn, minWidth: widths.min { $0.0 < $1.0 }?.0, minWidthAt: widths.min { $0.0 < $1.0 }?.1,
                            minHeadroom: heads.min { $0.0 < $1.0 }?.0, minHeadroomAt: heads.min { $0.0 < $1.0 }?.1)
    }

    private static func fill(_ values: inout [Double?]) {
        let known = values.indices.filter { values[$0] != nil }
        for i in values.indices where values[i] == nil {
            if let j = known.min(by: { abs($0 - i) < abs($1 - i) }) { values[i] = values[j] }
        }
    }
}

/// Moves a box (the appliance) along the scanned centre line and checks it
/// against every mesh point. At each station it tries upright and tilted along
/// the stair (as on a hand truck), each also turned sideways, small yaw changes
/// and a sideways shift, and keeps the variant with the most clearance.
/// Conservative simplification: rigid box, mesh accuracy about ±2 cm,
/// carriers, straps and packaging are not modelled.
struct StairTransport {
    enum Handling: String, Codable, CaseIterable { case upright, uprightSideways, tilted, tiltedSideways }
    enum Verdict: String { case possible, tight, blocked }
    enum Limit: String { case side, top, none }
    struct Pose {
        let distance: Double
        let handling: Handling
        let centre: StairVec              // box centre, world
        let along: StairVec, lateral: StairVec, up: StairVec  // box axes
        let size: StairVec                // extents along / lateral / up
        let clearance: Double             // ≥ 0 free space, < 0 overlap depth
        let limit: Limit
    }
    struct Object: Equatable { var width: Double, depth: Double, height: Double }

    let verdict: Verdict
    let poses: [Pose]
    let worst: Pose
    let handlings: [Handling]          // in walking order, without repeats
    static let tolerance = 0.03

    init?(profile: StairProfile, mesh: StairMesh, object: Object, margin: Double = 0.02, stride: Int = 2) {
        let st = profile.stations
        guard st.count >= 2, object.width > 0, object.depth > 0, object.height > 0 else { return nil }
        // 3 cm voxels keep the check fast on dense meshes.
        var seen = Set<Int64>(), pts: [StairVec] = []
        for i in 0..<mesh.vertexCount {
            let p = mesh.position(i)
            let ix: Int64 = Int64(Foundation.floor(p.x / 0.03)) & 0x1FFFFF
            let iy: Int64 = Int64(Foundation.floor(p.y / 0.03)) & 0x1FFFFF
            let iz: Int64 = Int64(Foundation.floor(p.z / 0.03)) & 0x1FFFFF
            let key: Int64 = ix | (iy << 21) | (iz << 42)
            if seen.insert(key).inserted { pts.append(p) }
        }
        let grid = StairPointGrid(xs: pts.map(\.x), zs: pts.map(\.z), cell: 0.25)
        let reach = sqrt(pow(max(object.width, object.depth, object.height) / 2, 2) * 2) + 0.5

        func index(from i: Int, offset: Double) -> Int {
            let target = st[i].distance + offset
            var j = i
            if offset < 0 { while j > 0 && st[j].distance > target { j -= 1 } } else { while j < st.count - 1 && st[j].distance < target { j += 1 } }
            return j
        }

        var poses: [Pose] = []
        for i in Swift.stride(from: 0, to: st.count, by: max(1, stride)) {
            let origin = StairVec(st[i].x, st[i].floor, st[i].z)
            var near: [StairVec] = []
            grid.near(x: origin.x, z: origin.z, radius: reach) { k in near.append(pts[k] - origin) }
            var best: Pose?
            for handling in Handling.allCases {
                let tilted = handling == .tilted || handling == .tiltedSideways
                let sideways = handling == .uprightSideways || handling == .tiltedSideways
                // (along, lateral, up) extents of the box.
                let size: StairVec
                switch (tilted, sideways) {
                case (false, false): size = .init(object.depth, object.width, object.height)
                case (false, true): size = .init(object.width, object.depth, object.height)
                case (true, false): size = .init(object.height, object.width, object.depth)
                case (true, true): size = .init(object.height, object.depth, object.width)
                }
                let a = st[index(from: i, offset: -size.x / 2)], b = st[index(from: i, offset: size.x / 2)]
                var chord = StairVec(b.x - a.x, 0, b.z - a.z).normalized
                if chord.length == 0 { chord = StairVec(sin(st[i].heading), 0, -cos(st[i].heading)) }
                let run = hypot(b.x - a.x, b.z - a.z)
                let pitch = tilted ? atan2(b.floor - a.floor, max(run, 1e-6)) : 0
                for yawDegrees in [0.0, -10, 10, -20, 20] {
                    for factor in tilted ? [1.0, 0.7, 0.4] : [1.0] {
                        let yaw = yawDegrees * .pi / 180, p = pitch * factor
                        let h = StairVec(chord.x * cos(yaw) - chord.z * sin(yaw), 0, chord.x * sin(yaw) + chord.z * cos(yaw))
                        let along = StairVec(h.x * cos(p), sin(p), h.z * cos(p)).normalized
                        let lateral = StairVec(-h.z, 0, h.x).normalized
                        var up = lateral.cross(along)
                        if up.y < 0 { up = up * -1 }
                        for shift in [0, -0.1, 0.1] {
                            let o = lateral * shift
                            let candidate = Self.evaluate(near: near, offset: o, along: along, lateral: lateral, up: up, size: size)
                            let pose = Pose(distance: st[i].distance, handling: handling,
                                            centre: origin + o + up * (candidate.base + size.z / 2),
                                            along: along, lateral: lateral, up: up, size: size,
                                            clearance: candidate.clearance, limit: candidate.limit)
                            if let current = best {
                                // Prefer the simplest handling that has enough room.
                                let currentOK = current.clearance >= margin, poseOK = pose.clearance >= margin
                                if poseOK && !currentOK { best = pose }
                                else if poseOK == currentOK && !currentOK && pose.clearance > current.clearance + 1e-9 { best = pose }
                            } else { best = pose }
                        }
                    }
                }
            }
            poses.append(best!)
        }
        let worst = poses.min { $0.clearance < $1.clearance }!
        self.poses = poses
        self.worst = worst
        self.verdict = worst.clearance >= margin ? .possible : worst.clearance >= -Self.tolerance ? .tight : .blocked
        var list: [Handling] = []
        for p in poses where list.last != p.handling { list.append(p.handling) }
        self.handlings = list
    }

    /// Clearance of one box pose against nearby points (relative to the station).
    static func evaluate(near: [StairVec], offset: StairVec, along: StairVec, lateral: StairVec, up: StairVec, size: StairVec) -> (clearance: Double, base: Double, limit: Limit) {
        let hl = size.x / 2, hw = size.y / 2, height = size.z
        var local: [(Double, Double, Double)] = []
        local.reserveCapacity(near.count)
        var lift = -0.6
        for q in near {
            let d = q - offset
            let a = d.dot(along), l = d.dot(lateral), u = d.dot(up)
            local.append((a, l, u))
            // Resting on the highest tread / floor point under the footprint.
            if abs(a) <= hl && abs(l) <= hw && u >= -0.6 && u <= 0.3 && u > lift { lift = u }
        }
        if lift == -0.6 { lift = 0 }
        let base = lift + 0.01, top = base + height, mid = (base + top) / 2
        var clearance = 1.0, limit = Limit.none
        for (a, l, u) in local where u >= base + 0.02 {
            let qx = abs(a) - hl, qy = abs(l) - hw, qz = abs(u - mid) - height / 2
            let outside = sqrt(pow(max(qx, 0), 2) + pow(max(qy, 0), 2) + pow(max(qz, 0), 2))
            let sd = outside + min(max(qx, qy, qz), 0)
            if sd < clearance {
                clearance = sd
                // The face the point is closest to (inside) or furthest beyond (outside).
                limit = qz >= qx && qz >= qy && u > mid ? .top : .side
            }
        }
        return (clearance, base, limit)
    }
}

/// `stairs.json` of one stair scan (mesh in `mesh.bin` next to it).
struct StairScanDocument: Codable {
    var format = "kantura-stair-scan"
    var version = 1
    var name: String
    let createdAt: String
    let id: String
    var units = "m"
    var building: RoomPlanDocument.Building?
    /// Camera positions while walking (x, y, z), at least 5 cm apart.
    var path: [[Double]]
    var profile: StairProfile
    static let fileName = "stairs.json"

    enum ValidationError: Error { case invalid }
    func validate() throws {
        guard format == "kantura-stair-scan", version == 1, units == "m", !name.isEmpty, name.count <= 200, !id.isEmpty,
              path.count <= 20000, path.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }),
              profile.stations.count <= 20000 else { throw ValidationError.invalid }
        if let b = building, ![b.name, b.floor, b.room].allSatisfy({ !$0.isEmpty && $0.count <= 200 }) { throw ValidationError.invalid }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct SavedStairScan {
    let document: StairScanDocument
    let folder: URL
    var jsonURL: URL { folder.appendingPathComponent(StairScanDocument.fileName) }
    var meshURL: URL { folder.appendingPathComponent(StairMesh.fileName) }
    var displayName: String { document.building?.room ?? document.name }

    static func directory(in documents: URL) -> URL { documents.appendingPathComponent("KanturaStairs", isDirectory: true) }

    static func load(from directory: URL) -> [SavedStairScan] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> SavedStairScan? in
            let json = folder.appendingPathComponent(StairScanDocument.fileName)
            guard let size = try? json.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1024 * 1024,
                  let data = try? Data(contentsOf: json),
                  let document = try? JSONDecoder().decode(StairScanDocument.self, from: data),
                  (try? document.validate()) != nil else { return nil }
            return SavedStairScan(document: document, folder: folder)
        }.sorted { $0.document.createdAt > $1.document.createdAt }
    }

    static func save(_ document: StairScanDocument, mesh: StairMesh, in directory: URL) throws -> SavedStairScan {
        try document.validate()
        let folder = directory.appendingPathComponent(document.id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try mesh.encoded().write(to: folder.appendingPathComponent(StairMesh.fileName), options: .atomic)
        try document.encoded().write(to: folder.appendingPathComponent(StairScanDocument.fileName), options: .atomic)
        return SavedStairScan(document: document, folder: folder)
    }

    func loadMesh() throws -> StairMesh { try StairMesh(data: Data(contentsOf: meshURL)) }

    /// Run the current analysis again on the stored walk and mesh, and save it.
    func reanalyzed(mesh: StairMesh) throws -> SavedStairScan {
        var updated = document
        updated.profile = try StairAnalyzer.analyze(mesh: mesh, path: document.path.map { StairVec($0[0], $0[1], $0[2]) })
        try updated.validate()
        try updated.encoded().write(to: jsonURL, options: .atomic)
        return SavedStairScan(document: updated, folder: folder)
    }

    func relabeled(name: String, apartment: String, floor: String) throws -> SavedStairScan {
        var updated = document
        updated.name = name
        updated.building = LibraryLabels.building(room: name, apartment: apartment, floor: floor)
        try updated.validate()
        try updated.encoded().write(to: jsonURL, options: .atomic)
        return SavedStairScan(document: updated, folder: folder)
    }
}

/// Shared rules for naming scans and assigning them to an apartment and floor.
enum LibraryLabels {
    static let placeholder = "–"
    static func building(room: String, apartment: String, floor: String) -> RoomPlanDocument.Building? {
        let a = apartment.trimmingCharacters(in: .whitespacesAndNewlines), f = floor.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty && f.isEmpty { return nil }
        return RoomPlanDocument.Building(name: String((a.isEmpty ? placeholder : a).prefix(200)), floor: String((f.isEmpty ? placeholder : f).prefix(200)), room: String(room.prefix(200)))
    }
    /// Group title on the start screen ("" = not assigned).
    static func group(_ building: RoomPlanDocument.Building?) -> String {
        guard let b = building else { return "" }
        return [b.name, b.floor].filter { $0 != placeholder }.joined(separator: " · ")
    }
}
