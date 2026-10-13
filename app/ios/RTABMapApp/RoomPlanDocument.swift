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

        struct Measurement: Equatable {
            enum Kind: Equatable { case width, height, area }
            let kind: Kind
            let value: Double
            var unit: String { kind == .area ? "m²" : "m" }
        }

        /// Architectural surfaces use local X for width and local Y for height;
        /// these are bounding extents, not necessarily a rectangular outline.
        /// Never present local Z as measured wall/floor thickness. Floors require
        /// their detected polygon, rather than a bounding-box area estimate.
        /// Bounds/polygon contract (Apple documentation):
        /// https://developer.apple.com/documentation/roomplan/capturedroom/surface/dimensions
        /// https://developer.apple.com/documentation/roomplan/capturedroom/surface/polygoncorners
        /// Additional local-axis example from an independent developer, not an
        /// Apple API guarantee: https://developer.apple.com/forums/thread/713409
        var displayMeasurements: [Measurement] {
            if kind == "floor" {
                guard let area = polygonArea else { return [] }
                return [Measurement(kind: .area, value: area)]
            }
            guard ["wall", "door", "window", "opening"].contains(kind),
                  dimensions.count == 3,
                  dimensions.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return [] }
            return [Measurement(kind: .width, value: dimensions[0]),
                    Measurement(kind: .height, value: dimensions[1])]
        }

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
    /// Detected furniture and fixtures (for example `stairs`, `refrigerator`) as
    /// oriented boxes. Dimensions are the box extents in metres, not a shape.
    var objects: [Object]? = nil
    /// Manual corrections by the user: surface id → new kind ("wall", "door",
    /// "window", "opening") or "deleted". The detected surfaces stay unchanged
    /// in the file so a correction can always be undone.
    var corrections: [String: String]? = nil

    static let correctionKinds = ["wall", "door", "window", "opening", "deleted"]

    /// The room as the user corrected it (used for display, areas and exports).
    func applyingCorrections() -> RoomPlanDocument {
        guard let corrections = corrections, !corrections.isEmpty else { return self }
        // An opening that sits inside a detected wall and is marked "wall" simply
        // closes that wall; it must not become a second, overlapping wall.
        let hosted = Set(RoomPlanGeometry.openingsByWall(self.surfaces).values.flatMap { $0.map(\.id) })
        let surfaces = self.surfaces.compactMap { s -> Surface? in
            guard let kind = corrections[s.id] else { return s }
            if kind == "deleted" { return nil }
            if kind == "wall" && hosted.contains(s.id) { return nil }
            // A floor is never re-classified; its outline is the area basis.
            guard s.kind != "floor", kind != s.kind else { return s }
            return Surface(id: s.id, kind: kind, dimensions: s.dimensions, transform: s.transform, confidence: s.confidence, polygonCorners: s.polygonCorners)
        }
        var corrected = RoomPlanDocument(name: name, createdAt: createdAt, roomId: roomId, surfaces: surfaces)
        corrected.building = building
        corrected.objects = objects
        corrected.corrections = corrections
        return corrected
    }

    struct Object: Codable, Equatable {
        let id: String
        let category: String
        let dimensions: [Double]
        let transform: [Double]
        let confidence: String
    }

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
        if let corrections = corrections {
            let known = Set(surfaces.map(\.id))
            guard corrections.count <= 150, corrections.allSatisfy({ known.contains($0.key) && Self.correctionKinds.contains($0.value) }) else {
                throw ValidationError.invalidSurface
            }
        }
        if let objects = objects {
            guard objects.count <= 150, objects.allSatisfy({ object in
                !object.id.isEmpty && object.category.range(of: "^[A-Za-z]{1,40}$", options: .regularExpression) != nil &&
                    object.dimensions.count == 3 && object.dimensions.allSatisfy({ $0.isFinite && $0 >= 0 }) &&
                    object.transform.count == 16 && object.transform.allSatisfy(\.isFinite) &&
                    ["high", "medium", "low", "unknown"].contains(object.confidence)
            }) else { throw ValidationError.invalidSurface }
        }
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
    /// The room with the user's corrections applied.
    let document: RoomPlanDocument
    let jsonURL: URL
    let modelURL: URL
    /// The file contents as stored (detection plus correction list).
    let original: RoomPlanDocument

    init(document: RoomPlanDocument, jsonURL: URL, modelURL: URL) {
        self.original = document
        self.document = document.applyingCorrections()
        self.jsonURL = jsonURL
        self.modelURL = modelURL
    }

    /// Store a correction (nil restores the detected kind) and return the reloaded room.
    func correcting(_ id: String, to kind: String?) throws -> SavedRoomPlan {
        var updated = original
        var list = updated.corrections ?? [:]
        let detected = original.surfaces.first { $0.id == id }?.kind
        if let kind = kind, kind != detected { list[id] = kind } else { list[id] = nil }
        updated.corrections = list.isEmpty ? nil : list
        try updated.encoded().write(to: jsonURL, options: .atomic)
        return SavedRoomPlan(document: updated, jsonURL: jsonURL, modelURL: modelURL)
    }

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
