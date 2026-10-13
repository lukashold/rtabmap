import UIKit

/// Shared look for marker kinds.
enum MarkerStyle {
    static func color(_ kind: String) -> UIColor {
        switch kind {
        case "defect": return .systemRed
        case "question": return .systemOrange
        case "idea": return .systemBlue
        default: return .systemPurple
        }
    }
    static func icon(_ kind: String) -> String {
        switch kind {
        case "defect": return "exclamationmark.triangle.fill"
        case "question": return "questionmark.circle.fill"
        case "idea": return "lightbulb.fill"
        default: return "ruler.fill"
        }
    }
    static func name(_ kind: String) -> String { MeasurementGuide.homeText("marker_" + kind) }
}

/// Create or edit one marker: kind, title, description, responsible person,
/// open/done and an optional photo (camera or library).
final class MarkerEditorViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
    private var marker: RoomExtras.Marker
    private let folder: URL
    private let isNew: Bool
    var onSave: ((RoomExtras.Marker) -> Void)?
    var onDelete: (() -> Void)?
    private let kind = UISegmentedControl()
    private let titleField = UITextField()
    private let detail = UITextView()
    private let assignee = UITextField()
    private let done = UISwitch()
    private let photoView = UIImageView()
    private var pendingPhoto: Data?
    private var removePhoto = false
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    init(marker: RoomExtras.Marker, folder: URL, isNew: Bool) {
        self.marker = marker; self.folder = folder; self.isNew = isNew
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        title = text(isNew ? "markerNew" : "markerEdit")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        let column = KanturaDesign.scrollColumn(in: self, spacing: 10).column
        for (index, k) in RoomExtras.markerKinds.enumerated() { kind.insertSegment(withTitle: MarkerStyle.name(k), at: index, animated: false) }
        kind.selectedSegmentIndex = RoomExtras.markerKinds.firstIndex(of: marker.kind) ?? 0
        column.addArrangedSubview(kind)
        func field(_ f: UITextField, _ placeholder: String, _ value: String) {
            f.text = value; f.placeholder = placeholder; f.accessibilityLabel = placeholder
            f.font = .preferredFont(forTextStyle: .body); f.adjustsFontForContentSizeCategory = true
            f.backgroundColor = KanturaDesign.surface; f.layer.cornerRadius = 12
            f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48)); f.leftViewMode = .always
            f.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            f.delegate = self
        }
        field(titleField, text("markerTitle"), marker.title)
        column.addArrangedSubview(titleField)
        detail.text = marker.detail
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.backgroundColor = KanturaDesign.surface
        detail.layer.cornerRadius = 12
        detail.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        detail.accessibilityLabel = text("markerDetail")
        detail.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        column.addArrangedSubview(KanturaDesign.label(text("markerDetail"), style: .footnote, secondary: true))
        column.addArrangedSubview(detail)
        field(assignee, text("markerAssignee"), marker.assignee)
        column.addArrangedSubview(assignee)
        done.isOn = marker.status == "done"
        done.onTintColor = KanturaDesign.mint
        let doneRow = UIStackView(arrangedSubviews: [KanturaDesign.label(text("markerDone"), style: .body), done])
        doneRow.alignment = .center
        column.addArrangedSubview(doneRow)
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 14
        photoView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        photoView.isHidden = true
        if let file = marker.photo, let image = UIImage(contentsOfFile: folder.appendingPathComponent(file).path) { photoView.image = image; photoView.isHidden = false }
        column.addArrangedSubview(photoView)
        let photoButtons = UIStackView(arrangedSubviews: [
            KanturaDesign.secondaryButton(text("markerCamera"), icon: "camera") { [weak self] in self?.pick(.camera) },
            KanturaDesign.secondaryButton(text("markerLibrary"), icon: "photo") { [weak self] in self?.pick(.photoLibrary) }
        ])
        photoButtons.spacing = 10
        photoButtons.distribution = .fillEqually
        column.addArrangedSubview(photoButtons)
        if !isNew {
            column.addArrangedSubview(KanturaDesign.secondaryButton(text("removeSurface"), icon: "trash") { [weak self] in self?.confirmDelete() })
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    private func pick(_ source: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(source), presentedViewController == nil else { return }
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        // Downsize to keep exports small; orientation is baked in by rendering.
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        pendingPhoto = resized.jpegData(compressionQuality: 0.75)
        photoView.image = resized
        photoView.isHidden = false
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        let titleText = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        marker.kind = RoomExtras.markerKinds[max(0, kind.selectedSegmentIndex)]
        marker.title = String((titleText.isEmpty ? MarkerStyle.name(marker.kind) : titleText).prefix(200))
        marker.detail = String(detail.text.prefix(4000))
        marker.assignee = String((assignee.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        marker.status = done.isOn ? "done" : "open"
        marker.updatedAt = RoomExtras.now()
        if let data = pendingPhoto {
            let directory = folder.appendingPathComponent("markers", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "markers/\(marker.id).jpg"
            if (try? data.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil { marker.photo = name }
        }
        let saved = marker, callback = onSave
        dismiss(animated: true) { callback?(saved) }
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: text("markerDeleteTitle"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("delete"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            if let file = self.marker.photo { try? FileManager.default.removeItem(at: self.folder.appendingPathComponent(file)) }
            let callback = self.onDelete
            self.dismiss(animated: true) { callback?() }
        })
        present(alert, animated: true)
    }
}

/// All markers of a room with an open/all filter; tap to edit.
final class MarkerListViewController: UITableViewController {
    private let folder: URL
    private var extras: RoomExtras
    private var showDone = false
    var onChange: ((RoomExtras) -> Void)?
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }
    private var visible: [RoomExtras.Marker] { extras.markers.filter { showDone || $0.status == "open" }.sorted { $0.createdAt < $1.createdAt } }

    init(folder: URL) {
        self.folder = folder
        extras = RoomExtras.load(from: folder)
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KanturaDesign.navigation(self)
        title = text("markers")
        tableView.backgroundColor = KanturaDesign.background
        let filter = UISegmentedControl(items: [text("markersOpen"), text("markersAll")])
        filter.selectedSegmentIndex = 0
        filter.addAction(UIAction { [weak self, weak filter] _ in self?.showDone = filter?.selectedSegmentIndex == 1; self?.tableView.reloadData() }, for: .valueChanged)
        navigationItem.titleView = filter
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1, visible.count) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = KanturaDesign.surface
        guard !visible.isEmpty else {
            cell.textLabel?.text = text("markersEmpty"); cell.textLabel?.numberOfLines = 0; cell.textLabel?.textColor = KanturaDesign.muted
            cell.selectionStyle = .none; return cell
        }
        let m = visible[indexPath.row]
        cell.imageView?.image = UIImage(systemName: MarkerStyle.icon(m.kind))
        cell.imageView?.tintColor = MarkerStyle.color(m.kind)
        cell.textLabel?.text = "\(indexPath.row + 1). " + m.title
        cell.textLabel?.numberOfLines = 0
        var detail = [MarkerStyle.name(m.kind), text(m.status == "done" ? "markerStatusDone" : "markerStatusOpen")]
        if !m.assignee.isEmpty { detail.append(m.assignee) }
        if m.photo != nil { detail.append("📷") }
        cell.detailTextLabel?.text = detail.joined(separator: " · ")
        cell.detailTextLabel?.textColor = KanturaDesign.muted
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !visible.isEmpty else { return }
        let marker = visible[indexPath.row]
        let editor = MarkerEditorViewController(marker: marker, folder: folder, isNew: false)
        editor.onSave = { [weak self] updated in self?.update { $0.markers = $0.markers.map { $0.id == updated.id ? updated : $0 } } }
        editor.onDelete = { [weak self] in self?.update { $0.markers.removeAll { $0.id == marker.id } } }
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    private func update(_ change: (inout RoomExtras) -> Void) {
        change(&extras)
        try? extras.write(to: folder)
        tableView.reloadData()
        onChange?(extras)
    }
}

/// Choose furniture from the built-in catalogue, added open catalogues (by URL)
/// or create a custom piece from its dimensions.
final class FurnitureCatalogViewController: UITableViewController, UISearchResultsUpdating {
    var onPick: ((FurnitureCatalog.Item, String) -> Void)?
    private var catalogs: [FurnitureCatalog] = []
    private var query = ""
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KanturaCatalogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func savedCatalogs() -> [FurnitureCatalog] {
        let files = (try? FileManager.default.contentsOfDirectory(at: storeURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(FurnitureCatalog.self, from: data), (try? catalog.validate()) != nil else { return nil }
            return catalog
        }.sorted { $0.name < $1.name }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        KanturaDesign.navigation(self)
        title = text("furnitureTitle")
        tableView.backgroundColor = KanturaDesign.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
        let add = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: nil, menu: UIMenu(children: [
            UIAction(title: text("furnitureCustom"), image: UIImage(systemName: "cube")) { [weak self] _ in self?.custom() },
            UIAction(title: text("furnitureAddCatalog"), image: UIImage(systemName: "link")) { [weak self] _ in self?.addCatalog() }
        ]))
        add.accessibilityLabel = text("furnitureAdd")
        navigationItem.rightBarButtonItem = add
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        reload()
    }

    private func reload() { catalogs = [FurnitureCatalog.builtIn] + Self.savedCatalogs(); tableView.reloadData() }
    func updateSearchResults(for searchController: UISearchController) { query = searchController.searchBar.text ?? ""; tableView.reloadData() }
    private func items(_ section: Int) -> [FurnitureCatalog.Item] {
        let all = catalogs[section].items
        guard !query.isEmpty else { return all }
        return all.filter { ($0.name + " " + $0.manufacturer + " " + $0.category).localizedCaseInsensitiveContains(query) }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { catalogs.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let c = catalogs[section]
        return [c.name, c.publisher == c.name ? nil : c.publisher, c.license].compactMap { $0 }.joined(separator: " · ")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items(section).count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items(indexPath.section)[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = KanturaDesign.surface
        cell.textLabel?.text = item.manufacturer.isEmpty ? item.name : item.manufacturer + " " + item.name
        cell.textLabel?.numberOfLines = 0
        let m = { (v: Double) in KanturaDesign.metric(v, unit: "m", decimals: 2) }
        cell.detailTextLabel?.text = m(item.width) + " × " + m(item.depth) + " × " + m(item.height)
        cell.detailTextLabel?.textColor = KanturaDesign.muted
        cell.imageView?.image = UIImage(systemName: "cube")
        cell.imageView?.tintColor = KanturaDesign.tint
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items(indexPath.section)[indexPath.row], name = catalogs[indexPath.section].name
        let callback = onPick
        dismiss(animated: true) { callback?(item, name) }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }

    @objc private func close() { dismiss(animated: true) }

    private func custom() {
        let alert = UIAlertController(title: text("furnitureCustom"), message: text("furnitureCustomHelp"), preferredStyle: .alert)
        for (key, value) in [("furnitureName", ""), ("width", "1,00"), ("depth", "0,60"), ("heightField", "0,80")] {
            alert.addTextField { f in f.placeholder = self.text(key); f.accessibilityLabel = self.text(key); if !value.isEmpty { f.text = value; f.keyboardType = .decimalPad } }
        }
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("furnitureAdd"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let f = alert?.textFields else { return }
            let n = f[1...3].compactMap { Double(($0.text ?? "").replacingOccurrences(of: ",", with: ".")) }
            guard n.count == 3, n.allSatisfy({ $0 > 0.01 && $0 <= 20 }) else { return }
            let name = (f[0].text ?? "").trimmingCharacters(in: .whitespaces)
            let item = FurnitureCatalog.Item(id: RoomExtras.newID(), name: name.isEmpty ? self.text("furnitureCustom") : name, manufacturer: "", category: "other", width: n[0], depth: n[1], height: n[2])
            let callback = self.onPick
            self.dismiss(animated: true) { callback?(item, self.text("furnitureCustom")) }
        })
        present(alert, animated: true)
    }

    /// Download an open catalogue (JSON) from an https URL and keep it offline.
    private func addCatalog() {
        let alert = UIAlertController(title: text("furnitureAddCatalog"), message: text("furnitureCatalogHelp"), preferredStyle: .alert)
        alert.addTextField { f in f.placeholder = "https://…/catalog.json"; f.keyboardType = .URL; f.autocapitalizationType = .none; f.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("furnitureAdd"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: raw), url.scheme == "https" else { self?.message(self?.text("furnitureCatalogFailed") ?? ""); return }
            URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 30)) { data, response, _ in
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                let catalog = data.flatMap { $0.count <= 8 * 1024 * 1024 ? try? JSONDecoder().decode(FurnitureCatalog.self, from: $0) : nil }
                DispatchQueue.main.async {
                    guard ok, let catalog = catalog, (try? catalog.validate()) != nil, let data = data else { self.message(self.text("furnitureCatalogFailed")); return }
                    let file = Self.storeURL.appendingPathComponent(SavedRoomPlan.exportStem(name: catalog.name, identifier: UUID()) + ".json")
                    try? data.write(to: file, options: .atomic)
                    self.reload()
                }
            }.resume()
        })
        present(alert, animated: true)
    }

    private func message(_ text: String) {
        let alert = UIAlertController(title: text, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .default))
        present(alert, animated: true)
    }
}

/// The original photo that best shows a tapped point, with the point marked.
final class RoomPhotoViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let point: CGPoint
    private let scroll = UIScrollView()
    private let imageView = UIImageView()

    /// `u`, `v` are pixel coordinates in the stored (sensor-landscape) photo.
    init(url: URL, u: Double, v: Double) {
        let raw = UIImage(contentsOfFile: url.path) ?? UIImage()
        // ARKit stores the image in sensor orientation; a phone held upright
        // sees it rotated 90° clockwise. Show it upright and move the point along.
        if let cg = raw.cgImage {
            image = UIImage(cgImage: cg, scale: 1, orientation: .right)
            point = CGPoint(x: CGFloat(cg.height) - CGFloat(v), y: CGFloat(u))
        } else { image = raw; point = .zero }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = MeasurementGuide.homeText("photoOriginal")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        let rendered = UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
            let r = max(image.size.width, image.size.height) * 0.02
            UIColor.systemRed.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
            ring.lineWidth = r * 0.35
            ring.stroke()
        }
        imageView.image = rendered
        imageView.contentMode = .scaleAspectFit
        scroll.delegate = self
        scroll.maximumZoomScale = 5
        scroll.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor)
        ])
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    @objc private func close() { dismiss(animated: true) }
}
