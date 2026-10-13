import ARKit
import CoreImage
import UIKit

/// Takes photos from RoomPlan's own AR session while a room is being scanned.
///
/// It only *reads* `session.currentFrame` a few times per second, so RoomPlan's
/// session delegate and capture are untouched. A frame is kept when tracking is
/// normal and the camera moved or turned enough (see `RoomPhotoProjection.isNewView`).
/// At most one JPEG is being encoded at a time so ARKit's buffer pool is never starved.
final class RoomPhotoRecorder {
    let directory: URL
    private(set) var photos: [RoomPhotoSet.Photo] = []
    private weak var session: ARSession?
    private var timer: Timer?
    private var encoding = false
    private let queue = DispatchQueue(label: "kantura.room-photos", qos: .utility)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let lock = NSLock()

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("KanturaCapture-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return photos.count }

    func start(session: ARSession) {
        self.session = session
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Let an in-flight encode finish before callers read `photos`.
        queue.sync {}
    }

    private func tick() {
        guard !encoding, let frame = session?.currentFrame, count < RoomPhotoSet.maxPhotos else { return }
        guard case .normal = frame.camera.trackingState else { return }
        let m = frame.camera.transform
        let transform = (0..<4).flatMap { c in (0..<4).map { r in Double(m[c][r]) } }
        lock.lock()
        let kept = photos.map(\.transform)
        lock.unlock()
        guard RoomPhotoProjection.isNewView(transform, kept: kept) else { return }
        let k = frame.camera.intrinsics
        let intrinsics = (0..<3).flatMap { c in (0..<3).map { r in Double(k[c][r]) } }
        let width = CVPixelBufferGetWidth(frame.capturedImage), height = CVPixelBufferGetHeight(frame.capturedImage)
        // Copy the image now; holding on to ARFrame would keep ARKit's buffer busy.
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let timestamp = frame.timestamp
        encoding = true
        queue.async { [weak self] in
            guard let self = self else { return }
            let name = String(format: "photo-%03d.jpg", self.count + 1)
            let url = self.directory.appendingPathComponent(name)
            let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72]
            if let space = CGColorSpace(name: CGColorSpace.sRGB),
               let data = self.context.jpegRepresentation(of: image, colorSpace: space, options: options),
               (try? data.write(to: url, options: .atomic)) != nil {
                self.lock.lock()
                self.photos.append(.init(file: name, transform: transform, intrinsics: intrinsics, width: width, height: height, timestamp: timestamp))
                self.lock.unlock()
            }
            DispatchQueue.main.async { self.encoding = false }
        }
    }

    /// Copy the photos and their index into `destination` (a room folder).
    /// May run off the main thread: it only waits for a pending encode (the
    /// timer was already stopped on the main thread when capture finished).
    func write(to destination: URL) throws {
        queue.sync {}
        lock.lock()
        let set = RoomPhotoSet(photos: photos)
        lock.unlock()
        guard !set.photos.isEmpty else { return }
        try set.validate()
        let folder = destination.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for photo in set.photos {
            let target = folder.appendingPathComponent(photo.file)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: directory.appendingPathComponent(photo.file), to: target)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(set).write(to: folder.appendingPathComponent(RoomPhotoSet.fileName), options: .atomic)
    }

    func discard() {
        stop()
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        timer?.invalidate()
        try? FileManager.default.removeItem(at: directory)
    }
}
