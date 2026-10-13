import UIKit
import SceneKit
import ImageIO

/// A saved room in three readable views:
/// - Floor plan: top-down, dark walls, dimension lines outside every wall,
///   doors/windows marked, area in the room.
/// - 3D: dollhouse without ceiling, walls with thickness and lighting, real
///   cut-outs for doors and windows, wall lengths and room height.
/// - Inside: stand in the middle of the room at eye height (drag to look,
///   pinch to zoom); walls show the scan photos when there are any.
///
/// Photos are projected onto RoomPlan's flat surfaces: furniture in front of a
/// wall appears painted onto that wall, and areas no photo saw stay plain.
final class RoomWalkthroughViewController: UIViewController, UIGestureRecognizerDelegate {
    private enum Mode: Int { case plan, model, inside }

    private var room: SavedRoomPlan
    private let photoDirectory: URL
    private let photos: RoomPhotoSet?
    private var summary: RoomPlanSummary
    private let scene = SCNScene()
    private let sceneView = SCNView()
    private let planCamera = SCNNode(), modelCamera = SCNNode(), eyeCamera = SCNNode()
    // Content groups switched per mode.
    private let solid = SCNNode(), photoTiles = SCNNode(), plainCeiling = SCNNode()
    private let planMarks = SCNNode(), modelLabels = SCNNode(), insideLabels = SCNNode()
    /// Everything that turns with the two-finger rotation, pivoting on the room centre.
    private let world = SCNNode()
    private var startRotation: Float = 0
    private var startPan = SCNVector3Zero
    private var wallMaterial = SCNMaterial()
    private let mode = UISegmentedControl()
    private let measures = UIButton(type: .system)
    private let status = KanturaHintPill("")
    private var yaw: Float = 0, pitch: Float = 0, startYaw: Float = 0, startPitch: Float = 0
    private var lookGestures: [UIGestureRecognizer] = []
    private var planGestures: [UIGestureRecognizer] = []
    private var hintShown = false
    private var centre = (x: 0.0, z: 0.0), floorY = 0.0, extent = 5.0
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    init(room: SavedRoomPlan) {
        self.room = room
        photoDirectory = room.jsonURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)
        photos = RoomPhotoSet.load(from: photoDirectory)
        summary = RoomPlanSummary(room.document)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func hasPhotos(_ room: SavedRoomPlan) -> Bool {
        RoomPhotoSet.load(from: room.jsonURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)) != nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KanturaDesign.background
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = room.document.building?.room ?? room.document.name
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.1, alpha: 1) : UIColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1) }
        sceneView.antialiasingMode = .multisampling4X
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityLabel = text("walkTitle")
        view.addSubview(sceneView)

        for (index, key) in ["walkPlan", "walkOutside", "walkInside"].enumerated() { mode.insertSegment(withTitle: text(key), at: index, animated: false) }
        mode.selectedSegmentIndex = Mode.model.rawValue
        mode.selectedSegmentTintColor = KanturaDesign.mint
        mode.setTitleTextAttributes([.foregroundColor: KanturaDesign.ink], for: .selected)
        mode.addAction(UIAction { [weak self] _ in self?.applyMode() }, for: .valueChanged)
        measures.setImage(UIImage(systemName: "ruler"), for: .normal)
        measures.setTitle("  " + text("walkMeasures"), for: .normal)
        measures.tintColor = KanturaDesign.ink
        measures.backgroundColor = KanturaDesign.mint
        measures.layer.cornerRadius = 16
        measures.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        measures.accessibilityTraits.insert(.selected)
        measures.addAction(UIAction { [weak self] _ in self?.toggleMeasures() }, for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [mode, measures])
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor), sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            status.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(look(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))
        sceneView.addGestureRecognizer(pan)
        sceneView.addGestureRecognizer(pinch)
        lookGestures = [pan, pinch]
        // Two fingers turn the room (plan, 3D and inside); one tap corrects a surface.
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(turn(_:)))
        rotate.delegate = self
        sceneView.addGestureRecognizer(rotate)
        let tap = UITapGestureRecognizer(target: self, action: #selector(pickSurface(_:)))
        sceneView.addGestureRecognizer(tap)
        let planPan = UIPanGestureRecognizer(target: self, action: #selector(movePlan(_:)))
        planPan.maximumNumberOfTouches = 1
        let planPinch = UIPinchGestureRecognizer(target: self, action: #selector(zoomPlan(_:)))
        planPinch.delegate = self
        sceneView.addGestureRecognizer(planPan)
        sceneView.addGestureRecognizer(planPinch)
        planGestures = [planPan, planPinch]
        let export = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(openExport))
        export.accessibilityLabel = text("export")
        navigationItem.rightBarButtonItem = export
        status.isHidden = true

        buildContent()
        buildCameras()
        scene.rootNode.addChildNode(world)
        [solid, plainCeiling, photoTiles, planMarks, modelLabels, insideLabels].forEach { world.addChildNode($0) }
        alignToLongestWall()
        addLights()
        applyMode()
        buildPhotoTiles()
    }

    private func buildContent() {
        [solid, plainCeiling, planMarks, modelLabels, insideLabels].forEach { group in group.childNodes.forEach { $0.removeFromParentNode() } }
        buildSolid()
        buildPlanMarks()
        buildModelLabels()
        world.pivot = SCNMatrix4MakeTranslation(Float(centre.x), 0, Float(centre.z))
        world.position = SCNVector3(Float(centre.x), 0, Float(centre.z))
    }

    /// Start with the longest wall horizontal, like a drawn floor plan.
    private func alignToLongestWall() {
        guard let wall = walls.max(by: { $0.dimensions[0] < $1.dimensions[0] }) else { return }
        let x = (wall.transform[0], wall.transform[2])
        world.eulerAngles.y = Float(atan2(x.1, x.0))
        orientPlanLabels()
    }

    /// Keep the lengths along the walls readable (never upside down) after turning.
    private func orientPlanLabels() {
        for holder in planMarks.childNodes where holder.name == "length" {
            let total = holder.eulerAngles.y + world.eulerAngles.y
            if cos(total) < 0 { holder.eulerAngles.y += .pi }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func turn(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { startRotation = world.eulerAngles.y }
        // Screen-clockwise fingers turn the room clockwise as seen from above.
        world.eulerAngles.y = startRotation - Float(gesture.rotation)
        if gesture.state == .ended || gesture.state == .changed { orientPlanLabels() }
    }

    @objc private func movePlan(_ gesture: UIPanGestureRecognizer) {
        guard let camera = planCamera.camera else { return }
        if gesture.state == .began { startPan = planCamera.position }
        let t = gesture.translation(in: sceneView)
        let metresPerPoint = Float(camera.orthographicScale * 2) / Float(max(1, sceneView.bounds.height))
        planCamera.position = SCNVector3(startPan.x - Float(t.x) * metresPerPoint, startPan.y, startPan.z - Float(t.y) * metresPerPoint)
    }

    @objc private func zoomPlan(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = planCamera.camera else { return }
        camera.orthographicScale = max(0.8, min(60, camera.orthographicScale / Double(gesture.scale)))
        gesture.scale = 1
    }

    @objc private func openExport() {
        navigationController?.pushViewController(RoomShareViewController(room: room), animated: true)
    }

    // MARK: Corrections

    @objc private func pickSurface(_ gesture: UITapGestureRecognizer) {
        guard presentedViewController == nil, Mode(rawValue: mode.selectedSegmentIndex) != .inside else { return }
        let hits = sceneView.hitTest(gesture.location(in: sceneView), options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        guard let name = hits.lazy.compactMap({ hit -> String? in
            var node: SCNNode? = hit.node
            while let current = node { if let n = current.name, n.hasPrefix("surface:") { return n } ; node = current.parent }
            return nil
        }).first else { return }
        let id = String(name.dropFirst("surface:".count))
        guard let surface = room.original.surfaces.first(where: { $0.id == id }) else { return }
        let current = room.original.corrections?[id] ?? surface.kind
        let sheet = UIAlertController(title: text("editTitle"), message: MeasurementGuide.roomText(surface.kind) + " · " + length(surface.dimensions[0]) + " × " + length(surface.dimensions[1]), preferredStyle: .actionSheet)
        let options: [(String, String)] = surface.kind == "wall" ? [] : [("wall", "asWall"), ("door", "asDoor"), ("window", "asWindow"), ("opening", "asOpening")]
        for (kind, key) in options where kind != current {
            sheet.addAction(UIAlertAction(title: text(key), style: .default) { [weak self] _ in self?.correct(id, kind) })
        }
        if current != "deleted" { sheet.addAction(UIAlertAction(title: text("removeSurface"), style: .destructive) { [weak self] _ in self?.correct(id, "deleted") }) }
        if room.original.corrections?[id] != nil { sheet.addAction(UIAlertAction(title: text("resetEdit"), style: .default) { [weak self] _ in self?.correct(id, nil) }) }
        sheet.addAction(UIAlertAction(title: text("cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = sceneView
        sheet.popoverPresentationController?.sourceRect = CGRect(origin: gesture.location(in: sceneView), size: CGSize(width: 1, height: 1))
        present(sheet, animated: true)
    }

    private func correct(_ id: String, _ kind: String?) {
        do {
            room = try room.correcting(id, to: kind)
            summary = RoomPlanSummary(room.document)
            let rotation = world.eulerAngles.y
            buildContent()
            world.eulerAngles.y = rotation
            orientPlanLabels()
            applyMode()
            NotificationCenter.default.post(name: SavedRoomViewController.changed, object: room)
            UIAccessibility.post(notification: .announcement, argument: text("edited"))
        } catch {
            let alert = UIAlertController(title: MeasurementGuide.roomText("exportFailed"), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: MeasurementGuide.roomText("close"), style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: Geometry helpers

    private func matrix(_ m: [Double]) -> SCNMatrix4 {
        SCNMatrix4(m11: Float(m[0]), m12: Float(m[1]), m13: Float(m[2]), m14: Float(m[3]),
                   m21: Float(m[4]), m22: Float(m[5]), m23: Float(m[6]), m24: Float(m[7]),
                   m31: Float(m[8]), m32: Float(m[9]), m33: Float(m[10]), m34: Float(m[11]),
                   m41: Float(m[12]), m42: Float(m[13]), m43: Float(m[14]), m44: Float(m[15]))
    }
    private func vector(_ p: RoomPlanGeometry.Point) -> SCNVector3 { SCNVector3(Float(p.x), Float(p.y), Float(p.z)) }
    private func path(_ outline: [(Double, Double)]) -> UIBezierPath {
        let path = UIBezierPath()
        for (i, p) in outline.enumerated() { i == 0 ? path.move(to: CGPoint(x: p.0, y: p.1)) : path.addLine(to: CGPoint(x: p.0, y: p.1)) }
        path.close()
        return path
    }
    private func material(_ color: UIColor, lit: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = lit ? .blinn : .constant
        m.isDoubleSided = true
        return m
    }
    private var walls: [RoomPlanDocument.Surface] { room.document.surfaces.filter { $0.kind == "wall" && $0.transform.count == 16 && $0.dimensions.count == 3 } }
    private var floors: [RoomPlanDocument.Surface] { room.document.surfaces.filter { $0.kind == "floor" && $0.polygonCorners != nil && $0.transform.count == 16 } }
    private var height: Double { summary.wallHeight ?? 2.5 }
    /// Horizontal unit vector from a point towards the room centre.
    private func inward(from p: RoomPlanGeometry.Point) -> (x: Double, z: Double) {
        let dx = centre.x - p.x, dz = centre.z - p.z, d = max(1e-6, hypot(dx, dz))
        return (dx / d, dz / d)
    }

    // MARK: Solid model (walls with cut-outs, floor, windows)

    private func buildSolid() {
        // Room centre, floor level and size for cameras and label placement.
        let floorPoints = floors.flatMap { f in f.polygonCorners!.map { RoomPlanGeometry.world($0, f.transform) } }
        let wallPoints = walls.map { RoomPlanGeometry.world([0, 0, 0], $0.transform) }
        let points = floorPoints.isEmpty ? wallPoints : floorPoints
        if !points.isEmpty {
            centre = (points.map { $0.x }.reduce(0, +) / Double(points.count), points.map { $0.z }.reduce(0, +) / Double(points.count))
            let xs = points.map { $0.x }, zs = points.map { $0.z }
            extent = max(2, xs.max()! - xs.min()!, zs.max()! - zs.min()!)
        }
        floorY = floorPoints.isEmpty ? (walls.map { RoomPlanGeometry.world([0, -$0.dimensions[1] / 2, 0], $0.transform).y }.min() ?? 0) : floorPoints.map { $0.y }.reduce(0, +) / Double(floorPoints.count)

        wallMaterial = material(UIColor(white: 0.96, alpha: 1))
        let openings = RoomPlanGeometry.openingsByWall(room.document.surfaces)
        for wall in walls {
            let shape = path(RoomPlanGeometry.outline(wall))
            for o in openings[wall.id] ?? [] {
                // Doors and openings reach the floor; cut them as holes in the wall.
                shape.append(UIBezierPath(rect: CGRect(x: o.x0, y: o.y0, width: o.x1 - o.x0, height: o.y1 - o.y0)))
            }
            shape.usesEvenOddFillRule = true
            shape.flatness = 0.001
            let geometry = SCNShape(path: shape, extrusionDepth: 0.1)
            geometry.materials = [wallMaterial]
            let node = SCNNode(geometry: geometry)
            node.name = "surface:" + wall.id
            node.transform = matrix(wall.transform)
            for o in openings[wall.id] ?? [] where o.kind != "window" {
                // A faint tappable pane, so doors and openings can be corrected.
                let pane = SCNNode(geometry: SCNPlane(width: CGFloat(o.x1 - o.x0), height: CGFloat(o.y1 - o.y0)))
                pane.geometry?.materials = [material(KanturaDesign.mint.withAlphaComponent(0.18))]
                pane.position = SCNVector3(Float((o.x0 + o.x1) / 2), Float((o.y0 + o.y1) / 2), 0)
                pane.name = "surface:" + o.id
                node.addChildNode(pane)
            }
            for o in openings[wall.id] ?? [] where o.kind == "window" {
                let glass = SCNPlane(width: CGFloat(o.x1 - o.x0), height: CGFloat(o.y1 - o.y0))
                glass.materials = [material(UIColor.systemTeal.withAlphaComponent(0.35))]
                let pane = SCNNode(geometry: glass)
                pane.name = "surface:" + o.id
                pane.position = SCNVector3(Float((o.x0 + o.x1) / 2), Float((o.y0 + o.y1) / 2), 0)
                node.addChildNode(pane)
            }
            solid.addChildNode(node)
        }
        // Openings not inside any wall are shown on their own (and can be corrected).
        let hosted = Set(openings.values.flatMap { $0.map(\.id) })
        for s in room.document.surfaces where ["door", "window", "opening"].contains(s.kind) && !hosted.contains(s.id) && s.transform.count == 16 && s.dimensions.count == 3 {
            let box = SCNBox(width: CGFloat(s.dimensions[0]), height: CGFloat(s.dimensions[1]), length: 0.04, chamferRadius: 0)
            box.materials = [material((s.kind == "window" ? UIColor.systemTeal : KanturaDesign.mint).withAlphaComponent(0.45))]
            let node = SCNNode(geometry: box)
            node.transform = matrix(s.transform)
            node.name = "surface:" + s.id
            solid.addChildNode(node)
        }
        let floorMaterial = material(UIColor(red: 0.86, green: 0.78, blue: 0.66, alpha: 1))
        for floor in floors {
            let geometry = SCNShape(path: path(RoomPlanGeometry.outline(floor)), extrusionDepth: 0.02)
            geometry.materials = [floorMaterial]
            let node = SCNNode(geometry: geometry)
            node.transform = matrix(floor.transform)
            solid.addChildNode(node)
            // Plain ceiling for the inside view when there are no photos.
            let ceiling = SCNNode(geometry: SCNShape(path: path(RoomPlanGeometry.outline(floor)), extrusionDepth: 0.01))
            ceiling.geometry?.materials = [material(UIColor(white: 0.98, alpha: 1))]
            ceiling.transform = matrix(floor.transform)
            ceiling.position.y += Float(height)
            plainCeiling.addChildNode(ceiling)
        }
    }

    private func addLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 700
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)
    }

    // MARK: Labels

    private func pill(_ string: String, accent: Bool = false, size: CGFloat) -> SCNNode {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accent ? KanturaDesign.ink : UIColor.white]
        let textSize = (string as NSString).size(withAttributes: attributes)
        let canvas = CGSize(width: ceil(textSize.width) + 44, height: ceil(textSize.height) + 22)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            (accent ? KanturaDesign.mint : KanturaDesign.ink).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: canvas.height / 2).fill()
            (string as NSString).draw(at: CGPoint(x: 22, y: 11), withAttributes: attributes)
        }
        let plane = SCNPlane(width: size * canvas.width / canvas.height, height: size)
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 100
        return node
    }
    private func billboard(_ node: SCNNode) -> SCNNode {
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        node.constraints = [constraint]
        return node
    }
    private func length(_ value: Double) -> String { KanturaDesign.metric(value, unit: "m", decimals: 2) }
    private func bar(from a: SCNVector3, to b: SCNVector3, thickness: CGFloat, color: UIColor) -> SCNNode {
        let dx = b.x - a.x, dz = b.z - a.z, dy = b.y - a.y
        let box = SCNBox(width: CGFloat(sqrt(dx * dx + dz * dz + dy * dy)), height: thickness, length: thickness, chamferRadius: 0)
        box.materials = [material(color, lit: false)]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        node.eulerAngles.y = -atan2(dz, dx)
        return node
    }

    /// Floor plan: dimension line outside every wall with ticks and value,
    /// door/window markers on the wall line, area and name in the room.
    private func buildPlanMarks() {
        let top = Float(floorY + height + 0.05)
        let ink = UIColor(white: 0.55, alpha: 1)
        for wall in walls {
            let w = wall.dimensions[0], h = wall.dimensions[1]
            let a = RoomPlanGeometry.world([-w / 2, -h / 2, 0], wall.transform), b = RoomPlanGeometry.world([w / 2, -h / 2, 0], wall.transform)
            let mid = RoomPlanGeometry.world([0, -h / 2, 0], wall.transform)
            let towardsCentre = inward(from: mid)
            let off = 0.45, outX = -towardsCentre.x * off, outZ = -towardsCentre.z * off
            let p = SCNVector3(Float(a.x + outX), top, Float(a.z + outZ)), q = SCNVector3(Float(b.x + outX), top, Float(b.z + outZ))
            planMarks.addChildNode(bar(from: p, to: q, thickness: 0.025, color: ink))
            for end in [a, b] {
                planMarks.addChildNode(bar(from: SCNVector3(Float(end.x + outX * 0.55), top, Float(end.z + outZ * 0.55)),
                                           to: SCNVector3(Float(end.x + outX * 1.3), top, Float(end.z + outZ * 1.3)), thickness: 0.025, color: ink))
            }
            // Text runs along the wall and is never upside down in the plan.
            let label = pill(length(w), size: max(0.22, CGFloat(extent) * 0.045))
            label.eulerAngles.x = -.pi / 2
            let holder = SCNNode()
            holder.name = "length"
            holder.position = SCNVector3(Float(mid.x + outX * 1.65), top + 0.01, Float(mid.z + outZ * 1.65))
            var angle = -atan2(Float(b.z - a.z), Float(b.x - a.x))
            if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
            holder.eulerAngles.y = angle
            holder.addChildNode(label)
            planMarks.addChildNode(holder)
        }
        // Doors and windows: coloured bar on the wall and their width inside the room.
        let openings = RoomPlanGeometry.openingsByWall(room.document.surfaces)
        for wall in walls {
            for o in openings[wall.id] ?? [] {
                let a = RoomPlanGeometry.world([o.x0, -wall.dimensions[1] / 2, 0], wall.transform), b = RoomPlanGeometry.world([o.x1, -wall.dimensions[1] / 2, 0], wall.transform)
                let color = o.kind == "window" ? UIColor.systemTeal : KanturaDesign.mint
                let marker = bar(from: SCNVector3(Float(a.x), top + 0.02, Float(a.z)), to: SCNVector3(Float(b.x), top + 0.02, Float(b.z)), thickness: 0.14, color: color)
                marker.name = "surface:" + o.id
                planMarks.addChildNode(marker)
                let mid = RoomPlanGeometry.world([(o.x0 + o.x1) / 2, -wall.dimensions[1] / 2, 0], wall.transform), towards = inward(from: mid)
                let label = pill(MeasurementGuide.roomText(o.kind) + " " + length(o.x1 - o.x0), accent: true, size: max(0.17, CGFloat(extent) * 0.034))
                label.position = SCNVector3(Float(mid.x + towards.x * 0.4), top + 0.03, Float(mid.z + towards.z * 0.4))
                planMarks.addChildNode(billboard(label))
            }
        }
        let name = room.document.building?.room ?? room.document.name
        let area = pill(name + " · " + KanturaDesign.metric(summary.floorArea, unit: "m²", decimals: 1), accent: true, size: max(0.25, CGFloat(extent) * 0.05))
        area.position = SCNVector3(Float(centre.x), top + 0.04, Float(centre.z))
        planMarks.addChildNode(billboard(area))
    }

    /// 3D: one length label per wall above its top edge, the room height once,
    /// door/window sizes in their opening, area on the floor.
    private func buildModelLabels() {
        let size = max(0.13, CGFloat(extent) * 0.028)
        var tallest: RoomPlanDocument.Surface?
        for wall in walls {
            let h = wall.dimensions[1]
            let top = RoomPlanGeometry.world([0, h / 2, 0], wall.transform), out = inward(from: top)
            modelLabels.addChildNode(billboard({ let n = pill("↔ " + length(wall.dimensions[0]), size: size)
                n.position = SCNVector3(Float(top.x - out.x * 0.1), Float(top.y + 0.18), Float(top.z - out.z * 0.1)); return n }()))
            if tallest == nil || wall.dimensions[0] > tallest!.dimensions[0] { tallest = wall }
        }
        if let wall = tallest {
            // Room height once, at the end of the longest wall.
            let w = wall.dimensions[0]
            let p = RoomPlanGeometry.world([w / 2 - 0.15, 0, 0], wall.transform), towards = inward(from: p)
            modelLabels.addChildNode(billboard({ let n = pill("↕ " + length(height), size: size)
                n.position = SCNVector3(Float(p.x + towards.x * 0.15), Float(p.y), Float(p.z + towards.z * 0.15)); return n }()))
        }
        for s in room.document.surfaces where ["door", "window", "opening"].contains(s.kind) && s.transform.count == 16 && s.dimensions.count == 3 {
            let p = RoomPlanGeometry.world([0, 0, 0], s.transform)
            let label = pill(MeasurementGuide.roomText(s.kind) + " " + length(s.dimensions[0]) + " × " + length(s.dimensions[1]), accent: true, size: size * 0.85)
            label.position = vector(p)
            modelLabels.addChildNode(billboard(label))
            let inside = pill(MeasurementGuide.roomText(s.kind) + " " + length(s.dimensions[0]) + " × " + length(s.dimensions[1]), accent: true, size: 0.09)
            inside.position = vector(p)
            insideLabels.addChildNode(billboard(inside))
        }
        let area = pill(text("floorArea") + " " + KanturaDesign.metric(summary.floorArea, unit: "m²", decimals: 1), accent: true, size: size * 1.1)
        area.position = SCNVector3(Float(centre.x), Float(floorY + 0.05), Float(centre.z))
        area.eulerAngles.x = -.pi / 2
        modelLabels.addChildNode(area)
        for object in room.document.objects ?? [] where object.category == "stairs" && object.transform.count == 16 {
            let d = object.dimensions
            let label = pill(text("stairs") + " " + length(d[0]) + " × " + length(d[2]) + " · ↕ " + length(d[1]), accent: true, size: size)
            label.position = vector(RoomPlanGeometry.world([0, d[1] / 2 + 0.2, 0], object.transform))
            modelLabels.addChildNode(billboard(label))
        }
        // Inside: each wall's length at knee height, just in front of the wall.
        for wall in walls {
            let p = RoomPlanGeometry.world([0, -wall.dimensions[1] / 2 + 0.5, 0], wall.transform), towards = inward(from: p)
            let label = pill("↔ " + length(wall.dimensions[0]) + "   ↕ " + length(wall.dimensions[1]), size: 0.1)
            label.position = SCNVector3(Float(p.x + towards.x * 0.08), Float(p.y), Float(p.z + towards.z * 0.08))
            insideLabels.addChildNode(billboard(label))
        }
    }

    // MARK: Photos (inside view)

    private func buildPhotoTiles() {
        guard let set = photos?.photos, !set.isEmpty else { return }
        status.label.text = text("walkLoading")
        let document = room.document, ceilingHeight = summary.wallHeight
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mesh = RoomPhotoMesh.build(document, photos: set, ceilingHeight: ceilingHeight)
            var images: [Int: UIImage] = [:]
            for bucket in mesh.buckets {
                guard let index = bucket.photoIndex, let self = self else { continue }
                images[index] = Self.thumbnail(self.photoDirectory.appendingPathComponent(set[index].file), maxPixel: 1280)
            }
            DispatchQueue.main.async { self?.install(mesh, images: images) }
        }
    }

    static func thumbnail(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: false
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func install(_ mesh: RoomPhotoMesh, images: [Int: UIImage]) {
        for bucket in mesh.buckets {
            let vertices = stride(from: 0, to: bucket.positions.count, by: 3).map {
                SCNVector3(Float(bucket.positions[$0]), Float(bucket.positions[$0 + 1]), Float(bucket.positions[$0 + 2]))
            }
            let coordinates = stride(from: 0, to: bucket.uvs.count, by: 2).map { CGPoint(x: bucket.uvs[$0], y: bucket.uvs[$0 + 1]) }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: coordinates)],
                                       elements: [SCNGeometryElement(indices: bucket.indices, primitiveType: .triangles)])
            let m = material(UIColor(white: 0.9, alpha: 1), lit: false)
            if let index = bucket.photoIndex, let image = images[index] {
                m.diffuse.contents = image
                m.diffuse.wrapS = .clamp
                m.diffuse.wrapT = .clamp
            }
            geometry.materials = [m]
            photoTiles.addChildNode(SCNNode(geometry: geometry))
        }
        let percent = mesh.totalTiles > 0 ? Int((Double(mesh.coveredTiles) / Double(mesh.totalTiles) * 100).rounded()) : 0
        status.label.text = text("walkCoverage").replacingOccurrences(of: "{percent}", with: "\(percent)")
        applyMode()
    }

    // MARK: Cameras and modes

    private func buildCameras() {
        let span = Float(extent)
        let plan = SCNCamera()
        plan.usesOrthographicProjection = true
        plan.orthographicScale = Double(span) * 0.8
        plan.zFar = 200
        planCamera.camera = plan
        planCamera.position = SCNVector3(Float(centre.x), Float(floorY) + 30, Float(centre.z))
        planCamera.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        let model = SCNCamera()
        model.fieldOfView = 50
        model.zFar = 200
        modelCamera.camera = model
        modelCamera.position = SCNVector3(Float(centre.x) + span * 0.9, Float(floorY) + span * 1.25, Float(centre.z) + span * 1.15)
        modelCamera.look(at: SCNVector3(Float(centre.x), Float(floorY), Float(centre.z)))
        let eye = SCNCamera()
        eye.fieldOfView = 72
        eye.zNear = 0.05
        eye.zFar = 100
        eyeCamera.camera = eye
        eyeCamera.position = SCNVector3(Float(centre.x), Float(floorY + 1.6), Float(centre.z))
        [planCamera, modelCamera, eyeCamera].forEach { scene.rootNode.addChildNode($0) }
    }

    private var measuresOn = true
    private func toggleMeasures() {
        measuresOn.toggle()
        measures.backgroundColor = measuresOn ? KanturaDesign.mint : KanturaDesign.surface
        if measuresOn { measures.accessibilityTraits.insert(.selected) } else { measures.accessibilityTraits.remove(.selected) }
        applyMode()
    }

    private func applyMode() {
        let current = Mode(rawValue: mode.selectedSegmentIndex) ?? .model
        let hasTiles = !photoTiles.childNodes.isEmpty
        planMarks.isHidden = current != .plan || !measuresOn
        modelLabels.isHidden = current != .model || !measuresOn
        insideLabels.isHidden = current != .inside || !measuresOn
        photoTiles.isHidden = current != .inside || !hasTiles
        // Inside with photos: the photo-textured surfaces replace the plain model.
        solid.isHidden = current == .inside && hasTiles
        plainCeiling.isHidden = current != .inside || hasTiles
        wallMaterial.diffuse.contents = current == .plan ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.96, alpha: 1)
        switch current {
        case .plan: sceneView.pointOfView = planCamera
        case .model: sceneView.pointOfView = modelCamera
        case .inside: sceneView.pointOfView = eyeCamera
        }
        // Inside: own look-around gestures. Plan/3D: SceneKit's orbit/zoom control.
        // Plan: own pan/zoom (two fingers turn). 3D: SceneKit orbit. Inside: look around.
        sceneView.allowsCameraControl = current == .model
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        lookGestures.forEach { $0.isEnabled = current == .inside }
        planGestures.forEach { $0.isEnabled = current == .plan }
        if current != .inside && !hintShown {
            hintShown = true
            status.isHidden = false
            status.alpha = 1
            status.label.text = text("editHint")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, self.status.label.text == self.text("editHint") else { return }
                UIView.animate(withDuration: 0.4, animations: { self.status.alpha = 0 }) { _ in self.status.isHidden = true; self.status.alpha = 1 }
            }
            return
        }
        sceneView.accessibilityHint = text(current == .inside ? "walkHint" : "walkOutsideHint")
        status.isHidden = current != .inside || photos == nil
        if current == .inside && photos == nil {
            status.isHidden = false
            status.label.text = text("walkNoPhotos")
        }
    }

    @objc private func look(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { startYaw = yaw; startPitch = pitch }
        let t = gesture.translation(in: sceneView)
        // Drag the room like a photo sphere: moving the finger right turns the view left.
        yaw = startYaw + Float(t.x) * 0.005
        pitch = max(-1.3, min(1.3, startPitch + Float(t.y) * 0.005))
        eyeCamera.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = eyeCamera.camera else { return }
        camera.fieldOfView = max(35, min(100, camera.fieldOfView / gesture.scale))
        gesture.scale = 1
    }
}
