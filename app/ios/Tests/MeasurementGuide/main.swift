import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let guides = try JSONDecoder().decode([String: MeasurementGuide].self, from: data)
precondition(Set(guides.keys) == Set(MeasurementGuide.languages))
for language in MeasurementGuide.languages {
    let guide = guides[language]!
    precondition(guide.steps.count == 7)
    precondition(guide.steps.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty && !$0.icon.isEmpty })
    precondition(!guide.saveFiles.isEmpty && !guide.cloudHelp.isEmpty)
    let workflow = guide.workflow!
    precondition(workflow.stages.count == 4)
    precondition(workflow.stages.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    precondition(!workflow.prepareBody.isEmpty && !workflow.measureHint.isEmpty && !workflow.tutorial.isEmpty)
    precondition(guide.roomPlan!.count == 61)
    for key in ["videoTitle", "videoDetail", "videoUnavailable", "videoUnavailableDetail",
                "dimensionWidth", "dimensionHeight", "dimensionArea", "areaUnavailable", "confidenceHelp"] {
        precondition(!(guide.roomPlan![key] ?? "").isEmpty)
    }
    precondition(guide.roomPlan!.values.allSatisfy { !$0.isEmpty })
    precondition(Set(guide.roomPlan!.keys) == Set(guides["de"]!.roomPlan!.keys))
    precondition(guide.objectCapture!.count == 37)
    precondition(Set(guide.objectCapture!.keys) == Set(guides["en"]!.objectCapture!.keys))
    precondition(guide.objectCapture!.values.allSatisfy { !$0.isEmpty })
    precondition(guide.objectCapture!["photosCount"]!.contains("{count}") && guide.objectCapture!["photosCount"]!.contains("{max}"))
    precondition(guide.splat!.count == 9)
    precondition(Set(guide.splat!.keys) == Set(guides["en"]!.splat!.keys))
    precondition(guide.splat!.values.allSatisfy { !$0.isEmpty })
}
precondition(MeasurementGuide.languageCode("fr-CA") == "fr")
precondition(MeasurementGuide.languageCode("zh_TW") == "zh-Hans")
precondition(MeasurementGuide.languageCode("it") == "it")
for (locale, expected) in [("pt-BR","pt"), ("ar-EG","ar"), ("hi-IN","hi"), ("bn-BD","bn"), ("ru-RU","ru"), ("ja-JP","ja"), ("ko-KR","ko"), ("id-ID","id"), ("tr-TR","tr"), ("in_ID","id")] {
    precondition(MeasurementGuide.languageCode(locale) == expected)
}
precondition(MeasurementGuide.languages.count == 15)
precondition(MeasurementGuide.languageCode("en-US") == "en")
precondition(MeasurementGuide.languageCode("EN_gb") == "en")
precondition(MeasurementGuide.languageCode("nl-NL") == "de")

let ready = MeasurementWorkflowState(phase: .ready, canReconstruct: false, hasProjects: false)
precondition(ready.availableActions == [.scan] && ready.primaryAction == .scan)
let captured = MeasurementWorkflowState(phase: .captured, canReconstruct: true, hasProjects: true)
precondition(captured.availableActions == [.scan, .assemble, .library] && captured.primaryAction == .assemble)
let mesh = MeasurementWorkflowState(phase: .mesh, canReconstruct: true, hasProjects: true)
precondition(mesh.availableActions == [.scan, .assemble, .measure, .share, .library] && mesh.primaryAction == .measure)
let loadedMesh = MeasurementWorkflowState(phase: .mesh, canReconstruct: false, hasProjects: false)
precondition(!loadedMesh.availableActions.contains(.assemble) && loadedMesh.availableActions.contains(.measure))
let cloud = MeasurementWorkflowState(phase: .pointCloud, canReconstruct: false, hasProjects: false)
precondition(!cloud.availableActions.contains(.measure) && cloud.availableActions.contains(.share) && cloud.primaryAction == .share)
let active = MeasurementWorkflowState(phase: .busy, canReconstruct: true, hasProjects: true)
precondition(active.availableActions.isEmpty && active.primaryAction == nil)
print("Measurement guide: fifteen languages, language fallback, and six scanner workflow states passed")

// A rotated floor's area is calculated from its local polygon, without assuming
// that every captured floor occupies the same pair of world axes.
let matrix: [Double] = [1,0,0,0, 0,0,1,0, 0,-1,0,0, 3,0,5,1]
let floor = RoomPlanDocument.Surface(id: "floor-1", kind: "floor", dimensions: [3,2,0], transform: matrix,
    confidence: "medium", polygonCorners: [[0,0,0],[3,0,0],[3,1,0],[1,1,0],[1,2,0],[0,2,0]])
precondition(floor.polygonArea == 4)
let vertical = RoomPlanDocument.Surface(id: "wall-1", kind: "wall", dimensions: [3,2,0], transform: matrix,
    confidence: "high", polygonCorners: nil)
precondition(vertical.polygonArea == nil)
// Width and height retain the surface's local axes even when its world
// transform is rotated. Z is not a measured thickness for these surfaces.
for kind in ["wall", "door", "window", "opening"] {
    let surface = RoomPlanDocument.Surface(id: kind, kind: kind, dimensions: [0.91,2.13,0.04], transform: matrix,
        confidence: "high", polygonCorners: nil)
    precondition(surface.displayMeasurements == [.init(kind: .width, value: 0.91), .init(kind: .height, value: 2.13)])
    precondition(surface.displayMeasurements.allSatisfy { $0.unit == "m" })
}
// A concave floor's bounding rectangle is 6 m² but its detected area is 4 m².
precondition(floor.displayMeasurements == [.init(kind: .area, value: 4)])
precondition(floor.displayMeasurements[0].unit == "m²")
let floorWithoutOutline = RoomPlanDocument.Surface(id: "no-outline", kind: "floor", dimensions: [3,2,0], transform: matrix,
    confidence: "high", polygonCorners: nil)
precondition(floorWithoutOutline.displayMeasurements.isEmpty)
let degenerateFloor = RoomPlanDocument.Surface(id: "line", kind: "floor", dimensions: [3,2,0], transform: matrix,
    confidence: "high", polygonCorners: [[0,0,0],[1,1,0],[2,2,0]])
precondition(degenerateFloor.displayMeasurements.isEmpty)
let malformedSurface = RoomPlanDocument.Surface(id: "missing-dimension", kind: "wall", dimensions: [2], transform: matrix,
    confidence: "high", polygonCorners: nil)
precondition(malformedSurface.displayMeasurements.isEmpty)
var document = RoomPlanDocument(name: "Kitchen", createdAt: "2026-10-11T10:00:00Z", roomId: "room-1", surfaces: [floor, vertical])
document.building = RoomPlanDocument.Building(name: "House", floor: "First floor", room: "Kitchen")
let roomData = try document.encoded()
let raw = try JSONSerialization.jsonObject(with: roomData) as! [String: Any]
precondition(raw["format"] as? String == "kantura-room-plan" && raw["units"] as? String == "m")
let rawSurface = (raw["surfaces"] as! [[String: Any]])[0]
precondition(rawSurface["displayMeasurements"] == nil) // Presentation does not change interchange v1.
let roundtrip = try JSONDecoder().decode(RoomPlanDocument.self, from: roomData)
precondition(roundtrip.building?.floor == "First floor")
precondition(roundtrip.surfaces[0].transform[12] == 3 && roundtrip.surfaces[0].transform[14] == 5)
try roundtrip.validate()
let invalid = RoomPlanDocument.Surface(id: "bad", kind: "wall", dimensions: [3,.nan,0], transform: matrix, confidence: "high", polygonCorners: nil)
precondition(invalid.displayMeasurements.isEmpty)
let invalidDocument = RoomPlanDocument(name: "Bad", createdAt: "2026-10-11T10:00:00Z", roomId: "bad", surfaces: [invalid])
precondition((try? invalidDocument.encoded()) == nil)
var invalidBuilding = document
invalidBuilding.building = RoomPlanDocument.Building(name: "", floor: "First", room: "Kitchen")
precondition((try? invalidBuilding.encoded()) == nil)
let crowded = RoomPlanDocument(name: "Too many", createdAt: "2026-10-11T10:00:00Z", roomId: "crowded", surfaces: Array(repeating: floor, count: 151))
do { try crowded.validate(); preconditionFailure("Expected surface limit") }
catch RoomPlanDocument.ValidationError.tooComplex { }
let oversizedPolygon = RoomPlanDocument.Surface(id: "many-corners", kind: "floor", dimensions: [3,2,0], transform: matrix,
    confidence: "high", polygonCorners: Array(repeating: [0,0,0], count: 101))
let tooDetailed = RoomPlanDocument(name: "Too detailed", createdAt: "2026-10-11T10:00:00Z", roomId: "detailed", surfaces: [oversizedPolygon])
do { try tooDetailed.validate(); preconditionFailure("Expected polygon limit") }
catch RoomPlanDocument.ValidationError.tooComplex { }

let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: library) }
let saved = library.appendingPathComponent("saved")
try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
try roomData.write(to: saved.appendingPathComponent("room.kantura-room.json"))
// A missing model must not appear as a complete export in the room library.
precondition(SavedRoomPlan.load(from: library).isEmpty)
try Data([0]).write(to: saved.appendingPathComponent("room.usdz"))
precondition(SavedRoomPlan.load(from: library).count == 1)
let stem = SavedRoomPlan.exportStem(name: "../Kitchen: 1/2", identifier: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!)
precondition(stem == "Kitchen--1-2-12345678")

var lifecycle = RoomPlanLifecycle()
precondition(!lifecycle.finish() && !lifecycle.processed() && !lifecycle.export())
precondition(lifecycle.authorize() && lifecycle.start() && lifecycle.finish() && lifecycle.processed() && lifecycle.export())
lifecycle.exported()
precondition(lifecycle.phase == .review)
lifecycle.cancel()
precondition(!lifecycle.processed() && !lifecycle.start() && !lifecycle.export())
lifecycle.fail()
precondition(lifecycle.phase == .cancelled)
var permission = RoomPlanLifecycle()
precondition(permission.authorize())
permission.cancel()
precondition(!permission.start())
var failed = RoomPlanLifecycle()
precondition(failed.authorize() && failed.start() && failed.finish())
failed.fail()
precondition(!failed.processed() && !failed.export())
print("RoomPlan: polygon area, schema roundtrip, building metadata, library completeness, and capture lifecycle checks passed")

var photoFlow = PhotoCaptureLifecycle()
precondition(!photoFlow.process() && !photoFlow.captured() && !photoFlow.completed())
precondition(photoFlow.start() && !photoFlow.start())
precondition(!photoFlow.finish(imageCount: 19) && photoFlow.phase == .capturing)
precondition(photoFlow.finish(imageCount: 20) && photoFlow.captured() && photoFlow.process())
photoFlow.processingStopped()
precondition(photoFlow.phase == .photos && photoFlow.process() && photoFlow.completed())
photoFlow.cancel()
precondition(!photoFlow.completed() && !photoFlow.captured() && !photoFlow.start())
photoFlow.fail()
precondition(photoFlow.phase == .cancelled)
var cancelledCapture = PhotoCaptureLifecycle()
precondition(cancelledCapture.start() && cancelledCapture.finish(imageCount: 30))
cancelledCapture.cancel()
precondition(!cancelledCapture.captured())

let photoRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let datasetDirectory = photoRoot.appendingPathComponent(UUID().uuidString)
let imageDirectory = datasetDirectory.appendingPathComponent("Images")
try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: photoRoot) }
// Byte fixtures exercise manifest/library integrity, not image reconstruction.
for index in 0..<20 { try Data([1]).write(to: imageDirectory.appendingPathComponent("IMG_\(index).HEIC")) }
let photoRecord = try SavedPhotoDataset.finish(directory: datasetDirectory, name: "Vase")
precondition(photoRecord.manifest.images.count == 20 && !photoRecord.hasModel)
precondition(SavedPhotoDataset.load(from: photoRoot).count == 1)
let photoRoundtrip = try JSONDecoder().decode(PhotoDataset.self, from: photoRecord.manifest.encoded())
precondition(photoRoundtrip.scaleStatus == "unverified" && photoRoundtrip.images == photoRecord.manifest.images)
let modifiedImage = imageDirectory.appendingPathComponent("IMG_0.HEIC")
try Data([1,2]).write(to: modifiedImage)
precondition(SavedPhotoDataset.load(from: photoRoot).isEmpty)
try Data([1]).write(to: modifiedImage)
let checkpoint = datasetDirectory.appendingPathComponent("Checkpoint")
try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
try Data([1]).write(to: checkpoint.appendingPathComponent("model-in-progress.usdz"))
precondition(!photoRecord.hasModel && SavedPhotoDataset.load(from: photoRoot).count == 1)
for unsafeName in ["Images/../escape.jpg", "../escape.jpg", "Images/..\\escape.jpg", "Images/.hidden.jpg", "Images/data.exe"] {
    let invalid = PhotoDataset(id: UUID().uuidString, name: "Bad", createdAt: "2026-10-11T12:00:00Z",
        images: [.init(file: unsafeName, bytes: 1)])
    precondition((try? invalid.encoded()) == nil)
}
let duplicatePhotos = PhotoDataset(id: UUID().uuidString, name: "Duplicate", createdAt: "2026-10-11T12:00:00Z",
    images: [.init(file: "Images/a.jpg", bytes: 1), .init(file: "Images/a.jpg", bytes: 1)])
precondition((try? duplicatePhotos.encoded()) == nil)
print("Photo capture: cancellation/late callbacks, retry, minimum images, private dataset schema and incomplete-library checks passed")

let splatRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: splatRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: splatRoot) }
let rawSplat = splatRoot.appendingPathComponent("test.splat")
try Data(repeating: 0, count: 32).write(to: rawSplat)
let splatDocument = try SplatDocument.read(from: rawSplat, maximumBytes: 32)
precondition(splatDocument.data.count == 32)
do { _ = try SplatDocument.read(from: rawSplat, maximumBytes: 31); preconditionFailure("Expected bounded read") }
catch SplatDocument.Failure.tooLarge { }
try Data(repeating: 0, count: 31).write(to: rawSplat)
do { _ = try SplatDocument.read(from: rawSplat); preconditionFailure("Expected incomplete splat rejection") }
catch SplatDocument.Failure.invalidFile { }
let wrongType = splatRoot.appendingPathComponent("test.html")
try Data("ply\n".utf8).write(to: wrongType)
do { _ = try SplatDocument.read(from: wrongType); preconditionFailure("Expected unsupported extension") }
catch SplatDocument.Failure.unsupportedType { }
let plyFile = splatRoot.appendingPathComponent("test.ply")
try Data("ply\r\nformat ascii 1.0\r\n".utf8).write(to: plyFile)
let acceptedPLY = try SplatDocument.read(from: plyFile)
precondition(acceptedPLY.name == "test.ply")
try Data("<html>invalid</html>".utf8).write(to: plyFile)
do { _ = try SplatDocument.read(from: plyFile); preconditionFailure("Expected invalid PLY signature") }
catch SplatDocument.Failure.invalidFile { }
// Quotes, script-looking text and bidi characters must round-trip as data;
// filenames are JSON strings, never an interpolated executable expression.
let hostileName = "\";window.attack();//\u{202E}.splat"
let hostile = SplatDocument(name: hostileName, data: Data([0,1,255]))
let payload = try hostile.javascriptPayload(language: "ar")
let decodedPayload = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: String]
precondition(decodedPayload["name"] == hostileName && decodedPayload["language"] == "ar")
precondition(Data(base64Encoded: decodedPayload["base64"]!) == hostile.data)
print("Offline Splat import: bounded reads, file-type/signature checks, truncated data, and safe bridge payload checks passed")
