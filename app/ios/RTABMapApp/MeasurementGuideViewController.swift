import UIKit

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
    private let accent = UIColor.systemIndigo

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.tintColor = accent
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let preferredWidth = content.widthAnchor.constraint(equalToConstant: 560)
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

    private func label(_ text: String, style: UIFont.TextStyle, color: UIColor = .label) -> UILabel {
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
        result.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        result.titleLabel?.adjustsFontForContentSizeCategory = true
        result.titleLabel?.numberOfLines = 0
        result.contentEdgeInsets = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        result.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        result.layer.cornerRadius = 16
        result.backgroundColor = filled ? accent : .secondarySystemGroupedBackground
        result.tintColor = filled ? .white : accent
        result.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return result
    }

    private func render() {
        guard let guide = guides[MeasurementGuide.selectedLanguage] else { return }
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
        hero.layer.cornerRadius = 18
        hero.clipsToBounds = true
        hero.translatesAutoresizingMaskIntoConstraints = false
        let heroContainer = UIView()
        heroContainer.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.widthAnchor.constraint(equalToConstant: 76),
            hero.heightAnchor.constraint(equalToConstant: 76),
            hero.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            hero.topAnchor.constraint(equalTo: heroContainer.topAnchor),
            hero.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor)
        ])
        hero.isAccessibilityElement = false
        content.addArrangedSubview(heroContainer)
        let heading = label(guide.subtitle, style: .title1)
        heading.textAlignment = .center
        content.addArrangedSubview(heading)
        let status: String
        switch workflowState.phase {
        case .ready: status = workflow.readyTitle
        case .captured, .pointCloud: status = workflow.capturedTitle
        case .mesh: status = workflow.modelTitle
        case .busy: status = workflow.availableLater
        }
        let statusLabel = label(status, style: .subheadline, color: .secondaryLabel)
        statusLabel.textAlignment = .center
        content.addArrangedSubview(statusLabel)
        if workflowState.availableActions.contains(.scan) {
            content.addArrangedSubview(button(MeasurementGuide.roomText("modeTitle"), icon: "square.split.bottomrightquarter") { [weak self] in
                guard let self = self else { return }
                let callback = self.onRoomPlan
                let closed = self.onClose
                self.dismiss(animated: true) { closed?(); callback?() }
            })
            content.addArrangedSubview(label(MeasurementGuide.roomText("modeDetail"), style: .footnote, color: .secondaryLabel))
            content.addArrangedSubview(button(MeasurementGuide.roomText("library"), icon: "building.2") { [weak self] in
                guard let self = self else { return }
                let callback = self.onRoomPlanLibrary
                let closed = self.onClose
                self.dismiss(animated: true) { closed?(); callback?() }
            })
        }
        let entries: [(Action, String)] = [(.scan, "camera.viewfinder"), (.assemble, "cube.transparent"), (.measure, "ruler"), (.share, "square.and.arrow.up")]
        for (index, entry) in entries.enumerated() where workflow.stages.indices.contains(index) {
            let stage = workflow.stages[index]
            let available = workflowState.availableActions.contains(entry.0)
            let recommended = workflowState.primaryAction == entry.0
            let card = WorkflowCard(number: index + 1, title: stage.title, detail: stage.detail,
                                    icon: entry.1, recommended: recommended, enabled: available)
            card.accessibilityHint = available ? stage.detail : workflow.availableLater
            card.addAction(UIAction { [weak self] _ in self?.perform(entry.0) }, for: .touchUpInside)
            content.addArrangedSubview(card)
        }
        if workflowState.availableActions.contains(.library) {
            content.addArrangedSubview(button(workflow.projects, icon: "folder") { [weak self] in self?.perform(.library) })
        }
        content.addArrangedSubview(button(workflow.tutorial, icon: "play.circle") { [weak self] in
            self?.step = 0
            self?.render()
        })
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
        progress.accessibilityLabel = "\(step + 1) / \(guide.steps.count)"
        content.addArrangedSubview(progress)
        let symbol = UIImageView(image: UIImage(systemName: current.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 64, weight: .light)))
        symbol.contentMode = .scaleAspectFit
        symbol.tintColor = accent
        symbol.heightAnchor.constraint(equalToConstant: 90).isActive = true
        symbol.isAccessibilityElement = false
        content.addArrangedSubview(symbol)
        content.addArrangedSubview(label(current.title, style: .title1))
        content.addArrangedSubview(label(current.body, style: .body))
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

private final class WorkflowCard: UIButton {
    init(number: Int, title: String, detail: String, icon: String, recommended: Bool, enabled: Bool) {
        super.init(frame: .zero)
        isEnabled = enabled
        backgroundColor = recommended ? .systemIndigo : .secondarySystemGroupedBackground
        layer.cornerRadius = 20
        layer.borderWidth = recommended ? 0 : 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.25).cgColor
        let foreground: UIColor = recommended ? .white : enabled ? .label : .secondaryLabel
        let symbol = UIImageView(image: UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 25, weight: .medium)))
        symbol.tintColor = foreground
        symbol.contentMode = .scaleAspectFit
        symbol.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let heading = UILabel()
        heading.text = "\(number). \(title)"
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.textColor = foreground
        let subtitle = UILabel()
        subtitle.text = detail
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = recommended ? UIColor.white.withAlphaComponent(0.85) : .secondaryLabel
        [heading, subtitle].forEach {
            $0.numberOfLines = 0
            $0.adjustsFontForContentSizeCategory = true
        }
        let text = UIStackView(arrangedSubviews: [heading, subtitle])
        text.axis = .vertical
        text.spacing = 5
        let arrow = UIImageView(image: UIImage(systemName: enabled ? "chevron.right" : "lock"))
        arrow.tintColor = foreground
        arrow.contentMode = .scaleAspectFit
        arrow.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let row = UIStackView(arrangedSubviews: [symbol, text, arrow])
        row.spacing = 14
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
        accessibilityLabel = "\(number). \(title)"
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
