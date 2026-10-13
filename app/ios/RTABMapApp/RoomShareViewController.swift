import UIKit
import Security
import Zip

/// Export a saved room as HTML (computer), DXF (CAD), USDZ (3D) or a complete
/// project ZIP with photos, and send it either through the iOS share sheet —
/// which reaches OneDrive, Google Drive, Dropbox and Files through their own
/// apps — or directly to the user's own Kantura Docker server.
final class RoomShareViewController: UIViewController {
    private let room: SavedRoomPlan
    private var column: UIStackView!
    private let status = KanturaDesign.label("", style: .subheadline, secondary: true)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var buttons: [UIButton] = []
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    init(room: SavedRoomPlan) { self.room = room; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    enum Format: CaseIterable { case html, dxf, usdz, project }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = text("export")
        column = KanturaDesign.scrollColumn(in: self, spacing: 12).column
        for (format, key, detail, icon) in [(Format.html, "exportHTML", "exportHTMLDetail", "safari"), (.dxf, "exportDXF", "exportDXFDetail", "square.and.pencil"),
                                            (.usdz, "exportUSDZ", "exportUSDZDetail", "cube"), (.project, "exportProject", "exportProjectDetail", "doc.zipper")] {
            let card = KanturaActionCard(title: text(key), detail: text(detail), icon: icon)
            card.addAction(UIAction { [weak self, weak card] _ in self?.share(format, from: card) }, for: .touchUpInside)
            buttons.append(card)
            column.addArrangedSubview(card)
        }
        column.addArrangedSubview(KanturaDesign.label(text("toFilesHelp"), style: .footnote, secondary: true))
        let server = KanturaDesign.label(text("toServer"), style: .title3)
        server.accessibilityTraits.insert(.header)
        column.setCustomSpacing(26, after: column.arrangedSubviews.last!)
        column.addArrangedSubview(server)
        let upload = KanturaDesign.primaryButton(text("uploadServer"), icon: "arrow.up.to.line") { [weak self] in self?.uploadToServer() }
        buttons.append(upload)
        column.addArrangedSubview(upload)
        column.addArrangedSubview(KanturaDesign.secondaryButton(text("serverSettings"), icon: "gearshape") { [weak self] in self?.editServer(thenUpload: false) })
        spinner.hidesWhenStopped = true
        let feedback = UIStackView(arrangedSubviews: [spinner, status])
        feedback.spacing = 8
        column.addArrangedSubview(feedback)
        if room.original.corrections != nil { column.addArrangedSubview(KanturaDesign.label(text("editUSDZNote"), style: .footnote, secondary: true)) }
    }

    // MARK: Files

    private var labels: RoomExport.Labels {
        var l = RoomExport.Labels()
        l.title = room.document.building?.room ?? room.document.name
        l.wall = MeasurementGuide.roomText("wall"); l.door = MeasurementGuide.roomText("door"); l.window = MeasurementGuide.roomText("window")
        l.opening = MeasurementGuide.roomText("opening"); l.stairs = text("stairs")
        l.floorArea = text("floorArea"); l.grossWall = text("grossWall"); l.netWall = text("netWall"); l.height = text("height")
        l.width = text("width"); l.heightShort = text("heightField"); l.plan = text("walkPlan"); l.model = text("walkOutside")
        l.dimensions = text("allSurfaces"); l.note = text("accuracyNote"); l.language = MeasurementGuide.selectedLanguage
        return l
    }

    private var stem: String { SavedRoomPlan.exportStem(name: room.document.building?.room ?? room.document.name, identifier: UUID()) }
    private var folder: URL { room.jsonURL.deletingLastPathComponent() }

    /// Builds the requested file in a temporary folder (off the main thread).
    private func make(_ format: Format) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KanturaExport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = stem
        let photoDirectory = folder.appendingPathComponent("photos", isDirectory: true)
        switch format {
        case .html:
            // Up to 24 photos, downsized, so the file stays easy to e-mail.
            let photos = (RoomPhotoSet.load(from: photoDirectory)?.photos ?? []).enumerated().filter { $0.offset % 3 == 0 }.prefix(24).compactMap { item -> (name: String, jpeg: Data)? in
                guard let image = RoomWalkthroughViewController.thumbnail(photoDirectory.appendingPathComponent(item.element.file), maxPixel: 900),
                      let data = image.jpegData(compressionQuality: 0.7) else { return nil }
                return (item.element.file, data)
            }
            let url = directory.appendingPathComponent(name + ".html")
            try RoomExport.html(room.document, labels: labels, photos: photos).write(to: url, atomically: true, encoding: .utf8)
            return url
        case .dxf:
            let url = directory.appendingPathComponent(name + ".dxf")
            try RoomExport.dxf(room.document, labels: labels).write(to: url, atomically: true, encoding: .ascii)
            return url
        case .usdz:
            let url = directory.appendingPathComponent(name + ".usdz")
            try FileManager.default.copyItem(at: room.modelURL, to: url)
            return url
        case .project:
            // Everything: room data (with corrections), 3D model, HTML, DXF and photos.
            let content = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: room.jsonURL, to: content.appendingPathComponent(name + ".kantura-room.json"))
            try FileManager.default.copyItem(at: room.modelURL, to: content.appendingPathComponent(name + ".usdz"))
            try RoomExport.html(room.document, labels: labels).write(to: content.appendingPathComponent(name + ".html"), atomically: true, encoding: .utf8)
            try RoomExport.dxf(room.document, labels: labels).write(to: content.appendingPathComponent(name + ".dxf"), atomically: true, encoding: .ascii)
            if FileManager.default.fileExists(atPath: photoDirectory.path) {
                try FileManager.default.copyItem(at: photoDirectory, to: content.appendingPathComponent("photos", isDirectory: true))
            }
            let zip = directory.appendingPathComponent(name + ".zip")
            try Zip.zipFiles(paths: try FileManager.default.contentsOfDirectory(at: content, includingPropertiesForKeys: nil), zipFilePath: zip, password: nil, progress: nil)
            return zip
        }
    }

    private func busy(_ on: Bool, _ message: String = "") {
        buttons.forEach { $0.isEnabled = !on }
        on ? spinner.startAnimating() : spinner.stopAnimating()
        status.text = message
        if !message.isEmpty { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    private func share(_ format: Format, from source: UIView?) {
        guard presentedViewController == nil else { return }
        busy(true, text("preparing"))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = Result { try self.make(format) }
            DispatchQueue.main.async {
                self.busy(false)
                switch result {
                case .success(let url):
                    // The share sheet reaches OneDrive, Google Drive, Dropbox (their
                    // apps), Files, AirDrop and mail without extra sign-ins here.
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activity.popoverPresentationController?.sourceView = source ?? self.view
                    activity.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    self.present(activity, animated: true)
                case .failure: self.status.text = MeasurementGuide.roomText("exportFailed")
                }
            }
        }
    }

    // MARK: Own server

    private static let urlKey = "KanturaServerURL"

    static func serverURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: urlKey), let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private func editServer(thenUpload: Bool) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: text("toServer"), message: text("serverHelp"), preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://kantura.example.at"
            field.text = UserDefaults.standard.string(forKey: Self.urlKey)
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.accessibilityLabel = self.text("serverURL")
        }
        alert.addTextField { field in
            field.placeholder = self.text("serverKey")
            field.text = ServerKeychain.token()
            field.isSecureTextEntry = true
            field.accessibilityLabel = self.text("serverKey")
        }
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: thenUpload ? text("uploadServer") : text("serverSave"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let fields = alert?.textFields else { return }
            var raw = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            while raw.hasSuffix("/") { raw.removeLast() }
            UserDefaults.standard.set(raw, forKey: Self.urlKey)
            ServerKeychain.set((fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            if thenUpload { self.uploadToServer() }
        })
        present(alert, animated: true)
    }

    private func uploadToServer() {
        guard let base = Self.serverURL(), let token = ServerKeychain.token(), token.count >= 32 else { editServer(thenUpload: true); return }
        busy(true, text("uploading"))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let made = Result { try self.make(.project) }
            guard case .success(let zip) = made else {
                DispatchQueue.main.async { self.busy(false, MeasurementGuide.roomText("exportFailed")) }
                return
            }
            var components = URLComponents(url: base.appendingPathComponent("api/projects"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "name", value: String((self.room.document.building?.room ?? self.room.document.name).prefix(120)))]
            guard let url = components?.url else { return }
            var request = URLRequest(url: url, timeoutInterval: 300)
            request.httpMethod = "POST"
            request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            URLSession.shared.uploadTask(with: request, fromFile: zip) { _, response, error in
                try? FileManager.default.removeItem(at: zip.deletingLastPathComponent())
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if error == nil && code == 201 {
                        self.busy(false, self.text("uploaded"))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        self.busy(false, self.text("uploadFailed") + (code > 0 ? " (\(code))" : ""))
                    }
                }
            }.resume()
        }
    }
}

/// The server key is stored in the iOS keychain, never in user defaults.
enum ServerKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.lukashold.kantura.server"]

    static func token() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ token: String) {
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
