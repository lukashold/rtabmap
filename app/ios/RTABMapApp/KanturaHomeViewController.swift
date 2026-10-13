import UIKit
import AVKit

/// The app's front door: saved rooms first, one obvious way to scan the next
/// one, and every other capture type one tap away under "Other capture types".
/// All scanning, saving and processing stays in the existing controllers; this
/// screen only lists results and routes the user.
final class KanturaHomeViewController: UIViewController {
    enum Route { case roomScan, stairScan, gateScan, lidarProjects, lidarWorkflow, photoObject, scenePhotos, splat, expert, transport }
    var onRoute: ((Route) -> Void)?
    var onLanguageChange: (() -> Void)?
    /// RoomPlan needs a LiDAR iPhone/iPad with iOS 17; otherwise the main button
    /// explains that instead of failing after a tap.
    var roomScanSupported = true
    /// Status of an unfinished RTAB-Map LiDAR session, shown as a card to continue it.
    var lidarStatus: String?

    private var scroll: UIScrollView!
    private var column: UIStackView!
    private var bottomBar: UIView?
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        let layout = KanturaDesign.scrollColumn(in: self, spacing: 12)
        scroll = layout.scroll
        column = layout.column
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    /// Re-read saved rooms, for example after a scan was saved or deleted.
    func reload() {
        guard isViewLoaded else { return }
        render()
    }

    private func render() {
        KanturaDesign.navigation(self)
        title = text("title")
        let settings = UIBarButtonItem(title: nil, image: UIImage(systemName: "gearshape"), primaryAction: nil, menu: settingsMenu())
        settings.accessibilityLabel = text("settings")
        navigationItem.rightBarButtonItem = settings
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        ContextMenu.shared.actions.removeAll()

        if let status = lidarStatus {
            let card = KanturaActionCard(title: text("gate"), detail: status, icon: "camera.viewfinder", emphasis: .mint)
            card.addAction(UIAction { [weak self] _ in self?.onRoute?(.lidarWorkflow) }, for: .touchUpInside)
            column.addArrangedSubview(card)
            column.setCustomSpacing(24, after: card)
        }
        let items = Self.savedRooms().map(LibraryItem.room) + Self.savedStairs().map(LibraryItem.stair)
        if items.isEmpty {
            column.addArrangedSubview(emptyState())
        } else {
            let groups = Dictionary(grouping: items) { LibraryLabels.group($0.building) }
            for title in groups.keys.sorted(by: { ($0.isEmpty ? 1 : 0, $0) < ($1.isEmpty ? 1 : 0, $1) }) {
                if !title.isEmpty || groups.count > 1 {
                    let header = KanturaDesign.label(title.isEmpty ? MeasurementGuide.roomText("otherRooms") : title, style: .subheadline, secondary: true)
                    header.accessibilityTraits.insert(.header)
                    column.addArrangedSubview(header)
                    column.setCustomSpacing(8, after: header)
                }
                for item in groups[title]!.sorted(by: { $0.createdAt > $1.createdAt }) { column.addArrangedSubview(card(for: item)) }
                if let last = column.arrangedSubviews.last { column.setCustomSpacing(26, after: last) }
            }
        }

        bottomBar?.removeFromSuperview()
        let scan = KanturaDesign.primaryButton(text("scanRoom"), icon: "viewfinder") { [weak self] in self?.startRoomScan() }
        scan.accessibilityHint = text("scanRoomDetail")
        let more = UIButton(type: .system)
        more.setTitle(text("more"), for: .normal)
        more.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        more.titleLabel?.adjustsFontForContentSizeCategory = true
        more.tintColor = KanturaDesign.tint
        more.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        more.addAction(UIAction { [weak self] _ in self?.showMore() }, for: .touchUpInside)
        let bar = KanturaDesign.bottomBar([scan, more], in: self)
        bottomBar = bar
        view.layoutIfNeeded()
        let inset = bar.frame.height - view.safeAreaInsets.bottom + 12
        scroll.contentInset.bottom = max(inset, 120)
        scroll.verticalScrollIndicatorInsets.bottom = max(inset, 120)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let bar = bottomBar else { return }
        let inset = bar.frame.height - view.safeAreaInsets.bottom + 12
        if abs(scroll.contentInset.bottom - inset) > 1 && inset > 0 {
            scroll.contentInset.bottom = inset
            scroll.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    static func savedRooms() -> [SavedRoomPlan] {
        SavedRoomPlan.load(from: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KanturaRooms", isDirectory: true))
    }

    static func savedStairs() -> [SavedStairScan] {
        SavedStairScan.load(from: SavedStairScan.directory(in: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]))
    }

    /// A saved room or stair scan as shown on the start screen.
    enum LibraryItem {
        case room(SavedRoomPlan), stair(SavedStairScan)
        var name: String {
            switch self {
            case .room(let r): return r.document.building?.room ?? r.document.name
            case .stair(let s): return s.displayName
            }
        }
        var building: RoomPlanDocument.Building? {
            switch self { case .room(let r): return r.original.building; case .stair(let s): return s.document.building }
        }
        var createdAt: String {
            switch self { case .room(let r): return r.document.createdAt; case .stair(let s): return s.document.createdAt }
        }
    }

    private func emptyState() -> UIView {
        let illustration = KanturaDesign.symbolTile("cube.transparent", size: 88)
        let wrapper = UIView()
        illustration.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(illustration)
        NSLayoutConstraint.activate([
            illustration.topAnchor.constraint(equalTo: wrapper.topAnchor),
            illustration.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            illustration.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor)
        ])
        let heading = KanturaDesign.label(text("emptyTitle"), style: .title2)
        heading.textAlignment = .center
        heading.accessibilityTraits.insert(.header)
        let body = KanturaDesign.label(text("emptyBody"), style: .body, secondary: true)
        body.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [wrapper, heading, body])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(24, after: wrapper)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 56, left: 12, bottom: 24, right: 12)
        return stack
    }

    private func card(for item: LibraryItem) -> UIView {
        let name = item.name
        let heading = KanturaDesign.label(name, style: .headline)
        var facts: [String] = []
        let icon: String
        switch item {
        case .room(let room):
            let summary = RoomPlanSummary(room.document)
            icon = "square.split.bottomrightquarter"
            facts.append(KanturaDesign.metric(summary.floorArea, unit: "m²", decimals: 1))
            if summary.wallHeight != nil { facts.append(KanturaDesign.metric(summary.wallHeight, unit: "m", decimals: 2)) }
        case .stair(let stair):
            icon = "figure.stairs"
            let p = stair.document.profile
            facts.append("↕ " + KanturaDesign.metric(p.drop, unit: "m", decimals: 2))
            if let w = p.minWidth { facts.append("↔ " + KanturaDesign.metric(w, unit: "m", decimals: 2)) }
        }
        let detail = KanturaDesign.label(facts.joined(separator: " · "), style: .subheadline, secondary: true)
        let time = KanturaDesign.label(Self.date(item.createdAt), style: .footnote, secondary: true)
        let copy = UIStackView(arrangedSubviews: [heading, detail, time])
        copy.axis = .vertical
        copy.spacing = 3
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = KanturaDesign.muted
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [KanturaDesign.symbolTile(icon), copy, chevron])
        row.spacing = 14
        row.alignment = .center
        row.isUserInteractionEnabled = false
        let button = UIButton(type: .custom)
        let card = KanturaDesign.inset(row, padding: 14)
        card.isUserInteractionEnabled = false
        card.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: button.leadingAnchor), card.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            card.topAnchor.constraint(equalTo: button.topAnchor), card.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.isAccessibilityElement = true
        button.accessibilityLabel = name + ", " + facts.joined(separator: ", ") + ", " + Self.date(item.createdAt)
        button.accessibilityTraits = .button
        button.addAction(UIAction { [weak self] _ in self?.open(item) }, for: .touchUpInside)
        button.addAction(UIAction { [weak button] _ in button?.alpha = 0.7 }, for: [.touchDown, .touchDragEnter])
        button.addAction(UIAction { [weak button] _ in button?.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        button.addInteraction(UIContextMenuInteraction(delegate: ContextMenu.shared))
        ContextMenu.shared.actions[ObjectIdentifier(button)] = menu(for: item)
        button.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: text("rename")) { [weak self] _ in self?.edit(item); return true },
            UIAccessibilityCustomAction(name: text("delete")) { [weak self] _ in self?.confirmDelete(item); return true }
        ]
        return button
    }

    /// Long-press menu: rename, move to an apartment/floor, delete.
    private func menu(for item: LibraryItem) -> [UIMenuElement] {
        let rename = UIAction(title: text("rename"), image: UIImage(systemName: "pencil")) { [weak self] _ in self?.edit(item) }
        let current = item.building
        var places: [(apartment: String, floor: String)] = []
        for other in Self.savedRooms().map(LibraryItem.room) + Self.savedStairs().map(LibraryItem.stair) {
            guard let b = other.building, !places.contains(where: { $0.apartment == b.name && $0.floor == b.floor }) else { continue }
            places.append((b.name, b.floor))
        }
        var assign: [UIMenuElement] = places.sorted { ($0.apartment, $0.floor) < ($1.apartment, $1.floor) }.map { place in
            let title = LibraryLabels.group(RoomPlanDocument.Building(name: place.apartment, floor: place.floor, room: ""))
            let action = UIAction(title: title, image: UIImage(systemName: "building.2")) { [weak self] _ in
                self?.relabel(item, name: item.name, apartment: place.apartment, floor: place.floor)
            }
            if current?.name == place.apartment && current?.floor == place.floor { action.state = .on }
            return action
        }
        assign.append(UIAction(title: text("newApartment"), image: UIImage(systemName: "plus")) { [weak self] _ in self?.edit(item, focusApartment: true) })
        if current != nil {
            assign.append(UIAction(title: text("noApartment"), image: UIImage(systemName: "tray")) { [weak self] _ in
                self?.relabel(item, name: item.name, apartment: "", floor: "")
            })
        }
        let delete = UIAction(title: text("delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete(item) }
        return [rename, UIMenu(title: text("assign"), image: UIImage(systemName: "building.2"), children: assign), UIMenu(options: .displayInline, children: [delete])]
    }

    private func edit(_ item: LibraryItem, focusApartment: Bool = false) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: text("renameTitle"), message: nil, preferredStyle: .alert)
        let b = item.building
        let values = [item.name, b.map { $0.name == LibraryLabels.placeholder ? "" : $0.name } ?? "", b.map { $0.floor == LibraryLabels.placeholder ? "" : $0.floor } ?? ""]
        for (index, placeholder) in [text("itemName"), text("apartment"), text("floorLabel")].enumerated() {
            alert.addTextField { field in
                field.placeholder = placeholder
                field.text = values[index]
                field.autocapitalizationType = .sentences
                field.clearButtonMode = .whileEditing
                field.accessibilityLabel = placeholder
            }
        }
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("done"), style: .default) { [weak self, weak alert] _ in
            let fields = alert?.textFields ?? []
            let name = (fields.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self?.relabel(item, name: name.isEmpty ? item.name : name, apartment: fields.count > 1 ? fields[1].text ?? "" : "", floor: fields.count > 2 ? fields[2].text ?? "" : "")
        })
        present(alert, animated: true) {
            if focusApartment, let fields = alert.textFields, fields.count > 1 { fields[1].text = ""; fields[1].becomeFirstResponder() }
        }
    }

    private func relabel(_ item: LibraryItem, name: String, apartment: String, floor: String) {
        do {
            switch item {
            case .room(let room):
                let updated = try room.relabeled(name: name, apartment: apartment, floor: floor)
                NotificationCenter.default.post(name: SavedRoomViewController.changed, object: updated)
            case .stair(let stair): _ = try stair.relabeled(name: name, apartment: apartment, floor: floor)
            }
        } catch {
            let alert = UIAlertController(title: text("invalidInput"), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
            present(alert, animated: true)
        }
        reload()
    }

    static func date(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return String(iso.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func open(_ item: LibraryItem) {
        switch item {
        case .room(let room):
            let detail = SavedRoomViewController(room: room)
            detail.onDeleted = { [weak self] in self?.reload() }
            navigationController?.pushViewController(detail, animated: true)
        case .stair(let stair):
            navigationController?.pushViewController(StairResultViewController(scan: stair), animated: true)
        }
    }

    private func confirmDelete(_ item: LibraryItem) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: text("deleteTitle"), message: text("deleteBody"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("delete"), style: .destructive) { [weak self] _ in
            switch item {
            case .room(let room): SavedRoomViewController.remove(room)
            case .stair(let stair): try? FileManager.default.removeItem(at: stair.folder)
            }
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func startRoomScan() {
        guard roomScanSupported else {
            let alert = UIAlertController(title: MeasurementGuide.roomText("title"), message: MeasurementGuide.roomText("unsupported"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("more"), style: .default) { [weak self] _ in self?.showMore() })
            alert.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .cancel))
            present(alert, animated: true)
            return
        }
        onRoute?(.roomScan)
    }

    private func showMore() {
        guard presentedViewController == nil else { return }
        let sheet = KanturaMoreCaptureViewController()
        sheet.onRoute = { [weak self] route in
            // The transport check needs no camera; it opens inside this navigation.
            if route == .transport {
                let check = TransportCheckViewController()
                check.onStairScan = { [weak self] in self?.onRoute?(.stairScan) }
                self?.navigationController?.pushViewController(check, animated: true)
            }
            else { self?.onRoute?(route) }
        }
        let navigation = UINavigationController(rootViewController: sheet)
        if #available(iOS 15.0, *), let presentation = navigation.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func settingsMenu() -> UIMenu {
        let guide = MeasurementGuide.all[MeasurementGuide.selectedLanguage]
        let language = UIAction(title: guide?.language ?? "Language", image: UIImage(systemName: "globe")) { [weak self] _ in self?.selectLanguage() }
        let video = UIAction(title: text("tutorial"), image: UIImage(systemName: "play.rectangle")) { [weak self] _ in self?.playTutorial() }
        let expert = UIAction(title: text("expert"), image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.onRoute?(.expert) }
        return UIMenu(title: text("settings"), children: [language, video, UIMenu(options: .displayInline, children: [expert])])
    }

    private func selectLanguage() {
        guard presentedViewController == nil else { return }
        let languages = KanturaLanguageViewController(style: .insetGrouped)
        languages.onSelection = { [weak self] language in
            MeasurementGuide.selectedLanguage = language
            let direction: UISemanticContentAttribute = MeasurementGuide.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
            self?.navigationController?.view.semanticContentAttribute = direction
            self?.render()
            self?.onLanguageChange?()
        }
        let navigation = UINavigationController(rootViewController: languages)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func playTutorial() {
        guard presentedViewController == nil else { return }
        guard let url = Bundle.main.url(forResource: "kantura-" + MeasurementGuide.selectedLanguage, withExtension: "mp4", subdirectory: "videos") else {
            let alert = UIAlertController(title: MeasurementGuide.roomText("videoUnavailable"), message: MeasurementGuide.roomText("videoUnavailableDetail"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .cancel))
            present(alert, animated: true)
            return
        }
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        present(controller, animated: true) { player.play() }
    }
}

/// Context-menu actions keyed by the card that owns them, so cards stay plain buttons.
private final class ContextMenu: NSObject, UIContextMenuInteractionDelegate {
    static let shared = ContextMenu()
    var actions: [ObjectIdentifier: [UIMenuElement]] = [:]
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let view = interaction.view, let items = actions[ObjectIdentifier(view)] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in UIMenu(children: items) }
    }
}

/// Everything that is not a room scan, in one short list.
final class KanturaMoreCaptureViewController: UIViewController {
    var onRoute: ((KanturaHomeViewController.Route) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        title = MeasurementGuide.homeText("moreTitle")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: MeasurementGuide.all[MeasurementGuide.selectedLanguage]?.close, style: .done, target: self, action: #selector(close))
        let (_, column) = KanturaDesign.scrollColumn(in: self, spacing: 10)
        let entries: [(KanturaHomeViewController.Route, String, String, String)] = [
            (.stairScan, MeasurementGuide.homeText("stairTitle"), MeasurementGuide.homeText("stairDetail"), "figure.stairs"),
            (.gateScan, MeasurementGuide.homeText("gate"), MeasurementGuide.homeText("gateDetail"), "camera.viewfinder"),
            (.photoObject, MeasurementGuide.objectText("title"), MeasurementGuide.objectText("detail"), "camera.aperture"),
            (.scenePhotos, MeasurementGuide.sceneText("title"), MeasurementGuide.sceneText("detail"), "camera.on.rectangle"),
            (.splat, MeasurementGuide.splatText("title"), MeasurementGuide.splatText("detail"), "sparkles"),
            (.transport, MeasurementGuide.homeText("transportTitle"), MeasurementGuide.homeText("transportMore"), "shippingbox"),
            (.lidarProjects, MeasurementGuide.homeText("lidarProjects"), MeasurementGuide.homeText("lidarProjectsDetail"), "folder")
        ]
        for (route, title, detail, icon) in entries {
            let card = KanturaActionCard(title: title, detail: detail, icon: icon)
            card.addAction(UIAction { [weak self] _ in
                let callback = self?.onRoute
                self?.dismiss(animated: true) { callback?(route) }
            }, for: .touchUpInside)
            column.addArrangedSubview(card)
        }
    }

    @objc private func close() { dismiss(animated: true) }
}
