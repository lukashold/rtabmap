import UIKit
import AVKit

/// A native workspace in front of the scanner. Capture and reconstruction remain
/// RTAB-Map's; tutorial content is shared with the browser measurement workspace.
final class MeasurementGuideViewController: UIViewController {
    typealias Action = MeasurementAction
    var onAction: ((Action) -> Void)?
    var onLanguageChange: (() -> Void)?
    var onClose: (() -> Void)?
    var onRoomPlan: (() -> Void)?
    var onRoomPlanLibrary: (() -> Void)?
    var workflowState = MeasurementWorkflowState(phase: .ready, canReconstruct: false, hasProjects: false)
    private let guides = MeasurementGuide.all
    private var step: Int?
    private let content = UIStackView()
    private let scroll = UIScrollView()
    private let accent = KanturaDesign.tint

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        view.tintColor = accent
        KanturaDesign.navigation(self)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let preferredWidth = content.widthAnchor.constraint(equalToConstant: 600)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            preferredWidth
        ])
        render()
    }

    private func label(_ text: String, style: UIFont.TextStyle, color: UIColor = KanturaDesign.text) -> UILabel {
        let result = UILabel()
        result.text = text
        result.font = .preferredFont(forTextStyle: style)
        result.textColor = color
        result.numberOfLines = 0
        result.adjustsFontForContentSizeCategory = true
        return result
    }

    private func button(_ text: String, icon: String, filled: Bool = false, handler: @escaping () -> Void) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle("  " + text, for: .normal)
        result.setImage(UIImage(systemName: icon), for: .normal)
        KanturaDesign.button(result, primary: filled)
        result.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return result
    }

    private func render() {
        guard let guide = guides[MeasurementGuide.selectedLanguage] else { return }
        KanturaDesign.navigation(self)
        title = "KANTURA"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: guide.close, style: .done, target: self, action: #selector(closeGuide))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: guide.language, style: .plain, target: self, action: #selector(selectLanguage))
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let step = step, guide.steps.indices.contains(step) {
            renderTutorial(guide, step: step)
        } else {
            self.step = nil
            renderOverview(guide)
        }
        scroll.setContentOffset(.zero, animated: false)
    }

    private func renderOverview(_ guide: MeasurementGuide) {
        guard let workflow = guide.workflow else {
            step = 0
            renderTutorial(guide, step: 0)
            return
        }
        let hero = UIImageView(image: UIImage(named: "KanturaMark"))
        hero.contentMode = .scaleAspectFit
        hero.layer.cornerRadius = 16
        hero.clipsToBounds = true
        hero.translatesAutoresizingMaskIntoConstraints = false
        let heroContainer = UIView()
        heroContainer.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.widthAnchor.constraint(equalToConstant: 60),
            hero.heightAnchor.constraint(equalToConstant: 60),
            hero.leadingAnchor.constraint(equalTo: heroContainer.leadingAnchor),
            hero.topAnchor.constraint(equalTo: heroContainer.topAnchor),
            hero.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor)
        ])
        hero.isAccessibilityElement = false
        content.addArrangedSubview(heroContainer)
        let heading = label(guide.title, style: .largeTitle)
        heading.accessibilityTraits.insert(.header)
        content.addArrangedSubview(heading)
        content.addArrangedSubview(label(guide.subtitle, style: .body, color: KanturaDesign.muted))
        let status: String
        switch workflowState.phase {
        case .ready: status = workflow.readyTitle
        case .captured, .pointCloud: status = workflow.capturedTitle
        case .mesh: status = workflow.modelTitle
        case .busy: status = workflow.availableLater
        }
        let statusLabel = label(status, style: .subheadline, color: KanturaDesign.muted)
        content.addArrangedSubview(KanturaDesign.inset(statusLabel, padding: 16))
        content.setCustomSpacing(24, after: content.arrangedSubviews.last!)
        if workflowState.availableActions.contains(.scan) {
            let roomPlan = KanturaActionCard(title: MeasurementGuide.roomText("modeTitle"),
                detail: MeasurementGuide.roomText("modeDetail"), icon: "square.split.bottomrightquarter", emphasis: .prominent)
            roomPlan.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                let callback = self.onRoomPlan
                let closed = self.onClose
                self.dismiss(animated: true) { closed?(); callback?() }
            }, for: .touchUpInside)
            content.addArrangedSubview(roomPlan)
            let library = KanturaActionCard(title: MeasurementGuide.roomText("library"),
                detail: ["building", "floorName", "name"].map { MeasurementGuide.roomText($0) }.joined(separator: " · "), icon: "building.2")
            library.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                let callback = self.onRoomPlanLibrary
                let closed = self.onClose
                self.dismiss(animated: true) { closed?(); callback?() }
            }, for: .touchUpInside)
            content.addArrangedSubview(library)
            content.setCustomSpacing(28, after: library)
        }
        let workflowHeading = label(guide.start, style: .title2)
        workflowHeading.accessibilityTraits.insert(.header)
        content.addArrangedSubview(workflowHeading)
        let entries: [(Action, String)] = [(.scan, "camera.viewfinder"), (.assemble, "cube.transparent"), (.measure, "ruler"), (.share, "square.and.arrow.up")]
        for (index, entry) in entries.enumerated() where workflow.stages.indices.contains(index) {
            let stage = workflow.stages[index]
            let available = workflowState.availableActions.contains(entry.0)
            let recommended = workflowState.primaryAction == entry.0
            let card = KanturaActionCard(title: "\(index + 1). \(stage.title)", detail: stage.detail,
                                    icon: entry.1, emphasis: recommended ? .mint : .standard, enabled: available)
            card.accessibilityHint = available ? stage.detail : workflow.availableLater
            card.addAction(UIAction { [weak self] _ in self?.perform(entry.0) }, for: .touchUpInside)
            content.addArrangedSubview(card)
        }
        if workflowState.availableActions.contains(.library) {
            content.addArrangedSubview(button(workflow.projects, icon: "folder") { [weak self] in self?.perform(.library) })
        }
        let video = KanturaActionCard(title: MeasurementGuide.roomText("videoTitle"),
            detail: MeasurementGuide.roomText("videoDetail") + "\n" + guide.name,
            icon: "play.rectangle.fill", emphasis: .mint)
        video.addAction(UIAction { [weak self] _ in self?.showTutorialVideo() }, for: .touchUpInside)
        content.addArrangedSubview(video)
        content.addArrangedSubview(button(workflow.tutorial, icon: "text.book.closed") { [weak self] in
            self?.step = 0
            self?.render()
        })
    }

    private func showTutorialVideo() {
        guard presentedViewController == nil,
              let guide = guides[MeasurementGuide.selectedLanguage] else { return }
        guard let url = Bundle.main.url(forResource: "kantura-" + MeasurementGuide.selectedLanguage,
                                        withExtension: "mp4", subdirectory: "videos") else {
            let alert = UIAlertController(title: MeasurementGuide.roomText("videoUnavailable"),
                message: MeasurementGuide.roomText("videoUnavailableDetail"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: guide.workflow?.tutorial ?? guide.title, style: .default) { [weak self] _ in
                self?.step = 0
                self?.render()
            })
            alert.addAction(UIAlertAction(title: guide.close, style: .cancel))
            present(alert, animated: true)
            return
        }
        // Keep the dashboard and scanner state intact; this only plays a bundled lesson.
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        present(controller, animated: true) { player.play() }
    }

    private func renderTutorial(_ guide: MeasurementGuide, step: Int) {
        guard guide.steps.indices.contains(step) else { return }
        let current = guide.steps[step]
        if let overview = guide.workflow?.overview {
            content.addArrangedSubview(button(overview, icon: "square.grid.2x2") { [weak self] in
                self?.step = nil
                self?.render()
            })
        }
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progress = Float(step + 1) / Float(guide.steps.count)
        progress.progressTintColor = KanturaDesign.tint
        progress.trackTintColor = KanturaDesign.border
        progress.accessibilityLabel = "\(step + 1) / \(guide.steps.count)"
        content.addArrangedSubview(progress)
        let symbol = UIImageView(image: UIImage(systemName: current.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 64, weight: .light)))
        symbol.contentMode = .scaleAspectFit
        symbol.tintColor = accent
        symbol.heightAnchor.constraint(equalToConstant: 90).isActive = true
        symbol.isAccessibilityElement = false
        let lesson = UIStackView(arrangedSubviews: [symbol, label(current.title, style: .title1), label(current.body, style: .body)])
        lesson.axis = .vertical
        lesson.spacing = 22
        content.addArrangedSubview(KanturaDesign.inset(lesson, padding: 24))
        let back = button(guide.back, icon: "chevron.left") { [weak self] in
            self?.step = max(0, step - 1)
            self?.render()
        }
        back.isEnabled = step > 0
        let last = step == guide.steps.count - 1
        let next = button(last ? guide.done : guide.next, icon: last ? "checkmark" : "chevron.right", filled: true) { [weak self] in
            self?.step = last ? nil : step + 1
            self?.render()
        }
        let navigation = UIStackView(arrangedSubviews: [back, next])
        navigation.axis = .vertical
        navigation.spacing = 10
        content.addArrangedSubview(navigation)
        let action: Action? = step <= 1 ? .scan : step == 2 ? .assemble : step == 3 ? .measure : step == 6 ? .share : nil
        if let action = action, workflowState.availableActions.contains(action) {
            let actionTitle: String
            switch action {
            case .scan: actionTitle = guide.start
            case .assemble: actionTitle = guide.assemble
            case .measure: actionTitle = guide.measure
            case .share: actionTitle = guide.share
            case .library: return
            }
            content.addArrangedSubview(button(actionTitle, icon: "arrow.right.circle") { [weak self] in self?.perform(action) })
        }
    }

    private func perform(_ action: Action) {
        guard workflowState.availableActions.contains(action) else { return }
        let callback = onAction
        let closed = onClose
        dismiss(animated: true) { closed?(); callback?(action) }
    }

    @objc private func closeGuide() {
        let closed = onClose
        dismiss(animated: true) { closed?() }
    }

    @objc private func selectLanguage() {
        guard let guide = guides[MeasurementGuide.selectedLanguage] else { return }
        let sheet = UIAlertController(title: guide.language, message: nil, preferredStyle: .actionSheet)
        for language in MeasurementGuide.languages {
            sheet.addAction(UIAlertAction(title: guides[language]?.name ?? language, style: .default) { [weak self] _ in
                MeasurementGuide.selectedLanguage = language
                self?.render()
                self?.onLanguageChange?()
            })
        }
        sheet.addAction(UIAlertAction(title: guide.close, style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }
}
