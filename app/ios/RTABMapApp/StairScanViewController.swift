import ARKit
import SceneKit
import UIKit

/// Walk a stair (for example down to the basement) with LiDAR meshing on.
/// RoomPlan treats a room as one storey, so stairs get their own capture:
/// the mesh around the walked path plus the path itself, analysed afterwards
/// for clear width, headroom, steps and turns (see `StairAnalyzer`).
final class StairScanViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
    var onClose: (() -> Void)?
    var onSaved: (() -> Void)?

    static var isSupported: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    private let sceneView = ARSCNView()
    private var path: [StairVec] = []
    private var lastSample: StairVec?
    private var lastTime: TimeInterval = 0
    private var speedWarningUntil: TimeInterval = 0
    private var started = false
    private var finishing = false
    private var hint: KanturaHintPill!
    private var stats: KanturaHintPill!
    private var finish: KanturaCaptureButton!
    private var meshUpdates: [UUID: TimeInterval] = [:]
    private func text(_ key: String, _ values: [String: CustomStringConvertible] = [:]) -> String { MeasurementGuide.homeText(key, values) }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = text("stairTitle")
        KanturaDesign.navigation(self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("cancel"), style: .plain, target: self, action: #selector(cancel))
        showPreparation()
    }

    // MARK: Preparation

    private func showPreparation() {
        let (_, column) = KanturaDesign.scrollColumn(in: self, spacing: 16)
        view.backgroundColor = KanturaDesign.background
        column.addArrangedSubview(KanturaDesign.symbolTile("figure.stairs", size: 72))
        let heading = KanturaDesign.label(text("stairPrepTitle"), style: .title2)
        heading.accessibilityTraits.insert(.header)
        column.addArrangedSubview(heading)
        for key in ["stairTip1", "stairTip2", "stairTip3", "stairTip4"] {
            column.addArrangedSubview(KanturaDesign.inset(KanturaDesign.label(text(key), style: .body), padding: 14))
        }
        column.addArrangedSubview(KanturaDesign.label(text("stairPrepNote"), style: .footnote, secondary: true))
        let start = KanturaDesign.primaryButton(text("startScan"), icon: "viewfinder") { [weak self] in self?.startCapture() }
        _ = KanturaDesign.bottomBar([start], in: self)
    }

    // MARK: Capture

    private func startCapture() {
        guard Self.isSupported else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        view.backgroundColor = .black
        navigationController?.setNavigationBarHidden(true, animated: true)
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = false
        sceneView.rendersCameraGrain = false
        view.addSubview(sceneView)

        hint = KanturaHintPill(text("stairHintStart"))
        stats = KanturaHintPill(text("stairProgress", ["distance": KanturaDesign.metric(0, unit: "m", decimals: 1), "height": KanturaDesign.metric(0, unit: "m", decimals: 2)]))
        finish = KanturaCaptureButton(title: text("done"))
        finish.isEnabled = false
        finish.addAction(UIAction { [weak self] _ in self?.finishCapture() }, for: .touchUpInside)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = text("cancel")
        close.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)
        for v in [hint!, stats!, finish!, close] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor), sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor), sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            close.topAnchor.constraint(equalTo: g.topAnchor, constant: 8), close.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
            hint.topAnchor.constraint(equalTo: g.topAnchor, constant: 10), hint.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 8),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -16),
            stats.centerXAnchor.constraint(equalTo: g.centerXAnchor), stats.bottomAnchor.constraint(equalTo: finish.topAnchor, constant: -16),
            stats.leadingAnchor.constraint(greaterThanOrEqualTo: g.leadingAnchor, constant: 16),
            finish.centerXAnchor.constraint(equalTo: g.centerXAnchor), finish.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -16)
        ])
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
        started = true
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard started, !finishing else { return }
        let m = frame.camera.transform.columns.3
        let p = StairVec(Double(m.x), Double(m.y), Double(m.z))
        let now = frame.timestamp
        switch frame.camera.trackingState {
        case .normal: break
        default:
            DispatchQueue.main.async { self.hint.label.text = self.text("stairHintTracking") }
            return
        }
        if let last = lastSample {
            let moved = (p - last).length
            guard moved >= 0.05 else { return }
            let speed = moved / max(0.01, now - lastTime)
            if speed > 0.8 { speedWarningUntil = now + 2 }
        }
        lastSample = p
        lastTime = now
        if path.count < 20000 { path.append(p) }
        let walked = zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.z - $1.0.z) }
        let height = path.count > 1 ? p.y - path[0].y : 0
        let slow = now < speedWarningUntil
        DispatchQueue.main.async {
            self.stats.label.text = self.text("stairProgress", ["distance": KanturaDesign.metric(walked, unit: "m", decimals: 1),
                                                                 "height": KanturaDesign.metric(height, unit: "m", decimals: 2)])
            self.hint.label.text = slow ? self.text("stairHintSlow") : walked < 0.5 ? self.text("stairHintStart") : self.text("stairHintLook")
            self.finish.isEnabled = walked >= 1.0
        }
    }

    // Live mesh as a light wireframe so the user sees what is covered.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let mesh = anchor as? ARMeshAnchor else { return nil }
        let node = SCNNode(geometry: Self.geometry(mesh.geometry))
        return node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        let now = CACurrentMediaTime()
        if let last = meshUpdates[anchor.identifier], now - last < 0.5 { return }
        meshUpdates[anchor.identifier] = now
        node.geometry = Self.geometry(mesh.geometry)
    }

    private static func geometry(_ g: ARMeshGeometry) -> SCNGeometry {
        let v = g.vertices
        let vertexData = Data(bytes: v.buffer.contents().advanced(by: v.offset), count: v.stride * v.count)
        let source = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: v.count, usesFloatComponents: true,
                                       componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: v.stride)
        let f = g.faces
        let faceData = Data(bytes: f.buffer.contents(), count: f.count * f.indexCountPerPrimitive * f.bytesPerIndex)
        let element = SCNGeometryElement(data: faceData, primitiveType: .triangles, primitiveCount: f.count, bytesPerIndex: f.bytesPerIndex)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = KanturaDesign.mint.withAlphaComponent(0.55)
        material.fillMode = .lines
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    // MARK: Finish

    private func finishCapture() {
        guard !finishing else { return }
        finishing = true
        finish.isEnabled = false
        hint.label.text = text("stairAnalyzing")
        let anchors = sceneView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        let mesh = Self.worldMesh(anchors)
        sceneView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        let path = self.path
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indicator)
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        indicator.startAnimating()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<SavedStairScan, Error> = Result {
                let cropped = mesh.cropped(near: path, radius: 2.0)
                let profile = try StairAnalyzer.analyze(mesh: cropped, path: path)
                let stamp = ISO8601DateFormatter().string(from: Date())
                let name = MeasurementGuide.homeText("stairName")
                var document = StairScanDocument(name: name, createdAt: stamp, id: UUID().uuidString, building: nil,
                                                 path: path.map(\.array), profile: profile)
                let last = UserDefaults.standard.string(forKey: "KanturaRoomBuilding") ?? ""
                let floor = UserDefaults.standard.string(forKey: "KanturaRoomFloor") ?? ""
                document.building = LibraryLabels.building(room: name, apartment: last, floor: floor)
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                return try SavedStairScan.save(document, mesh: cropped, in: SavedStairScan.directory(in: documents))
            }
            DispatchQueue.main.async {
                indicator.removeFromSuperview()
                guard let self = self else { return }
                switch result {
                case .success(let scan):
                    self.onSaved?()
                    self.navigationController?.setNavigationBarHidden(false, animated: false)
                    let detail = StairResultViewController(scan: scan)
                    detail.onClose = self.onClose
                    self.navigationController?.setViewControllers([detail], animated: true)
                case .failure:
                    let alert = UIAlertController(title: self.text("stairTooShort"), message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: self.text("cancel"), style: .cancel) { _ in self.cancel() })
                    alert.addAction(UIAlertAction(title: self.text("rescan"), style: .default) { _ in
                        self.finishing = false
                        self.path = []
                        self.lastSample = nil
                        self.startCapture()
                    })
                    self.present(alert, animated: true)
                }
            }
        }
    }

    /// All mesh anchors in world coordinates.
    static func worldMesh(_ anchors: [ARMeshAnchor]) -> StairMesh {
        var mesh = StairMesh()
        for anchor in anchors {
            let g = anchor.geometry, t = anchor.transform
            let base = UInt32(mesh.vertexCount)
            guard mesh.vertexCount + g.vertices.count <= StairMesh.maxVertices else { break }
            let rotation = simd_float3x3(simd_make_float3(t.columns.0), simd_make_float3(t.columns.1), simd_make_float3(t.columns.2))
            for i in 0..<g.vertices.count {
                let p = g.vertices.buffer.contents().advanced(by: g.vertices.offset + g.vertices.stride * i).assumingMemoryBound(to: Float.self)
                let w = t * simd_float4(p[0], p[1], p[2], 1)
                mesh.positions += [w.x, w.y, w.z]
                let q = g.normals.buffer.contents().advanced(by: g.normals.offset + g.normals.stride * i).assumingMemoryBound(to: Float.self)
                let n = simd_normalize(rotation * simd_float3(q[0], q[1], q[2]))
                mesh.normals += [n.x.isFinite ? n.x : 0, n.y.isFinite ? n.y : 0, n.z.isFinite ? n.z : 0]
            }
            let f = g.faces
            guard f.indexCountPerPrimitive == 3 else { continue }
            let raw = f.buffer.contents()
            for i in 0..<f.count * 3 {
                let index: UInt32 = f.bytesPerIndex == 4 ? raw.load(fromByteOffset: i * 4, as: UInt32.self) : UInt32(raw.load(fromByteOffset: i * 2, as: UInt16.self))
                mesh.faces.append(base + index)
            }
        }
        return mesh
    }

    @objc private func cancel() {
        started = false
        sceneView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss(animated: true) { [onClose] in onClose?() }
    }
}
