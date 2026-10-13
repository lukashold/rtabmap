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
        column.addArrangedSubview(KanturaDesign.primaryButton(text("stairWalk"), icon: "figure.walk") { [weak self] in
            guard let self = self, let mesh = self.mesh else { return }
            self.navigationController?.pushViewController(StairWalkViewController(scan: self.scan, mesh: mesh, transport: self.transport), animated: true)
        })
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
            // Scans analysed with an older version are re-analysed from the stored walk.
            var updated: SavedStairScan?
            if let mesh = mesh, (scan.document.profile.analysis ?? 1) < StairAnalyzer.version {
                updated = try? scan.reanalyzed(mesh: mesh)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mesh = mesh
                if let updated = updated {
                    self.scan = updated
                    self.renderMetrics()
                }
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


/// Walk through the scanned stairs yourself: first person at eye height along
/// the centre line, with a slider (or play) to move and one finger to look around.
final class StairWalkViewController: UIViewController {
    private let scan: SavedStairScan
    private let mesh: StairMesh
    private let transport: StairTransport?
    private let sceneView = SCNView()
    private let eye = SCNNode()
    private let slider = UISlider()
    private let status = UILabel()
    private let play = UIButton(type: .system)
    private let carry = UIButton(type: .system)
    private var box: SCNNode?
    private var position = 0.0
    private var yaw = 0.0, pitch = -0.15
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var startLevel = 0.0
    private func text(_ key: String, _ values: [String: CustomStringConvertible] = [:]) -> String { MeasurementGuide.homeText(key, values) }

    init(scan: SavedStairScan, mesh: StairMesh, transport: StairTransport?) {
        self.scan = scan; self.mesh = mesh; self.transport = transport
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var stations: [StairProfile.Station] { scan.document.profile.stations }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = text("stairWalk")
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        let scene = SCNScene()
        if mesh.vertexCount > 0, !mesh.faces.isEmpty {
            let vertices = (0..<mesh.vertexCount).map { SCNVector3(mesh.positions[3 * $0], mesh.positions[3 * $0 + 1], mesh.positions[3 * $0 + 2]) }
            let normals = (0..<mesh.vertexCount).map { SCNVector3(mesh.normals[3 * $0], mesh.normals[3 * $0 + 1], mesh.normals[3 * $0 + 2]) }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                       elements: [SCNGeometryElement(indices: mesh.faces, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.86, alpha: 1)
            material.isDoubleSided = true
            material.lightingModel = .lambert
            geometry.materials = [material]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        }
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)
        eye.camera = SCNCamera()
        eye.camera?.zNear = 0.05
        eye.camera?.fieldOfView = 75
        let lamp = SCNNode(); lamp.light = SCNLight(); lamp.light?.type = .omni; lamp.light?.intensity = 900; lamp.light?.attenuationEndDistance = 6
        eye.addChildNode(lamp)
        scene.rootNode.addChildNode(eye)
        if let pose = transport?.poses.first {
            let node = SCNNode(geometry: SCNBox(width: CGFloat(pose.size.x), height: CGFloat(pose.size.z), length: CGFloat(pose.size.y), chamferRadius: 0.02))
            node.isHidden = true
            scene.rootNode.addChildNode(node)
            box = node
        }
        sceneView.scene = scene
        sceneView.pointOfView = eye
        sceneView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        sceneView.antialiasingMode = .multisampling4X
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityLabel = text("stairWalk")

        slider.minimumValue = 0
        slider.maximumValue = Float(max(0.1, scan.document.profile.length))
        slider.minimumTrackTintColor = KanturaDesign.mint
        slider.accessibilityLabel = text("stairLength")
        slider.addAction(UIAction { [weak self] _ in self?.stop(); self?.move(to: Double(self?.slider.value ?? 0)) }, for: .valueChanged)
        play.setImage(UIImage(systemName: "play.fill"), for: .normal)
        play.tintColor = .white
        play.accessibilityLabel = text("animate")
        play.addAction(UIAction { [weak self] _ in self?.togglePlay() }, for: .touchUpInside)
        carry.setImage(UIImage(systemName: "shippingbox"), for: .normal)
        carry.tintColor = KanturaDesign.mint
        carry.accessibilityLabel = text("stairWalkFridge")
        carry.isHidden = box == nil
        carry.addAction(UIAction { [weak self] _ in
            guard let self = self, let box = self.box else { return }
            box.isHidden.toggle()
            self.carry.tintColor = box.isHidden ? KanturaDesign.mint : .systemOrange
            self.update()
        }, for: .touchUpInside)
        status.textColor = .white
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textAlignment = .center
        let hint = UILabel()
        hint.text = text("stairWalkHint")
        hint.textColor = UIColor(white: 1, alpha: 0.7)
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        let controls = UIStackView(arrangedSubviews: [play, slider, carry])
        controls.spacing = 12
        controls.alignment = .center
        play.widthAnchor.constraint(equalToConstant: 44).isActive = true
        carry.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let panel = UIStackView(arrangedSubviews: [status, controls, hint])
        panel.axis = .vertical
        panel.spacing = 8
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 20
        blur.clipsToBounds = true
        for v in [sceneView, blur, panel] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor), sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor), sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 28), panel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -28),
            panel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -24),
            blur.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: -12), blur.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: 12),
            blur.topAnchor.constraint(equalTo: panel.topAnchor, constant: -12), blur.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: 12)
        ])
        let look = UIPanGestureRecognizer(target: self, action: #selector(lookAround(_:)))
        look.maximumNumberOfTouches = 1
        sceneView.addGestureRecognizer(look)
        let floors = stations.filter { $0.distance <= 0.5 }.map(\.floor).sorted()
        startLevel = floors.isEmpty ? (stations.first?.floor ?? 0) : floors[floors.count / 2]
        move(to: 0)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    /// Station values interpolated at a distance along the centre line.
    private func sample(_ d: Double) -> (x: Double, z: Double, floor: Double, heading: Double, station: StairProfile.Station)? {
        guard let first = stations.first else { return nil }
        guard let j = stations.firstIndex(where: { $0.distance >= d }), j > 0 else {
            let s = d <= 0 ? first : stations.last!
            return (s.x, s.z, s.floor, s.heading, s)
        }
        let a = stations[j - 1], b = stations[j], t = (d - a.distance) / max(1e-6, b.distance - a.distance)
        // Floor: the higher of the two neighbours, so the eye does not dip at a riser.
        let floor = a.floor + (b.floor - a.floor) * t
        // Looking direction: chord to a point 60 cm ahead (smooths phone swings).
        let ahead = stations.first(where: { $0.distance >= d + 0.6 }) ?? stations.last!
        let heading = hypot(ahead.x - a.x, ahead.z - a.z) > 0.1 ? atan2(ahead.x - (a.x + (b.x - a.x) * t), -(ahead.z - (a.z + (b.z - a.z) * t))) : a.heading
        return (a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, floor, heading, t < 0.5 ? a : b)
    }

    private func move(to d: Double) {
        position = min(max(0, d), scan.document.profile.length)
        update()
    }

    private func update() {
        guard let s = sample(position) else { return }
        eye.position = SCNVector3(Float(s.x), Float(s.floor + 1.6), Float(s.z))
        // SceneKit cameras look along −z; heading is measured from −z towards +x.
        eye.eulerAngles = SCNVector3(Float(pitch), Float(-(s.heading + yaw)), 0)
        slider.value = Float(position)
        let profile = scan.document.profile
        var parts: [String] = []
        if profile.risers > 0, let riser = profile.riser, riser > 0 {
            let step = min(profile.risers, max(0, Int((abs(startLevel - s.floor) / riser).rounded())))
            parts.append(text("stairWalkStep", ["step": step, "steps": profile.risers]))
        }
        if let w = s.station.smoothedWidth ?? s.station.width { parts.append(text("stairWidth") + " " + KanturaDesign.metric(w, unit: "m", decimals: 2)) }
        if let h = s.station.headroom { parts.append(text("stairHeadroom") + " " + KanturaDesign.metric(h, unit: "m", decimals: 2)) }
        status.text = parts.joined(separator: " · ")
        if let box = box, !box.isHidden, let poses = transport?.poses,
           let pose = poses.min(by: { abs($0.distance - (position + 0.9)) < abs($1.distance - (position + 0.9)) }) {
            // The appliance goes ahead of you, as when carrying it down.
            let geometry = SCNBox(width: CGFloat(pose.size.x), height: CGFloat(pose.size.z), length: CGFloat(pose.size.y), chamferRadius: 0.02)
            let material = SCNMaterial()
            material.diffuse.contents = (pose.clearance >= 0.02 ? UIColor.systemGreen : pose.clearance >= -StairTransport.tolerance ? UIColor.systemOrange : UIColor.systemRed).withAlphaComponent(0.6)
            material.isDoubleSided = true
            geometry.materials = [material]
            box.geometry = geometry
            var m = SCNMatrix4Identity
            m.m11 = Float(pose.along.x); m.m12 = Float(pose.along.y); m.m13 = Float(pose.along.z)
            m.m21 = Float(pose.up.x); m.m22 = Float(pose.up.y); m.m23 = Float(pose.up.z)
            let lateral = pose.along.cross(pose.up)
            m.m31 = Float(lateral.x); m.m32 = Float(lateral.y); m.m33 = Float(lateral.z)
            m.m41 = Float(pose.centre.x); m.m42 = Float(pose.centre.y); m.m43 = Float(pose.centre.z)
            box.transform = m
        }
    }

    @objc private func lookAround(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: sceneView)
        gesture.setTranslation(.zero, in: sceneView)
        yaw -= Double(t.x) * 0.005
        pitch = min(1.2, max(-1.2, pitch - Double(t.y) * 0.005))
        update()
    }

    private func togglePlay() { link == nil ? start() : stop() }

    private func start() {
        if position >= scan.document.profile.length - 0.05 { position = 0 }
        yaw = 0
        lastTick = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        play.setImage(UIImage(systemName: "pause.fill"), for: .normal)
    }

    private func stop() {
        link?.invalidate()
        link = nil
        play.setImage(UIImage(systemName: "play.fill"), for: .normal)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        // Walking pace on stairs: about 0.45 m/s along the line.
        move(to: position + 0.45 * dt)
        if position >= scan.document.profile.length { stop() }
    }
}
