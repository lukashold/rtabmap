import UIKit
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import QuickLook
import Zip

/// Independent camera workspace: the presenting scanner has already stopped
/// its AR/camera session. No bounding box and no claim of automatic 3D or scale.
final class SceneCaptureViewController: UIViewController, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    var onClose: (() -> Void)?
    private let stack = UIStackView()
    private let nameField = UITextField()
    private let status = UILabel()
    private var photos: [SavedPhotoDataset] = []
    private var media: [SavedMediaDataset] = []
    private var busy = false
    private var importMode = "video"
    private var previewURL: URL?
    private func text(_ key: String) -> String { MeasurementGuide.sceneText(key) }
    private var captureName: String {
        let value = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? text("title") : String(value.prefix(200))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = text("title")
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: MeasurementGuide.roomText("close"), style: .done,
                                                           target: self, action: #selector(close))
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        nameField.placeholder = MeasurementGuide.objectText("name")
        nameField.accessibilityLabel = nameField.placeholder
        nameField.borderStyle = .roundedRect
        nameField.font = .preferredFont(forTextStyle: .body); nameField.adjustsFontForContentSizeCategory = true
        nameField.returnKeyType = .done
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true; status.textColor = KanturaDesign.muted
        reload()
    }

    private func label(_ value: String, heading: Bool = false) -> UILabel {
        let label = UILabel(); label.text = value; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: heading ? .title2 : .body)
        label.adjustsFontForContentSizeCategory = true; label.textColor = KanturaDesign.text
        if heading { label.accessibilityTraits.insert(.header) }
        return label
    }
    private func action(_ title: String, detail: String? = nil, icon: String, perform: @escaping () -> Void) {
        let button = KanturaActionCard(title: title, detail: detail ?? "", icon: icon)
        button.addAction(UIAction { _ in perform() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
    private func reload() {
        photos = (try? SavedPhotoDataset.root()).map { SavedPhotoDataset.load(from: $0).filter { $0.manifest.source == "apple-camera" } } ?? []
        media = (try? SavedMediaDataset.root()).map { SavedMediaDataset.load(from: $0) } ?? []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(label(text("detail")))
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(label(text("photoHelp")))
        for (mode, icon) in [("room", "house"), ("outdoor", "sun.max"), ("splat", "sparkles")] {
            action(text(mode), icon: icon) { [weak self] in self?.startPhotos(mode: mode) }
        }
        action(text("panorama"), detail: text("panoramaCaptureHelp"), icon: "pano") { [weak self] in self?.startPhotos(mode: "panorama") }
        action(text("generation-input"), detail: text("generationHelp"), icon: "cube.transparent") { [weak self] in self?.startPhotos(mode: "generation-input") }
        action(text("importGeneration"), icon: "photo") { [weak self] in self?.chooseFile(mode: "generation-input") }
        stack.addArrangedSubview(label(text("videoHelp")))
        action(text("recordVideo"), icon: "video") { [weak self] in self?.recordVideo() }
        action(text("importVideo"), icon: "film") { [weak self] in self?.chooseFile(mode: "video") }
        action(text("importPanorama"), detail: text("panoramaHelp"), icon: "pano") { [weak self] in self?.chooseFile(mode: "panorama") }
        stack.addArrangedSubview(label(text("privacy")))
        stack.addArrangedSubview(label(text("library"), heading: true))
        if photos.isEmpty && media.isEmpty { stack.addArrangedSubview(label(MeasurementGuide.objectText("libraryEmpty"))) }
        for record in photos {
            action(record.manifest.name, detail: text(record.manifest.captureMode) + " · " +
                   text(record.manifest.captureMode == "panorama" ? "panoramaCount" : record.manifest.captureMode == "generation-input" ? "generationCount" : "count").replacingOccurrences(of: "{count}", with: String(record.manifest.images.count)), icon: "photo.on.rectangle") { [weak self] in self?.open(record) }
        }
        for record in media {
            action(record.manifest.name, detail: text(record.manifest.captureMode == "video" ? "recordVideo" : record.manifest.captureMode == "generation-input" ? "generation-input" : "importPanorama") +
                   " · " + ByteCountFormatter.string(fromByteCount: Int64(record.manifest.original.bytes), countStyle: .file),
                   icon: record.manifest.captureMode == "video" ? "film" : "photo") { [weak self] in self?.open(record) }
        }
        stack.addArrangedSubview(status)
    }
    private func setBusy(_ value: Bool) {
        busy = value; stack.isUserInteractionEnabled = !value
        navigationItem.leftBarButtonItem?.isEnabled = !value
        status.text = value ? MeasurementGuide.roomText("exporting") : nil
        if value {
            let progress = UIActivityIndicatorView(style: .medium); progress.startAnimating()
            progress.accessibilityLabel = MeasurementGuide.roomText("exporting")
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: progress)
        } else { navigationItem.rightBarButtonItem = nil }
    }
    private func startPhotos(mode: String, saved: SavedPhotoDataset? = nil) {
        guard !busy, presentedViewController == nil else { return }
        view.endEditing(true)
        let camera = ScenePhotoCameraViewController(mode: mode, name: saved?.manifest.name ?? captureName, saved: saved)
        camera.onFinished = { [weak self] in self?.reload() }
        let navigation = UINavigationController(rootViewController: camera)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
    private func chooseFile(mode: String) {
        guard !busy, presentedViewController == nil else { return }
        view.endEditing(true); importMode = mode
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mode == "video" ? [.movie] : [.jpeg, .png], asCopy: false)
        picker.allowsMultipleSelection = false; picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, !busy else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        importOriginal(url, source: "files", mode: importMode) { if scoped { url.stopAccessingSecurityScopedResource() } }
    }
    private func recordVideo() {
        guard !busy, presentedViewController == nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) == true else {
            failure(text("unavailable")); return
        }
        setBusy(true)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] cameraAllowed in
            AVCaptureDevice.requestAccess(for: .audio) { microphoneAllowed in
                DispatchQueue.main.async {
                    guard let self = self else { return }; self.setBusy(false)
                    guard cameraAllowed && microphoneAllowed else { self.failure(self.text("permission")); return }
                    guard self.view.window != nil, self.presentedViewController == nil else { return }
                    let picker = UIImagePickerController(); picker.sourceType = .camera
                    picker.mediaTypes = [UTType.movie.identifier]; picker.cameraCaptureMode = .video
                    picker.videoQuality = .typeHigh; picker.videoMaximumDuration = 180
                    picker.allowsEditing = false; picker.delegate = self
                    picker.modalPresentationStyle = .fullScreen
                    self.present(picker, animated: true)
                }
            }
        }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let url = info[.mediaURL] as? URL else { picker.dismiss(animated: true) { self.failure(self.text("invalid")) }; return }
        // Retain the system camera's temporary file until the private copy is
        // complete; don't rely on its lifetime after dismissing the picker.
        picker.view.isUserInteractionEnabled = false
        importOriginal(url, source: "apple-camera", mode: "video", beforeResult: {
            picker.dismiss(animated: true)
        })
    }
    private func importOriginal(_ url: URL, source: String, mode: String, beforeResult: @escaping () -> Void = {}) {
        guard !busy else { beforeResult(); return }
        setBusy(true)
        let name = captureName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var copyResult: Result<SavedMediaDataset, Error>?
            var coordinationError: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
                copyResult = Result {
                    let values = try coordinated.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values.fileSize, size > 0, size <= MediaDataset.maximumBytes(for: mode)
                    else { throw MediaDataset.Failure.fileTooLarge }
                    if mode == "video" {
                        let asset = AVURLAsset(url: coordinated)
                        let duration = CMTimeGetSeconds(asset.duration)
                        guard duration.isFinite, duration > 0, !asset.tracks(withMediaType: .video).isEmpty
                        else { throw MediaDataset.Failure.invalidFile }
                    } else {
                        guard let image = CGImageSourceCreateWithURL(coordinated as CFURL, nil),
                              let imageType = CGImageSourceGetType(image),
                              [UTType.jpeg.identifier, UTType.png.identifier].contains(imageType as String),
                              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
                        else { throw MediaDataset.Failure.invalidFile }
                        if mode == "panorama" {
                            guard width.intValue >= 512, width.intValue <= 8192, height.intValue > 0, height.intValue <= 4096,
                                  abs(width.doubleValue / height.doubleValue - 2) < 0.02 else { throw MediaDataset.Failure.invalidFile }
                        } else {
                            guard MediaDataset.generationInputFits(bytes: size, width: width.intValue, height: height.intValue)
                            else { throw MediaDataset.Failure.invalidFile }
                        }
                    }
                    return try SavedMediaDataset.save(from: coordinated, name: name, source: source, mode: mode)
                }
            }
            let result = copyResult ?? .failure(coordinationError ?? NSError(domain: "KanturaMedia", code: 1))
            DispatchQueue.main.async {
                beforeResult()
                guard let self = self else { return }
                self.setBusy(false); self.reload()
                if case .failure(let error) = result { self.failure(self.text("invalid") + "\n" + error.localizedDescription) }
                else { self.status.text = self.text("saved") }
            }
        }
    }
    private func open(_ record: SavedPhotoDataset) {
        guard !busy else { return }
        let generatedInput = record.manifest.captureMode == "generation-input"
        let menu = UIAlertController(title: record.manifest.name, message: text(record.manifest.captureMode == "panorama" ? "panoramaCaptureHelp" : generatedInput ? "generationHelp" : "photoHelp"), preferredStyle: .alert)
        if !generatedInput {
            menu.addAction(UIAlertAction(title: text("resume"), style: .default) { [weak self] _ in
                self?.startPhotos(mode: record.manifest.captureMode, saved: record)
            })
        } else if let original = record.manifest.images.first {
            menu.addAction(UIAlertAction(title: text("exportOriginal"), style: .default) { [weak self] _ in
                self?.export(record.directory.appendingPathComponent(original.file))
            })
        }
        menu.addAction(UIAlertAction(title: MeasurementGuide.objectText("exportPhotos"), style: .default) { [weak self] _ in
            self?.zip([record.imagesURL, record.manifestURL], id: record.id)
        })
        menu.addAction(UIAlertAction(title: MeasurementGuide.roomText("preview"), style: .default) { [weak self] _ in
            if let last = record.manifest.images.last { self?.preview(record.directory.appendingPathComponent(last.file)) }
        })
        menu.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .cancel))
        present(menu, animated: true)
    }
    private func open(_ record: SavedMediaDataset) {
        guard !busy else { return }
        let menu = UIAlertController(title: record.manifest.name, message: text(record.manifest.captureMode == "generation-input" ? "generationHelp" : "saved"), preferredStyle: .alert)
        menu.addAction(UIAlertAction(title: text("exportOriginal"), style: .default) { [weak self] _ in self?.export(record.originalURL) })
        menu.addAction(UIAlertAction(title: text("exportDataset"), style: .default) { [weak self] _ in
            self?.zip([record.directory.appendingPathComponent("Original"), record.manifestURL], id: record.manifest.id)
        })
        menu.addAction(UIAlertAction(title: MeasurementGuide.roomText("preview"), style: .default) { [weak self] _ in self?.preview(record.originalURL) })
        menu.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .cancel))
        present(menu, animated: true)
    }
    private func zip(_ paths: [URL], id: String) {
        guard !busy else { return }; setBusy(true)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("kantura-source-" + id + ".zip")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Zip.zipFiles(paths: paths, zipFilePath: target, password: nil, progress: nil) }
            DispatchQueue.main.async {
                guard let self = self else { return }; self.setBusy(false)
                switch result {
                case .success: self.export(target)
                case .failure(let error): self.failure(error.localizedDescription)
                }
            }
        }
    }
    private func export(_ url: URL) {
        guard presentedViewController == nil else { return }
        present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true)
    }
    private func preview(_ url: URL) {
        guard presentedViewController == nil else { return }; previewURL = url
        let preview = QLPreviewController(); preview.dataSource = self; present(preview, animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewURL! as NSURL }
    private func failure(_ value: String) { status.text = value; UIAccessibility.post(notification: .announcement, argument: value) }
    @objc private func close() {
        guard !busy, presentedViewController == nil else { return }; let callback = onClose
        dismiss(animated: true) { callback?() }
    }
}

private final class SceneCameraPreview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// Only one shot can be in flight; metadata/container bytes are written directly
/// from AVCapturePhoto. Navigation waits for this write rather than losing it.
private final class ScenePhotoCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onFinished: (() -> Void)?
    private let mode: String
    private let captureName: String
    private var directory: URL?
    private var count = 0
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "io.kantura.scene-camera")
    private let preview = SceneCameraPreview()
    private let countLabel = UILabel()
    private let message = UILabel()
    private let thumbnail = UIImageView()
    private let shutter = KanturaButton(type: .system)
    private var configured = false // Only accessed on queue.
    private var shot = ScenePhotoWriteBarrier() // Only accessed on main queue.
    private var capturing: Bool { shot.isBusy }
    private var cameraReady = false
    private var closed = false
    private var observers: [NSObjectProtocol] = []
    private func text(_ key: String) -> String { MeasurementGuide.sceneText(key) }
    private var captureHelp: String { text(mode == "panorama" ? "panoramaCaptureHelp" : mode == "generation-input" ? "generationHelp" : "photoHelp") }
    private var maximumPhotos: Int { mode == "generation-input" ? 1 : mode == "panorama" ? 36 : 2000 }

    init(mode: String, name: String, saved: SavedPhotoDataset?) {
        self.mode = mode; captureName = name; directory = saved?.directory; count = saved?.manifest.images.count ?? 0
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = text(mode); view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: MeasurementGuide.roomText("close"), style: .done,
                                                           target: self, action: #selector(finish))
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.previewLayer.videoGravity = .resizeAspect; preview.previewLayer.session = session
        preview.backgroundColor = .black; view.addSubview(preview)
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let controls = UIStackView(); controls.axis = .vertical; controls.spacing = 14
        controls.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(controls)
        for label in [countLabel, message] {
            label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true; label.textColor = KanturaDesign.text
        }
        countLabel.accessibilityTraits.insert(.updatesFrequently)
        message.text = captureHelp + "\n" + text("fixedLens")
        thumbnail.contentMode = .scaleAspectFit; thumbnail.heightAnchor.constraint(equalToConstant: 90).isActive = true
        thumbnail.accessibilityLabel = text("review"); thumbnail.isAccessibilityElement = true
        shutter.setTitle(text("shutter"), for: .normal); KanturaDesign.button(shutter, primary: true)
        shutter.addAction(UIAction { [weak self] _ in self?.capture() }, for: .touchUpInside)
        let resume = KanturaButton(type: .system); resume.setTitle(text("resume"), for: .normal)
        KanturaDesign.button(resume, primary: false); resume.addAction(UIAction { [weak self] _ in self?.start() }, for: .touchUpInside)
        for item in [countLabel, shutter, thumbnail, message, resume] { controls.addArrangedSubview(item) }
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor), preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preview.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.42),
            scroll.topAnchor.constraint(equalTo: preview.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controls.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            controls.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -18),
            controls.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            controls.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        updateControls()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() })
        for event in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: event, object: session, queue: .main) { [weak self] _ in self?.pause() })
        }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); start() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if preview.previewLayer.connection?.isVideoOrientationSupported == true { preview.previewLayer.connection?.videoOrientation = orientation }
    }
    private var orientation: AVCaptureVideoOrientation {
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
    private func start() {
        guard !closed, !capturing, view.window != nil else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self, !self.closed else { return }
                guard granted else { self.message.text = self.text("permission"); return }
                guard UIApplication.shared.applicationState == .active else { return }
                self.queue.async {
                    do {
                        if !self.configured {
                            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                            else { throw MediaDataset.Failure.invalidFile }
                            let input = try AVCaptureDeviceInput(device: device)
                            // Use one physical rear-wide lens throughout the
                            // dataset; no virtual-camera switching or digital zoom.
                            try device.lockForConfiguration()
                            device.videoZoomFactor = 1
                            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                            device.unlockForConfiguration()
                            self.session.beginConfiguration()
                            self.session.sessionPreset = .photo
                            guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                                self.session.commitConfiguration(); throw MediaDataset.Failure.invalidFile
                            }
                            self.session.addInput(input); self.session.addOutput(self.output)
                            self.output.isHighResolutionCaptureEnabled = true
                            self.output.maxPhotoQualityPrioritization = .quality
                            self.session.commitConfiguration(); self.configured = true
                        }
                        if !self.session.isRunning { self.session.startRunning() }
                        DispatchQueue.main.async {
                            guard !self.closed, UIApplication.shared.applicationState == .active else { self.pause(); return }
                            self.cameraReady = self.session.isRunning; self.updateControls()
                        }
                    } catch { DispatchQueue.main.async { self.message.text = self.text("unavailable"); self.cameraReady = false; self.updateControls() } }
                }
            }
        }
    }
    private func pause() {
        cameraReady = false; updateControls(); message.text = text("paused")
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
    private func updateControls() {
        countLabel.text = text(mode == "panorama" ? "panoramaCount" : mode == "generation-input" ? "generationCount" : "count").replacingOccurrences(of: "{count}", with: String(count))
        shutter.isEnabled = cameraReady && !capturing && count < maximumPhotos
        navigationItem.leftBarButtonItem?.isEnabled = !capturing
    }
    private func capture() {
        guard cameraReady, !capturing, count < maximumPhotos else { return }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        guard shot.begin(id: settings.uniqueID) else { return }
        updateControls(); let orientation = self.orientation
        queue.async {
            guard self.session.isRunning else { DispatchQueue.main.async { self.shot.captureFinished(id: settings.uniqueID); self.pause() }; return }
            if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            settings.isHighResolutionPhotoEnabled = self.mode != "generation-input"
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .off
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Delegate callbacks can arrive on an AVFoundation queue. All file
        // writes share our serial queue; UIKit updates return to the main queue.
        let data = photo.fileDataRepresentation()
        let id = photo.resolvedSettings.uniqueID
        DispatchQueue.main.async { self.shot.processingStarted(id: id) }
        queue.async {
            do {
                if let error = error { throw error }
                guard let data = data else { throw MediaDataset.Failure.invalidFile }
                let folder = try self.directory ?? SavedPhotoDataset.createDirectory()
                self.directory = folder
                let filename = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000_000) + "-" + UUID().uuidString + ".jpg"
                let url = folder.appendingPathComponent("Images/" + filename)
                try data.write(to: url, options: .atomic)
                let saved = try SavedPhotoDataset.finish(directory: folder, name: self.captureName, source: "apple-camera", captureMode: self.mode)
                var image: UIImage?
                var quality: PhotoQuality?
                var generationOversized = self.mode == "generation-input" && data.count > MediaDataset.maximumGenerationInputBytes
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    if self.mode == "generation-input",
                       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                       let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                       let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                        generationOversized = !MediaDataset.generationInputFits(bytes: data.count, width: width.intValue, height: height.intValue)
                    }
                    if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 500] as CFDictionary) {
                        image = UIImage(cgImage: thumb)
                        quality = self.assessPreview(thumb)
                    }
                }
                DispatchQueue.main.async {
                    self.count = saved.manifest.images.count; self.shot.writeFinished(id: id)
                    self.thumbnail.image = image
                    let hint = quality?.hint
                    let qualityHint = hint.map { self.text($0.rawValue) + "\n" } ?? ""
                    let sizeHint = generationOversized ? self.text("generationSize") + "\n" : ""
                    self.message.text = sizeHint + qualityHint + self.text("qualityScope") + "\n" + self.text("review") + "\n" + self.captureHelp
                    self.updateControls()
                    UIAccessibility.post(notification: .announcement, argument: sizeHint + qualityHint + (self.countLabel.text ?? ""))
                }
            } catch { DispatchQueue.main.async { self.shot.writeFinished(id: id); self.message.text = self.text("invalid") + "\n" + error.localizedDescription; self.updateControls() } }
        }
    }
    private func assessPreview(_ image: CGImage) -> PhotoQuality? {
        let scale = min(128.0 / Double(image.width), 128.0 / Double(image.height))
        let width = max(3, min(128, Int((Double(image.width) * scale).rounded())))
        let height = max(3, min(128, Int((Double(image.height) * scale).rounded())))
        var grayscale = [UInt8](repeating: 0, count: width * height)
        let rendered = grayscale.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        return rendered ? PhotoQuality.analyze(grayscale: grayscale, width: width, height: height) : nil
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        DispatchQueue.main.async {
            self.shot.captureFinished(id: resolvedSettings.uniqueID)
            if let error = error { self.message.text = error.localizedDescription }
            self.updateControls()
        }
    }
    @objc private func finish() {
        guard !capturing, !closed else { return }; closed = true; shutter.isEnabled = false
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { let callback = self.onFinished; self.dismiss(animated: true) { callback?() } }
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
