import SceneKit
import UIKit

/// A saved stair scan: 3D view of the scanned stairwell with the walked
/// centre line, the key numbers, and the appliance check along the real path
/// with an animation of the box going down.
final class StairResultViewController: UIViewController, UITextFieldDelegate {
    var onClose: (() -> Void)?
    private var scan: SavedStairScan
    private var mesh: StairMesh?
    private let sceneView = SCNView()
    private let world = SCNNode()
    private var column: UIStackView!
    private var metrics: UIView?
    private var fields: [String: UITextField] = [:]
    private let result = UIStackView()
    private var boxNode: SCNNode?
    private var worstNode: SCNNode?
    private var transport: StairTransport?
    private var checking = false
    private func text(_ key: String, _ values: [String: CustomStringConvertible] = [:]) -> String { MeasurementGuide.homeText(key, values) }
    private func length(_ v: Double?, _ decimals: Int = 2) -> String { KanturaDesign.metric(v, unit: "m", decimals: decimals) }

    init(scan: SavedStairScan) {
        self.scan = scan
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = scan.displayName
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("done"), style: .done, target: self, action: #selector(close))
        }
        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareScan))
        share.accessibilityLabel = text("export")
        let rename = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain, target: self, action: #selector(renameScan))
        rename.accessibilityLabel = text("rename")
        navigationItem.rightBarButtonItems = [share, rename]

        column = KanturaDesign.scrollColumn(in: self, spacing: 14).column
        sceneView.backgroundColor = KanturaDesign.surface
        sceneView.layer.cornerRadius = 20
        sceneView.layer.cornerCurve = .continuous
        sceneView.clipsToBounds = true
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityLabel = text("stairTitle")
        sceneView.heightAnchor.constraint(equalTo: sceneView.widthAnchor, multiplier: 0.95).isActive = true
        column.addArrangedSubview(sceneView)
        column.addArrangedSubview(KanturaDesign.label(text("stairViewHint"), style: .footnote, secondary: true))
        renderMetrics()
        buildCheck()
        loadScene()
    }

    @objc private func close() { dismiss(animated: true) { [onClose] in onClose?() } }

    // MARK: Numbers

    private func renderMetrics() {
        let p = scan.document.profile
        var items: [(title: String, value: String)] = [
            (text("stairDrop"), length(p.drop)),
            (text("stairSteps"), p.risers > 0 ? "\(p.risers) × " + length(p.riser, 2) : text("notDetected")),
            (text("stairWidth"), length(p.minWidth)),
            (text("stairHeadroom"), length(p.minHeadroom)),
            (text("stairGoing"), length(p.going)),
            (text("stairTurn"), abs(p.turnDegrees) < 15 ? text("stairStraight") : "\(Int((abs(p.turnDegrees) / 5).rounded() * 5))°")
        ]
        if let slope = p.slopeDegrees { items.append((text("stairSlope"), "\(Int(slope.rounded()))°")) }
        items.append((text("stairLength"), length(p.length, 1)))
        let grid = KanturaMetricGrid(items)
        if let old = metrics, let index = column.arrangedSubviews.firstIndex(of: old) {
            old.removeFromSuperview()
            column.insertArrangedSubview(grid, at: index)
        } else {
            column.addArrangedSubview(grid)
        }
        metrics = grid
        if p.minWidth == nil || p.minHeadroom == nil {
            column.addArrangedSubview(KanturaDesign.label(text("stairPartial"), style: .footnote, secondary: true))
        }
    }

    // MARK: Appliance check

    private func buildCheck() {
        let heading = KanturaDesign.label(text("stairCheckTitle"), style: .title3)
        heading.accessibilityTraits.insert(.header)
        column.addArrangedSubview(heading)
        let catalog = KanturaDesign.secondaryButton(text("deviceCatalog"), icon: "list.bullet") {}
        catalog.menu = UIMenu(children: TransportAppliance.catalog.map { item in
            UIAction(title: "\(item.brand) \(item.model)") { [weak self] _ in
                self?.set("w", item.width); self?.set("d", item.depth); self?.set("h", item.height)
            }
        })
        catalog.showsMenuAsPrimaryAction = true
        column.addArrangedSubview(catalog)
        let row = UIStackView()
        row.spacing = 10
        row.distribution = .fillEqually
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { row.axis = .vertical }
        for (key, title, value) in [("w", text("width"), 0.60), ("d", text("depth"), 0.66), ("h", text("heightField"), 2.03)] {
            let caption = KanturaDesign.label(title, style: .footnote, secondary: true)
            let field = UITextField()
            field.keyboardType = .decimalPad
            field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium))
            field.adjustsFontForContentSizeCategory = true
            field.backgroundColor = KanturaDesign.surface
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1
            field.layer.borderColor = KanturaDesign.border.cgColor
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 44))
            field.leftViewMode = .always
            let unit = UILabel()
            unit.text = "m  "
            unit.textColor = KanturaDesign.muted
            field.rightView = unit
            field.rightViewMode = .always
            field.accessibilityLabel = title
            field.delegate = self
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
            fields[key] = field
            set(key, value)
            let cell = UIStackView(arrangedSubviews: [caption, field])
            cell.axis = .vertical
            cell.spacing = 4
            row.addArrangedSubview(cell)
        }
        column.addArrangedSubview(row)
        column.addArrangedSubview(KanturaDesign.primaryButton(text("check"), icon: "checkmark.shield") { [weak self] in self?.runCheck() })
        result.axis = .vertical
        result.spacing = 10
        column.addArrangedSubview(result)
        column.addArrangedSubview(KanturaDesign.label(text("stairLimits"), style: .footnote, secondary: true))
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
        guard let raw = fields[key]?.text?.trimmingCharacters(in: .whitespaces), let v = Double(raw.replacingOccurrences(of: ",", with: ".")),
              v.isFinite, v > 0.05, v < 5 else { return nil }
        return v
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    private func runCheck() {
        view.endEditing(true)
        guard !checking else { return }
        guard let w = value("w"), let d = value("d"), let h = value("h") else {
            let alert = UIAlertController(title: text("invalidInput"), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
            present(alert, animated: true)
            return
        }
        guard let mesh = mesh else { return }
        checking = true
        result.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        result.addArrangedSubview(spinner)
        let profile = scan.document.profile
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let check = StairTransport(profile: profile, mesh: mesh, object: .init(width: w, depth: d, height: h))
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checking = false
                self.transport = check
                self.showResult(check)
            }
        }
    }

    private func showResult(_ check: StairTransport?) {
        result.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let check = check else { return }
        let title: String, color: UIColor, icon: String
        switch check.verdict {
        case .possible: title = text("verdictPossible"); color = .systemGreen; icon = "checkmark.circle.fill"
        case .tight: title = text("stairTight"); color = .systemOrange; icon = "exclamationmark.triangle.fill"
        case .blocked: title = text("verdictBlocked"); color = .systemRed; icon = "xmark.octagon.fill"
        }
        let symbol = UIImageView(image: UIImage(systemName: icon))
        symbol.tintColor = color
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        let headline = KanturaDesign.label(title, style: .headline)
        let line = UIStackView(arrangedSubviews: [symbol, headline])
        line.spacing = 10
        line.alignment = .center
        var lines: [String] = []
        lines.append(text("stairHow") + " " + check.handlings.map { text("handling_" + $0.rawValue) }.joined(separator: " → "))
        let w = check.worst
        let cm = Int((abs(w.clearance) * 100).rounded())
        let reason = w.limit == .top ? "stairLimitTop" : "stairLimitSide"
        lines.append(text(w.clearance >= 0 ? "stairNarrowest" : "stairCollision",
                          ["distance": length(w.distance, 1), "cm": cm, "where": text(reason)]))
        let body = KanturaDesign.label(lines.joined(separator: "\n"), style: .subheadline, secondary: true)
        let card = UIStackView(arrangedSubviews: [line, body])
        card.axis = .vertical
        card.spacing = 8
        result.addArrangedSubview(KanturaDesign.inset(card, padding: 16))
        result.addArrangedSubview(KanturaDesign.secondaryButton(text("animate"), icon: "play.fill") { [weak self] in self?.animate() })
        markWorst(w)
        animate()
    }

    // MARK: 3D

    private func loadScene() {
        let scan = self.scan
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mesh = try? scan.loadMesh()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mesh = mesh
                self.buildScene(mesh)
            }
        }
    }

    private func buildScene(_ mesh: StairMesh?) {
        let scene = SCNScene()
        scene.rootNode.addChildNode(world)
        let profile = scan.document.profile
        if let mesh = mesh, mesh.vertexCount > 0, !mesh.faces.isEmpty {
            let vertices = (0..<mesh.vertexCount).map { SCNVector3(mesh.positions[3 * $0], mesh.positions[3 * $0 + 1], mesh.positions[3 * $0 + 2]) }
            let normals = (0..<mesh.vertexCount).map { SCNVector3(mesh.normals[3 * $0], mesh.normals[3 * $0 + 1], mesh.normals[3 * $0 + 2]) }
            let element = SCNGeometryElement(indices: mesh.faces, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.82, alpha: 1)
            material.isDoubleSided = true
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.9
            geometry.materials = [material]
            world.addChildNode(SCNNode(geometry: geometry))
        }
        // Centre line with floor height.
        let line = profile.stations.map { SCNVector3(Float($0.x), Float($0.floor + 0.03), Float($0.z)) }
        if line.count > 1 {
            var indices: [UInt32] = []
            for i in 0..<(line.count - 1) { indices += [UInt32(i), UInt32(i + 1)] }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: line)], elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
            let material = SCNMaterial()
            material.diffuse.contents = KanturaDesign.mint
            material.lightingModel = .constant
            geometry.materials = [material]
            world.addChildNode(SCNNode(geometry: geometry))
        }
        // Narrowest width and lowest headroom.
        for (distance, color) in [(profile.minWidthAt, UIColor.systemOrange), (profile.minHeadroomAt, UIColor.systemPurple)] {
            guard let d = distance, let s = profile.stations.min(by: { abs($0.distance - d) < abs($1.distance - d) }) else { continue }
            let sphere = SCNNode(geometry: SCNSphere(radius: 0.05))
            sphere.geometry?.firstMaterial?.diffuse.contents = color
            sphere.geometry?.firstMaterial?.lightingModel = .constant
            sphere.position = SCNVector3(Float(s.x), Float(s.floor + 1.0), Float(s.z))
            world.addChildNode(sphere)
        }
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .ambient
        light.light?.intensity = 500
        scene.rootNode.addChildNode(light)
        // Camera outside the stairwell, looking at its middle.
        let (minB, maxB) = world.boundingBox
        let centre = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        let size = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z, 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.02
        camera.position = SCNVector3(centre.x + size * 0.9, centre.y + size * 0.7, centre.z + size * 0.9)
        camera.look(at: centre)
        scene.rootNode.addChildNode(camera)
        sceneView.scene = scene
        sceneView.pointOfView = camera
        sceneView.defaultCameraController.target = centre
    }

    private func markWorst(_ pose: StairTransport.Pose) {
        worstNode?.removeFromParentNode()
        let ring = SCNNode(geometry: SCNSphere(radius: 0.07))
        ring.geometry?.firstMaterial?.diffuse.contents = pose.clearance >= 0 ? UIColor.systemOrange : UIColor.systemRed
        ring.geometry?.firstMaterial?.lightingModel = .constant
        ring.position = SCNVector3(Float(pose.centre.x), Float(pose.centre.y + pose.size.z / 2 + 0.1), Float(pose.centre.z))
        ring.runAction(.repeatForever(.sequence([.scale(to: 1.4, duration: 0.5), .scale(to: 1, duration: 0.5)])))
        world.addChildNode(ring)
        worstNode = ring
    }

    private func animate() {
        guard let check = transport, !check.poses.isEmpty else { return }
        boxNode?.removeFromParentNode()
        let first = check.poses[0]
        let box = SCNNode(geometry: SCNBox(width: CGFloat(first.size.x), height: CGFloat(first.size.z), length: CGFloat(first.size.y), chamferRadius: 0.02))
        world.addChildNode(box)
        boxNode = box
        var actions: [SCNAction] = []
        for pose in check.poses {
            let geometry = SCNBox(width: CGFloat(pose.size.x), height: CGFloat(pose.size.z), length: CGFloat(pose.size.y), chamferRadius: 0.02)
            let material = SCNMaterial()
            material.diffuse.contents = (pose.clearance >= 0.02 ? UIColor.systemGreen : pose.clearance >= -StairTransport.tolerance ? UIColor.systemOrange : UIColor.systemRed).withAlphaComponent(0.75)
            material.isDoubleSided = true
            geometry.materials = [material]
            let transform = Self.transform(pose)
            actions.append(.run { node in
                node.geometry = geometry
                node.transform = transform
            })
            actions.append(.wait(duration: 0.06))
        }
        box.runAction(.sequence(actions + [.wait(duration: 1.2)])) { [weak box] in
            DispatchQueue.main.async { box?.opacity = 0.35 }
        }
    }

    /// SceneKit transform of a box pose (box local x = along, y = up, z = lateral).
    private static func transform(_ p: StairTransport.Pose) -> SCNMatrix4 {
        var m = SCNMatrix4Identity
        m.m11 = Float(p.along.x); m.m12 = Float(p.along.y); m.m13 = Float(p.along.z)
        m.m21 = Float(p.up.x); m.m22 = Float(p.up.y); m.m23 = Float(p.up.z)
        let lateral = p.along.cross(p.up)
        m.m31 = Float(lateral.x); m.m32 = Float(lateral.y); m.m33 = Float(lateral.z)
        m.m41 = Float(p.centre.x); m.m42 = Float(p.centre.y); m.m43 = Float(p.centre.z)
        return m
    }

    // MARK: Actions

    @objc private func renameScan() {
        let alert = UIAlertController(title: text("renameTitle"), message: nil, preferredStyle: .alert)
        let b = scan.document.building
        let values = [scan.displayName, b.map { $0.name == LibraryLabels.placeholder ? "" : $0.name } ?? "", b.map { $0.floor == LibraryLabels.placeholder ? "" : $0.floor } ?? ""]
        for (index, placeholder) in [text("itemName"), text("apartment"), text("floorLabel")].enumerated() {
            alert.addTextField { $0.placeholder = placeholder; $0.text = values[index]; $0.accessibilityLabel = placeholder }
        }
        alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: text("done"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let fields = alert?.textFields, fields.count == 3 else { return }
            let name = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let updated = try? self.scan.relabeled(name: name.isEmpty ? self.scan.displayName : name, apartment: fields[1].text ?? "", floor: fields[2].text ?? "") {
                self.scan = updated
                self.title = updated.displayName
            }
        })
        present(alert, animated: true)
    }

    @objc private func shareScan() {
        guard let mesh = mesh else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KanturaStairExport-" + UUID().uuidString, isDirectory: true)
        let stem = SavedRoomPlan.exportStem(name: scan.displayName, identifier: UUID(uuidString: scan.document.id) ?? UUID())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let json = folder.appendingPathComponent(stem + ".kantura-stairs.json")
            let obj = folder.appendingPathComponent(stem + ".obj")
            try scan.document.encoded().write(to: json)
            try mesh.obj().write(to: obj, atomically: true, encoding: .utf8)
            let sheet = UIActivityViewController(activityItems: [json, obj], applicationActivities: nil)
            sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(sheet, animated: true)
        } catch {
            let alert = UIAlertController(title: text("uploadFailed"), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
            present(alert, animated: true)
        }
    }
}
