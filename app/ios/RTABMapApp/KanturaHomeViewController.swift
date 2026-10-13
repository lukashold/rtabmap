import UIKit
import AVKit

/// The app's front door: saved rooms first, one obvious way to scan the next
/// one, and every other capture type one tap away under "Other capture types".
/// All scanning, saving and processing stays in the existing controllers; this
/// screen only lists results and routes the user.
final class KanturaHomeViewController: UIViewController {
    enum Route { case roomScan, gateScan, lidarProjects, lidarWorkflow, photoObject, scenePhotos, splat, expert, transport }
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
        let rooms = Self.savedRooms()
        if rooms.isEmpty {
            column.addArrangedSubview(emptyState())
        } else {
            let groups = Dictionary(grouping: rooms) { room -> String in
                guard let building = room.document.building else { return "" }
                return building.name + " · " + building.floor
            }
            for title in groups.keys.sorted() {
                if !title.isEmpty || groups.count > 1 {
                    let header = KanturaDesign.label(title.isEmpty ? MeasurementGuide.roomText("otherRooms") : title, style: .subheadline, secondary: true)
                    header.accessibilityTraits.insert(.header)
                    column.addArrangedSubview(header)
                    column.setCustomSpacing(8, after: header)
                }
                for room in groups[title]! { column.addArrangedSubview(card(for: room)) }
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

    private func card(for room: SavedRoomPlan) -> UIView {
        let summary = RoomPlanSummary(room.document)
        let name = room.document.building?.room ?? room.document.name
        let heading = KanturaDesign.label(name, style: .headline)
        var facts = [KanturaDesign.metric(summary.floorArea, unit: "m²", decimals: 1)]
        if summary.wallHeight != nil { facts.append(KanturaDesign.metric(summary.wallHeight, unit: "m", decimals: 2)) }
        facts.append(Self.date(room.document.createdAt))
        let detail = KanturaDesign.label(facts.joined(separator: " · "), style: .subheadline, secondary: true)
        let copy = UIStackView(arrangedSubviews: [heading, detail])
        copy.axis = .vertical
        copy.spacing = 4
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = KanturaDesign.muted
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [KanturaDesign.symbolTile("square.split.bottomrightquarter"), copy, chevron])
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
        button.accessibilityLabel = name + ", " + facts.joined(separator: ", ")
        button.accessibilityTraits = .button
        button.addAction(UIAction { [weak self] _ in self?.open(room) }, for: .touchUpInside)
        button.addAction(UIAction { [weak button] _ in button?.alpha = 0.7 }, for: [.touchDown, .touchDragEnter])
        button.addAction(UIAction { [weak button] _ in button?.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        let delete = UIAction(title: text("delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete(room) }
        button.addInteraction(UIContextMenuInteraction(delegate: ContextMenu.shared))
        ContextMenu.shared.actions[ObjectIdentifier(button)] = [delete]
        button.accessibilityCustomActions = [UIAccessibilityCustomAction(name: text("delete")) { [weak self] _ in self?.confirmDelete(room); return true }]
        return button
    }

    static func date(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return String(iso.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func open(_ room: SavedRoomPlan) {
        let detail = SavedRoomViewController(room: room)
        detail.onDeleted = { [weak self] in self?.reload() }
        navigationController?.pushViewController(detail, animated: true)
    }

    private func confirmDelete(_ room: SavedRoomPlan) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: text("deleteTitle"), message: text("deleteBody"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("delete"), style: .destructive) { [weak self] _ in
            SavedRoomViewController.remove(room)
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
            if route == .transport { self?.navigationController?.pushViewController(TransportCheckViewController(), animated: true) }
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
