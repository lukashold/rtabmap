import Foundation

/// Photos taken automatically during a RoomPlan capture, with the camera pose
/// of each one in the same world coordinates as the captured room.
///
/// Conventions (ARKit): `transform` is camera-to-world, column-major 4×4; the
/// camera looks along its local −Z with +Y up. `intrinsics` is column-major 3×3
/// in pixels of the stored image (x right, y down). A world point P projects to
/// u = cx + fx·x/(−z), v = cy − fy·y/(−z) with (x, y, z) = T⁻¹·P.
struct RoomPhotoSet: Codable, Equatable {
    struct Photo: Codable, Equatable {
        let file: String
        let transform: [Double]
        let intrinsics: [Double]
        let width: Int
        let height: Int
        let timestamp: Double
    }
    var format = "kantura-room-photos"
    var version = 1
    var photos: [Photo]

    static let fileName = "photos.json"
    static let maxPhotos = 160

    enum ValidationError: Error { case invalid }

    func validate() throws {
        guard format == "kantura-room-photos", version == 1, photos.count <= Self.maxPhotos else { throw ValidationError.invalid }
        var files = Set<String>()
        for photo in photos {
            guard files.insert(photo.file).inserted,
                  photo.file.range(of: "^[A-Za-z0-9-]{1,80}\\.jpg$", options: .regularExpression) != nil,
                  photo.transform.count == 16, photo.transform.allSatisfy(\.isFinite),
                  photo.intrinsics.count == 9, photo.intrinsics.allSatisfy(\.isFinite),
                  photo.intrinsics[0] > 0, photo.intrinsics[4] > 0,
                  (1...10000).contains(photo.width), (1...10000).contains(photo.height),
                  photo.timestamp.isFinite else { throw ValidationError.invalid }
        }
    }

    static func load(from directory: URL) -> RoomPhotoSet? {
        let url = directory.appendingPathComponent(fileName)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let set = try? JSONDecoder().decode(RoomPhotoSet.self, from: data),
              (try? set.validate()) != nil else { return nil }
        // Only keep entries whose image actually exists.
        let present = set.photos.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path) }
        return present.isEmpty ? nil : RoomPhotoSet(photos: present)
    }
}

/// Pure geometry for deciding which photo covers which part of a surface.
enum RoomPhotoProjection {
    typealias Vec3 = (x: Double, y: Double, z: Double)

    static func position(_ m: [Double]) -> Vec3 { (m[12], m[13], m[14]) }
    static func forward(_ m: [Double]) -> Vec3 { (-m[8], -m[9], -m[10]) }

    /// Pixel coordinates and depth (distance along the view axis) of a world point.
    static func project(_ p: Vec3, photo: RoomPhotoSet.Photo) -> (u: Double, v: Double, depth: Double)? {
        let m = photo.transform
        let d = (p.x - m[12], p.y - m[13], p.z - m[14])
        // Inverse of a rigid transform: rotation transposed.
        let x = d.0 * m[0] + d.1 * m[1] + d.2 * m[2]
        let y = d.0 * m[4] + d.1 * m[5] + d.2 * m[6]
        let z = d.0 * m[8] + d.1 * m[9] + d.2 * m[10]
        guard z < -0.05 else { return nil }
        let k = photo.intrinsics
        let fx = k[0], fy = k[4], cx = k[6], cy = k[7]
        return (cx + fx * x / -z, cy - fy * y / -z, -z)
    }

    struct Choice: Equatable {
        let photoIndex: Int
        /// Normalized texture coordinates (0…1, origin top-left) for each input corner.
        let uv: [[Double]]
    }

    /// Best photo for one planar tile, or nil when no photo sees all of it.
    /// Prefers views facing the surface head-on, then nearer ones; rejects
    /// grazing angles and corners within 3 % of the image border.
    static func bestPhoto(corners: [Vec3], normal: Vec3, photos: [RoomPhotoSet.Photo]) -> Choice? {
        guard corners.count >= 3, !photos.isEmpty else { return nil }
        let center = corners.reduce((x: 0.0, y: 0.0, z: 0.0)) { (x: $0.x + $1.x / Double(corners.count), y: $0.y + $1.y / Double(corners.count), z: $0.z + $1.z / Double(corners.count)) }
        var best: (score: Double, choice: Choice)?
        for (index, photo) in photos.enumerated() {
            let c = position(photo.transform)
            var view = (x: center.x - c.x, y: center.y - c.y, z: center.z - c.z)
            let distance = sqrt(view.x * view.x + view.y * view.y + view.z * view.z)
            guard distance > 0.2, distance < 8 else { continue }
            view = (view.x / distance, view.y / distance, view.z / distance)
            // Facing: the camera must look at the visible side of the surface.
            let facing = -(view.x * normal.x + view.y * normal.y + view.z * normal.z)
            guard abs(facing) > 0.35 else { continue }
            let f = forward(photo.transform)
            let centred = view.x * f.x + view.y * f.y + view.z * f.z
            guard centred > 0.5 else { continue }
            let marginX = 0.03 * Double(photo.width), marginY = 0.03 * Double(photo.height)
            var uv: [[Double]] = []
            for corner in corners {
                guard let p = project(corner, photo: photo),
                      p.u >= marginX, p.u <= Double(photo.width) - marginX,
                      p.v >= marginY, p.v <= Double(photo.height) - marginY else { uv = []; break }
                uv.append([p.u / Double(photo.width), p.v / Double(photo.height)])
            }
            guard uv.count == corners.count else { continue }
            let score = abs(facing) * 2 + centred - distance * 0.25
            if best == nil || score > best!.score { best = (score, Choice(photoIndex: index, uv: uv)) }
        }
        return best?.choice
    }

    /// Split a w × h rectangle centred at the origin into tiles of at most `size`.
    static func tiles(width: Double, height: Double, size: Double) -> [[(Double, Double)]] {
        guard width > 0, height > 0, size > 0 else { return [] }
        let nx = max(1, Int(ceil(width / size))), ny = max(1, Int(ceil(height / size)))
        var result: [[(Double, Double)]] = []
        for j in 0..<ny {
            for i in 0..<nx {
                let x0 = -width / 2 + width * Double(i) / Double(nx), x1 = -width / 2 + width * Double(i + 1) / Double(nx)
                let y0 = -height / 2 + height * Double(j) / Double(ny), y1 = -height / 2 + height * Double(j + 1) / Double(ny)
                result.append([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
            }
        }
        return result
    }

    /// Point-in-polygon test (even-odd) in 2D.
    static func inside(_ p: (Double, Double), _ polygon: [(Double, Double)]) -> Bool {
        var result = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.1 > p.1) != (b.1 > p.1) && p.0 < (b.0 - a.0) * (p.1 - a.1) / (b.1 - a.1) + a.0 { result.toggle() }
            j = i
        }
        return result
    }

    /// Should a new frame be kept, given the poses already kept?
    /// Keeps a frame once the camera moved ≥ 0.35 m or turned ≥ 20° from every kept frame.
    static func isNewView(_ transform: [Double], kept: [[Double]]) -> Bool {
        let p = position(transform), f = forward(transform)
        for other in kept {
            let q = position(other), g = forward(other)
            let moved = sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2) + pow(p.z - q.z, 2))
            let turned = acos(max(-1, min(1, f.x * g.x + f.y * g.y + f.z * g.z))) * 180 / .pi
            if moved < 0.35 && turned < 20 { return false }
        }
        return true
    }
}

/// Textured room surfaces grouped by photo: one bucket per photo plus one
/// (`photoIndex == nil`) for parts that no photo covers. Foundation only.
struct RoomPhotoMesh {
    struct Bucket {
        let photoIndex: Int?
        var positions: [Double] = []   // xyz per vertex, world metres
        var uvs: [Double] = []         // uv per vertex (0…1, origin top-left)
        var indices: [Int32] = []
        var tiles = 0
    }
    var buckets: [Bucket]
    var coveredTiles: Int
    var totalTiles: Int
    /// Eye position for "standing in the room": floor centroid + 1.6 m.
    var eye: (x: Double, y: Double, z: Double)
    var floorY: Double

    static func build(_ document: RoomPlanDocument, photos: [RoomPhotoSet.Photo], tileSize: Double = 0.35, ceilingHeight: Double?) -> RoomPhotoMesh {
        typealias V = RoomPhotoProjection.Vec3
        func world(_ p: [Double], _ m: [Double]) -> V {
            (m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13], m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14])
        }
        var byPhoto: [Int: Bucket] = [:]
        var uncovered = Bucket(photoIndex: nil)
        var covered = 0, total = 0
        func add(_ corners: [V], normal: V) {
            total += 1
            let choice = RoomPhotoProjection.bestPhoto(corners: corners, normal: normal, photos: photos)
            var bucket = choice.map { byPhoto[$0.photoIndex] ?? Bucket(photoIndex: $0.photoIndex) } ?? uncovered
            let base = Int32(bucket.positions.count / 3)
            for (i, c) in corners.enumerated() {
                bucket.positions += [c.x, c.y, c.z]
                bucket.uvs += choice?.uv[i] ?? [0, 0]
            }
            bucket.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            bucket.tiles += 1
            if let choice = choice { covered += 1; byPhoto[choice.photoIndex] = bucket } else { uncovered = bucket }
        }
        func surface(_ s: RoomPlanDocument.Surface, offset: V = (0, 0, 0)) {
            let m = s.transform
            let normal: V = (m[8], m[9], m[10])
            let outline = s.polygonCorners?.map { ($0[0], $0[1]) }
            let xs = outline?.map { $0.0 } ?? [-s.dimensions[0] / 2, s.dimensions[0] / 2]
            let ys = outline?.map { $0.1 } ?? [-s.dimensions[1] / 2, s.dimensions[1] / 2]
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            for tile in RoomPhotoProjection.tiles(width: maxX - minX, height: maxY - minY, size: tileSize) {
                let local = tile.map { ($0.0 + cx, $0.1 + cy) }
                if let outline = outline {
                    let centre = (local.map { $0.0 }.reduce(0, +) / 4, local.map { $0.1 }.reduce(0, +) / 4)
                    guard RoomPhotoProjection.inside(centre, outline) else { continue }
                }
                add(local.map { p in let w = world([p.0, p.1, 0], m); return (w.x + offset.x, w.y + offset.y, w.z + offset.z) }, normal: normal)
            }
        }
        let walls = document.surfaces.filter { $0.kind == "wall" && $0.dimensions.count == 3 && $0.transform.count == 16 }
        let floors = document.surfaces.filter { $0.kind == "floor" && $0.polygonCorners != nil && $0.transform.count == 16 }
        walls.forEach { surface($0) }
        floors.forEach { surface($0) }
        if let height = ceilingHeight, height > 0.5 { floors.forEach { surface($0, offset: (0, height, 0)) } }

        // Eye: centroid of the floor outline(s), else of the wall centres.
        var points: [V] = floors.flatMap { f in f.polygonCorners!.map { world($0, f.transform) } }
        var floorY = points.isEmpty ? 0 : points.map { $0.y }.reduce(0, +) / Double(points.count)
        if points.isEmpty {
            points = walls.map { world([0, 0, 0], $0.transform) }
            let bottoms = walls.map { world([0, -$0.dimensions[1] / 2, 0], $0.transform).y }
            floorY = bottoms.isEmpty ? 0 : bottoms.reduce(0, +) / Double(bottoms.count)
        }
        let n = Double(max(1, points.count))
        let eye = (x: points.map { $0.x }.reduce(0, +) / n, y: floorY + 1.6, z: points.map { $0.z }.reduce(0, +) / n)
        var buckets = byPhoto.keys.sorted().map { byPhoto[$0]! }
        if uncovered.tiles > 0 { buckets.append(uncovered) }
        return RoomPhotoMesh(buckets: buckets, coveredTiles: covered, totalTiles: total, eye: eye, floorY: floorY)
    }
}
