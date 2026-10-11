import Foundation

/// Limits native -> base64 -> WebKit copies before constructing a JS payload.
struct SplatDocument {
    static let maximumBytes = 32 * 1024 * 1024
    enum Failure: Error { case unsupportedType, tooLarge, invalidFile }
    let name: String
    let data: Data

    static func read(from url: URL, maximumBytes: Int = SplatDocument.maximumBytes) throws -> SplatDocument {
        guard ["ply", "splat"].contains(url.pathExtension.lowercased()) else { throw Failure.unsupportedType }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw Failure.invalidFile }
        guard maximumBytes > 0, size <= maximumBytes else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(512 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumBytes else { throw Failure.tooLarge }
            data.append(chunk)
        }
        guard !data.isEmpty else { throw Failure.invalidFile }
        if url.pathExtension.lowercased() == "splat", data.count % 32 != 0 { throw Failure.invalidFile }
        if url.pathExtension.lowercased() == "ply", !data.starts(with: [112,108,121,10]) && !data.starts(with: [112,108,121,13,10]) {
            throw Failure.invalidFile
        }
        return SplatDocument(name: String(url.lastPathComponent.prefix(240)), data: data)
    }

    func javascriptPayload(language: String) throws -> String {
        struct Payload: Encodable { let base64: Data; let name: String; let language: String }
        // JSONEncoder base64-encodes Data and escapes filenames as JSON strings.
        // No filename or file bytes are interpolated as executable JavaScript.
        let json = try JSONEncoder().encode(Payload(base64: data, name: name, language: language))
        guard let string = String(data: json, encoding: .utf8) else { throw Failure.invalidFile }
        return string
    }
}
