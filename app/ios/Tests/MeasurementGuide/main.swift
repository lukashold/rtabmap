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
    precondition(guide.roomPlan!.count == 52)
    precondition(guide.roomPlan!.values.allSatisfy { !$0.isEmpty })
    precondition(Set(guide.roomPlan!.keys) == Set(guides["de"]!.roomPlan!.keys))
}
precondition(MeasurementGuide.languageCode("fr-CA") == "fr")
precondition(MeasurementGuide.languageCode("zh_TW") == "zh-Hans")
precondition(MeasurementGuide.languageCode("it") == "it")
precondition(MeasurementGuide.languages.count == 6)
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
print("Measurement guide: six languages, language fallback, and six scanner workflow states passed")

// A rotated floor's area is calculated from its local polygon, without assuming
// that every captured floor occupies the same pair of world axes.
let matrix: [Double] = [1,0,0,0, 0,0,1,0, 0,-1,0,0, 3,0,5,1]
let floor = RoomPlanDocument.Surface(id: "floor-1", kind: "floor", dimensions: [3,2,0], transform: matrix,
    confidence: "medium", polygonCorners: [[0,0,0],[3,0,0],[3,1,0],[1,1,0],[1,2,0],[0,2,0]])
precondition(floor.polygonArea == 4)
let vertical = RoomPlanDocument.Surface(id: "wall-1", kind: "wall", dimensions: [3,2,0], transform: matrix,
    confidence: "high", polygonCorners: nil)
precondition(vertical.polygonArea == nil)
var document = RoomPlanDocument(name: "Kitchen", createdAt: "2026-10-11T10:00:00Z", roomId: "room-1", surfaces: [floor, vertical])
document.building = RoomPlanDocument.Building(name: "House", floor: "First floor", room: "Kitchen")
let roomData = try document.encoded()
let raw = try JSONSerialization.jsonObject(with: roomData) as! [String: Any]
precondition(raw["format"] as? String == "kantura-room-plan" && raw["units"] as? String == "m")
let roundtrip = try JSONDecoder().decode(RoomPlanDocument.self, from: roomData)
precondition(roundtrip.building?.floor == "First floor")
precondition(roundtrip.surfaces[0].transform[12] == 3 && roundtrip.surfaces[0].transform[14] == 5)
try roundtrip.validate()
let invalid = RoomPlanDocument.Surface(id: "bad", kind: "wall", dimensions: [3,.nan,0], transform: matrix, confidence: "high", polygonCorners: nil)
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
