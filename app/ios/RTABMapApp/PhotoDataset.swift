import Foundation

/// The original capture images (including embedded metadata) remain unchanged.
/// This manifest does not invent poses, calibration or a verified metric scale.
struct PhotoDataset: Codable {
    struct Image: Codable, Equatable { let file: String; let bytes: Int }
    var format = "kantura-photo-dataset"
    var version = 1
    let id: String
    let name: String
    let createdAt: String
    var source = "apple-object-capture"
    var captureMode = "object"
    var scaleStatus = "unverified"
    let images: [Image]

    enum Failure: Error { case invalidManifest, invalidImage, incompleteCapture }
    func validate() throws {
        guard format == "kantura-photo-dataset", version == 1,
              UUID(uuidString: id) != nil, !name.isEmpty, name.count <= 200,
              ISO8601DateFormatter().date(from: createdAt) != nil,
              source == "apple-object-capture", captureMode == "object", scaleStatus == "unverified",
              !images.isEmpty, images.count <= 2000 else { throw Failure.invalidManifest }
        var names = Set<String>()
        for image in images {
            let components = image.file.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2, components[0] == "Images",
                  !components[1].isEmpty, !components[1].hasPrefix("."),
                  !image.file.contains("\\"), !image.file.contains(":"),
                  image.bytes > 0, names.insert(image.file).inserted,
                  ["heic", "heif", "jpg", "jpeg", "png"].contains((image.file as NSString).pathExtension.lowercased())
            else { throw Failure.invalidImage }
        }
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct SavedPhotoDataset: Identifiable {
    let manifest: PhotoDataset
    let directory: URL
    var id: String { manifest.id }
    var imagesURL: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    var manifestURL: URL { directory.appendingPathComponent("manifest.json") }
    var modelURL: URL { directory.appendingPathComponent("model.usdz") }
    var hasModel: Bool {
        guard let values = try? modelURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("KanturaPhotoObjects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Raw photography stays local; an explicit Files export is the handoff.
        var excluded = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return folder
    }

    static func createDirectory() throws -> URL {
        let folder = try root().appendingPathComponent(UUID().uuidString, isDirectory: true)
        for component in ["Images", "Checkpoint"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(component, isDirectory: true),
                                                    withIntermediateDirectories: true)
        }
        return folder
    }

    static func finish(directory: URL, name: String) throws -> SavedPhotoDataset {
        let imagesURL = directory.appendingPathComponent("Images", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: imagesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles])
        let images = try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file -> PhotoDataset.Image? in
            guard ["heic", "heif", "jpg", "jpeg", "png"].contains(file.pathExtension.lowercased()) else { return nil }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0 else { throw PhotoDataset.Failure.invalidImage }
            return PhotoDataset.Image(file: "Images/" + file.lastPathComponent, bytes: size)
        }
        guard images.count >= PhotoCaptureLifecycle.minimumImages else { throw PhotoDataset.Failure.incompleteCapture }
        let manifest = PhotoDataset(id: directory.lastPathComponent, name: String(name.prefix(200)),
            createdAt: ISO8601DateFormatter().string(from: Date()), images: images)
        let result = SavedPhotoDataset(manifest: manifest, directory: directory)
        try manifest.encoded().write(to: result.manifestURL, options: .atomic)
        return result
    }

    static func load(from root: URL) -> [SavedPhotoDataset] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> SavedPhotoDataset? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let size = try? folder.appendingPathComponent("manifest.json").resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 2 * 1024 * 1024,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(PhotoDataset.self, from: data),
                  manifest.id == folder.lastPathComponent, (try? manifest.validate()) != nil else { return nil }
            let complete = manifest.images.allSatisfy { image in
                guard let values = try? folder.appendingPathComponent(image.file).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == image.bytes
            }
            return complete ? SavedPhotoDataset(manifest: manifest, directory: folder) : nil
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }
}

/// Terminal capture callbacks must not restart a cancelled or unrelated job.
struct PhotoCaptureLifecycle {
    static let minimumImages = 20
    enum Phase: Equatable { case ready, capturing, finishing, photos, processing, result, failed, cancelled }
    private(set) var phase: Phase = .ready
    @discardableResult mutating func start() -> Bool {
        guard phase == .ready else { return false }
        phase = .capturing; return true
    }
    @discardableResult mutating func finish(imageCount: Int) -> Bool {
        guard phase == .capturing, imageCount >= Self.minimumImages else { return false }
        phase = .finishing; return true
    }
    @discardableResult mutating func captured() -> Bool {
        guard phase == .finishing else { return false }
        phase = .photos; return true
    }
    @discardableResult mutating func process() -> Bool {
        guard phase == .photos || phase == .result else { return false }
        phase = .processing; return true
    }
    @discardableResult mutating func completed() -> Bool {
        guard phase == .processing else { return false }
        phase = .result; return true
    }
    mutating func processingStopped() { if phase == .processing { phase = .photos } }
    mutating func selectSaved(hasModel: Bool) { if phase == .ready || phase == .photos || phase == .result { phase = hasModel ? .result : .photos } }
    mutating func fail() { if phase != .cancelled { phase = .failed } }
    mutating func cancel() { phase = .cancelled }
}
