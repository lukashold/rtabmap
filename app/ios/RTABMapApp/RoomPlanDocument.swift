import Foundation

/// Portable, metre-based interchange. Matrices retain RoomPlan's column-major
/// local-to-world convention; polygon corners are in the surface's local plane.
struct RoomPlanDocument: Codable {
    struct Building: Codable {
        let name: String
        let floor: String
        let room: String
    }
    struct CoordinateSystem: Codable {
        var upAxis = "y"
        var handedness = "right"
        var matrixOrder = "column-major"
    }
    struct Surface: Codable {
        let id: String
        let kind: String
        let dimensions: [Double]
        let transform: [Double]
        let confidence: String
        let polygonCorners: [[Double]]?

        var polygonArea: Double? {
            guard let corners = polygonCorners, corners.count >= 3,
                  corners.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { return nil }
            // Newell's area vector also handles concave planar polygons. Rigid
            // RoomPlan transforms preserve this area, so no world-axis guess is needed.
            var normal = [0.0, 0.0, 0.0]
            for index in corners.indices {
                let a = corners[index], b = corners[(index + 1) % corners.count]
                normal[0] += (a[1] - b[1]) * (a[2] + b[2])
                normal[1] += (a[2] - b[2]) * (a[0] + b[0])
                normal[2] += (a[0] - b[0]) * (a[1] + b[1])
            }
            let area = sqrt(normal.reduce(0) { $0 + $1 * $1 }) / 2
            return area.isFinite && area > 0 ? area : nil
        }
    }

    var format = "kantura-room-plan"
    var version = 1
    let name: String
    let createdAt: String
    let roomId: String
    var units = "m"
    var coordinateSystem = CoordinateSystem()
    let surfaces: [Surface]
    var building: Building? = nil

    enum ValidationError: Error { case invalidDocument, invalidSurface, tooComplex }

    func validate() throws {
        guard surfaces.count <= 150,
              surfaces.allSatisfy({ ($0.polygonCorners?.count ?? 0) <= 100 }) else {
            throw ValidationError.tooComplex
        }
        guard format == "kantura-room-plan", version == 1, units == "m",
              coordinateSystem.upAxis == "y", coordinateSystem.handedness == "right",
              coordinateSystem.matrixOrder == "column-major", !name.isEmpty,
              name.count <= 200, !roomId.isEmpty, !surfaces.isEmpty else {
            throw ValidationError.invalidDocument
        }
        var ids = Set<String>()
        if let building = building {
            guard [building.name, building.floor, building.room].allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else {
                throw ValidationError.invalidDocument
            }
        }
        for surface in surfaces {
            guard !surface.id.isEmpty, ids.insert(surface.id).inserted,
                  ["wall", "door", "window", "opening", "floor"].contains(surface.kind),
                  ["high", "medium", "low", "unknown"].contains(surface.confidence),
                  surface.dimensions.count == 3,
                  surface.dimensions.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  surface.transform.count == 16, surface.transform.allSatisfy(\.isFinite),
                  abs(surface.transform[15] - 1) < 0.001 else {
                throw ValidationError.invalidSurface
            }
            if let polygon = surface.polygonCorners {
                guard polygon.count >= 3,
                      polygon.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else {
                    throw ValidationError.invalidSurface
                }
            }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct SavedRoomPlan {
    let document: RoomPlanDocument
    let jsonURL: URL
    let modelURL: URL

    static func exportStem(name: String, identifier: UUID) -> String {
        let safe = name.prefix(60).unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "-"
        }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return (safe.isEmpty ? "room" : safe) + "-" + String(identifier.uuidString.prefix(8))
    }

    static func load(from directory: URL) -> [SavedRoomPlan] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> SavedRoomPlan? in
            guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
            let manifests = contents.filter { $0.lastPathComponent.hasSuffix(".kantura-room.json") }
            guard manifests.count == 1, let json = manifests.first else { return nil }
            let model = folder.appendingPathComponent(String(json.lastPathComponent.dropLast(".kantura-room.json".count)) + ".usdz")
            guard FileManager.default.fileExists(atPath: model.path),
                  let size = try? json.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 10 * 1024 * 1024,
                  let data = try? Data(contentsOf: json),
                  let document = try? JSONDecoder().decode(RoomPlanDocument.self, from: data),
                  (try? document.validate()) != nil else { return nil }
            return SavedRoomPlan(document: document, jsonURL: json, modelURL: model)
        }.sorted { $0.document.createdAt > $1.document.createdAt }
    }
}

/// Keeps late RoomPlan callbacks from reviving a cancelled or failed session.
struct RoomPlanLifecycle {
    enum Phase { case ready, authorizing, capturing, processing, review, exporting, failed, cancelled }
    private(set) var phase: Phase = .ready

    @discardableResult mutating func authorize() -> Bool {
        guard phase == .ready else { return false }
        phase = .authorizing
        return true
    }
    @discardableResult mutating func start() -> Bool {
        guard phase == .authorizing else { return false }
        phase = .capturing
        return true
    }
    @discardableResult mutating func finish() -> Bool {
        guard phase == .capturing else { return false }
        phase = .processing
        return true
    }
    @discardableResult mutating func processed() -> Bool {
        guard phase == .processing else { return false }
        phase = .review
        return true
    }
    @discardableResult mutating func export() -> Bool {
        guard phase == .review else { return false }
        phase = .exporting
        return true
    }
    mutating func exported() { if phase == .exporting { phase = .review } }
    mutating func fail() { if phase != .cancelled { phase = .failed } }
    mutating func cancel() { phase = .cancelled }
}
