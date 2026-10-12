import Foundation

/// A private, unmodified video, existing panorama or single AI input photo.
/// Source material is not a stitched panorama, generated model or metric scan.
struct MediaDataset: Codable {
    struct Original: Codable { let file: String; let bytes: Int }
    var format = "kantura-media-dataset"
    var version = 1
    let id: String
    let name: String
    let createdAt: String
    let source: String
    let captureMode: String
    var scaleStatus = "unverified"
    let original: Original
    static let maximumVideoBytes = 2 * 1024 * 1024 * 1024
    static let maximumPanoramaBytes = 32 * 1024 * 1024
    static let maximumGenerationInputBytes = 20 * 1024 * 1024
    enum Failure: Error { case invalidManifest, invalidFile, fileTooLarge, incompleteCopy }

    /// Check before decoding full-resolution pixels. Bounds precede the pixel
    /// multiplication so malformed metadata cannot overflow it.
    static func generationInputFits(bytes: Int, width: Int, height: Int) -> Bool {
        bytes > 0 && bytes <= maximumGenerationInputBytes &&
            (64...8192).contains(width) && (64...8192).contains(height) &&
            width * height <= 16 * 1024 * 1024
    }

    static func extensions(for mode: String) -> [String] {
        mode == "video" ? ["mov", "mp4", "m4v"] : ["panorama", "generation-input"].contains(mode) ? ["jpg", "jpeg", "png"] : []
    }
    static func maximumBytes(for mode: String) -> Int {
        mode == "video" ? maximumVideoBytes : mode == "generation-input" ? maximumGenerationInputBytes : maximumPanoramaBytes
    }
    func validate() throws {
        guard format == "kantura-media-dataset", version == 1, UUID(uuidString: id) != nil,
              !name.isEmpty, name.count <= 200, ISO8601DateFormatter().date(from: createdAt) != nil,
              ["apple-camera", "files"].contains(source), ["video", "panorama", "generation-input"].contains(captureMode),
              !(source == "apple-camera" && captureMode == "panorama"), scaleStatus == "unverified"
        else { throw Failure.invalidManifest }
        let ext = (original.file as NSString).pathExtension.lowercased()
        guard Self.extensions(for: captureMode).contains(ext), original.file == "Original/source." + ext,
              original.bytes > 0 else { throw Failure.invalidFile }
        guard original.bytes <= Self.maximumBytes(for: captureMode) else { throw Failure.fileTooLarge }
    }
}

struct SavedMediaDataset {
    let manifest: MediaDataset
    let directory: URL
    var originalURL: URL { directory.appendingPathComponent(manifest.original.file) }
    var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        var folder = base.appendingPathComponent("KanturaMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder
    }

    /// Copies in bounded chunks instead of reading a movie into RAM. The new
    /// folder only becomes a library entry after an atomic manifest write.
    static func save(from file: URL, name: String, source: String, mode: String,
                     root: URL? = nil) throws -> SavedMediaDataset {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0
        else { throw MediaDataset.Failure.invalidFile }
        let identifier = UUID().uuidString
        let manifest = MediaDataset(id: identifier, name: String(name.prefix(200)),
            createdAt: ISO8601DateFormatter().string(from: Date()), source: source, captureMode: mode,
            original: .init(file: "Original/source." + file.pathExtension.lowercased(), bytes: size))
        try manifest.validate()
        let folder = try (root ?? Self.root()).appendingPathComponent(identifier, isDirectory: true)
        let record = SavedMediaDataset(manifest: manifest, directory: folder)
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Original"), withIntermediateDirectories: true)
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            guard FileManager.default.createFile(atPath: record.originalURL.path, contents: nil) else { throw MediaDataset.Failure.invalidFile }
            let output = try FileHandle(forWritingTo: record.originalURL)
            defer { try? output.close() }
            var copied = 0
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                copied += chunk.count
                guard copied <= size, copied <= MediaDataset.maximumBytes(for: mode) else { throw MediaDataset.Failure.fileTooLarge }
                try output.write(contentsOf: chunk)
            }
            guard copied == size else { throw MediaDataset.Failure.incompleteCopy }
            try output.synchronize()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: record.manifestURL, options: .atomic)
            return record
        } catch {
            // The folder was freshly created here using a UUID, never supplied
            // by a caller and never a pre-existing library record.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func load(from root: URL) -> [SavedMediaDataset] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder -> SavedMediaDataset? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let size = try? folder.appendingPathComponent("manifest.json").resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 64 * 1024, let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(MediaDataset.self, from: data),
                  manifest.id == folder.lastPathComponent, (try? manifest.validate()) != nil else { return nil }
            let record = SavedMediaDataset(manifest: manifest, directory: folder)
            guard let values = try? record.originalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == manifest.original.bytes else { return nil }
            return record
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }
}
