import UIKit

/// Shared native presentation tokens. All controls work on iOS 14 and adapt to
/// Dynamic Type and dark appearance; this layer contains no capture logic.
enum KanturaDesign {
    static let ink = UIColor(red: 37.0 / 255.0, green: 26.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)
    static let mint = UIColor(red: 112.0 / 255.0, green: 237.0 / 255.0, blue: 197.0 / 255.0, alpha: 1)
    static let background = UIColor { $0.userInterfaceStyle == .dark ? color(0x15111F) : color(0xFAF8F3) }
    static let surface = UIColor { $0.userInterfaceStyle == .dark ? color(0x251D34) : .white }
    static let text = UIColor { $0.userInterfaceStyle == .dark ? color(0xF5F0FA) : ink }
    static let muted = UIColor { $0.userInterfaceStyle == .dark ? color(0xC0B7CD) : color(0x70677D) }
    static let border = UIColor { $0.userInterfaceStyle == .dark ? color(0x44384F) : color(0xE8E2EB) }
    static let softMint = UIColor { $0.userInterfaceStyle == .dark ? color(0x23483E) : color(0xE4F7ED) }
    static let tint = UIColor { $0.userInterfaceStyle == .dark ? mint : ink }

    private static func color(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func label(_ value: String, style: UIFont.TextStyle, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = value
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = secondary ? muted : text
        return label
    }

    static func navigation(_ controller: UIViewController) {
        let direction: UISemanticContentAttribute = MeasurementGuide.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        controller.view.semanticContentAttribute = direction
        controller.navigationController?.navigationBar.semanticContentAttribute = direction
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: text, .font: UIFont.preferredFont(forTextStyle: .headline)]
        controller.navigationItem.standardAppearance = appearance
        controller.navigationItem.scrollEdgeAppearance = appearance
        controller.navigationItem.compactAppearance = appearance
        controller.navigationController?.navigationBar.tintColor = tint
        controller.view.tintColor = tint
    }

    static func button(_ button: UIButton, primary: Bool) {
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.titleLabel?.textAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 17, left: 20, bottom: 17, right: 20)
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.backgroundColor = primary ? mint : surface
        button.tintColor = primary ? ink : tint
        button.setTitleColor(primary ? ink : text, for: .normal)
        button.setTitleColor(muted, for: .disabled)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
    }

    static func inset(_ child: UIView, padding: CGFloat = 20) -> UIView {
        let card = KanturaSurface(frame: .zero)
        child.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            child.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            child.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            child.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding)
        ])
        return card
    }
}

/// UIButton's default intrinsic height can remain one line even when its title
/// wraps. Recompute it at the actual constrained width for large text/languages.
final class KanturaButton: UIButton {
    private var measuredWidth: CGFloat = 0
    override var intrinsicContentSize: CGSize {
        let original = super.intrinsicContentSize
        guard bounds.width > 0, let label = titleLabel else { return original }
        let imageWidth = image(for: .normal)?.size.width ?? 0
        let width = max(1, bounds.width - contentEdgeInsets.left - contentEdgeInsets.right - imageWidth)
        let titleSize = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: original.width, height: max(56, titleSize.height + contentEdgeInsets.top + contentEdgeInsets.bottom))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if measuredWidth != bounds.width {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        invalidateIntrinsicContentSize()
    }
}

final class KanturaSurface: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KanturaDesign.surface
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        refreshBorder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshBorder()
    }
    private func refreshBorder() { layer.borderColor = KanturaDesign.border.resolvedColor(with: traitCollection).cgColor }
}

final class KanturaActionCard: UIButton {
    enum Emphasis { case standard, prominent, mint }
    private let emphasis: Emphasis
    private var contentRow: UIStackView?
    private var accessibleCopyWidth: NSLayoutConstraint?
    private weak var accessory: UIImageView?

    init(title: String, detail: String, icon: String, emphasis: Emphasis = .standard, enabled: Bool = true) {
        self.emphasis = emphasis
        super.init(frame: .zero)
        isEnabled = enabled
        layer.cornerRadius = emphasis == .prominent ? 26 : 22
        layer.cornerCurve = .continuous
        layer.borderWidth = emphasis == .standard ? 1 : 0
        backgroundColor = emphasis == .prominent ? KanturaDesign.ink : emphasis == .mint ? KanturaDesign.mint : KanturaDesign.surface
        let foreground = emphasis == .prominent ? UIColor.white : emphasis == .mint ? KanturaDesign.ink : enabled ? KanturaDesign.text : KanturaDesign.muted
        let symbol = UIImageView(image: UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)))
        symbol.tintColor = emphasis == .prominent ? KanturaDesign.mint : foreground
        symbol.contentMode = .scaleAspectFit
        let iconBox = UIView()
        iconBox.backgroundColor = emphasis == .prominent ? UIColor.white.withAlphaComponent(0.10) : emphasis == .mint ? UIColor.white.withAlphaComponent(0.35) : KanturaDesign.softMint
        iconBox.layer.cornerRadius = 16
        symbol.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(symbol)
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 48),
            iconBox.heightAnchor.constraint(equalToConstant: 48),
            symbol.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor)
        ])
        let heading = KanturaDesign.label(title, style: emphasis == .prominent ? .title2 : .headline)
        heading.textColor = foreground
        let subtitle = KanturaDesign.label(detail, style: .subheadline, secondary: true)
        subtitle.textColor = emphasis == .prominent ? UIColor.white.withAlphaComponent(0.82) : emphasis == .mint ? KanturaDesign.ink.withAlphaComponent(0.8) : KanturaDesign.muted
        let copy = UIStackView(arrangedSubviews: [heading, subtitle])
        copy.axis = .vertical
        copy.spacing = 7
        let arrow = UIImageView(image: UIImage(systemName: enabled ? "chevron.forward" : "lock"))
        arrow.tintColor = foreground
        arrow.contentMode = .scaleAspectFit
        arrow.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let row = UIStackView(arrangedSubviews: [iconBox, copy, arrow])
        row.spacing = 15
        row.alignment = .top
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        contentRow = row
        accessibleCopyWidth = copy.widthAnchor.constraint(equalTo: row.widthAnchor)
        accessory = arrow
        addSubview(row)
        let padding: CGFloat = emphasis == .prominent ? 24 : 20
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            row.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            heightAnchor.constraint(greaterThanOrEqualToConstant: emphasis == .prominent ? 132 : 98)
        ])
        accessibilityLabel = title
        accessibilityHint = detail
        isAccessibilityElement = true
        refreshBorder()
        adaptToTextSize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.84 : 1 } }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshBorder()
        adaptToTextSize()
    }
    private func refreshBorder() { layer.borderColor = KanturaDesign.border.resolvedColor(with: traitCollection).cgColor }
    private func adaptToTextSize() {
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        contentRow?.axis = large ? .vertical : .horizontal
        contentRow?.alignment = large ? .leading : .top
        accessibleCopyWidth?.isActive = large
        accessory?.isHidden = large
    }
}

// MARK: - Scan-first building blocks (home, capture, result)

extension KanturaDesign {
    /// Localized number with a fixed number of decimals and an isolated SI unit,
    /// so values read correctly inside right-to-left text.
    static func metric(_ value: Double?, unit: String, decimals: Int) -> String {
        guard let value = value, value.isFinite else { return MeasurementGuide.homeText("notDetected") }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
        return "\u{2066}\(number) \(unit)\u{2069}"
    }

    /// Short headline numbers of a room, in the order the home and result screens use.
    static func roomMetrics(_ summary: RoomPlanSummary) -> [(title: String, value: String)] {
        [(MeasurementGuide.homeText("floorArea"), metric(summary.floorArea, unit: "m²", decimals: 1)),
         (MeasurementGuide.homeText("netWall"), metric(summary.walls > 0 ? summary.netWallArea : nil, unit: "m²", decimals: 1)),
         (MeasurementGuide.homeText("height"), metric(summary.wallHeight, unit: "m", decimals: 2)),
         (MeasurementGuide.homeText("grossWall"), metric(summary.walls > 0 ? summary.grossWallArea : nil, unit: "m²", decimals: 1))]
    }

    static func roomNotes(_ summary: RoomPlanSummary) -> [String] {
        var notes: [String] = []
        if summary.incomplete { notes.append(MeasurementGuide.homeText("partialNote")) }
        if summary.unresolvedOpenings > 0 { notes.append(MeasurementGuide.homeText("unresolvedNote", ["count": summary.unresolvedOpenings])) }
        notes.append(MeasurementGuide.homeText("accuracyNote"))
        return notes
    }

    static func symbolTile(_ name: String, size: CGFloat = 44, filled: Bool = false) -> UIView {
        let tile = UIView()
        tile.backgroundColor = filled ? mint : softMint
        tile.layer.cornerRadius = size * 0.32
        tile.layer.cornerCurve = .continuous
        let symbol = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)))
        symbol.tintColor = filled ? ink : tint
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(symbol)
        tile.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: size), tile.heightAnchor.constraint(equalToConstant: size),
            symbol.centerXAnchor.constraint(equalTo: tile.centerXAnchor), symbol.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
        return tile
    }

    /// Large primary call to action with an SF Symbol, used at the bottom of screens.
    static func primaryButton(_ title: String, icon: String?, handler: @escaping () -> Void) -> KanturaButton {
        let button = KanturaButton(type: .system)
        button.setTitle(icon == nil ? title : "  " + title, for: .normal)
        if let icon = icon { button.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)), for: .normal) }
        self.button(button, primary: true)
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return button
    }

    static func secondaryButton(_ title: String, icon: String? = nil, handler: @escaping () -> Void) -> KanturaButton {
        let button = KanturaButton(type: .system)
        button.setTitle(icon == nil ? title : "  " + title, for: .normal)
        if let icon = icon { button.setImage(UIImage(systemName: icon), for: .normal) }
        self.button(button, primary: false)
        button.layer.borderWidth = 1
        button.layer.borderColor = border.cgColor
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return button
    }

    /// A translucent bottom bar that keeps its buttons above the home indicator.
    static func bottomBar(_ views: [UIView], in controller: UIViewController) -> UIView {
        let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(stack)
        bar.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(bar)
        let readable = stack.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        let fill = stack.widthAnchor.constraint(equalTo: bar.widthAnchor, constant: -40)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: bar.contentView.topAnchor, constant: 14),
            stack.centerXAnchor.constraint(equalTo: bar.contentView.centerXAnchor),
            readable, fill,
            stack.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        return bar
    }

    /// Vertical scroll with a readable, centred content column.
    static func scrollColumn(in controller: UIViewController, spacing: CGFloat = 16) -> (scroll: UIScrollView, column: UIStackView) {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = spacing
        column.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        scroll.addSubview(column)
        let preferred = column.widthAnchor.constraint(equalToConstant: 600)
        preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: controller.view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            column.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            preferred
        ])
        return (scroll, column)
    }
}

/// Two-column grid of headline numbers; one column at accessibility text sizes.
final class KanturaMetricGrid: UIView {
    private let rows = UIStackView()
    private var items: [(title: String, value: String)] = []

    init(_ items: [(title: String, value: String)]) {
        super.init(frame: .zero)
        rows.axis = .vertical
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor), rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor), rows.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        update(items)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ items: [(title: String, value: String)]) {
        self.items = items
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let perRow = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
        for start in stride(from: 0, to: items.count, by: perRow) {
            let row = UIStackView(arrangedSubviews: items[start..<min(items.count, start + perRow)].map(tile))
            row.spacing = 10
            row.distribution = .fillEqually
            rows.addArrangedSubview(row)
        }
    }

    private func tile(_ item: (title: String, value: String)) -> UIView {
        let value = KanturaDesign.label(item.value, style: .title2)
        value.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .monospacedDigitSystemFont(ofSize: 24, weight: .semibold))
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        let caption = KanturaDesign.label(item.title, style: .footnote, secondary: true)
        let stack = UIStackView(arrangedSubviews: [value, caption])
        stack.axis = .vertical
        stack.spacing = 4
        let card = KanturaDesign.inset(stack, padding: 16)
        card.isAccessibilityElement = true
        card.accessibilityLabel = item.title + ": " + item.value
        return card
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory.isAccessibilityCategory != traitCollection.preferredContentSizeCategory.isAccessibilityCategory { update(items) }
    }
}

/// Round shutter-style control used to finish a capture.
final class KanturaCaptureButton: UIControl {
    private let ring = UIView(), core = UIView(), caption = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.borderWidth = 5
        ring.layer.cornerRadius = 40
        ring.isUserInteractionEnabled = false
        core.backgroundColor = KanturaDesign.mint
        core.layer.cornerRadius = 9
        core.layer.cornerCurve = .continuous
        core.isUserInteractionEnabled = false
        caption.text = title
        caption.textColor = .white
        caption.font = .preferredFont(forTextStyle: .headline)
        caption.adjustsFontForContentSizeCategory = true
        caption.textAlignment = .center
        caption.layer.shadowColor = UIColor.black.cgColor
        caption.layer.shadowOpacity = 0.6
        caption.layer.shadowRadius = 4
        caption.layer.shadowOffset = .zero
        for view in [ring, core, caption] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 80), ring.heightAnchor.constraint(equalToConstant: 80),
            ring.topAnchor.constraint(equalTo: topAnchor), ring.centerXAnchor.constraint(equalTo: centerXAnchor),
            core.widthAnchor.constraint(equalToConstant: 34), core.heightAnchor.constraint(equalToConstant: 34),
            core.centerXAnchor.constraint(equalTo: ring.centerXAnchor), core.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            caption.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: 8),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor), caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool { didSet { ring.alpha = isHighlighted ? 0.6 : 1; core.transform = isHighlighted ? CGAffineTransform(scaleX: 0.85, y: 0.85) : .identity } }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.45 } }
}

/// Dark translucent pill for short live instructions over the camera.
final class KanturaHintPill: UIVisualEffectView {
    let label = UILabel()
    init(_ text: String) {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        label.text = text
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
