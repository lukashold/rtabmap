import UIKit
import AVFoundation
import RoomPlan
import QuickLook
import SceneKit

/// A separate indoor, parametric capture path. It never starts RTAB-Map's AR
/// session and never represents RoomPlan's schematic surfaces as photo textures.
///
/// Flow: prepare (four short tips) → full-screen capture with one finish control
/// → result with the 3D model and headline numbers → save into the local room
/// library (no file dialog) → share separately when needed.
@available(iOS 17.0, *)
final class RoomPlanViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, UITextFieldDelegate {
    static var isSupported: Bool { RoomCaptureSession.isSupported }
    var onClose: (() -> Void)?
    /// Start another capture right after this one (skips the tips).
    var onNewRoom: (() -> Void)?
    /// A room was written to (or updated in) the local library.
    var onSaved: (() -> Void)?
    var skipPreparation = false

    private let capture = RoomCaptureView(frame: .zero)
    private var lifecycle = RoomPlanLifecycle()
    private var result: CapturedRoom?
    private var savedFiles: [URL] = []
    private var savedNames: [String]?
    private var savedDirectory: URL?
    private var interruptionObserver: NSObjectProtocol?
    private var timeout: DispatchWorkItem?
    private func text(_ key: String) -> String { MeasurementGuide.roomText(key) }
    private func home(_ key: String) -> String { MeasurementGuide.homeText(key) }

    // Preparation / failure
    private let prepScroll = UIScrollView()
    private let prepColumn = UIStackView()
    private var prepBar: UIView!
    private var prepButton: KanturaButton!
    // Capture overlay
    private let overlay = UIView()
    private let hint = KanturaHintPill(MeasurementGuide.homeText("scanHint"))
    private let finishButton = KanturaCaptureButton(title: MeasurementGuide.homeText("done"))
    private let closeButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    // Review
    private let reviewScroll = UIScrollView()
    private let reviewColumn = UIStackView()
    private var reviewBar: UIView!
    private var saveButton: KanturaButton!
    private var againButton: KanturaButton!
    private let metrics = KanturaMetricGrid([])
    private let counts = KanturaDesign.label("", style: .subheadline, secondary: true)
    private let notes = UIStackView()
    private let nameField = UITextField()
    private let buildingField = UITextField()
    private let floorField = UITextField()
    private let locationFields = UIStackView()
    private let locationToggle = UIButton(type: .system)
    private var captureFull: [NSLayoutConstraint] = []
    private var captureTop: [NSLayoutConstraint] = []
    private var document: RoomPlanDocument?
    private let photoRecorder = RoomPhotoRecorder()
    private let photoBadge = KanturaHintPill("")
    private let shutter = UIButton(type: .system)
    private var lastCoverageCheck = Date.distantPast
    private var coverageText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        view.tintColor = KanturaDesign.tint
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        isModalInPresentation = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("close"), style: .plain, target: self, action: #selector(close))
        capture.delegate = self
        capture.captureSession.delegate = self
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.clipsToBounds = true
        capture.isHidden = true
        view.addSubview(capture)
        captureFull = [
            capture.topAnchor.constraint(equalTo: view.topAnchor), capture.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            capture.leadingAnchor.constraint(equalTo: view.leadingAnchor), capture.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        captureTop = [
            capture.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            capture.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            capture.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            capture.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.38)
        ]
        buildPreparation()
        buildOverlay()
        buildReview()
        interruptionObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.lifecycle.phase == .capturing else { return }
            self.fail(self.text("interrupted"))
        }
        if !Self.isSupported { fail(text("unsupported")) } else { showPreparation() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // "Scan next room" goes straight to the camera; the tips were just seen.
        if skipPreparation && lifecycle.phase == .ready { skipPreparation = false; authorizeCamera() }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { overlay.isHidden ? .default : .lightContent }

    // MARK: Layout

    private func column(_ scroll: UIScrollView, _ column: UIStackView) {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        column.axis = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(column)
        let preferred = column.widthAnchor.constraint(equalToConstant: 600)
        preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            column.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            preferred
        ])
    }

    private func buildPreparation() {
        column(prepScroll, prepColumn)
        prepButton = KanturaDesign.primaryButton(home("startScan"), icon: "viewfinder") { [weak self] in self?.prepAction() }
        prepBar = KanturaDesign.bottomBar([prepButton], in: self)
        NSLayoutConstraint.activate([
            prepScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            prepScroll.bottomAnchor.constraint(equalTo: prepBar.topAnchor)
        ])
    }

    private func showPreparation() {
        prepColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = KanturaDesign.label(home("prepTitle"), style: .largeTitle)
        heading.accessibilityTraits.insert(.header)
        prepColumn.addArrangedSubview(heading)
        prepColumn.addArrangedSubview(KanturaDesign.label(home("prepSubtitle"), style: .body, secondary: true))
        prepColumn.setCustomSpacing(24, after: prepColumn.arrangedSubviews.last!)
        for (key, icon) in [("tipLight", "lightbulb"), ("tipSlow", "figure.walk"), ("tipWalls", "square.split.bottomrightquarter"), ("tipFinish", "arrow.triangle.2.circlepath")] {
            let title = KanturaDesign.label(home(key), style: .headline)
            let detail = KanturaDesign.label(home(key + "Detail"), style: .subheadline, secondary: true)
            let copy = UIStackView(arrangedSubviews: [title, detail])
            copy.axis = .vertical
            copy.spacing = 3
            let row = UIStackView(arrangedSubviews: [KanturaDesign.symbolTile(icon), copy])
            row.spacing = 14
            row.alignment = .top
            row.isAccessibilityElement = true
            row.accessibilityLabel = home(key) + ". " + home(key + "Detail")
            prepColumn.addArrangedSubview(row)
            prepColumn.setCustomSpacing(20, after: row)
        }
        prepColumn.addArrangedSubview(KanturaDesign.label(text("noTexture"), style: .footnote, secondary: true))
        prepButton.setTitle("  " + home("startScan"), for: .normal)
        prepButton.setImage(UIImage(systemName: "viewfinder"), for: .normal)
        setStage(prep: true)
    }

    private func buildOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        view.addSubview(overlay)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 22
        closeButton.accessibilityLabel = text("close")
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        finishButton.addTarget(self, action: #selector(finishCapture), for: .touchUpInside)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        photoBadge.isHidden = true
        photoBadge.isAccessibilityElement = true
        // Deliberate photos: tap to take the next steady frame.
        let shutterConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        shutter.setImage(UIImage(systemName: "camera.fill", withConfiguration: shutterConfig), for: .normal)
        shutter.tintColor = .white
        shutter.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        shutter.layer.cornerRadius = 28
        shutter.accessibilityLabel = home("photoNow")
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addAction(UIAction { [weak self] _ in
            self?.photoRecorder.captureNow()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }, for: .touchUpInside)
        overlay.addSubview(shutter)
        NSLayoutConstraint.activate([
            shutter.widthAnchor.constraint(equalToConstant: 56), shutter.heightAnchor.constraint(equalToConstant: 56),
            shutter.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        ])
        photoRecorder.onPhoto = { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4) }
        for item in [closeButton, hint, finishButton, spinner, photoBadge] as [UIView] { item.translatesAutoresizingMaskIntoConstraints = false; overlay.addSubview(item) }
        NSLayoutConstraint.activate([
            photoBadge.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            photoBadge.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor), overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44), closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),
            hint.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            finishButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            finishButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .none
        field.backgroundColor = KanturaDesign.surface
        field.textColor = KanturaDesign.text
        field.tintColor = KanturaDesign.tint
        field.layer.cornerRadius = 14
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = KanturaDesign.border.cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 50))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 50))
        field.rightViewMode = .always
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.delegate = self
        field.autocapitalizationType = .words
        field.clearButtonMode = .whileEditing
        field.addTarget(self, action: #selector(namesChanged), for: .editingChanged)
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    }

    private func buildReview() {
        column(reviewScroll, reviewColumn)
        saveButton = KanturaDesign.primaryButton(home("save"), icon: "checkmark") { [weak self] in self?.saveOrFinish() }
        againButton = KanturaDesign.secondaryButton(home("rescan"), icon: "arrow.counterclockwise") { [weak self] in self?.newRoom() }
        reviewBar = KanturaDesign.bottomBar([saveButton, againButton], in: self)
        let followsBar = reviewScroll.bottomAnchor.constraint(equalTo: reviewBar.topAnchor)
        followsBar.priority = .defaultHigh
        NSLayoutConstraint.activate([
            reviewScroll.topAnchor.constraint(equalTo: capture.bottomAnchor, constant: 4),
            followsBar,
            reviewScroll.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor)
        ])
        notes.axis = .vertical
        notes.spacing = 6
        styleField(nameField, placeholder: home("roomName"))
        nameField.returnKeyType = .done
        styleField(buildingField, placeholder: text("building"))
        buildingField.returnKeyType = .next
        styleField(floorField, placeholder: text("floorName"))
        floorField.returnKeyType = .done
        locationFields.axis = .vertical
        locationFields.spacing = 8
        locationFields.isHidden = true
        [buildingField, floorField].forEach { locationFields.addArrangedSubview($0) }
        locationToggle.contentHorizontalAlignment = .leading
        locationToggle.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        locationToggle.titleLabel?.adjustsFontForContentSizeCategory = true
        locationToggle.tintColor = KanturaDesign.tint
        locationToggle.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.locationFields.isHidden.toggle()
            self.refreshLocationToggle()
        }, for: .touchUpInside)
        let surfaces = KanturaDesign.secondaryButton(home("allSurfaces"), icon: "list.bullet") { [weak self] in
            guard let self = self, let document = self.document else { return }
            self.navigationController?.pushViewController(RoomSurfacesViewController(document: document), animated: true)
        }
        let heading = KanturaDesign.label(home("resultTitle"), style: .title2)
        heading.accessibilityTraits.insert(.header)
        for item in [heading, metrics, counts, nameField, locationToggle, locationFields, notes, surfaces] as [UIView] { reviewColumn.addArrangedSubview(item) }
        reviewColumn.setCustomSpacing(20, after: counts)
    }

    private func refreshLocationToggle() {
        let building = (buildingField.text ?? "").trimmingCharacters(in: .whitespaces), floor = (floorField.text ?? "").trimmingCharacters(in: .whitespaces)
        let summary = [building, floor].filter { !$0.isEmpty }.joined(separator: " · ")
        locationToggle.setTitle("  " + home("buildingFloor") + (summary.isEmpty ? "" : ": " + summary), for: .normal)
        locationToggle.setImage(UIImage(systemName: locationFields.isHidden ? "chevron.down" : "chevron.up"), for: .normal)
    }

    /// Exactly one of preparation, live capture or review is visible.
    private func setStage(prep: Bool = false, capturing: Bool = false, review: Bool = false) {
        prepScroll.isHidden = !prep
        prepBar.isHidden = !prep
        overlay.isHidden = !capturing
        reviewScroll.isHidden = !review
        reviewBar.isHidden = !review
        capture.isHidden = !(capturing || review)
        NSLayoutConstraint.deactivate(captureFull + captureTop)
        NSLayoutConstraint.activate(review ? captureTop : captureFull)
        capture.layer.cornerRadius = review ? 22 : 0
        capture.layer.cornerCurve = .continuous
        view.backgroundColor = capturing ? .black : KanturaDesign.background
        navigationController?.setNavigationBarHidden(capturing, animated: true)
        title = review ? home("resultTitle") : nil
        setNeedsStatusBarAppearanceUpdate()
        view.bringSubviewToFront(overlay)
    }

    // MARK: Capture

    private func prepAction() {
        switch lifecycle.phase {
        case .ready: authorizeCamera()
        default: closeNow()
        }
    }

    private func authorizeCamera() {
        guard lifecycle.authorize() else { return }
        prepButton.isEnabled = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.lifecycle.phase == .authorizing else { return }
                    if granted { self.startCapture() } else { self.fail(self.text("cameraDenied")) }
                }
            }
        default: fail(text("cameraDenied"))
        }
    }

    private func startCapture() {
        guard Self.isSupported, lifecycle.start() else { return }
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        hint.label.text = home("scanHint")
        hint.isHidden = false
        finishButton.isEnabled = true
        finishButton.isHidden = false
        setStage(capturing: true)
        capture.captureSession.run(configuration: configuration)
        // Photos come from RoomPlan's own AR session, so they share the room's coordinates.
        photoRecorder.start(session: capture.captureSession.arSession)
        photoBadge.isHidden = false
        refreshPhotoBadge()
        UIAccessibility.post(notification: .screenChanged, argument: hint)
    }

    @objc private func finishCapture() {
        guard lifecycle.finish() else { return }
        finishButton.isEnabled = false
        finishButton.isHidden = true
        hint.label.text = home("processing")
        spinner.startAnimating()
        UIAccessibility.post(notification: .announcement, argument: home("processing"))
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.lifecycle.phase == .processing else { return }
            self.fail(self.text("processingFailed"))
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
        photoRecorder.stop()
        photoBadge.isHidden = true
        capture.captureSession.stop(pauseARSession: true)
    }

    private func refreshPhotoBadge() {
        guard lifecycle.phase == .capturing else { return }
        photoBadge.label.text = "📷 \(photoRecorder.count)" + (coverageText.isEmpty ? "" : " · " + coverageText)
        photoBadge.accessibilityLabel = home("photosTaken").replacingOccurrences(of: "{count}", with: "\(photoRecorder.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshPhotoBadge() }
    }

    /// Live room updates: every 2 s, check which walls still lack photos and
    /// point the user to the next one ("left", "right", "behind you", …).
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.lifecycle.phase == .capturing, Date().timeIntervalSince(self.lastCoverageCheck) > 2 else { return }
            self.lastCoverageCheck = Date()
            let document = self.makeDocument(room, name: "live"), photos = self.photoRecorder.photos, camera = self.photoRecorder.latestTransform
            DispatchQueue.global(qos: .utility).async {
                let walls = RoomPhotoCoverage.walls(document, photos: photos, tileSize: 0.6)
                guard !walls.isEmpty else { return }
                let total = walls.map { $0.fraction }.reduce(0, +) / Double(walls.count)
                let next = walls.filter { $0.fraction < 0.7 }.min { $0.fraction < $1.fraction }
                DispatchQueue.main.async {
                    guard self.lifecycle.phase == .capturing else { return }
                    self.coverageText = self.home("photoCoverage").replacingOccurrences(of: "{percent}", with: "\(Int((total * 100).rounded()))")
                    if let next = next, let camera = camera {
                        self.hint.label.text = self.home("photoGuide_" + RoomPhotoCoverage.direction(to: next.centre, camera: camera).rawValue)
                    } else if walls.allSatisfy({ $0.fraction >= 0.7 }) {
                        self.hint.label.text = self.home("photoGuideDone")
                    }
                }
            }
        }
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        // The return value must be decided synchronously, even if RoomPlan calls
        // its delegate from outside the main queue.
        if !Thread.isMainThread {
            return DispatchQueue.main.sync { self.shouldPresent(error: error) }
        }
        return shouldPresent(error: error)
    }

    private func shouldPresent(error: Error?) -> Bool {
        guard lifecycle.phase == .processing else { return false }
        if error != nil { fail(text("processingFailed")); return false }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.lifecycle.phase == .processing else { return }
            guard error == nil else { self.fail(self.text("processingFailed")); return }
            let document = self.makeDocument(processedResult, name: self.text("title"))
            do { try document.validate() }
            catch RoomPlanDocument.ValidationError.tooComplex { self.fail(self.text("tooComplex")); return }
            catch { self.fail(self.text("empty")); return }
            guard self.lifecycle.processed() else { return }
            self.timeout?.cancel()
            self.spinner.stopAnimating()
            self.result = processedResult
            self.showReview(document)
        }
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if error != nil && (self.lifecycle.phase == .capturing || self.lifecycle.phase == .processing) {
                self.fail(self.text("processingFailed"))
            } else if self.lifecycle.phase == .capturing {
                self.fail(self.text("interrupted"))
            }
        }
    }

    // MARK: Review and save

    private func showReview(_ document: RoomPlanDocument) {
        self.document = document
        let summary = RoomPlanSummary(document)
        metrics.update(KanturaDesign.roomMetrics(summary))
        counts.text = home("doorsWindows").replacingOccurrences(of: "{doors}", with: "\(summary.doors)").replacingOccurrences(of: "{windows}", with: "\(summary.windows)")
        notes.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for note in KanturaDesign.roomNotes(summary) + [text("separateOrigins")] {
            notes.addArrangedSubview(KanturaDesign.label(note, style: .footnote, secondary: true))
        }
        buildingField.text = UserDefaults.standard.string(forKey: "KanturaRoomBuilding") ?? text("defaultBuilding")
        floorField.text = UserDefaults.standard.string(forKey: "KanturaRoomFloor") ?? text("defaultFloor")
        nameField.text = ""
        refreshLocationToggle()
        setStage(review: true)
        namesChanged()
        reviewScroll.setContentOffset(.zero, animated: false)
        UIAccessibility.post(notification: .screenChanged, argument: metrics)
    }

    private var enteredNames: [String] {
        [(buildingField, "defaultBuilding"), (floorField, "defaultFloor"), (nameField, "title")].map { field, fallback in
            let value = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return String((value.isEmpty ? text(fallback) : value).prefix(200))
        }
    }

    private var hasSavedReview: Bool {
        savedNames == enteredNames && savedFiles.count == 2 &&
            savedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    @objc private func namesChanged() {
        guard lifecycle.phase == .review else { return }
        let saved = hasSavedReview
        saveButton.setTitle("  " + home(saved ? "done" : "save"), for: .normal)
        saveButton.setImage(UIImage(systemName: saved ? "checkmark.circle.fill" : "checkmark"), for: .normal)
        againButton.setTitle("  " + home(saved ? "nextRoom" : "rescan"), for: .normal)
        againButton.setImage(UIImage(systemName: saved ? "plus" : "arrow.counterclockwise"), for: .normal)
        againButton.isHidden = onNewRoom == nil
        if saved {
            let share = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share(_:)))
            share.accessibilityLabel = home("share")
            navigationItem.rightBarButtonItem = share
        } else { navigationItem.rightBarButtonItem = nil }
        refreshLocationToggle()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === buildingField { floorField.becomeFirstResponder() } else { textField.resignFirstResponder() }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        view.layoutIfNeeded()
        reviewScroll.scrollRectToVisible(textField.convert(textField.bounds, to: reviewScroll).insetBy(dx: 0, dy: -20), animated: true)
    }

    private func makeDocument(_ room: CapturedRoom, name: String) -> RoomPlanDocument {
        func convert(_ surface: CapturedRoom.Surface, kind: String) -> RoomPlanDocument.Surface {
            let matrix = surface.transform
            let transform = (0..<4).flatMap { column in (0..<4).map { row in Double(matrix[column][row]) } }
            let confidence: String
            switch surface.confidence {
            case .high: confidence = "high"
            case .medium: confidence = "medium"
            case .low: confidence = "low"
            @unknown default: confidence = "unknown"
            }
            let corners = surface.polygonCorners.map { [Double($0.x), Double($0.y), Double($0.z)] }
            return RoomPlanDocument.Surface(id: surface.identifier.uuidString, kind: kind,
                dimensions: [Double(surface.dimensions.x), Double(surface.dimensions.y), Double(surface.dimensions.z)],
                transform: transform, confidence: confidence, polygonCorners: corners.count >= 3 ? corners : nil)
        }
        let surfaces = room.walls.map { convert($0, kind: "wall") }
            + room.doors.map { convert($0, kind: "door") }
            + room.windows.map { convert($0, kind: "window") }
            + room.openings.map { convert($0, kind: "opening") }
            + room.floors.map { convert($0, kind: "floor") }
        var document = RoomPlanDocument(name: name, createdAt: ISO8601DateFormatter().string(from: Date()), roomId: room.identifier.uuidString, surfaces: surfaces)
        let objects = room.objects.map { object -> RoomPlanDocument.Object in
            let matrix = object.transform
            let confidence: String
            switch object.confidence {
            case .high: confidence = "high"
            case .medium: confidence = "medium"
            case .low: confidence = "low"
            @unknown default: confidence = "unknown"
            }
            let category = String(describing: object.category).filter(\.isLetter)
            return RoomPlanDocument.Object(id: object.identifier.uuidString, category: category.isEmpty ? "unknown" : String(category.prefix(40)),
                dimensions: [Double(object.dimensions.x), Double(object.dimensions.y), Double(object.dimensions.z)],
                transform: (0..<4).flatMap { column in (0..<4).map { row in Double(matrix[column][row]) } }, confidence: confidence)
        }
        if !objects.isEmpty { document.objects = Array(objects.prefix(150)) }
        return document
    }

    private func saveOrFinish() {
        guard let room = result, lifecycle.phase == .review else { return }
        view.endEditing(true)
        if hasSavedReview { closeNow(); return }
        guard lifecycle.export() else { return }
        let names = enteredNames
        var document = makeDocument(room, name: names[2])
        document.building = RoomPlanDocument.Building(name: names[0], floor: names[1], room: names[2])
        UserDefaults.standard.set(document.building?.name, forKey: "KanturaRoomBuilding")
        UserDefaults.standard.set(document.building?.floor, forKey: "KanturaRoomFloor")
        let exportDocument = document
        // Renaming after a save updates the same library entry instead of adding a copy.
        let previous = savedDirectory
        let recorder = photoRecorder
        setReviewEnabled(false)
        saveButton.setTitle("  " + text("exporting"), for: .normal)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<(URL, [URL]), Error>
            do {
                let identifier = UUID()
                let directory = previous ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("KanturaRooms", isDirectory: true)
                    .appendingPathComponent(identifier.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stem = SavedRoomPlan.exportStem(name: exportDocument.name, identifier: identifier)
                let json = directory.appendingPathComponent(stem + ".kantura-room.json")
                let usdz = directory.appendingPathComponent(stem + ".usdz")
                let stale = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                try exportDocument.encoded().write(to: json, options: .atomic)
                try room.export(to: usdz, exportOptions: .mesh)
                // Photos are optional: a failed copy must not lose the room itself.
                try? recorder.write(to: directory)
                // Only after both new files exist, remove the previous pair (photos stay).
                for file in stale where file != json && file != usdz && file.lastPathComponent != "photos" { try? FileManager.default.removeItem(at: file) }
                outcome = .success((directory, [json, usdz]))
            } catch { outcome = .failure(error) }
            DispatchQueue.main.async {
                guard let self = self, self.lifecycle.phase == .exporting else { return }
                self.lifecycle.exported()
                self.setReviewEnabled(true)
                switch outcome {
                case .success(let (directory, urls)):
                    self.savedDirectory = directory
                    self.savedNames = names
                    self.savedFiles = urls
                    self.document = exportDocument
                    self.onSaved?()
                    UIAccessibility.post(notification: .announcement, argument: self.home("saved"))
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                case .failure:
                    let alert = UIAlertController(title: self.text("exportFailed"), message: self.text("exportRetry"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: self.text("close"), style: .default))
                    self.present(alert, animated: true)
                }
                self.namesChanged()
            }
        }
    }

    private func setReviewEnabled(_ enabled: Bool) {
        [saveButton, againButton].forEach { $0?.isEnabled = enabled }
        [nameField, buildingField, floorField].forEach { $0.isEnabled = enabled }
        navigationItem.leftBarButtonItem?.isEnabled = enabled
        navigationItem.rightBarButtonItem?.isEnabled = enabled
    }

    @objc private func share(_ sender: UIBarButtonItem) {
        guard presentedViewController == nil, hasSavedReview else { return }
        let activity = UIActivityViewController(activityItems: savedFiles, applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = sender
        present(activity, animated: true)
    }

    // MARK: Failure and leaving

    private func fail(_ message: String) {
        guard lifecycle.phase != .cancelled && lifecycle.phase != .failed else { return }
        let wasCapturing = lifecycle.phase == .capturing
        lifecycle.fail()
        timeout?.cancel()
        if wasCapturing { capture.captureSession.stop(pauseARSession: true) }
        capture.captureSession.arSession.pause()
        spinner.stopAnimating()
        photoRecorder.stop()
        prepColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let icon = KanturaDesign.symbolTile("exclamationmark.triangle", size: 64)
        let wrapper = UIView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(icon)
        NSLayoutConstraint.activate([icon.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 40), icon.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor), icon.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor)])
        let label = KanturaDesign.label(message, style: .title3)
        label.textAlignment = .center
        prepColumn.addArrangedSubview(wrapper)
        prepColumn.addArrangedSubview(label)
        prepButton.isEnabled = true
        prepButton.setTitle(text("close"), for: .normal)
        prepButton.setImage(nil, for: .normal)
        setStage(prep: true)
        UIAccessibility.post(notification: .screenChanged, argument: label)
    }

    @objc private func close() { leave(after: nil) }
    private func newRoom() {
        if hasSavedReview { closeNow(after: onNewRoom) } else { leave(after: onNewRoom) }
    }

    private func leave(after callback: (() -> Void)?) {
        guard lifecycle.phase != .exporting, presentedViewController == nil else { return }
        let hasUnsavedWork = lifecycle.phase == .capturing || lifecycle.phase == .processing || (lifecycle.phase == .review && !hasSavedReview)
        if hasUnsavedWork {
            let alert = UIAlertController(title: text("discardTitle"), message: text("discardBody"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("keep"), style: .cancel))
            alert.addAction(UIAlertAction(title: text("discard"), style: .destructive) { [weak self] _ in self?.closeNow(after: callback) })
            present(alert, animated: true)
        } else { closeNow(after: callback) }
    }

    private func closeNow(after next: (() -> Void)? = nil) {
        let wasCapturing = lifecycle.phase == .capturing
        photoRecorder.discard()
        lifecycle.cancel()
        timeout?.cancel()
        capture.delegate = nil
        capture.captureSession.delegate = nil
        if wasCapturing { capture.captureSession.stop(pauseARSession: true) }
        capture.captureSession.arSession.pause()
        let callback = onClose
        dismiss(animated: true) { callback?(); next?() }
    }

    deinit {
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer) }
        timeout?.cancel()
    }
}

private enum RoomPlanPresentation {
    static func addMeasurements(_ document: RoomPlanDocument, to stack: UIStackView) {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        func number(_ value: Double) -> String { formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value) }
        // RoomPlan confidence describes the recognized category, not an accuracy
        // estimate for dimensions. Explain it once before the individual values.
        stack.addArrangedSubview(KanturaDesign.label(MeasurementGuide.roomText("confidenceHelp"), style: .footnote, secondary: true))
        var counts: [String: Int] = [:]
        for surface in document.surfaces {
            counts[surface.kind, default: 0] += 1
            let title = MeasurementGuide.roomText(surface.kind) + " \(counts[surface.kind]!)"
            let heading = KanturaDesign.label(title, style: .headline)
            let content = UIStackView(arrangedSubviews: [heading])
            var accessibility = [title]
            for measurement in surface.displayMeasurements {
                let key: String
                switch measurement.kind {
                case .width: key = "dimensionWidth"
                case .height: key = "dimensionHeight"
                case .area: key = "dimensionArea"
                }
                let label = MeasurementGuide.roomText(key)
                let value = "\(number(measurement.value)) \(measurement.unit)"
                // Isolate the numeric value and SI unit, keeping the translated
                // label in the natural reading direction (including Arabic).
                let metric = KanturaDesign.label(label + ": \u{2066}" + value + "\u{2069}", style: .body)
                metric.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium))
                content.addArrangedSubview(metric)
                accessibility.append(label + ": " + value)
            }
            if surface.kind == "floor", surface.displayMeasurements.isEmpty {
                let unavailable = MeasurementGuide.roomText("areaUnavailable")
                content.addArrangedSubview(KanturaDesign.label(unavailable, style: .body, secondary: true))
                accessibility.append(unavailable)
            }
            let confidenceText = MeasurementGuide.roomText("confidence") + ": " + MeasurementGuide.roomText(surface.confidence)
            content.addArrangedSubview(KanturaDesign.label(confidenceText, style: .footnote, secondary: true))
            accessibility.append(confidenceText)
            content.axis = .vertical
            content.spacing = 6
            let card = KanturaDesign.inset(content, padding: 16)
            card.isAccessibilityElement = true
            card.accessibilityLabel = accessibility.joined(separator: ", ")
            card.accessibilityLanguage = MeasurementGuide.selectedLanguage
            stack.addArrangedSubview(card)
        }
    }
}

/// Every detected wall, door, window, opening and floor with its dimensions.
final class RoomSurfacesViewController: UIViewController {
    private let document: RoomPlanDocument
    init(document: RoomPlanDocument) { self.document = document; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = MeasurementGuide.homeText("allSurfaces")
        let (_, column) = KanturaDesign.scrollColumn(in: self, spacing: 10)
        column.addArrangedSubview(KanturaDesign.label(MeasurementGuide.roomText("verify"), style: .footnote, secondary: true))
        RoomPlanPresentation.addMeasurements(document, to: column)
    }
}

/// A saved room: interactive 3D model, headline numbers, share and delete.
/// Uses exactly the JSON/USDZ pair already on disk.
final class SavedRoomViewController: UIViewController, QLPreviewControllerDataSource {
    static let changed = Notification.Name("KanturaRoomChanged")
    private var room: SavedRoomPlan
    private var column: UIStackView!
    private var observer: NSObjectProtocol?
    var onDeleted: (() -> Void)?
    init(room: SavedRoomPlan) { self.room = room; super.init(nibName: nil, bundle: nil) }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    /// Remove one room folder from the local library (never anything outside it).
    static func remove(_ room: SavedRoomPlan) {
        let library = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KanturaRooms", isDirectory: true).standardizedFileURL
        let folder = room.jsonURL.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent() == library else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        let name = room.document.building?.room ?? room.document.name
        title = name
        let delete = UIAction(title: text("delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() }
        let more = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis.circle"), primaryAction: nil, menu: UIMenu(children: [delete]))
        more.accessibilityLabel = MeasurementGuide.homeText("settings")
        navigationItem.rightBarButtonItem = more

        column = KanturaDesign.scrollColumn(in: self, spacing: 14).column
        // Corrections made in the room view update numbers here as well.
        observer = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let updated = note.object as? SavedRoomPlan, updated.jsonURL == self.room.jsonURL else { return }
            self.room = updated
            self.render()
        }
        render()
    }

    private func render() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var context = [KanturaHomeViewController.date(room.document.createdAt)]
        if let building = room.document.building { context.insert(building.name + " · " + building.floor, at: 0) }
        column.addArrangedSubview(KanturaDesign.label(context.joined(separator: " · "), style: .subheadline, secondary: true))

        let scene = SCNView()
        scene.scene = try? SCNScene(url: room.modelURL, options: nil)
        scene.allowsCameraControl = true
        scene.autoenablesDefaultLighting = true
        scene.backgroundColor = KanturaDesign.surface
        scene.layer.cornerRadius = 22
        scene.layer.cornerCurve = .continuous
        scene.clipsToBounds = true
        scene.isAccessibilityElement = true
        scene.accessibilityLabel = text("view3d")
        scene.heightAnchor.constraint(equalTo: scene.widthAnchor, multiplier: 0.75).isActive = true
        column.addArrangedSubview(scene)

        let summary = RoomPlanSummary(room.document)
        column.addArrangedSubview(KanturaMetricGrid(KanturaDesign.roomMetrics(summary)))
        column.addArrangedSubview(KanturaDesign.label(text("doorsWindows").replacingOccurrences(of: "{doors}", with: "\(summary.doors)").replacingOccurrences(of: "{windows}", with: "\(summary.windows)"), style: .subheadline, secondary: true))
        column.addArrangedSubview(KanturaDesign.primaryButton(text("walkTitle"), icon: "figure.stand") { [weak self] in
            guard let self = self else { return }
            self.navigationController?.pushViewController(RoomWalkthroughViewController(room: self.room), animated: true)
        })
        if !RoomWalkthroughViewController.hasPhotos(room) {
            column.addArrangedSubview(KanturaDesign.label(text("walkNoPhotos"), style: .footnote, secondary: true))
        }
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("transportTitle"), icon: "shippingbox") { [weak self] in
            guard let self = self else { return }
            self.navigationController?.pushViewController(TransportCheckViewController(preselected: self.room), animated: true)
        })
        let extras = RoomExtras.load(from: room.jsonURL.deletingLastPathComponent())
        let openMarkers = extras.markers.filter { $0.status == "open" }.count
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("markers") + (extras.markers.isEmpty ? "" : " · " + text("markersOpenCount").replacingOccurrences(of: "{count}", with: "\(openMarkers)")), icon: "mappin.and.ellipse") { [weak self] in
            guard let self = self else { return }
            let list = MarkerListViewController(folder: self.room.jsonURL.deletingLastPathComponent())
            list.onChange = { [weak self] _ in self?.render() }
            self.navigationController?.pushViewController(list, animated: true)
        })
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("export"), icon: "square.and.arrow.up") { [weak self] in
            guard let self = self else { return }
            self.navigationController?.pushViewController(RoomShareViewController(room: self.room), animated: true)
        })
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("view3d"), icon: "arkit") { [weak self] in self?.preview() })
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("allSurfaces"), icon: "list.bullet") { [weak self] in
            guard let self = self else { return }
            self.navigationController?.pushViewController(RoomSurfacesViewController(document: self.room.document), animated: true)
        })
        for note in KanturaDesign.roomNotes(summary) + [text("computerNote"), MeasurementGuide.roomText("separateOrigins")] {
            column.addArrangedSubview(KanturaDesign.label(note, style: .footnote, secondary: true))
        }
    }

    private func share() {
        guard presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: [room.jsonURL, room.modelURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(activity, animated: true)
    }

    private func preview() {
        let controller = QLPreviewController()
        controller.dataSource = self
        navigationController?.pushViewController(controller, animated: true)
    }

    private func confirmDelete() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: text("deleteTitle"), message: text("deleteBody"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("delete"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            SavedRoomViewController.remove(self.room)
            self.onDeleted?()
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { room.modelURL as NSURL }
}
