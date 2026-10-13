import UIKit
import SceneKit
import ImageIO

/// "Stand in the room": the scanned walls, floor and ceiling textured with the
/// photos taken during the scan, seen from the middle of the room at eye height.
/// Drag to look around, pinch to zoom; dimensions are overlaid and can be hidden.
/// A second mode shows the whole room from outside.
///
/// Photos are projected onto RoomPlan's flat surfaces: furniture in front of a
/// wall appears painted onto that wall, and areas no photo saw stay grey.
final class RoomWalkthroughViewController: UIViewController {
    private let room: SavedRoomPlan
    private let photoDirectory: URL
    private let photos: RoomPhotoSet?
    private let scene = SCNScene()
    private let sceneView = SCNView()
    private let eyeCamera = SCNNode()
    private let orbitCamera = SCNNode()
    private let labels = SCNNode()
    private let mode = UISegmentedControl()
    private let measures = UIButton(type: .system)
    private let status = KanturaHintPill("")
    private var yaw: Float = 0, pitch: Float = 0, startYaw: Float = 0, startPitch: Float = 0
    private var images: [Int: UIImage] = [:]
    private var lookGestures: [UIGestureRecognizer] = []
    private func text(_ key: String) -> String { MeasurementGuide.homeText(key) }

    init(room: SavedRoomPlan) {
        self.room = room
        photoDirectory = room.jsonURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)
        photos = RoomPhotoSet.load(from: photoDirectory)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func hasPhotos(_ room: SavedRoomPlan) -> Bool {
        RoomPhotoSet.load(from: room.jsonURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)) != nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        KanturaDesign.navigation(self)
        navigationItem.largeTitleDisplayMode = .never
        title = text("walkTitle")
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        sceneView.antialiasingMode = .multisampling4X
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityLabel = text("walkTitle")
        sceneView.accessibilityHint = text("walkHint")
        view.addSubview(sceneView)

        mode.insertSegment(withTitle: text("walkInside"), at: 0, animated: false)
        mode.insertSegment(withTitle: text("walkOutside"), at: 1, animated: false)
        mode.selectedSegmentIndex = 0
        mode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        mode.selectedSegmentTintColor = KanturaDesign.mint
        mode.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        mode.setTitleTextAttributes([.foregroundColor: KanturaDesign.ink], for: .selected)
        mode.addAction(UIAction { [weak self] _ in self?.applyMode() }, for: .valueChanged)
        measures.setImage(UIImage(systemName: "ruler"), for: .normal)
        measures.setTitle("  " + text("walkMeasures"), for: .normal)
        measures.tintColor = .white
        measures.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        measures.layer.cornerRadius = 16
        measures.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        measures.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.labels.isHidden.toggle()
            self.measures.alpha = self.labels.isHidden ? 0.6 : 1
        }, for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [mode, measures])
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor), sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor), sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            status.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(look(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))
        sceneView.addGestureRecognizer(pan)
        sceneView.addGestureRecognizer(pinch)
        lookGestures = [pan, pinch]
        status.label.text = text("walkLoading")
        buildScene()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.barStyle = .black
    }

    // MARK: Scene

    private func buildScene() {
        let document = room.document
        let summary = RoomPlanSummary(document)
        let set = photos?.photos ?? []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mesh = RoomPhotoMesh.build(document, photos: set, ceilingHeight: summary.wallHeight)
            // Decode only the photos that are actually used, downsampled for the GPU.
            var used: [Int: UIImage] = [:]
            for bucket in mesh.buckets {
                guard let index = bucket.photoIndex, let self = self else { continue }
                used[index] = Self.thumbnail(self.photoDirectory.appendingPathComponent(set[index].file), maxPixel: 1280)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.images = used
                self.install(mesh, summary: summary)
            }
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

    private func install(_ mesh: RoomPhotoMesh, summary: RoomPlanSummary) {
        for bucket in mesh.buckets {
            let vertices = stride(from: 0, to: bucket.positions.count, by: 3).map {
                SCNVector3(Float(bucket.positions[$0]), Float(bucket.positions[$0 + 1]), Float(bucket.positions[$0 + 2]))
            }
            let coordinates = stride(from: 0, to: bucket.uvs.count, by: 2).map { CGPoint(x: bucket.uvs[$0], y: bucket.uvs[$0 + 1]) }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: coordinates)],
                                       elements: [SCNGeometryElement(indices: bucket.indices, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            if let index = bucket.photoIndex, let image = images[index] {
                material.diffuse.contents = image
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
            } else {
                material.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            }
            geometry.materials = [material]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        }
        addLabels(summary: summary)
        scene.rootNode.addChildNode(labels)

        let camera = SCNCamera()
        camera.fieldOfView = 70
        camera.zNear = 0.05
        camera.zFar = 100
        eyeCamera.camera = camera
        eyeCamera.position = SCNVector3(Float(mesh.eye.x), Float(mesh.eye.y), Float(mesh.eye.z))
        scene.rootNode.addChildNode(eyeCamera)
        let outside = SCNCamera()
        outside.fieldOfView = 55
        outside.zFar = 200
        orbitCamera.camera = outside
        orbitCamera.position = SCNVector3(Float(mesh.eye.x) + 4, Float(mesh.floorY) + 7, Float(mesh.eye.z) + 6)
        orbitCamera.look(at: SCNVector3(Float(mesh.eye.x), Float(mesh.floorY), Float(mesh.eye.z)))
        scene.rootNode.addChildNode(orbitCamera)
        applyMode()

        let percent = mesh.totalTiles > 0 ? Int((Double(mesh.coveredTiles) / Double(mesh.totalTiles) * 100).rounded()) : 0
        status.label.text = photos == nil ? text("walkNoPhotos") : text("walkCoverage").replacingOccurrences(of: "{percent}", with: "\(percent)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            UIView.animate(withDuration: 0.4) { self?.status.alpha = 0 }
        }
    }

    private func addLabels(summary: RoomPlanSummary) {
        func world(_ p: [Double], _ m: [Double]) -> SCNVector3 {
            SCNVector3(Float(m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12]), Float(m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13]), Float(m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]))
        }
        let length = { (value: Double) in KanturaDesign.metric(value, unit: "m", decimals: 2) }
        var counts: [String: Int] = [:]
        for surface in room.document.surfaces where surface.dimensions.count == 3 && surface.transform.count == 16 {
            counts[surface.kind, default: 0] += 1
            let w = surface.dimensions[0], h = surface.dimensions[1]
            switch surface.kind {
            case "wall":
                // Width along the bottom, height at the side: like a tape measure on the wall.
                labels.addChildNode(label("↔ " + length(w), at: world([0, -h / 2 + 0.35, 0.02], surface.transform)))
                labels.addChildNode(label("↕ " + length(h), at: world([w / 2 - 0.3, 0, 0.02], surface.transform)))
            case "door", "window", "opening":
                let name = MeasurementGuide.roomText(surface.kind)
                labels.addChildNode(label("\(name) " + length(w) + " × " + length(h), at: world([0, 0, 0.05], surface.transform), accent: true))
            case "floor":
                // Every edge of the floor outline, measured along the floor.
                if let corners = surface.polygonCorners, corners.count >= 3 {
                    for i in corners.indices {
                        let a = corners[i], b = corners[(i + 1) % corners.count]
                        let edge = hypot(b[0] - a[0], b[1] - a[1])
                        guard edge > 0.15 else { continue }
                        // Slightly inside the room so the label is not hidden in the wall.
                        let mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0]
                        let centre = [corners.map { $0[0] }.reduce(0, +) / Double(corners.count), corners.map { $0[1] }.reduce(0, +) / Double(corners.count)]
                        let toward = [centre[0] - mid[0], centre[1] - mid[1]], d = max(1e-6, hypot(toward[0], toward[1]))
                        let inset = min(0.25, d / 2)
                        labels.addChildNode(label("— " + length(edge), at: world([mid[0] + toward[0] / d * inset, mid[1] + toward[1] / d * inset, 0.03], surface.transform)))
                    }
                }
                if let area = surface.polygonArea {
                    labels.addChildNode(label(text("floorArea") + " " + KanturaDesign.metric(area, unit: "m²", decimals: 1), at: world([0, 0, 0.02], surface.transform), accent: true))
                }
            default: break
            }
        }
        for object in room.document.objects ?? [] where object.category == "stairs" && object.transform.count == 16 {
            let d = object.dimensions
            labels.addChildNode(label(text("stairs") + " " + length(d[0]) + " × " + length(d[2]) + " · ↕ " + length(d[1]),
                                      at: world([0, 0, 0], object.transform), accent: true))
        }
    }

    /// A camera-facing pill with text, drawn on top of the walls.
    private func label(_ string: String, at position: SCNVector3, accent: Bool = false) -> SCNNode {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accent ? KanturaDesign.ink : UIColor.white]
        let size = (string as NSString).size(withAttributes: attributes)
        let canvas = CGSize(width: ceil(size.width) + 48, height: ceil(size.height) + 24)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: canvas.height / 2)
            (accent ? KanturaDesign.mint : UIColor.black.withAlphaComponent(0.72)).setFill()
            path.fill()
            (string as NSString).draw(at: CGPoint(x: 24, y: 12), withAttributes: attributes)
        }
        let height: CGFloat = 0.11
        let plane = SCNPlane(width: height * canvas.width / canvas.height, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.renderingOrder = 100
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        return node
    }

    // MARK: Interaction

    private func applyMode() {
        let inside = mode.selectedSegmentIndex == 0
        sceneView.pointOfView = inside ? eyeCamera : orbitCamera
        sceneView.allowsCameraControl = !inside
        // Inside: our own look-around gestures. Outside: SceneKit's orbit control.
        lookGestures.forEach { $0.isEnabled = inside }
        sceneView.accessibilityHint = text(inside ? "walkHint" : "walkOutsideHint")
    }

    @objc private func look(_ gesture: UIPanGestureRecognizer) {
        guard mode.selectedSegmentIndex == 0 else { return }
        if gesture.state == .began { startYaw = yaw; startPitch = pitch }
        let t = gesture.translation(in: sceneView)
        // Drag the room: moving the finger right turns the view left, like a photo sphere.
        yaw = startYaw + Float(t.x) * 0.005
        pitch = max(-1.3, min(1.3, startPitch + Float(t.y) * 0.005))
        eyeCamera.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        guard mode.selectedSegmentIndex == 0, let camera = eyeCamera.camera else { return }
        camera.fieldOfView = max(35, min(100, camera.fieldOfView / gesture.scale))
        gesture.scale = 1
    }
}
