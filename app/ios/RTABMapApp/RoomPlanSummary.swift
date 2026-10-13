import Foundation

/// Headline numbers for one captured room: floor area, gross and net wall area,
/// typical wall height and opening counts.
///
/// This is the native counterpart of `tools/scan-workspace/src/areas.js` and uses
/// the same rules, so a room shows the same values on the phone and in the
/// browser workspace:
/// - local X is width, local Y is height, local Z is the surface normal;
/// - a door/window/opening is deducted only from a parallel wall whose plane is
///   within 0.2 m and whose extent contains the opening centre;
/// - two almost equally close candidate walls are ambiguous and not deducted;
/// - openings past the wall edge are clipped; overlapping openings count once;
/// - a wall without a usable height has no gross area and marks totals incomplete.
/// Manual reassignment is a browser feature; the phone shows the automatic result.
struct RoomPlanSummary: Equatable {
    var floorArea: Double?
    var floorPerimeter: Double?
    var grossWallArea: Double
    var openingArea: Double
    var netWallArea: Double
    var wallHeight: Double?
    var walls: Int
    var doors: Int
    var windows: Int
    var openings: Int
    /// Openings that could not be assigned and therefore were not deducted.
    var unresolvedOpenings: Int
    /// At least one wall or floor has no usable geometry; totals are partial.
    var incomplete: Bool

    static let planeTolerance = 0.2, edgeTolerance = 0.05, parallelLimit = 0.9, ambiguity = 0.02

    init(_ document: RoomPlanDocument) {
        typealias Rect = (x0: Double, y0: Double, x1: Double, y1: Double)
        func column(_ m: [Double], _ c: Int) -> [Double] { [m[c * 4], m[c * 4 + 1], m[c * 4 + 2]] }
        func dot(_ a: [Double], _ b: [Double]) -> Double { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
        func world(_ p: [Double], _ m: [Double]) -> [Double] {
            [m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
             m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
             m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]]
        }
        func local(_ p: [Double], _ m: [Double]) -> [Double] {
            let d = [p[0] - m[12], p[1] - m[13], p[2] - m[14]]
            return [dot(d, column(m, 0)), dot(d, column(m, 1)), dot(d, column(m, 2))]
        }
        func area(_ r: Rect) -> Double { max(0, r.x1 - r.x0) * max(0, r.y1 - r.y0) }
        func intersect(_ a: Rect, _ b: Rect) -> Rect { (max(a.x0, b.x0), max(a.y0, b.y0), min(a.x1, b.x1), min(a.y1, b.y1)) }
        func shoelace(_ pts: [[Double]]) -> Double {
            var s = 0.0
            for i in pts.indices { let a = pts[i], b = pts[(i + 1) % pts.count]; s += a[0] * b[1] - b[0] * a[1] }
            return abs(s) / 2
        }
        func inside(_ p: [Double], _ polygon: [[Double]]) -> Bool {
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count], dx = b[0] - a[0], dy = b[1] - a[1], len = dx * dx + dy * dy
                let t = len > 0 ? max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len)) : 0
                if hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy) <= 1e-6 { return true }
            }
            var result = false
            var j = polygon.count - 1
            for i in polygon.indices {
                let a = polygon[i], b = polygon[j]
                if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0] { result.toggle() }
                j = i
            }
            return result
        }

        struct Wall { let surface: RoomPlanDocument.Surface; let outline: [[Double]]; let bounds: Rect; let gross: Double?; let rectangular: Bool }
        let usable = document.surfaces.filter { $0.dimensions.count == 3 && $0.transform.count == 16 }
        let walls: [Wall] = usable.filter { $0.kind == "wall" }.map { s in
            let w = s.dimensions[0], h = s.dimensions[1]
            let outline = s.polygonCorners.map { $0.map { [$0[0], $0[1]] } } ?? [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]
            let xs = outline.map { $0[0] }, ys = outline.map { $0[1] }
            let bounds: Rect = (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
            var gross: Double?
            if let corners = s.polygonCorners {
                let value = shoelace(outline)
                gross = corners.allSatisfy({ abs($0[2]) <= 0.03 }) && value > 1e-9 ? value : nil
            } else if h > 1e-9 && w > 1e-9 { gross = w * h }
            return Wall(surface: s, outline: outline, bounds: bounds, gross: gross, rectangular: s.polygonCorners == nil)
        }
        var placed = Array(repeating: [Rect](), count: walls.count)
        var unresolved = 0
        for s in usable where ["door", "window", "opening"].contains(s.kind) {
            let w = s.dimensions[0], h = s.dimensions[1]
            guard w * h > 1e-9 else { unresolved += 1; continue }
            let center = world([0, 0, 0], s.transform), normal = column(s.transform, 2)
            let candidates = walls.indices.compactMap { index -> (Int, Double)? in
                let wall = walls[index], p = local(center, wall.surface.transform), b = wall.bounds, e = Self.edgeTolerance
                guard abs(dot(normal, column(wall.surface.transform, 2))) >= Self.parallelLimit, abs(p[2]) <= Self.planeTolerance,
                      p[0] >= b.x0 - e, p[0] <= b.x1 + e, p[1] >= b.y0 - e, p[1] <= b.y1 + e else { return nil }
                return (index, abs(p[2]))
            }.sorted { $0.1 < $1.1 }
            guard let best = candidates.first, candidates.count == 1 || candidates[1].1 - best.1 >= Self.ambiguity else { unresolved += 1; continue }
            let wall = walls[best.0]
            let corners = [[-w / 2, -h / 2, 0], [w / 2, -h / 2, 0], [w / 2, h / 2, 0], [-w / 2, h / 2, 0]].map { local(world($0, s.transform), wall.surface.transform) }
            let raw: Rect = (corners.map { $0[0] }.min()!, corners.map { $0[1] }.min()!, corners.map { $0[0] }.max()!, corners.map { $0[1] }.max()!)
            let clipped = intersect(raw, wall.bounds)
            guard area(clipped) > 1e-9, wall.gross != nil else { unresolved += 1; continue }
            if !wall.rectangular {
                let check = [[clipped.x0, clipped.y0], [clipped.x1, clipped.y0], [clipped.x1, clipped.y1], [clipped.x0, clipped.y1]]
                guard check.allSatisfy({ inside($0, wall.outline) }) else { unresolved += 1; continue }
            }
            placed[best.0].append(clipped)
        }
        func union(_ rects: [Rect]) -> Double {
            let live = rects.filter { area($0) > 1e-9 }
            let xs = Array(Set(live.flatMap { [$0.x0, $0.x1] })).sorted()
            var total = 0.0
            for i in 0..<max(0, xs.count - 1) {
                let x0 = xs[i], x1 = xs[i + 1]
                let spans = live.filter { $0.x0 <= x0 && $0.x1 >= x1 }.map { ($0.y0, $0.y1) }.sorted { $0.0 < $1.0 }
                var covered = 0.0, start = -Double.infinity, end = -Double.infinity
                for (s, e) in spans {
                    if s > end { if end > start { covered += end - start }; start = s; end = e } else { end = max(end, e) }
                }
                if end > start { covered += end - start }
                total += covered * (x1 - x0)
            }
            return total
        }
        var gross = 0.0, openingArea = 0.0
        for (index, wall) in walls.enumerated() {
            guard let value = wall.gross else { continue }
            gross += value
            openingArea += min(value, union(placed[index]))
        }
        let floors = usable.filter { $0.kind == "floor" }
        let floorAreas = floors.map { floor -> Double? in
            guard let corners = floor.polygonCorners, corners.allSatisfy({ abs($0[2]) <= 0.03 }) else { return nil }
            let value = shoelace(corners.map { [$0[0], $0[1]] })
            return value > 1e-9 ? value : nil
        }
        let knownFloors = floorAreas.compactMap { $0 }
        floorArea = knownFloors.isEmpty ? nil : knownFloors.reduce(0, +)
        if floors.count == 1, knownFloors.count == 1, let corners = floors[0].polygonCorners {
            floorPerimeter = corners.indices.reduce(0) { sum, i in
                let a = corners[i], b = corners[(i + 1) % corners.count]
                return sum + hypot(b[0] - a[0], b[1] - a[1])
            }
        }
        grossWallArea = gross
        self.openingArea = openingArea
        netWallArea = max(0, gross - openingArea)
        // Median of the detected wall heights: robust against one low partition wall.
        let heights = walls.map { $0.surface.dimensions[1] }.filter { $0 > 0.5 }.sorted()
        wallHeight = heights.isEmpty ? nil : heights.count % 2 == 1 ? heights[heights.count / 2] : (heights[heights.count / 2 - 1] + heights[heights.count / 2]) / 2
        self.walls = walls.count
        doors = usable.filter { $0.kind == "door" }.count
        windows = usable.filter { $0.kind == "window" }.count
        openings = usable.filter { $0.kind == "opening" }.count
        unresolvedOpenings = unresolved
        incomplete = walls.contains { $0.gross == nil } || floors.isEmpty || knownFloors.count != floors.count
    }
}
