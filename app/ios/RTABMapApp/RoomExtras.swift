import Foundation

/// Things the user adds to a scanned room: markers (defects, questions, ideas,
/// things to measure — for showing a builder where something is) and furniture.
/// Stored next to the scan as `extras.json`; marker photos in `markers/`.
/// All positions are in the room's own coordinates (metres, y up).
struct RoomExtras: Codable, Equatable {
    struct Marker: Codable, Equatable {
        var id: String
        var kind: String            // defect, question, idea, measure
        var title: String
        var detail: String
        var status: String          // open, done
        var assignee: String
        var position: [Double]      // x, y, z
        var photo: String?          // markers/<id>.jpg
        var createdAt: String
        var updatedAt: String
    }
    struct Furniture: Codable, Equatable {
        var id: String
        var name: String
        var manufacturer: String
        var category: String
        var width: Double           // along local x
        var depth: Double           // along local z
        var height: Double
        var x: Double               // footprint centre on the floor
        var z: Double
        var rotation: Double        // radians about y
        var catalog: String?        // catalogue name it came from
        var url: String?            // product page
        var model: String?          // optional glTF/USDZ URL
    }
    var format = "kantura-room-extras"
    var version = 1
    var markers: [Marker] = []
    var furniture: [Furniture] = []

    static let fileName = "extras.json"
    static let markerKinds = ["defect", "question", "idea", "measure"]
    static let statuses = ["open", "done"]
    enum ValidationError: Error { case invalid }

    func validate() throws {
        guard format == "kantura-room-extras", version == 1, markers.count <= 500, furniture.count <= 300 else { throw ValidationError.invalid }
        var ids = Set<String>()
        func text(_ s: String, _ max: Int) -> Bool { s.count <= max && !s.contains("\u{0}") }
        for m in markers {
            guard ids.insert(m.id).inserted, m.id.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
                  Self.markerKinds.contains(m.kind), Self.statuses.contains(m.status),
                  text(m.title, 200), !m.title.trimmingCharacters(in: .whitespaces).isEmpty, text(m.detail, 4000), text(m.assignee, 200),
                  m.position.count == 3, m.position.allSatisfy({ $0.isFinite && abs($0) < 10000 }),
                  m.photo == nil || m.photo == "markers/\(m.id).jpg" else { throw ValidationError.invalid }
        }
        for f in furniture {
            guard ids.insert(f.id).inserted, f.id.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
                  text(f.name, 200), text(f.manufacturer, 200), text(f.category, 60),
                  [f.width, f.depth, f.height].allSatisfy({ $0.isFinite && $0 > 0.01 && $0 <= 20 }),
                  [f.x, f.z, f.rotation].allSatisfy({ $0.isFinite && abs($0) < 10000 }) else { throw ValidationError.invalid }
        }
    }

    static func load(from folder: URL) -> RoomExtras {
        let url = folder.appendingPathComponent(fileName)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: url), let extras = try? JSONDecoder().decode(RoomExtras.self, from: data),
              (try? extras.validate()) != nil else { return RoomExtras() }
        return extras
    }

    func write(to folder: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    static func newID() -> String { UUID().uuidString.lowercased() }
    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }
}

/// Open furniture catalogue format. Anyone — a manufacturer, a shop, the
/// community or the user — can publish one as a JSON file at any URL:
///
///     { "format": "kantura-furniture-catalog", "version": 1,
///       "name": "…", "publisher": "…", "homepage": "https://…", "license": "CC-BY-4.0",
///       "items": [ { "id": "…", "name": "…", "manufacturer": "…", "category": "sofa",
///                    "width": 2.1, "depth": 0.9, "height": 0.8,
///                    "url": "https://…", "model": "https://…/model.usdz", "modelLicense": "CC-BY-4.0" } ] }
///
/// Dimensions are metres (width along the front, depth front-to-back). Items
/// without a model are shown as boxes with the correct size.
struct FurnitureCatalog: Codable, Equatable {
    struct Item: Codable, Equatable {
        let id: String
        let name: String
        let manufacturer: String
        let category: String
        let width: Double
        let depth: Double
        let height: Double
        var url: String? = nil
        var model: String? = nil
        var modelLicense: String? = nil
    }
    var format = "kantura-furniture-catalog"
    var version = 1
    let name: String
    let publisher: String
    var homepage: String? = nil
    var license: String? = nil
    let items: [Item]

    static let categories = ["sofa", "bed", "table", "chair", "desk", "wardrobe", "shelf", "dresser", "kitchen", "appliance", "bath", "other"]
    enum ValidationError: Error { case invalid }

    func validate() throws {
        guard format == "kantura-furniture-catalog", version == 1, !name.isEmpty, name.count <= 120, publisher.count <= 120,
              items.count <= 5000 else { throw ValidationError.invalid }
        var ids = Set<String>()
        for item in items {
            guard ids.insert(item.id).inserted, !item.id.isEmpty, item.id.count <= 120, !item.name.isEmpty, item.name.count <= 200,
                  item.manufacturer.count <= 200, Self.categories.contains(item.category),
                  [item.width, item.depth, item.height].allSatisfy({ $0.isFinite && $0 > 0.01 && $0 <= 20 }),
                  [item.url, item.model].allSatisfy({ $0 == nil || ($0!.hasPrefix("https://") && $0!.count <= 2000) }) else { throw ValidationError.invalid }
        }
    }

    /// Generic, manufacturer-neutral starter catalogue (typical sizes).
    static let builtIn = FurnitureCatalog(name: "KANTURA", publisher: "KANTURA", license: "BSD-3-Clause", items: [
        .init(id: "sofa-3", name: "Sofa 3-seat", manufacturer: "", category: "sofa", width: 2.10, depth: 0.90, height: 0.80),
        .init(id: "sofa-corner", name: "Corner sofa", manufacturer: "", category: "sofa", width: 2.70, depth: 1.70, height: 0.80),
        .init(id: "bed-140", name: "Bed 140 × 200", manufacturer: "", category: "bed", width: 1.45, depth: 2.10, height: 0.45),
        .init(id: "bed-180", name: "Bed 180 × 200", manufacturer: "", category: "bed", width: 1.85, depth: 2.10, height: 0.45),
        .init(id: "table-6", name: "Dining table (6)", manufacturer: "", category: "table", width: 1.80, depth: 0.90, height: 0.75),
        .init(id: "chair", name: "Chair", manufacturer: "", category: "chair", width: 0.45, depth: 0.52, height: 0.90),
        .init(id: "desk", name: "Desk", manufacturer: "", category: "desk", width: 1.40, depth: 0.70, height: 0.74),
        .init(id: "wardrobe-2", name: "Wardrobe 2 doors", manufacturer: "", category: "wardrobe", width: 1.00, depth: 0.60, height: 2.00),
        .init(id: "wardrobe-4", name: "Wardrobe 4 doors", manufacturer: "", category: "wardrobe", width: 2.00, depth: 0.60, height: 2.20),
        .init(id: "shelf", name: "Shelf", manufacturer: "", category: "shelf", width: 0.80, depth: 0.35, height: 1.80),
        .init(id: "dresser", name: "Chest of drawers", manufacturer: "", category: "dresser", width: 0.80, depth: 0.45, height: 0.90),
        .init(id: "kitchen-60", name: "Kitchen base unit 60", manufacturer: "", category: "kitchen", width: 0.60, depth: 0.60, height: 0.90),
        .init(id: "fridge", name: "Fridge-freezer", manufacturer: "", category: "appliance", width: 0.60, depth: 0.66, height: 2.03),
        .init(id: "washer", name: "Washing machine", manufacturer: "", category: "appliance", width: 0.60, depth: 0.60, height: 0.85),
        .init(id: "bathtub", name: "Bathtub 170", manufacturer: "", category: "bath", width: 1.70, depth: 0.75, height: 0.58)
    ] + TransportAppliance.catalog.map {
        .init(id: "appliance-" + $0.model, name: $0.model, manufacturer: $0.brand, category: "appliance", width: $0.width, depth: $0.depth, height: $0.height)
    })
}

/// Footprint checks for placed furniture (top view, room coordinates x/z).
enum FurnitureLayout {
    typealias P = (x: Double, z: Double)

    static func corners(_ f: RoomExtras.Furniture) -> [P] {
        let c = cos(f.rotation), s = sin(f.rotation), w = f.width / 2, d = f.depth / 2
        // SceneKit rotation about y: x' = x·c + z·s, z' = −x·s + z·c
        return [(-w, -d), (w, -d), (w, d), (-w, d)].map { (x: f.x + $0.0 * c + $0.1 * s, z: f.z - $0.0 * s + $0.1 * c) }
    }

    /// Separating-axis test for two convex polygons.
    static func overlap(_ a: [P], _ b: [P]) -> Bool {
        for poly in [a, b] {
            for i in poly.indices {
                let p = poly[i], q = poly[(i + 1) % poly.count]
                let axis = (x: -(q.z - p.z), z: q.x - p.x)
                let pa = a.map { $0.x * axis.x + $0.z * axis.z }, pb = b.map { $0.x * axis.x + $0.z * axis.z }
                if pa.max()! <= pb.min()! + 1e-6 || pb.max()! <= pa.min()! + 1e-6 { return false }
            }
        }
        return true
    }

    struct Conflicts: Equatable { var walls = 0; var doors = 0; var furniture = 0; var isEmpty: Bool { walls + doors + furniture == 0 } }

    /// Walls are 10 cm thick strips on the room side; doors need a square swing
    /// zone (door width × door width) in front of them on the room side.
    static func conflicts(of f: RoomExtras.Furniture, in document: RoomPlanDocument, others: [RoomExtras.Furniture]) -> Conflicts {
        let footprint = corners(f)
        var result = Conflicts()
        let walls = document.surfaces.filter { $0.kind == "wall" && $0.transform.count == 16 && $0.dimensions.count == 3 }
        let floorPoints = document.surfaces.filter { $0.kind == "floor" && $0.polygonCorners != nil }.flatMap { f in f.polygonCorners!.map { RoomPlanGeometry.world($0, f.transform) } }
        let centrePoints = floorPoints.isEmpty ? walls.map { RoomPlanGeometry.world([0, 0, 0], $0.transform) } : floorPoints
        let centre = (x: centrePoints.map { $0.x }.reduce(0, +) / Double(max(1, centrePoints.count)), z: centrePoints.map { $0.z }.reduce(0, +) / Double(max(1, centrePoints.count)))
        func strip(_ a: RoomPlanGeometry.Point, _ b: RoomPlanGeometry.Point, depth: Double) -> [P] {
            let dx = b.x - a.x, dz = b.z - a.z, l = max(1e-6, hypot(dx, dz))
            var nx = -dz / l, nz = dx / l
            let mid = ((a.x + b.x) / 2, (a.z + b.z) / 2)
            if nx * (centre.x - mid.0) + nz * (centre.z - mid.1) < 0 { nx = -nx; nz = -nz }
            return [(x: a.x, z: a.z), (x: b.x, z: b.z), (x: b.x + nx * depth, z: b.z + nz * depth), (x: a.x + nx * depth, z: a.z + nz * depth)]
        }
        let openings = RoomPlanGeometry.openingsByWall(document.surfaces)
        for wall in walls {
            let w = wall.dimensions[0], h = wall.dimensions[1]
            // Wall pieces between openings that reach the floor (doors) do not count as blocked.
            var free: [(Double, Double)] = [(-w / 2, w / 2)]
            for o in openings[wall.id] ?? [] where o.y0 <= -h / 2 + 0.15 {
                free = free.flatMap { seg -> [(Double, Double)] in
                    guard o.x1 > seg.0, o.x0 < seg.1 else { return [seg] }
                    return [(seg.0, max(seg.0, o.x0)), (min(seg.1, o.x1), seg.1)].filter { $0.1 - $0.0 > 0.01 }
                }
            }
            for seg in free {
                let p = RoomPlanGeometry.world([seg.0, -h / 2, 0], wall.transform), q = RoomPlanGeometry.world([seg.1, -h / 2, 0], wall.transform)
                if overlap(footprint, strip(p, q, depth: 0.02)) { result.walls += 1; break }
            }
            for o in openings[wall.id] ?? [] where o.kind == "door" {
                let p = RoomPlanGeometry.world([o.x0, -h / 2, 0], wall.transform), q = RoomPlanGeometry.world([o.x1, -h / 2, 0], wall.transform)
                if overlap(footprint, strip(p, q, depth: min(1.2, o.x1 - o.x0))) { result.doors += 1 }
            }
        }
        for other in others where other.id != f.id && overlap(footprint, corners(other)) { result.furniture += 1 }
        return result
    }
}

extension RoomPhotoProjection {
    /// The photo that shows a point best (facing it, centred, close), with the
    /// point's pixel position in that photo.
    static func bestPhoto(showing p: Vec3, photos: [RoomPhotoSet.Photo]) -> (index: Int, u: Double, v: Double)? {
        var best: (score: Double, index: Int, u: Double, v: Double)?
        for (index, photo) in photos.enumerated() {
            guard let q = project(p, photo: photo), q.u >= 0, q.v >= 0, q.u <= Double(photo.width), q.v <= Double(photo.height), q.depth < 8 else { continue }
            let du = (q.u / Double(photo.width) - 0.5), dv = (q.v / Double(photo.height) - 0.5)
            let score = -hypot(du, dv) * 2 - q.depth * 0.15
            if best == nil || score > best!.score { best = (score, index, q.u, q.v) }
        }
        return best.map { ($0.index, $0.u, $0.v) }
    }
}
