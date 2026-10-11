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
        let arrow = UIImageView(image: UIImage(systemName: enabled ? "arrow.up.right" : "lock"))
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
