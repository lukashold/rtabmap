import UIKit
import AVFoundation
import RoomPlan
import QuickLook

/// A separate indoor, parametric capture path. It never starts RTAB-Map's AR
/// session and never represents RoomPlan's schematic surfaces as photo textures.
@available(iOS 17.0, *)
final class RoomPlanViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, UITextFieldDelegate {
    static var isSupported: Bool { RoomCaptureSession.isSupported }
    var onClose: (() -> Void)?
    var onNewRoom: (() -> Void)?
    private let capture = RoomCaptureView(frame: .zero)
    private var lifecycle = RoomPlanLifecycle()
    private var result: CapturedRoom?
    private var savedFiles: [URL] = []
    private var savedNames: [String]?
    private let status = UILabel()
    private let statusCard = KanturaSurface(frame: .zero)
    private let primary = KanturaButton(type: .system)
    private let anotherRoom = KanturaButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let resultsScroll = UIScrollView()
    private let results = UIStackView()
    private let body = UIStackView()
    private let nameField = UITextField()
    private let buildingField = UITextField()
    private let floorField = UITextField()
    private var interruptionObserver: NSObjectProtocol?
    private var keyboardObserver: NSObjectProtocol?
    private var timeout: DispatchWorkItem?
    private var captureHeight: NSLayoutConstraint?
    private func text(_ key: String) -> String { MeasurementGuide.roomText(key) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = text("title")
        view.backgroundColor = KanturaDesign.background
        view.tintColor = KanturaDesign.tint
        KanturaDesign.navigation(self)
        isModalInPresentation = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("close"), style: .plain, target: self, action: #selector(close))
        capture.delegate = self
        capture.captureSession.delegate = self
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.layer.cornerRadius = 26
        capture.layer.cornerCurve = .continuous
        capture.clipsToBounds = true
        capture.isHidden = true
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .headline)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = KanturaDesign.text
        status.translatesAutoresizingMaskIntoConstraints = false
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(status)
        KanturaDesign.button(primary, primary: true)
        primary.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        primary.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(primary)
        KanturaDesign.button(anotherRoom, primary: false)
        anotherRoom.setTitle(text("newRoom"), for: .normal)
        anotherRoom.addTarget(self, action: #selector(newRoom), for: .touchUpInside)
        spinner.hidesWhenStopped = true
        spinner.color = KanturaDesign.tint
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.keyboardDismissMode = .interactive
        resultsScroll.alwaysBounceVertical = true
        view.addSubview(resultsScroll)
        results.axis = .vertical
        results.spacing = 16
        results.translatesAutoresizingMaskIntoConstraints = false
        body.axis = .vertical
        body.spacing = 16
        body.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.addSubview(body)
        let sections: [UIView] = [statusCard, capture, results]
        sections.forEach { body.addArrangedSubview($0) }
        view.bringSubviewToFront(spinner)
        captureHeight = capture.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.48)
        captureHeight?.priority = .defaultHigh
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -18),
            status.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 15),
            status.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -15),
            captureHeight!,
            primary.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            primary.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            primary.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: capture.centerYAnchor),
            resultsScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            resultsScroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            resultsScroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            resultsScroll.bottomAnchor.constraint(equalTo: primary.topAnchor, constant: -12),
            body.leadingAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.trailingAnchor),
            body.topAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.bottomAnchor),
            body.widthAnchor.constraint(equalTo: resultsScroll.frameLayoutGuide.widthAnchor)
        ])
        addInformation(text("intro"), icon: "viewfinder")
        addInformation(text("noTexture"), icon: "info.circle")
        status.text = text("prepare")
        primary.setTitle(text("start"), for: .normal)
        interruptionObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.lifecycle.phase == .capturing else { return }
            self.fail(self.text("interrupted"))
        }
        keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) { [weak self] _ in
            self?.revealFocusedField()
        }
        if !Self.isSupported { fail(text("unsupported")) }
    }

    private func addInformation(_ value: String, icon: String) {
        let symbol = UIImageView(image: UIImage(systemName: icon))
        symbol.tintColor = KanturaDesign.tint
        symbol.contentMode = .top
        symbol.widthAnchor.constraint(equalToConstant: 22).isActive = true
        symbol.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [symbol, KanturaDesign.label(value, style: .subheadline, secondary: true)])
        row.alignment = .top
        row.spacing = 12
        results.addArrangedSubview(KanturaDesign.inset(row, padding: 18))
    }

    @objc private func primaryAction() {
        switch lifecycle.phase {
        case .ready: authorizeCamera()
        case .capturing:
            guard lifecycle.finish() else { return }
            status.text = text("processing")
            primary.setTitle(text("processing"), for: .normal)
            primary.isEnabled = false
            spinner.startAnimating()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.lifecycle.phase == .processing else { return }
                self.fail(self.text("processingFailed"))
            }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
            capture.captureSession.stop(pauseARSession: true)
        case .review: exportFiles()
        case .failed: closeNow()
        default: break
        }
    }

    private func authorizeCamera() {
        guard lifecycle.authorize() else { return }
        primary.isEnabled = false
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
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        addInformation(text("scanHelp"), icon: "viewfinder")
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        status.text = text("scanning")
        primary.setTitle(text("finish"), for: .normal)
        primary.isEnabled = true
        capture.isHidden = false
        view.layoutIfNeeded()
        resultsScroll.setContentOffset(.zero, animated: false)
        capture.captureSession.run(configuration: configuration)
        UIAccessibility.post(notification: .screenChanged, argument: status)
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
            self.result = processedResult
            self.spinner.stopAnimating()
            self.status.text = self.text("review")
            self.primary.setTitle(self.text("export"), for: .normal)
            self.primary.isEnabled = true
            self.renderResults(document)
            self.resultsScroll.setContentOffset(.zero, animated: false)
            UIAccessibility.post(notification: .screenChanged, argument: self.status)
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

    private func renderResults(_ document: RoomPlanDocument) {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        captureHeight?.isActive = false
        captureHeight = capture.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.30)
        captureHeight?.priority = .defaultHigh
        captureHeight?.isActive = true
        buildingField.text = UserDefaults.standard.string(forKey: "KanturaRoomBuilding") ?? text("defaultBuilding")
        floorField.text = UserDefaults.standard.string(forKey: "KanturaRoomFloor") ?? text("defaultFloor")
        nameField.text = text("title")
        let fields = UIStackView()
        fields.axis = .vertical
        fields.spacing = 9
        for (field, key) in [(buildingField, "building"), (floorField, "floorName"), (nameField, "name")] {
            fields.addArrangedSubview(KanturaDesign.label(text(key), style: .subheadline, secondary: true))
            field.borderStyle = .none
            field.backgroundColor = KanturaDesign.background
            field.textColor = KanturaDesign.text
            field.tintColor = KanturaDesign.tint
            field.layer.cornerRadius = 12
            field.layer.cornerCurve = .continuous
            let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48))
            field.leftView = paddingView
            field.leftViewMode = .always
            field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48))
            field.rightViewMode = .always
            field.placeholder = text(key)
            field.accessibilityLabel = text(key)
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.delegate = self
            field.returnKeyType = field === nameField ? .done : .next
            field.autocapitalizationType = .words
            field.addTarget(self, action: #selector(namesChanged), for: .editingChanged)
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            fields.addArrangedSubview(field)
            fields.setCustomSpacing(19, after: field)
        }
        results.addArrangedSubview(KanturaDesign.inset(fields))
        if onNewRoom != nil { results.addArrangedSubview(anotherRoom) }
        addInformation(text("separateOrigins"), icon: "building.2")
        addInformation(text("verify"), icon: "ruler")
        RoomPlanPresentation.addMeasurements(document, to: results)
        addInformation(text("noTexture"), icon: "info.circle")
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
        status.text = text(saved ? "savedLocally" : "review")
        primary.setTitle(saved ? MeasurementGuide.all[MeasurementGuide.selectedLanguage]?.saveFiles : text("export"), for: .normal)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === buildingField { floorField.becomeFirstResponder() }
        else if textField === floorField { nameField.becomeFirstResponder() }
        else { textField.resignFirstResponder() }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) { revealFocusedField() }

    private func revealFocusedField() {
        guard let field = [buildingField, floorField, nameField].first(where: { $0.isFirstResponder }) else { return }
        view.layoutIfNeeded()
        resultsScroll.scrollRectToVisible(field.convert(field.bounds, to: resultsScroll).insetBy(dx: 0, dy: -20), animated: true)
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
        return RoomPlanDocument(name: name, createdAt: ISO8601DateFormatter().string(from: Date()), roomId: room.identifier.uuidString, surfaces: surfaces)
    }

    private func exportFiles() {
        guard let room = result, lifecycle.phase == .review else { return }
        view.endEditing(true)
        let names = enteredNames
        if hasSavedReview {
            present(UIDocumentPickerViewController(forExporting: savedFiles, asCopy: true), animated: true)
            return
        }
        guard lifecycle.export() else { return }
        var document = makeDocument(room, name: names[2])
        document.building = RoomPlanDocument.Building(name: names[0], floor: names[1], room: names[2])
        UserDefaults.standard.set(document.building?.name, forKey: "KanturaRoomBuilding")
        UserDefaults.standard.set(document.building?.floor, forKey: "KanturaRoomFloor")
        let exportDocument = document
        primary.isEnabled = false
        primary.setTitle(text("exporting"), for: .normal)
        anotherRoom.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        [buildingField, floorField, nameField].forEach { $0.isEnabled = false }
        spinner.startAnimating()
        status.text = text("exporting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome: Result<[URL], Error>
            do {
                let identifier = UUID()
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("KanturaRooms", isDirectory: true)
                    .appendingPathComponent(identifier.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stem = SavedRoomPlan.exportStem(name: exportDocument.name, identifier: identifier)
                let json = directory.appendingPathComponent(stem + ".kantura-room.json")
                let usdz = directory.appendingPathComponent(stem + ".usdz")
                try exportDocument.encoded().write(to: json, options: .atomic)
                try room.export(to: usdz, exportOptions: .mesh)
                outcome = .success([json, usdz])
            } catch { outcome = .failure(error) }
            DispatchQueue.main.async {
                guard let self = self, self.lifecycle.phase == .exporting else { return }
                self.lifecycle.exported()
                self.spinner.stopAnimating()
                self.primary.isEnabled = true
                self.anotherRoom.isEnabled = true
                self.navigationItem.leftBarButtonItem?.isEnabled = true
                [self.buildingField, self.floorField, self.nameField].forEach { $0.isEnabled = true }
                switch outcome {
                case .success(let urls):
                    self.savedNames = names
                    self.savedFiles = urls
                    self.namesChanged()
                    let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
                    self.present(picker, animated: true)
                case .failure:
                    self.namesChanged()
                    let alert = UIAlertController(title: self.text("exportFailed"), message: self.text("exportRetry"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: self.text("close"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func fail(_ message: String) {
        guard lifecycle.phase != .cancelled && lifecycle.phase != .failed else { return }
        let wasCapturing = lifecycle.phase == .capturing
        lifecycle.fail()
        timeout?.cancel()
        if wasCapturing { capture.captureSession.stop(pauseARSession: true) }
        capture.captureSession.arSession.pause()
        spinner.stopAnimating()
        status.text = message
        capture.isHidden = true
        primary.setTitle(text("close"), for: .normal)
        primary.isEnabled = true
        resultsScroll.setContentOffset(.zero, animated: false)
        UIAccessibility.post(notification: .screenChanged, argument: status)
    }

    @objc private func close() {
        leave(after: nil)
    }

    @objc private func newRoom() { leave(after: onNewRoom) }

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
        if let observer = keyboardObserver { NotificationCenter.default.removeObserver(observer) }
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
        var counts: [String: Int] = [:]
        for surface in document.surfaces {
            counts[surface.kind, default: 0] += 1
            let title = MeasurementGuide.roomText(surface.kind) + " \(counts[surface.kind]!)"
            let heading = KanturaDesign.label(title, style: .headline)
            let measurement: String
            if surface.kind == "floor", let area = surface.polygonArea {
                measurement = "\(number(area)) m²"
            } else {
                measurement = surface.dimensions.map { number($0) }.joined(separator: " × ") + " m"
            }
            // Preserve X/Y/Z order and the unit in an Arabic interface.
            let metric = KanturaDesign.label("\u{2066}" + measurement + "\u{2069}", style: .title2)
            metric.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .monospacedDigitSystemFont(ofSize: 23, weight: .semibold))
            let confidenceText = MeasurementGuide.roomText("confidence") + ": " + MeasurementGuide.roomText(surface.confidence)
            let confidence = KanturaDesign.label(confidenceText, style: .footnote, secondary: true)
            let content = UIStackView(arrangedSubviews: [heading, metric, confidence])
            content.axis = .vertical
            content.spacing = 10
            let card = KanturaDesign.inset(content)
            card.isAccessibilityElement = true
            card.accessibilityLabel = [title, measurement, confidenceText].joined(separator: ", ")
            stack.addArrangedSubview(card)
        }
    }
}

/// Each stored room has its own RoomPlan origin. Grouping by building and floor
/// organizes scans; it intentionally does not claim to align or merge them.
@available(iOS 17.0, *)
final class RoomPlanLibraryViewController: UITableViewController {
    var onClose: (() -> Void)?
    var onNewRoom: (() -> Void)?
    private var groups: [(title: String, rooms: [SavedRoomPlan])] = []
    private func text(_ key: String) -> String { MeasurementGuide.roomText(key) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = text("library")
        view.backgroundColor = KanturaDesign.background
        view.tintColor = KanturaDesign.tint
        KanturaDesign.navigation(self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("close"), style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: text("newRoom"), style: .plain, target: self, action: #selector(newRoom))
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KanturaRooms", isDirectory: true)
        let rooms = SavedRoomPlan.load(from: directory)
        let grouped = Dictionary(grouping: rooms) { room in
            guard let building = room.document.building else { return self.text("otherRooms") }
            return building.name + " · " + building.floor
        }
        groups = grouped.keys.sorted().map { (title: $0, rooms: grouped[$0]!) }
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 44
        tableView.separatorColor = KanturaDesign.border
        tableView.cellLayoutMarginsFollowReadableWidth = true
        if rooms.isEmpty {
            let empty = UILabel()
            empty.text = text("libraryEmpty")
            empty.textAlignment = .center
            empty.numberOfLines = 0
            empty.font = .preferredFont(forTextStyle: .body)
            empty.adjustsFontForContentSizeCategory = true
            empty.textColor = KanturaDesign.muted
            let illustration = UIImageView(image: UIImage(systemName: "building.2.crop.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .light)))
            illustration.contentMode = .scaleAspectFit
            illustration.tintColor = KanturaDesign.tint
            illustration.heightAnchor.constraint(equalToConstant: 72).isActive = true
            illustration.isAccessibilityElement = false
            let start = KanturaButton(type: .system)
            KanturaDesign.button(start, primary: true)
            start.setTitle(text("newRoom"), for: .normal)
            start.addTarget(self, action: #selector(newRoom), for: .touchUpInside)
            let content = UIStackView(arrangedSubviews: [illustration, empty, start])
            content.axis = .vertical
            content.spacing = 24
            let emptyContainer = UIView()
            content.translatesAutoresizingMaskIntoConstraints = false
            emptyContainer.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: 32),
                content.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor, constant: -32),
                content.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 32),
                content.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -32)
            ])
            tableView.tableHeaderView = emptyContainer
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if header.frame.width != width || header.frame.height != height {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { groups.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups[section].rooms.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { groups[section].title }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = KanturaDesign.muted
        header.textLabel?.font = .preferredFont(forTextStyle: .subheadline)
        header.textLabel?.adjustsFontForContentSizeCategory = true
        header.textLabel?.numberOfLines = 0
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = KanturaDesign.surface
        cell.tintColor = KanturaDesign.tint
        cell.textLabel?.textColor = KanturaDesign.text
        cell.detailTextLabel?.textColor = KanturaDesign.muted
        cell.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        let room = groups[indexPath.section].rooms[indexPath.row]
        cell.textLabel?.text = room.document.building?.room ?? room.document.name
        cell.detailTextLabel?.text = "\(room.document.surfaces.count) " + text("surfaces") + " · " + String(room.document.createdAt.prefix(10))
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.imageView?.image = UIImage(systemName: "square.split.bottomrightquarter")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let room = groups[indexPath.section].rooms[indexPath.row]
        navigationController?.pushViewController(SavedRoomPlanViewController(room: room), animated: true)
    }

    @objc private func close() {
        let callback = onClose
        dismiss(animated: true) { callback?() }
    }
    @objc private func newRoom() {
        let closeCallback = onClose
        let callback = onNewRoom
        dismiss(animated: true) { closeCallback?(); callback?() }
    }
}

/// Saved measurements remain useful without repeating a capture or exporting
/// again. Preview and Files use exactly the JSON/USDZ pair already on disk.
@available(iOS 17.0, *)
private final class SavedRoomPlanViewController: UIViewController, QLPreviewControllerDataSource {
    private let room: SavedRoomPlan
    init(room: SavedRoomPlan) { self.room = room; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = room.document.name
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        let scroll = UIScrollView()
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 16
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        let heading = KanturaDesign.label(room.document.name, style: .largeTitle)
        heading.accessibilityTraits.insert(.header)
        content.addArrangedSubview(heading)
        if let building = room.document.building {
            content.addArrangedSubview(KanturaDesign.label(building.name + " · " + building.floor, style: .body, secondary: true))
        }
        for (key, icon, handler) in [
            ("preview", "cube.transparent", #selector(preview)),
            ("export", "square.and.arrow.up", #selector(exportFiles))
        ] {
            let button = KanturaButton(type: .system)
            KanturaDesign.button(button, primary: key == "preview")
            button.setTitle("  " + MeasurementGuide.roomText(key), for: .normal)
            button.setImage(UIImage(systemName: icon), for: .normal)
            button.addTarget(self, action: handler, for: .touchUpInside)
            content.addArrangedSubview(button)
        }
        content.addArrangedSubview(KanturaDesign.inset(KanturaDesign.label(MeasurementGuide.roomText("verify"), style: .subheadline, secondary: true)))
        RoomPlanPresentation.addMeasurements(room.document, to: content)
        content.addArrangedSubview(KanturaDesign.label(MeasurementGuide.roomText("separateOrigins"), style: .footnote, secondary: true))
        if let help = MeasurementGuide.all[MeasurementGuide.selectedLanguage]?.cloudHelp {
            content.addArrangedSubview(KanturaDesign.inset(KanturaDesign.label(help, style: .subheadline, secondary: true)))
        }
    }

    @objc private func preview() {
        let controller = QLPreviewController()
        controller.dataSource = self
        navigationController?.pushViewController(controller, animated: true)
    }
    @objc private func exportFiles() {
        guard presentedViewController == nil else { return }
        present(UIDocumentPickerViewController(forExporting: [room.jsonURL, room.modelURL], asCopy: true), animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { room.modelURL as NSURL }
}
