import Foundation

/// Conservative envelope check for carrying a rectangular appliance along a
/// straight passage, up/down a stair slope and around a centred landing turn.
/// Native port of `tools/scan-workspace/src/transport.js`, same rules and
/// verdicts. Dimensions are metres; returned angles are degrees.
/// It is NOT a collision-free route planner: steps, handrails, carriers and
/// people are not modelled.
struct TransportAssessment {
    struct Object { var width: Double; var depth: Double; var height: Double }
    struct Route {
        var width: Double          // narrowest clear passage width
        var ceiling: Double        // clear height
        var landingWidth: Double
        var landingDepth: Double
        var rise: Double           // one step or a whole straight flight, consistent with run
        var run: Double
        var turnDegrees: Double
    }
    struct Sample { let phase: String; let yaw: Double; let tilt: Double; let width: Double; let depth: Double; let height: Double }
    struct Scenario {
        let id: String
        let sideways: Bool
        let tilt: Double
        let fits: Bool
        let clearances: [String: Double]
        let minimumClearance: Double
        let samples: [Sample]
        let envelope: (width: Double, depth: Double, height: Double)
    }
    enum Verdict: String { case possible, uncertain, blocked }
    enum InputError: Error, Equatable { case invalid(String) }

    let verdict: Verdict
    let reasons: [String]
    let stairAngle: Double
    let chosen: Scenario
    let scenarios: [Scenario]

    private static let eps = 1e-9, rad = Double.pi / 180

    init(object: Object, route: Route, margin: Double = 0, allowTilt: Bool = false) throws {
        func check(_ value: Double, _ min: Double, _ max: Double, _ field: String) throws {
            guard value.isFinite, value >= min, value <= max else { throw InputError.invalid(field) }
        }
        try check(object.width, 0.001, 20, "object.width"); try check(object.depth, 0.001, 20, "object.depth"); try check(object.height, 0.001, 20, "object.height")
        for (value, field) in [(route.width, "route.width"), (route.ceiling, "route.ceiling"), (route.landingWidth, "route.landingWidth"), (route.landingDepth, "route.landingDepth"), (route.run, "route.run")] {
            try check(value, 0.001, 100, field)
        }
        try check(route.rise, 0, 100, "route.rise"); try check(route.turnDegrees, -180, 180, "route.turnDegrees"); try check(margin, 0, 2, "margin")

        let angle = atan2(route.rise, route.run)
        var list = [Self.scenario(object, route, margin, false, 0, "upright"), Self.scenario(object, route, margin, true, 0, "upright-sideways")]
        if allowTilt && angle > Self.eps {
            list += [Self.scenario(object, route, margin, false, angle, "stair-tilt"), Self.scenario(object, route, margin, true, angle, "stair-tilt-sideways")]
        }
        // Prefer the simplest fitting handling orientation, then the least deficit.
        let best = list.first(where: { $0.fits }) ?? list.sorted { $0.minimumClearance > $1.minimumClearance }[0]
        let smallest = min(object.width, object.depth, object.height)
        var reasons: [String] = []
        if smallest + 2 * margin > route.width + Self.eps { reasons.append("corridor_narrower_than_smallest_dimension") }
        if smallest + 2 * margin > route.ceiling + Self.eps { reasons.append("ceiling_lower_than_smallest_dimension") }
        let verdict: Verdict
        if !reasons.isEmpty { verdict = .blocked }
        else if best.fits { verdict = .possible; reasons.append(best.tilt > 0 ? "tilted_envelope_fits" : "upright_envelope_fits") }
        else {
            verdict = .uncertain
            reasons.append("no_tested_orientation_fits")
            if (best.clearances["corridorWidth"] ?? 0) < -Self.eps { reasons.append("corridor_clearance_insufficient") }
            if (best.clearances["ceiling"] ?? 0) < -Self.eps { reasons.append("ceiling_clearance_insufficient") }
            if (best.clearances["landingWidth"] ?? 0) < -Self.eps || (best.clearances["landingDepth"] ?? 0) < -Self.eps { reasons.append("landing_requires_path_planning") }
        }
        self.verdict = verdict
        self.reasons = reasons
        self.stairAngle = angle / Self.rad
        self.chosen = best
        self.scenarios = list
    }

    private static func angles(_ start: Double, _ end: Double, _ critical: [Double] = []) -> [Double] {
        let lower = min(start, end), upper = max(start, end)
        let count = max(1, Int(ceil((upper - lower) / (5 * rad))))
        var result = (0...count).map { lower + (upper - lower) * Double($0) / Double(count) }
        for angle in critical where angle >= lower - eps && angle <= upper + eps { result.append(min(upper, max(lower, angle))) }
        return Array(Set(result)).sorted()
    }

    private static func yawCandidates(_ a: Double, _ b: Double, _ end: Double) -> [Double] {
        let peak = atan2(b, a)
        var critical: [Double] = []
        for k in -4...4 { critical += [Double(k) * .pi / 2, peak + Double(k) * .pi, -peak + Double(k) * .pi] }
        return angles(0, end, critical)
    }

    private static func projection(_ a: Double, _ b: Double, _ angle: Double) -> Double { a * abs(cos(angle)) + b * abs(sin(angle)) }
    private static func maximumProjection(_ a: Double, _ b: Double, _ end: Double) -> Double {
        yawCandidates(a, b, end).map { projection(a, b, $0) }.max() ?? 0
    }

    private static func scenario(_ object: Object, _ route: Route, _ margin: Double, _ sideways: Bool, _ tilt: Double, _ id: String) -> Scenario {
        let width = sideways ? object.depth : object.width
        let depth = sideways ? object.width : object.depth
        let turn = route.turnDegrees * rad
        let hasTurn = abs(turn) > eps
        // Tilt about the lateral axis: width unchanged, depth and height projected.
        let tiltAngles = angles(0, tilt, [atan2(object.height, depth), atan2(depth, object.height)])
        let maxDepth = tiltAngles.map { projection(depth, object.height, $0) }.max()!
        let maxHeight = tiltAngles.map { projection(object.height, depth, $0) }.max()!
        let fixedDepth = projection(depth, object.height, tilt)
        let fixedHeight = projection(object.height, depth, tilt)
        let yaws = Array(Set(yawCandidates(width, maxDepth, turn) + yawCandidates(maxDepth, width, turn))).sorted()
        var clearances = ["corridorWidth": route.width - width - 2 * margin, "ceiling": route.ceiling - maxHeight - 2 * margin]
        // A centred turn occupying this entire rectangular landing is sufficient,
        // not necessary: a translated turn may succeed when these bounds fail.
        if hasTurn || tilt > eps {
            clearances["landingWidth"] = route.landingWidth - maximumProjection(width, maxDepth, turn) - 2 * margin
            clearances["landingDepth"] = route.landingDepth - maximumProjection(maxDepth, width, turn) - 2 * margin
        }
        var samples = yaws.map { a in
            Sample(phase: "turn", yaw: a / rad, tilt: tilt / rad, width: projection(width, fixedDepth, a), depth: projection(fixedDepth, width, a), height: fixedHeight)
        }
        if tilt > eps {
            for a in tiltAngles { for yaw in hasTurn ? [0, turn] : [0] {
                let d = projection(depth, object.height, a)
                samples.append(Sample(phase: "tilt-transition", yaw: yaw / rad, tilt: a / rad, width: projection(width, d, yaw), depth: projection(d, width, yaw), height: projection(object.height, depth, a)))
            } }
        }
        let minimum = clearances.values.min() ?? 0
        return Scenario(id: id, sideways: sideways, tilt: tilt / rad, fits: clearances.values.allSatisfy { $0 >= -eps },
                        clearances: clearances, minimumClearance: minimum, samples: samples,
                        envelope: (maximumProjection(width, maxDepth, turn), maximumProjection(maxDepth, width, turn), maxHeight))
    }
}

/// Small verified offline catalogue (same entries as the browser workspace).
/// Manufacturer-listed unpacked dimensions; packaging, handles and permitted
/// transport positions must be checked for the actual device.
struct TransportAppliance {
    let brand: String, model: String, width: Double, depth: Double, height: Double, note: String
    static let catalog = [
        TransportAppliance(brand: "Bosch", model: "KGN39VLEA", width: 0.600, depth: 0.660, height: 2.030, note: "bosch-home.com, 2026-10-11"),
        TransportAppliance(brand: "Samsung", model: "RB34C600ESA/EF", width: 0.595, depth: 0.658, height: 1.853, note: "samsung.com/at, 2026-10-11 · depth without handle"),
        TransportAppliance(brand: "LG", model: "GBP62PZNAC", width: 0.595, depth: 0.675, height: 2.030, note: "lg.com/at, 2026-10-11")
    ]
}

/// Dimension suggestions read from saved room scans.
struct TransportScanSuggestion: Equatable {
    enum Kind: String { case door, stairs, roomHeight }
    let kind: Kind
    let room: String
    let width: Double
    let height: Double
    let length: Double

    static func collect(from documents: [RoomPlanDocument]) -> [TransportScanSuggestion] {
        var result: [TransportScanSuggestion] = []
        for document in documents {
            let room = document.building?.room ?? document.name
            for door in document.surfaces where (door.kind == "door" || door.kind == "opening") && door.dimensions.count == 3 && door.dimensions[0] > 0.3 {
                result.append(.init(kind: .door, room: room, width: door.dimensions[0], height: door.dimensions[1], length: 0))
            }
            for stairs in document.objects ?? [] where stairs.category == "stairs" && stairs.dimensions.count == 3 {
                // Object box: x = width, y = total height, z = horizontal length.
                result.append(.init(kind: .stairs, room: room, width: stairs.dimensions[0], height: stairs.dimensions[1], length: stairs.dimensions[2]))
            }
            if let height = RoomPlanSummary(document).wallHeight {
                result.append(.init(kind: .roomHeight, room: room, width: 0, height: height, length: 0))
            }
        }
        // Narrowest doors first: they usually limit the route.
        return result.sorted { ($0.kind.rawValue, $0.width) < ($1.kind.rawValue, $1.width) }
    }
}
