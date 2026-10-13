import UIKit
import SceneKit

/// "Will the fridge fit?" — a simplified envelope check (see `TransportAssessment`)
/// whose route dimensions can be taken from saved room scans: door widths and
/// heights, ceiling heights and detected stairs. Step height and tread depth are
/// best measured by hand; RoomPlan only reports stairs as a box.
final class TransportCheckViewController: UIViewController, UITextFieldDelegate {
    private let preselected: SavedRoomPlan?
    private var column: UIStackView!
    private var scroll: UIScrollView!
    private var fields: [String: UITextField] = [:]
    private let tilt = UISwitch()
    private let result = UIStackView()
    private let animation = SCNView()
    private var lastAssessment: TransportAssessment?
    /// Starts a stair scan (set by the start screen).
    var onStairScan: (() -> Void)?
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    init(preselected: SavedRoomPlan? = nil) {
        self.preselected = preselected
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = text("transportTitle")
        let layout = KanturaDesign.scrollColumn(in: self, spacing: 12)
        scroll = layout.scroll
        column = layout.column
        column.addArrangedSubview(KanturaDesign.label(text("transportIntro"), style: .subheadline, secondary: true))
        stairCard()

        section(text("device"))
        column.addArrangedSubview(menuButton(text("deviceCatalog"), icon: "list.bullet", menu: catalogMenu()))
        row([("objectWidth", text("width"), "0.60"), ("objectDepth", text("depth"), "0.66"), ("objectHeight", text("heightField"), "2.03")])

        section(text("route"))
        column.addArrangedSubview(menuButton(text("fromScan"), icon: "viewfinder", menu: scanMenu()))
        row([("passageWidth", text("passageWidth"), "0.80"), ("passageHeight", text("passageHeight"), "2.00")])
        row([("landingWidth", text("landingWidth"), "1.10"), ("landingDepth", text("landingDepth"), "1.10")])
        row([("turn", text("turn"), "180")])
        row([("rise", text("stepRise"), "0.18"), ("run", text("stepRun"), "0.27")])
        column.addArrangedSubview(KanturaDesign.label(text("stairHelp"), style: .footnote, secondary: true))
        row([("margin", text("margin"), "0.02")])
        let tiltLabel = KanturaDesign.label(text("allowTilt"), style: .body)
        tilt.onTintColor = KanturaDesign.mint
        let tiltRow = UIStackView(arrangedSubviews: [tiltLabel, tilt])
        tiltRow.alignment = .center
        tiltRow.spacing = 12
        column.addArrangedSubview(tiltRow)

        column.addArrangedSubview(KanturaDesign.primaryButton(text("check"), icon: "checkmark.shield") { [weak self] in self?.evaluate() })
        result.axis = .vertical
        result.spacing = 10
        column.addArrangedSubview(result)
        animation.backgroundColor = KanturaDesign.surface
        animation.layer.cornerRadius = 20
        animation.layer.cornerCurve = .continuous
        animation.clipsToBounds = true
        animation.allowsCameraControl = true
        animation.autoenablesDefaultLighting = true
        animation.isHidden = true
        animation.isAccessibilityElement = true
        animation.accessibilityLabel = text("animate")
        animation.heightAnchor.constraint(equalTo: animation.widthAnchor, multiplier: 0.8).isActive = true
        column.addArrangedSubview(animation)
        column.addArrangedSubview(KanturaDesign.label(text("limits"), style: .footnote, secondary: true))

        // Pre-fill the narrowest door and the ceiling height of the preselected room.
        if let room = preselected {
            let suggestions = TransportScanSuggestion.collect(from: [room.document])
            if let door = suggestions.first(where: { $0.kind == .door }) { apply(door) }
            if let height = suggestions.first(where: { $0.kind == .roomHeight }) { apply(height) }
            if let stairs = suggestions.first(where: { $0.kind == .stairs }) { apply(stairs) }
        }
    }

    /// Stairs are checked best against a stair scan: the appliance is moved
    /// along the real path instead of using a few hand-entered numbers.
    private func stairCard() {
        let stairs = KanturaHomeViewController.savedStairs()
        let card: KanturaActionCard
        if stairs.isEmpty {
            card = KanturaActionCard(title: text("stairTitle"), detail: text("stairTransportHint"), icon: "figure.stairs", emphasis: .mint)
            card.addAction(UIAction { [weak self] _ in self?.onStairScan?() }, for: .touchUpInside)
            card.isHidden = onStairScan == nil
            column.addArrangedSubview(card)
        } else {
            let button = KanturaDesign.secondaryButton(text("stairUseScan"), icon: "figure.stairs") {}
            var items: [UIMenuElement] = stairs.prefix(30).map { stair in
                UIAction(title: stair.displayName + " · " + KanturaHomeViewController.date(stair.document.createdAt)) { [weak self] _ in
                    self?.navigationController?.pushViewController(StairResultViewController(scan: stair), animated: true)
                }
            }
            if onStairScan != nil {
                items.append(UIAction(title: text("stairTitle"), image: UIImage(systemName: "plus")) { [weak self] _ in self?.onStairScan?() })
            }
            button.menu = UIMenu(children: items)
            button.showsMenuAsPrimaryAction = true
            column.addArrangedSubview(button)
        }
    }

    // MARK: Form

    private func section(_ title: String) {
        let label = KanturaDesign.label(title, style: .title3)
        label.accessibilityTraits.insert(.header)
        column.addArrangedSubview(label)
        column.setCustomSpacing(6, after: label)
    }

    private func row(_ items: [(key: String, title: String, value: String)]) {
        let stack = UIStackView()
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.alignment = .top
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { stack.axis = .vertical }
        for item in items {
            let caption = KanturaDesign.label(item.title, style: .footnote, secondary: true)
            let field = UITextField()
            field.text = item.value.replacingOccurrences(of: ".", with: Locale(identifier: MeasurementGuide.selectedLanguage).decimalSeparator ?? ".")
            field.keyboardType = item.key == "turn" ? .numbersAndPunctuation : .decimalPad
            field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium))
            field.adjustsFontForContentSizeCategory = true
            field.backgroundColor = KanturaDesign.surface
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1
            field.layer.borderColor = KanturaDesign.border.cgColor
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 44))
            field.leftViewMode = .always
            let unit = UILabel()
            unit.text = item.key == "turn" ? "°  " : "m  "
            unit.textColor = KanturaDesign.muted
            unit.font = .preferredFont(forTextStyle: .body)
            field.rightView = unit
            field.rightViewMode = .always
            field.accessibilityLabel = item.title
            field.delegate = self
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
            fields[item.key] = field
            let cell = UIStackView(arrangedSubviews: [caption, field])
            cell.axis = .vertical
            cell.spacing = 4
            stack.addArrangedSubview(cell)
        }
        column.addArrangedSubview(stack)
    }

    private func menuButton(_ title: String, icon: String, menu: UIMenu) -> UIButton {
        let button = KanturaDesign.secondaryButton(title, icon: icon) {}
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }

    private func catalogMenu() -> UIMenu {
        UIMenu(children: TransportAppliance.catalog.map { item in
            UIAction(title: "\(item.brand) \(item.model)") { [weak self] _ in
                self?.set("objectWidth", item.width); self?.set("objectDepth", item.depth); self?.set("objectHeight", item.height)
            }
        })
    }

    private func scanMenu() -> UIMenu {
        let documents = KanturaHomeViewController.savedRooms().map(\.document)
        let suggestions = TransportScanSuggestion.collect(from: documents)
        guard !suggestions.isEmpty else { return UIMenu(children: [UIAction(title: text("fromScanEmpty"), attributes: .disabled) { _ in }]) }
        let length = { (v: Double) in KanturaDesign.metric(v, unit: "m", decimals: 2).replacingOccurrences(of: "\u{2066}", with: "").replacingOccurrences(of: "\u{2069}", with: "") }
        return UIMenu(children: suggestions.prefix(40).map { item in
            let title: String
            switch item.kind {
            case .door: title = text("scanDoor").replacingOccurrences(of: "{width}", with: length(item.width)).replacingOccurrences(of: "{height}", with: length(item.height))
            case .stairs: title = text("scanStairs").replacingOccurrences(of: "{width}", with: length(item.width))
            case .roomHeight: title = text("scanRoomHeight").replacingOccurrences(of: "{height}", with: length(item.height))
            }
            return UIAction(title: title.replacingOccurrences(of: "{room}", with: item.room)) { [weak self] _ in self?.apply(item) }
        })
    }

    private func apply(_ item: TransportScanSuggestion) {
        switch item.kind {
        case .door: set("passageWidth", item.width); set("passageHeight", item.height)
        case .roomHeight: set("passageHeight", item.height)
        case .stairs:
            // Whole flight as one consistent slope; the clear width between
            // handrails is usually smaller than the detected stair box.
            set("passageWidth", item.width)
            if item.length > 0.1 { set("rise", item.height); set("run", item.length) }
        }
    }

    private func set(_ key: String, _ value: Double) {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: MeasurementGuide.selectedLanguage)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 3
        formatter.usesGroupingSeparator = false
        fields[key]?.text = formatter.string(from: NSNumber(value: value))
    }

    private func value(_ key: String) -> Double? {
        guard let raw = fields[key]?.text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    // MARK: Result

    private func evaluate() {
        view.endEditing(true)
        result.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let keys = ["objectWidth", "objectDepth", "objectHeight", "passageWidth", "passageHeight", "landingWidth", "landingDepth", "turn", "rise", "run", "margin"]
        let values = keys.compactMap(value)
        guard values.count == keys.count else { showError(); return }
        let v = Dictionary(uniqueKeysWithValues: zip(keys, values))
        let assessment: TransportAssessment
        do {
            assessment = try TransportAssessment(
                object: .init(width: v["objectWidth"]!, depth: v["objectDepth"]!, height: v["objectHeight"]!),
                route: .init(width: v["passageWidth"]!, ceiling: v["passageHeight"]!, landingWidth: v["landingWidth"]!, landingDepth: v["landingDepth"]!,
                             rise: v["rise"]!, run: v["run"]!, turnDegrees: v["turn"]!),
                margin: v["margin"]!, allowTilt: tilt.isOn)
        } catch { showError(); return }
        lastAssessment = assessment
        let (titleKey, color, icon): (String, UIColor, String) = {
            switch assessment.verdict {
            case .possible: return ("verdictPossible", UIColor.systemGreen, "checkmark.circle.fill")
            case .uncertain: return ("verdictUncertain", UIColor.systemOrange, "questionmark.circle.fill")
            case .blocked: return ("verdictBlocked", UIColor.systemRed, "xmark.octagon.fill")
            }
        }()
        let symbol = UIImageView(image: UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)))
        symbol.tintColor = color
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        let heading = KanturaDesign.label(text(titleKey), style: .title2)
        let top = UIStackView(arrangedSubviews: [symbol, heading])
        top.spacing = 10
        top.alignment = .center
        var lines: [String] = []
        let envelope = assessment.chosen.envelope
        let m = { (x: Double) in KanturaDesign.metric(x, unit: "m", decimals: 2) }
        lines.append(text("needed").replacingOccurrences(of: "{width}", with: m(envelope.width)).replacingOccurrences(of: "{height}", with: m(envelope.height))
            .replacingOccurrences(of: "{lw}", with: m(envelope.width)).replacingOccurrences(of: "{ld}", with: m(envelope.depth)))
        let reasonKeys = ["tilted_envelope_fits": "reasonTilted", "corridor_clearance_insufficient": "reasonCorridor", "corridor_narrower_than_smallest_dimension": "reasonCorridor",
                          "ceiling_clearance_insufficient": "reasonCeiling", "ceiling_lower_than_smallest_dimension": "reasonCeiling", "landing_requires_path_planning": "reasonLanding"]
        for reason in assessment.reasons { if let key = reasonKeys[reason] { lines.append(text(key)) } }
        let body = KanturaDesign.label(lines.joined(separator: "\n"), style: .body, secondary: true)
        let stack = UIStackView(arrangedSubviews: [top, body])
        stack.axis = .vertical
        stack.spacing = 8
        let card = KanturaDesign.inset(stack, padding: 18)
        card.isAccessibilityElement = true
        card.accessibilityLabel = text(titleKey) + ". " + lines.joined(separator: ". ")
        result.addArrangedSubview(card)
        animation.isHidden = false
        buildAnimation(assessment, v: v, color: color)
        UIAccessibility.post(notification: .screenChanged, argument: card)
        DispatchQueue.main.async { self.scroll.scrollRectToVisible(card.convert(card.bounds, to: self.scroll).insetBy(dx: 0, dy: -20), animated: true) }
    }

    private func showError() {
        result.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = KanturaDesign.label(text("invalidInput"), style: .body)
        label.textColor = .systemRed
        result.addArrangedSubview(label)
        animation.isHidden = true
    }

    /// Landing floor, passage walls and ceiling as translucent outlines; the
    /// appliance box turns through the checked yaw/tilt samples on a loop.
    private func buildAnimation(_ assessment: TransportAssessment, v: [String: Double], color: UIColor) {
        let scene = SCNScene()
        let lw = Float(v["landingWidth"]!), ld = Float(v["landingDepth"]!), h = Float(v["passageHeight"]!), pw = Float(v["passageWidth"]!)
        func translucent(_ c: UIColor, _ alpha: CGFloat) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = c.withAlphaComponent(alpha); m.isDoubleSided = true; m.lightingModel = .constant; return m
        }
        let floor = SCNPlane(width: CGFloat(lw), height: CGFloat(ld))
        floor.materials = [translucent(KanturaDesign.mint, 0.45)]
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floorNode)
        // Passage leading onto the landing (width × clear height).
        let passage = SCNBox(width: CGFloat(pw), height: CGFloat(h), length: 1.5, chamferRadius: 0)
        passage.materials = [translucent(UIColor.systemBlue, 0.12)]
        let passageNode = SCNNode(geometry: passage)
        passageNode.position = SCNVector3(0, h / 2, ld / 2 + 0.75)
        scene.rootNode.addChildNode(passageNode)
        let ceiling = SCNPlane(width: CGFloat(lw), height: CGFloat(ld))
        ceiling.materials = [translucent(UIColor.gray, 0.15)]
        let ceilingNode = SCNNode(geometry: ceiling)
        ceilingNode.eulerAngles.x = .pi / 2
        ceilingNode.position.y = h
        scene.rootNode.addChildNode(ceilingNode)

        let chosen = assessment.chosen
        let ow = Float(chosen.sideways ? v["objectDepth"]! : v["objectWidth"]!), od = Float(chosen.sideways ? v["objectWidth"]! : v["objectDepth"]!), oh = Float(v["objectHeight"]!)
        let box = SCNBox(width: CGFloat(ow), height: CGFloat(oh), length: CGFloat(od), chamferRadius: 0.01)
        let material = SCNMaterial()
        material.diffuse.contents = color.withAlphaComponent(0.85)
        box.materials = [material]
        let pivot = SCNNode()
        let boxNode = SCNNode(geometry: box)
        boxNode.position.y = oh / 2
        pivot.addChildNode(boxNode)
        scene.rootNode.addChildNode(pivot)
        let turnSamples = chosen.samples.filter { $0.phase == "turn" }
        let steps = (turnSamples.isEmpty ? chosen.samples : turnSamples).map { sample in
            SCNAction.rotateTo(x: CGFloat(-sample.tilt * .pi / 180), y: CGFloat(sample.yaw * .pi / 180), z: 0, duration: 0.08, usesShortestUnitArc: false)
        }
        if !steps.isEmpty {
            pivot.runAction(.repeatForever(.sequence(steps + [.wait(duration: 0.8), .rotateTo(x: 0, y: 0, z: 0, duration: 0.4), .wait(duration: 0.5)])))
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        let span = max(lw, ld, h)
        camera.position = SCNVector3(span * 1.4, h * 1.3, span * 1.8)
        camera.look(at: SCNVector3(0, h / 3, 0))
        scene.rootNode.addChildNode(camera)
        animation.scene = scene
        animation.pointOfView = camera
    }
}
