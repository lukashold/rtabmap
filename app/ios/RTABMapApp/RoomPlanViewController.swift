import UIKit
import AVFoundation
import RoomPlan
import QuickLook

/// A separate indoor, parametric capture path. It never starts RTAB-Map's AR
/// session and never represents RoomPlan's schematic surfaces as photo textures.
@available(iOS 17.0, *)
final class RoomPlanViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    static var isSupported: Bool { RoomCaptureSession.isSupported }
    var onClose: (() -> Void)?
    private let capture = RoomCaptureView(frame: .zero)
    private var lifecycle = RoomPlanLifecycle()
    private var result: CapturedRoom?
    private var exportedLocally = false
    private let status = UILabel()
    private let statusCard = KanturaSurface(frame: .zero)
    private let primary = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let resultsScroll = UIScrollView()
    private let results = UIStackView()
    private let nameField = UITextField()
    private let buildingField = UITextField()
    private let floorField = UITextField()
    private var interruptionObserver: NSObjectProtocol?
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
        view.addSubview(capture)
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .headline)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = KanturaDesign.text
        status.translatesAutoresizingMaskIntoConstraints = false
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(status)
        view.addSubview(statusCard)
        KanturaDesign.button(primary, primary: true)
        primary.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        primary.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(primary)
        spinner.hidesWhenStopped = true
        spinner.color = KanturaDesign.tint
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.keyboardDismissMode = .interactive
        view.addSubview(resultsScroll)
        results.axis = .vertical
        results.spacing = 16
        results.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.addSubview(results)
        captureHeight = capture.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.48)
        captureHeight?.priority = .defaultHigh
        NSLayoutConstraint.activate([
            statusCard.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusCard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            statusCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -18),
            status.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 15),
            status.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -15),
            capture.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 16),
            capture.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            capture.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            captureHeight!,
            primary.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            primary.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            primary.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: capture.centerYAnchor),
            resultsScroll.topAnchor.constraint(equalTo: capture.bottomAnchor, constant: 14),
            resultsScroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            resultsScroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            resultsScroll.bottomAnchor.constraint(equalTo: primary.topAnchor, constant: -12),
            results.leadingAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.trailingAnchor),
            results.topAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.topAnchor),
            results.bottomAnchor.constraint(equalTo: resultsScroll.contentLayoutGuide.bottomAnchor),
            results.widthAnchor.constraint(equalTo: resultsScroll.frameLayoutGuide.widthAnchor)
        ])
        addInformation(text("intro"), icon: "viewfinder")
        addInformation(text("noTexture"), icon: "info.circle")
        status.text = text("prepare")
        primary.setTitle(text("start"), for: .normal)
        interruptionObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.lifecycle.phase == .capturing else { return }
            self.fail(self.text("interrupted"))
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
        capture.captureSession.run(configuration: configuration)
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
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48))
            field.leftViewMode = .always
            field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48))
            field.rightViewMode = .always
            field.placeholder = text(key)
            field.accessibilityLabel = text(key)
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            fields.addArrangedSubview(field)
            fields.setCustomSpacing(19, after: field)
        }
        results.addArrangedSubview(KanturaDesign.inset(fields))
        addInformation(text("separateOrigins"), icon: "building.2")
        addInformation(text("verify"), icon: "ruler")
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        func number(_ value: Double) -> String { formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value) }
        var counts: [String: Int] = [:]
        for surface in document.surfaces {
            counts[surface.kind, default: 0] += 1
            let heading = KanturaDesign.label("\(text(surface.kind)) \(counts[surface.kind]!)", style: .headline)
            let measurement: String
            if surface.kind == "floor", let area = surface.polygonArea {
                measurement = "\(number(area)) m²"
            } else {
                measurement = surface.dimensions.map { number($0) }.joined(separator: " × ") + " m"
            }
            let metric = KanturaDesign.label(measurement, style: .title2)
            metric.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .monospacedDigitSystemFont(ofSize: 23, weight: .semibold))
            let confidence = KanturaDesign.label(text("confidence") + ": " + text(surface.confidence), style: .footnote, secondary: true)
            let measurementCard = UIStackView(arrangedSubviews: [heading, metric, confidence])
            measurementCard.axis = .vertical
            measurementCard.spacing = 10
            results.addArrangedSubview(KanturaDesign.inset(measurementCard))
        }
        addInformation(text("noTexture"), icon: "info.circle")
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
        guard let room = result, lifecycle.export() else { return }
        view.endEditing(true)
        let entered = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var document = makeDocument(room, name: String((entered.isEmpty ? text("title") : entered).prefix(200)))
        func fieldValue(_ field: UITextField, fallback: String) -> String {
            let value = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return String((value.isEmpty ? fallback : value).prefix(200))
        }
        document.building = RoomPlanDocument.Building(name: fieldValue(buildingField, fallback: text("defaultBuilding")),
            floor: fieldValue(floorField, fallback: text("defaultFloor")), room: document.name)
        UserDefaults.standard.set(document.building?.name, forKey: "KanturaRoomBuilding")
        UserDefaults.standard.set(document.building?.floor, forKey: "KanturaRoomFloor")
        let exportDocument = document
        primary.isEnabled = false
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
                switch outcome {
                case .success(let urls):
                    self.exportedLocally = true
                    self.status.text = self.text("savedLocally")
                    let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
                    self.present(picker, animated: true)
                case .failure:
                    self.status.text = self.text("review")
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
        primary.setTitle(text("failed"), for: .normal)
        primary.isEnabled = false
    }

    @objc private func close() {
        let hasUnsavedWork = lifecycle.phase == .capturing || lifecycle.phase == .processing || lifecycle.phase == .exporting || (lifecycle.phase == .review && !exportedLocally)
        if hasUnsavedWork {
            let alert = UIAlertController(title: text("discardTitle"), message: text("discardBody"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("keep"), style: .cancel))
            alert.addAction(UIAlertAction(title: text("discard"), style: .destructive) { [weak self] _ in self?.closeNow() })
            present(alert, animated: true)
        } else { closeNow() }
    }

    private func closeNow() {
        let wasCapturing = lifecycle.phase == .capturing
        lifecycle.cancel()
        timeout?.cancel()
        capture.delegate = nil
        capture.captureSession.delegate = nil
        if wasCapturing { capture.captureSession.stop(pauseARSession: true) }
        capture.captureSession.arSession.pause()
        let callback = onClose
        dismiss(animated: true) { callback?() }
    }

    deinit {
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer) }
        timeout?.cancel()
    }
}

/// Each stored room has its own RoomPlan origin. Grouping by building and floor
/// organizes scans; it intentionally does not claim to align or merge them.
@available(iOS 17.0, *)
final class RoomPlanLibraryViewController: UITableViewController, QLPreviewControllerDataSource {
    var onClose: (() -> Void)?
    var onNewRoom: (() -> Void)?
    private var groups: [(title: String, rooms: [SavedRoomPlan])] = []
    private var previewing: SavedRoomPlan?
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
            let content = UIStackView(arrangedSubviews: [illustration, empty])
            content.axis = .vertical
            content.spacing = 24
            let emptyContainer = UIView()
            content.translatesAutoresizingMaskIntoConstraints = false
            emptyContainer.addSubview(content)
            NSLayoutConstraint.activate([
                content.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
                content.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 32),
                content.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -32)
            ])
            tableView.backgroundView = emptyContainer
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
        let sheet = UIAlertController(title: room.document.name, message: text("separateOrigins"), preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: text("preview"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.previewing = room
            let preview = QLPreviewController()
            preview.dataSource = self
            self.navigationController?.pushViewController(preview, animated: true)
        })
        sheet.addAction(UIAlertAction(title: text("export"), style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(forExporting: [room.jsonURL, room.modelURL], asCopy: true)
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: text("close"), style: .cancel))
        if let cell = tableView.cellForRow(at: indexPath) {
            sheet.popoverPresentationController?.sourceView = cell
            sheet.popoverPresentationController?.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewing == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewing!.modelURL as NSURL
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
