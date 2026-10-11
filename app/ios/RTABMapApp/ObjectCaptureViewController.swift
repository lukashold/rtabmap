import UIKit

#if !targetEnvironment(simulator)
import RealityKit
import SwiftUI
import AVFoundation
import QuickLook
import Zip

/// Original UI around Apple's public Object Capture APIs. RTAB-Map's camera is
/// stopped before this controller is presented; it stays stopped until dismissal.
@available(iOS 17.0, *)
@MainActor
final class ObjectCaptureViewController: UIViewController, QLPreviewControllerDataSource {
    static var isSupported: Bool { ObjectCaptureSession.isSupported }
    var onClose: (() -> Void)?
    private let model = KanturaPhotoCaptureModel()
    private var previewURL: URL?
    private var backgroundObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MeasurementGuide.objectText("title")
        KanturaDesign.navigation(self)
        view.backgroundColor = KanturaDesign.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: MeasurementGuide.roomText("close"), style: .done,
                                                           target: self, action: #selector(close))
        model.onClosed = { [weak self] in
            guard let self = self else { return }
            let closed = self.onClose
            self.dismiss(animated: true) { closed?() }
        }
        model.onExport = { [weak self] url in
            guard let self = self, self.presentedViewController == nil else { return }
            self.present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true)
        }
        let root = KanturaPhotoCaptureView(model: model, preview: { [weak self] url in self?.preview(url) })
            .environment(\.layoutDirection, MeasurementGuide.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: MeasurementGuide.selectedLanguage))
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = KanturaDesign.background
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.pauseCapture() }
            }
    }

    @objc private func close() {
        guard presentedViewController == nil, !model.isClosing, !model.isExporting else { return }
        if model.isBusy {
            let alert = UIAlertController(title: MeasurementGuide.objectText("cancel"),
                message: MeasurementGuide.objectText("cancelBody"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: MeasurementGuide.roomText("keep"), style: .cancel))
            alert.addAction(UIAlertAction(title: MeasurementGuide.objectText("cancel"), style: .destructive) { [weak self] _ in self?.model.close() })
            present(alert, animated: true)
        } else { model.close() }
    }

    private func preview(_ url: URL) {
        guard presentedViewController == nil else { return }
        previewURL = url
        let controller = QLPreviewController()
        controller.dataSource = self
        present(controller, animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewURL! as NSURL }
    deinit { if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) } }
}

@available(iOS 17.0, *)
@MainActor
private final class KanturaPhotoCaptureModel: ObservableObject {
    @Published var lifecycle = PhotoCaptureLifecycle()
    @Published var session: ObjectCaptureSession?
    @Published var record: SavedPhotoDataset?
    @Published var library: [SavedPhotoDataset] = []
    @Published var name = ""
    @Published var message: String?
    @Published var progress: Double = 0
    @Published var isPaused = false
    @Published var isClosing = false
    @Published var isExporting = false
    var onClosed: (() -> Void)?
    var onExport: ((URL) -> Void)?
    private var activeDirectory: URL?
    private var reconstruction: PhotogrammetrySession?
    private var captureTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    var isBusy: Bool { authorizationTask != nil || session != nil || lifecycle.phase == .processing }
    init() { reloadLibrary() }
    private func text(_ key: String) -> String { MeasurementGuide.objectText(key) }
    private func reloadLibrary() { library = (try? SavedPhotoDataset.root()).map { SavedPhotoDataset.load(from: $0) } ?? [] }

    func prepareNewCapture() {
        guard !isBusy, !isExporting else { return }
        removeIncompleteCapture()
        record = nil; name = ""; message = nil
        lifecycle = PhotoCaptureLifecycle()
    }

    func start() {
        guard !isBusy, !isClosing, ObjectCaptureSession.isSupported else { return }
        removeIncompleteCapture()
        message = nil
        record = nil
        lifecycle = PhotoCaptureLifecycle()
        authorizationTask = Task { [weak self] in
            guard let self = self else { return }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            self.authorizationTask = nil
            guard !Task.isCancelled, !self.isClosing else { return }
            guard allowed else { self.message = MeasurementGuide.roomText("cameraDenied"); return }
            do {
                let directory = try SavedPhotoDataset.createDirectory()
                self.activeDirectory = directory
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
                let session = ObjectCaptureSession()
                self.session = session
                self.isPaused = false
                guard self.lifecycle.start() else { return }
                var configuration = ObjectCaptureSession.Configuration()
                configuration.checkpointDirectory = directory.appendingPathComponent("Checkpoint", isDirectory: true)
                configuration.isOverCaptureEnabled = false
                self.captureTask = Task { [weak self] in
                    for await state in session.stateUpdates {
                        guard !Task.isCancelled else { break }
                        self?.handleCapture(state)
                        if case .completed = state { break }
                        if case .failed = state { break }
                    }
                }
                session.start(imagesDirectory: directory.appendingPathComponent("Images", isDirectory: true), configuration: configuration)
                UIApplication.shared.isIdleTimerDisabled = true
                if case .failed = session.state { self.handleCapture(session.state) }
            } catch { self.lifecycle.fail(); self.message = self.text("failed") + "\n" + error.localizedDescription }
        }
    }

    func detect() {
        guard session?.state == .ready else { return }
        if session?.startDetecting() == false { message = text("detectHelp") } else { message = nil }
    }
    func capture() { guard session?.state == .detecting else { return }; message = nil; session?.startCapturing() }
    func nextPass() { guard session?.state == .capturing else { return }; session?.beginNewScanPass() }
    func finish() {
        guard let session = session, lifecycle.finish(imageCount: session.numberOfShotsTaken) else { return }
        session.finish()
    }
    func pauseCapture() { guard let session = session else { return }; session.pause(); isPaused = true }
    func resume() { guard isPaused else { return }; session?.resume(); isPaused = false }

    private func handleCapture(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .finishing:
            if let session = session { lifecycle.finish(imageCount: session.numberOfShotsTaken) }
        case .completed:
            session = nil
            captureTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
            guard !isClosing else { finishClosing(); return }
            guard lifecycle.captured(), let directory = activeDirectory else { return }
            do {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                record = try SavedPhotoDataset.finish(directory: directory, name: title.isEmpty ? text("title") : title)
                activeDirectory = nil
                message = nil
                reloadLibrary()
            } catch { lifecycle.fail(); message = text("failed") + "\n" + error.localizedDescription }
        case .failed(let error):
            session = nil
            captureTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
            if isClosing { finishClosing(); return }
            lifecycle.fail()
            message = text("failed") + "\n" + error.localizedDescription
        default: break
        }
    }

    func select(_ saved: SavedPhotoDataset) {
        guard !isBusy, !isExporting else { return }
        record = saved; message = nil
        lifecycle = PhotoCaptureLifecycle()
        lifecycle.selectSaved(hasModel: saved.hasModel)
    }

    func process() {
        guard let record = record, !isBusy, !isExporting else { return }
        guard PhotogrammetrySession.isSupported else { message = text("reconstructionUnsupported"); return }
        guard lifecycle.process() else { return }
        message = nil; progress = 0
        let work = record.directory.appendingPathComponent("Checkpoint", isDirectory: true)
        let output = work.appendingPathComponent("model-in-progress.usdz")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = work
            let processor = try PhotogrammetrySession(input: record.imagesURL, configuration: configuration)
            reconstruction = processor
            UIApplication.shared.isIdleTimerDisabled = true
            processingTask = Task { [weak self] in
                do {
                    try processor.process(requests: [.modelFile(url: output, detail: .reduced)])
                    for try await event in processor.outputs {
                        guard !Task.isCancelled, let self = self else { break }
                        switch event {
                        case .requestProgress(_, let fraction): self.progress = min(1, max(0, fraction))
                        case .requestError(_, let error):
                            processor.cancel()
                            if !self.isClosing { self.message = self.text("failed") + "\n" + error.localizedDescription }
                        case .processingComplete:
                            guard !self.isClosing, self.message == nil else { self.stoppedProcessing(); return }
                            guard let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { throw PhotoDataset.Failure.incompleteCapture }
                            if FileManager.default.fileExists(atPath: record.modelURL.path) { try FileManager.default.removeItem(at: record.modelURL) }
                            try FileManager.default.moveItem(at: output, to: record.modelURL)
                            self.lifecycle.completed()
                            self.releaseProcessor()
                            self.reloadLibrary()
                            return
                        case .processingCancelled: self.stoppedProcessing(); return
                        default: break
                        }
                    }
                    self?.stoppedProcessing()
                } catch {
                    self?.message = (self?.text("failed") ?? "") + "\n" + error.localizedDescription
                    self?.stoppedProcessing()
                }
            }
        } catch { message = text("failed") + "\n" + error.localizedDescription; stoppedProcessing() }
    }

    private func releaseProcessor() {
        reconstruction = nil; processingTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func stoppedProcessing() {
        releaseProcessor()
        lifecycle.processingStopped()
        if isClosing { finishClosing() }
    }
    func cancelProcessing() { reconstruction?.cancel() }

    func exportPhotos() {
        guard let record = record, !isBusy, !isExporting else { return }
        isExporting = true
        message = nil
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("kantura-photos-" + record.id + ".zip")
        // Zip's synchronous work stays off the main thread; completed manifests
        // and images are immutable while this job is active.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Zip.zipFiles(paths: [record.imagesURL, record.manifestURL], zipFilePath: target, password: nil, progress: nil) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isExporting = false
                switch result {
                case .success: self.onExport?(target)
                case .failure(let error): self.message = MeasurementGuide.roomText("exportFailed") + "\n" + error.localizedDescription
                }
            }
        }
    }
    func exportModel() { guard let record = record, record.hasModel, !isBusy, !isExporting else { return }; onExport?(record.modelURL) }

    func close() {
        guard !isClosing, !isExporting else { return }
        isClosing = true
        authorizationTask?.cancel(); authorizationTask = nil
        if let session = session { session.cancel(); return }
        if let reconstruction = reconstruction { reconstruction.cancel(); return }
        finishClosing()
    }
    private func finishClosing() {
        captureTask?.cancel(); captureTask = nil
        processingTask?.cancel(); processingTask = nil
        session = nil; reconstruction = nil
        lifecycle.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        removeIncompleteCapture()
        onClosed?()
    }
    private func removeIncompleteCapture() {
        // Only a fresh capture directory created by this model and without a
        // completed manifest is removed. Never touch the selected saved record.
        if let directory = activeDirectory, !FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path) {
            try? FileManager.default.removeItem(at: directory)
        }
        activeDirectory = nil
    }
}

@available(iOS 17.0, *)
@MainActor
private struct KanturaPhotoCaptureView: View {
    @ObservedObject var model: KanturaPhotoCaptureModel
    let preview: (URL) -> Void
    private func text(_ key: String) -> String { MeasurementGuide.objectText(key) }

    var body: some View {
        Group {
            if let session = model.session, !model.isClosing {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Keep camera gestures outside the scrolling controls:
                        // adjusting Apple's bounding box must not scroll the page.
                        ObjectCaptureView(session: session)
                            .frame(height: max(160, geometry.size.height * 0.52))
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .padding(.horizontal, 16)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                captureControls(session)
                                if let message = model.message { Text(message).font(.body) }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else { workspace }
        }
        .background(Color(KanturaDesign.background))
        .foregroundStyle(Color(KanturaDesign.text))
        .disabled(model.isExporting)
        .overlay { if model.isExporting { ProgressView(MeasurementGuide.roomText("exporting")).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isClosing {
                    ProgressView(text("cancel"))
                } else if model.lifecycle.phase == .processing {
                    Text(text("processing")).font(.largeTitle.bold())
                    ProgressView(value: model.progress)
                    Text(model.progress, format: .percent.precision(.fractionLength(0))).font(.title.monospacedDigit())
                    Text(text("processingHelp"))
                    action("cancel") { model.cancelProcessing() }
                } else if let record = model.record {
                    result(record)
                } else {
                    Text(text("title")).font(.largeTitle.bold())
                    Text(text("intro"))
                    Text(text("splatHelp")).font(.subheadline)
                    TextField(text("name"), text: $model.name).textFieldStyle(.roundedBorder).submitLabel(.done)
                    action("begin", primary: true) { model.start() }
                    Text(text("privacy")).font(.footnote).foregroundStyle(Color(KanturaDesign.muted))
                }
                if let message = model.message {
                    Text(message).font(.body).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(KanturaDesign.surface), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if !model.isBusy && !model.isClosing {
                    Text(text("scaleNote")).font(.footnote).foregroundStyle(Color(KanturaDesign.muted))
                    library
                }
            }
            .padding(24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func captureControls(_ session: ObjectCaptureSession) -> some View {
        if model.isPaused {
            Text(text("paused"))
            action("resume", primary: true) { model.resume() }
        } else {
            switch session.state {
            case .initializing: ProgressView()
            case .ready:
                Text(text("detectHelp"))
                action("detect", primary: true) { model.detect() }
            case .detecting:
                Text(text("detectHelp"))
                action("capture", primary: true) { model.capture() }
            case .capturing:
                Text(text("captureHelp"))
                Text(text("photosCount").replacingOccurrences(of: "{count}", with: String(session.numberOfShotsTaken))
                    .replacingOccurrences(of: "{max}", with: String(session.maximumNumberOfInputImages)))
                    .font(.headline.monospacedDigit())
                if session.feedback.contains(.environmentLowLight) || session.feedback.contains(.environmentTooDark) { Text(text("light")).font(.headline) }
                if session.feedback.contains(.movingTooFast) { Text(text("slow")).font(.headline) }
                if session.feedback.contains(.objectTooClose) || session.feedback.contains(.objectTooFar) { Text(text("distance")).font(.headline) }
                if needsFramingFeedback(session) { Text(text("frame")).font(.headline) }
                if session.userCompletedScanPass {
                    Text(text("passHelp"))
                    action("nextPass") { model.nextPass() }
                }
                action("finish", primary: true) { model.finish() }
                    .disabled(session.numberOfShotsTaken < PhotoCaptureLifecycle.minimumImages)
            case .finishing: ProgressView(MeasurementGuide.roomText("exporting"))
            default: EmptyView()
            }
        }
    }

    private func needsFramingFeedback(_ session: ObjectCaptureSession) -> Bool {
        if session.feedback.contains(.outOfFieldOfView) { return true }
        if #available(iOS 17.4, *) { return session.feedback.contains(.objectNotDetected) }
        return false
    }

    @ViewBuilder private func result(_ record: SavedPhotoDataset) -> some View {
        Text(record.manifest.name).font(.largeTitle.bold())
        Text(text(record.hasModel ? "resultReady" : "photosSaved"))
        if record.hasModel {
            Button { preview(record.modelURL) } label: { Label(MeasurementGuide.roomText("preview"), systemImage: "cube.transparent").font(.headline).padding() }
            action("exportModel", primary: true) { model.exportModel() }
        } else { action("createModel", primary: true) { model.process() } }
        action("exportPhotos") { model.exportPhotos() }
        Text(text("splatHelp")).font(.subheadline)
        Text(text("formatHelp")).font(.footnote).foregroundStyle(Color(KanturaDesign.muted))
        Text(text("privacy")).font(.footnote).foregroundStyle(Color(KanturaDesign.muted))
        action("begin") { model.prepareNewCapture() }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("library")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if model.library.isEmpty { Text(text("libraryEmpty")).foregroundStyle(Color(KanturaDesign.muted)) }
            ForEach(model.library) { saved in
                Button { model.select(saved) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(saved.manifest.name).font(.headline)
                        Text(text(saved.hasModel ? "resultReady" : "photosSaved")).font(.subheadline)
                        Text(saved.manifest.createdAt).font(.caption).foregroundStyle(Color(KanturaDesign.muted))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(KanturaDesign.surface), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
        }
    }
    private func action(_ key: String, primary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(text(key)).font(.headline).multilineTextAlignment(.center).padding(18).frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Color(primary ? KanturaDesign.ink : KanturaDesign.text))
                .background(Color(primary ? KanturaDesign.mint : KanturaDesign.surface), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
#else
@available(iOS 17.0, *)
final class ObjectCaptureViewController: UIViewController {
    static var isSupported: Bool { false }
    var onClose: (() -> Void)?
}
#endif
