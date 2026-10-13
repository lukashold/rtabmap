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
    precondition(guide.home!.count == 245)
    precondition(guide.home!["stairProgress"]!.contains("{distance}") && guide.home!["stairProgress"]!.contains("{height}"))
    for key in ["stairNarrowest", "stairCollision"] {
        precondition(["{distance}", "{cm}", "{where}"].allSatisfy { guide.home![key]!.contains($0) })
    }
    precondition(Set(guide.home!.keys) == Set(guides["de"]!.home!.keys))
    precondition(guide.home!.values.allSatisfy { !$0.isEmpty })
    precondition(guide.home!["doorsWindows"]!.contains("{doors}") && guide.home!["doorsWindows"]!.contains("{windows}"))
    precondition(guide.home!["unresolvedNote"]!.contains("{count}"))
    precondition(Set(guide.splat!.keys) == Set(guides["en"]!.splat!.keys))
    precondition(guide.splat!.values.allSatisfy { !$0.isEmpty })
    precondition(guide.sceneCapture!.count == 38)
    precondition(Set(guide.sceneCapture!.keys) == Set(guides["en"]!.sceneCapture!.keys))
    precondition(guide.sceneCapture!.values.allSatisfy { !$0.isEmpty })
    for key in ["count", "panoramaCount", "generationCount"] {
        precondition(guide.sceneCapture![key]!.contains("{count}"))
    }
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

// Generic scene capture persists even one photo, survives a fresh library load,
// and can add more images without re-encoding or losing the earlier bytes.
let sceneDirectory = photoRoot.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: sceneDirectory.appendingPathComponent("Images"), withIntermediateDirectories: true)
let sceneImage = sceneDirectory.appendingPathComponent("Images/000001-original.jpg")
let originalPhotoBytes = Data([0xff, 0xd8, 0x45, 0x58, 0x49, 0x46, 0xff, 0xd9])
try originalPhotoBytes.write(to: sceneImage)
for mode in ["room", "outdoor", "splat", "panorama", "generation-input"] {
    let first = try SavedPhotoDataset.finish(directory: sceneDirectory, name: "Courtyard", source: "apple-camera", captureMode: mode)
    precondition(first.manifest.images.count == 1 && first.manifest.captureMode == mode)
    precondition(SavedPhotoDataset.load(from: photoRoot).contains { $0.id == first.id })
    let retainedPhoto = try Data(contentsOf: sceneImage)
    precondition(retainedPhoto == originalPhotoBytes)
}
let previousManifest = try Data(contentsOf: sceneDirectory.appendingPathComponent("manifest.json"))
do { _ = try SavedPhotoDataset.finish(directory: sceneDirectory, name: "Wrong mode", source: "apple-camera", captureMode: "object"); preconditionFailure("Expected source/mode rejection") }
catch PhotoDataset.Failure.invalidManifest { }
let retainedManifest = try Data(contentsOf: sceneDirectory.appendingPathComponent("manifest.json"))
precondition(retainedManifest == previousManifest)
// Apple's object mode still requires its complete 20-image capture.
do { _ = try SavedPhotoDataset.finish(directory: sceneDirectory, name: "Incomplete object"); preconditionFailure("Expected incomplete object capture") }
catch PhotoDataset.Failure.incompleteCapture { }
try originalPhotoBytes.write(to: sceneDirectory.appendingPathComponent("Images/000002-original.jpg"))
let resumedScene = try SavedPhotoDataset.finish(directory: sceneDirectory, name: "Courtyard", source: "apple-camera", captureMode: "outdoor")
precondition(resumedScene.manifest.images.map { $0.file } == ["Images/000001-original.jpg", "Images/000002-original.jpg"])
precondition(resumedScene.manifest.scaleStatus == "unverified")

// A multi-chunk original is copied byte-for-byte. A partial or tampered original
// never appears as a valid library record. These are container byte fixtures,
// not claims of camera, video decode or panorama validation on a real device.
let mediaRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: mediaRoot) }
let mediaSource = mediaRoot.appendingPathComponent("camera.MOV")
var movieBytes = Data(repeating: 0x7b, count: 2 * 1024 * 1024 + 37)
movieBytes[0] = 0x11; movieBytes[movieBytes.count - 1] = 0x99
try movieBytes.write(to: mediaSource)
let savedMovie = try SavedMediaDataset.save(from: mediaSource, name: "Gate", source: "apple-camera", mode: "video", root: mediaRoot)
precondition(savedMovie.manifest.original.file == "Original/source.mov")
precondition(savedMovie.manifest.original.bytes == movieBytes.count)
let retainedMovie = try Data(contentsOf: savedMovie.originalURL)
let unchangedMovieSource = try Data(contentsOf: mediaSource)
precondition(retainedMovie == movieBytes && unchangedMovieSource == movieBytes)
precondition(SavedMediaDataset.load(from: mediaRoot).count == 1)
try Data([1]).write(to: savedMovie.originalURL)
precondition(SavedMediaDataset.load(from: mediaRoot).isEmpty)
try movieBytes.write(to: savedMovie.originalURL)
let badMedia = MediaDataset(id: UUID().uuidString, name: "Unsafe", createdAt: "2026-10-12T00:00:00Z", source: "files",
    captureMode: "video", original: .init(file: "Original/../other.mov", bytes: 1))
precondition((try? badMedia.validate()) == nil)
let overLimit = MediaDataset(id: UUID().uuidString, name: "Too large", createdAt: "2026-10-12T00:00:00Z", source: "files",
    captureMode: "video", original: .init(file: "Original/source.mp4", bytes: MediaDataset.maximumVideoBytes + 1))
do { try overLimit.validate(); preconditionFailure("Expected video size limit") } catch MediaDataset.Failure.fileTooLarge { }
// Sparse file exercises the pre-copy size guard without allocating 32 MiB.
let oversizedPanorama = mediaRoot.appendingPathComponent("too-large.jpg")
FileManager.default.createFile(atPath: oversizedPanorama.path, contents: nil)
let oversizedHandle = try FileHandle(forWritingTo: oversizedPanorama)
try oversizedHandle.truncate(atOffset: UInt64(MediaDataset.maximumPanoramaBytes + 1)); try oversizedHandle.close()
do { _ = try SavedMediaDataset.save(from: oversizedPanorama, name: "Too large", source: "files", mode: "panorama", root: mediaRoot); preconditionFailure("Expected panorama size limit") }
catch MediaDataset.Failure.fileTooLarge { }
let remainingFolders = try FileManager.default.contentsOfDirectory(at: mediaRoot, includingPropertiesForKeys: nil).filter { UUID(uuidString: $0.lastPathComponent) != nil }
precondition(remainingFolders.count == 1, "Oversized import must not create a partial library folder")
let aiSource = mediaRoot.appendingPathComponent("foreground.PNG")
try originalPhotoBytes.write(to: aiSource)
let aiInput = try SavedMediaDataset.save(from: aiSource, name: "Single object", source: "files", mode: "generation-input", root: mediaRoot)
let aiRetainedBytes = try Data(contentsOf: aiInput.originalURL)
precondition(aiRetainedBytes == originalPhotoBytes && aiInput.manifest.source == "files")
precondition(aiInput.manifest.scaleStatus == "unverified", "An original input is not yet a generated model")
precondition(MediaDataset.generationInputFits(bytes: MediaDataset.maximumGenerationInputBytes, width: 4096, height: 4096))
precondition(!MediaDataset.generationInputFits(bytes: MediaDataset.maximumGenerationInputBytes + 1, width: 4096, height: 4096))
precondition(!MediaDataset.generationInputFits(bytes: 1, width: 4097, height: 4096))
precondition(!MediaDataset.generationInputFits(bytes: 1, width: Int.max, height: Int.max))
precondition(!MediaDataset.generationInputFits(bytes: 0, width: 64, height: 64))
let oversizedAI = MediaDataset(id: UUID().uuidString, name: "Too large", createdAt: "2026-10-12T00:00:00Z", source: "files",
    captureMode: "generation-input", original: .init(file: "Original/source.png", bytes: MediaDataset.maximumGenerationInputBytes + 1))
do { try oversizedAI.validate(); preconditionFailure("Expected AI input size limit") } catch MediaDataset.Failure.fileTooLarge { }
print("Scene originals: interrupted/resumable photos, source/mode validation, atomic manifest retention, chunked immutable media copy, and import limits passed")

// Identical bright/dark counts and substantial overall contrast do not make a
// blurred edge sharp. Box-filter a step image, keeping both originals intact.
let qualitySide = 64
let sharpPixels: [UInt8] = (0..<(qualitySide * qualitySide)).map { $0 % qualitySide < qualitySide / 2 ? 64 : 192 }
let blurredPixels: [UInt8] = (0..<(qualitySide * qualitySide)).map { index in
    let y = index / qualitySide, x = index % qualitySide
    let sum = (-4...4).reduce(0) { partial, offset in
        partial + Int(sharpPixels[y * qualitySide + max(0, min(qualitySide - 1, x + offset))])
    }
    return UInt8(sum / 9)
}
let sharpQuality = PhotoQuality.analyze(grayscale: sharpPixels, width: qualitySide, height: qualitySide)!
let blurredQuality = PhotoQuality.analyze(grayscale: blurredPixels, width: qualitySide, height: qualitySide)!
precondition(sharpQuality.hint == nil && blurredQuality.hint == .weakEdges)
precondition(blurredQuality.laplacianVariance < sharpQuality.laplacianVariance / 20)
precondition(blurredQuality.contrastDeviation > 8 && blurredQuality.darkFraction == 0 && blurredQuality.brightFraction == 0)
for (value, expected) in [(UInt8(128), PhotoQuality.Hint.lowContrast), (UInt8(0), .dark), (UInt8(255), .bright)] {
    let result = PhotoQuality.analyze(grayscale: Array(repeating: value, count: 64 * 64), width: 64, height: 64)!
    precondition(result.hint == expected && result.laplacianVariance == 0)
}
precondition(PhotoQuality.analyze(grayscale: [], width: Int.max, height: Int.max) == nil)
precondition(PhotoQuality.analyze(grayscale: [1,2,3], width: 3, height: 3) == nil)
precondition(PhotoQuality.analyze(grayscale: Array(repeating: 128, count: 129 * 128), width: 129, height: 128) == nil)
precondition(PhotoQuality.analyze(grayscale: Array(repeating: 128, count: 3 * 3), width: 3, height: 3)?.hint == .lowContrast)
print("Photo preview quality: sharp/blurred edge separation, neutral/dark/bright uniform frames, safe bounds and AI input limits passed")
var photoWrite = ScenePhotoWriteBarrier()
precondition(photoWrite.begin(id: 1) && !photoWrite.begin(id: 2))
photoWrite.processingStarted(id: 1); photoWrite.captureFinished(id: 1)
precondition(photoWrite.isBusy, "Close must wait for the atomic write after capture finished")
photoWrite.writeFinished(id: 1); precondition(!photoWrite.isBusy)
precondition(photoWrite.begin(id: 2)); photoWrite.processingStarted(id: 2); photoWrite.writeFinished(id: 2)
precondition(photoWrite.isBusy, "A saved image must not enable a second camera request before the terminal callback")
photoWrite.captureFinished(id: 1); precondition(photoWrite.isBusy, "Stale callbacks cannot release a newer shot")
photoWrite.captureFinished(id: 2); precondition(!photoWrite.isBusy)
precondition(photoWrite.begin(id: 3)); photoWrite.captureFinished(id: 3)
precondition(!photoWrite.isBusy, "Early camera failure before image processing allows retry/close")
photoWrite.processingStarted(id: 3); photoWrite.writeFinished(id: 3)
precondition(!photoWrite.isBusy)
print("Scene camera write barrier: both callback orders, overlapping request rejection, early failure and stale callback checks passed")

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

// Room summary: the same 4 × 5 m, 2.5 m high acceptance room as the browser test
// (tools/scan-workspace/test/areas.test.mjs) must give 20 / 45 / 41.5 m².
func summaryFrame(_ center: [Double], _ x: [Double]) -> [Double] {
    let y = [0.0, 1, 0], z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]]
    return x + [0] + y + [0] + z + [0] + center + [1]
}
func summarySurface(_ id: String, _ kind: String, _ dimensions: [Double], _ transform: [Double], _ corners: [[Double]]? = nil) -> RoomPlanDocument.Surface {
    RoomPlanDocument.Surface(id: id, kind: kind, dimensions: dimensions, transform: transform, confidence: "high", polygonCorners: corners)
}
let summaryWalls = [
    summarySurface("w1", "wall", [4, 2.5, 0], summaryFrame([0, 1.25, -2.5], [1, 0, 0])),
    summarySurface("w2", "wall", [5, 2.5, 0], summaryFrame([2, 1.25, 0], [0, 0, 1])),
    summarySurface("w3", "wall", [4, 2.5, 0], summaryFrame([0, 1.25, 2.5], [-1, 0, 0])),
    summarySurface("w4", "wall", [5, 2.5, 0], summaryFrame([-2, 1.25, 0], [0, 0, -1]))
]
let summaryFloor = summarySurface("f", "floor", [4, 5, 0], [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1], [[-2,-2.5,0],[2,-2.5,0],[2,2.5,0],[-2,2.5,0]])
let summaryDoor = summarySurface("d", "door", [0.8, 2.5, 0.04], summaryFrame([0.5, 1.25, -2.49], [1, 0, 0]))
let summaryWindow = summarySurface("o", "window", [1, 1.5, 0.04], summaryFrame([2.01, 1.4, 1], [0, 0, 1]))
let summary = RoomPlanSummary(RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r",
    surfaces: summaryWalls + [summaryFloor, summaryDoor, summaryWindow]))
func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }
precondition(near(summary.floorArea, 20) && near(summary.floorPerimeter, 18))
precondition(near(summary.grossWallArea, 45) && near(summary.openingArea, 3.5) && near(summary.netWallArea, 41.5))
precondition(near(summary.wallHeight, 2.5) && summary.walls == 4 && summary.doors == 1 && summary.windows == 1)
precondition(summary.unresolvedOpenings == 0 && !summary.incomplete)
// Overlapping windows are deducted once; a stray opening is not deducted at all.
let overlapping = RoomPlanSummary(RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r",
    surfaces: summaryWalls + [summaryFloor,
        summarySurface("a", "window", [1, 1, 0], summaryFrame([0, 1.5, -2.5], [1, 0, 0])),
        summarySurface("b", "window", [1, 1, 0], summaryFrame([0.5, 1.5, -2.5], [1, 0, 0])),
        summarySurface("c", "door", [0.8, 2, 0], summaryFrame([0, 1, 0], [1, 0, 0]))]))
precondition(near(overlapping.openingArea, 1.5) && near(overlapping.netWallArea, 43.5) && overlapping.unresolvedOpenings == 1)
// A wall without height has no gross area; the total is marked incomplete.
var lowWalls = summaryWalls
lowWalls[1] = summarySurface("w2", "wall", [5, 0, 0], summaryFrame([2, 1.25, 0], [0, 0, 1]))
let partial = RoomPlanSummary(RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: lowWalls + [summaryFloor]))
precondition(partial.incomplete && near(partial.grossWallArea, 32.5))
print("Room summary: floor, gross/net wall area, overlap and incomplete-wall checks passed")

// Room photos: projection, best-photo choice and textured mesh coverage.
let frontCamera = RoomPhotoSet.Photo(file: "photo-001.jpg", transform: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,1.5,0,1],
    intrinsics: [1000,0,0, 0,1000,0, 960,720,1], width: 1920, height: 1440, timestamp: 1)
let projected = RoomPhotoProjection.project((0, 1.25, -2.5), photo: frontCamera)!
precondition(abs(projected.u - 960) < 1e-9 && abs(projected.v - 820) < 1e-9 && abs(projected.depth - 2.5) < 1e-9)
precondition(RoomPhotoProjection.project((0, 1.5, 1), photo: frontCamera) == nil, "points behind the camera are not visible")
// A camera looking along the wall (grazing) loses against one facing it.
let grazing = RoomPhotoSet.Photo(file: "photo-002.jpg", transform: [0,0,-1,0, 0,1,0,0, 1,0,0,0, 3,1.5,-2.3,1],
    intrinsics: [1000,0,0, 0,1000,0, 960,720,1], width: 1920, height: 1440, timestamp: 2)
let tile: [RoomPhotoProjection.Vec3] = [(-0.2, 1.0, -2.5), (0.2, 1.0, -2.5), (0.2, 1.4, -2.5), (-0.2, 1.4, -2.5)]
let choice = RoomPhotoProjection.bestPhoto(corners: tile, normal: (0, 0, 1), photos: [grazing, frontCamera])!
precondition(choice.photoIndex == 1 && choice.uv.allSatisfy { $0.allSatisfy { (0...1).contains($0) } })
precondition(RoomPhotoProjection.bestPhoto(corners: tile, normal: (0, 0, 1), photos: [grazing]) == nil)
precondition(RoomPhotoProjection.tiles(width: 1, height: 0.7, size: 0.35).count == 6)
precondition(!RoomPhotoProjection.isNewView(frontCamera.transform, kept: [frontCamera.transform]))
precondition(RoomPhotoProjection.isNewView(grazing.transform, kept: [frontCamera.transform]))
let photoSet = RoomPhotoSet(photos: [frontCamera, grazing])
try photoSet.validate()
let decodedPhotoSet = try JSONDecoder().decode(RoomPhotoSet.self, from: JSONEncoder().encode(photoSet))
precondition(decodedPhotoSet == photoSet)
do { try RoomPhotoSet(photos: [RoomPhotoSet.Photo(file: "../x.jpg", transform: frontCamera.transform, intrinsics: frontCamera.intrinsics, width: 1, height: 1, timestamp: 0)]).validate(); preconditionFailure("unsafe file name") } catch RoomPhotoSet.ValidationError.invalid { }
let photoMesh = RoomPhotoMesh.build(RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls + [summaryFloor]),
    photos: [frontCamera], ceilingHeight: 2.5)
precondition(photoMesh.totalTiles > 0 && photoMesh.coveredTiles > 0 && photoMesh.coveredTiles < photoMesh.totalTiles)
precondition(abs(photoMesh.eye.y - 1.6) < 1e-9 && abs(photoMesh.eye.x) < 1e-9 && abs(photoMesh.eye.z) < 1e-9)
precondition(photoMesh.buckets.allSatisfy { $0.positions.count / 3 * 2 == $0.uvs.count && $0.indices.count == $0.tiles * 6 })
// Detected objects (for example stairs) round-trip and are validated.
var withStairs = RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls)
withStairs.objects = [.init(id: "s", category: "stairs", dimensions: [1.0, 2.8, 3.2], transform: summaryWalls[0].transform, confidence: "high")]
try withStairs.validate()
withStairs.objects = [.init(id: "s", category: "../x", dimensions: [1, 1, 1], transform: summaryWalls[0].transform, confidence: "high")]
do { try withStairs.validate(); preconditionFailure("invalid object category") } catch RoomPlanDocument.ValidationError.invalidSurface { }
print("Room photos: projection, best view, tiling, mesh coverage and detected objects checks passed")

// Transport check: identical results to tools/scan-workspace/src/transport.js
// (reference values computed with the JavaScript implementation).
let fridge = TransportAssessment.Object(width: 0.6, depth: 0.66, height: 2.03)
let wide = try TransportAssessment(object: fridge, route: .init(width: 0.9, ceiling: 2.1, landingWidth: 1.2, landingDepth: 1.2, rise: 0.18, run: 0.27, turnDegrees: 180), margin: 0.02, allowTilt: true)
precondition(wide.verdict == .possible && wide.chosen.id == "upright" && abs(wide.chosen.minimumClearance - 0.03) < 1e-9)
precondition(wide.reasons == ["upright_envelope_fits"] && wide.chosen.samples.count == 41)
let tight = try TransportAssessment(object: fridge, route: .init(width: 0.8, ceiling: 2.4, landingWidth: 0.9, landingDepth: 0.9, rise: 0.18, run: 0.27, turnDegrees: 90), margin: 0.02)
precondition(tight.verdict == .uncertain && tight.chosen.id == "upright" && abs(tight.chosen.minimumClearance + 0.031964125) < 1e-8)
precondition(tight.reasons == ["no_tested_orientation_fits", "landing_requires_path_planning"] && tight.chosen.samples.count == 21)
let narrow = try TransportAssessment(object: fridge, route: .init(width: 0.55, ceiling: 2.4, landingWidth: 2, landingDepth: 2, rise: 0, run: 1, turnDegrees: 0))
precondition(narrow.verdict == .blocked && narrow.reasons == ["corridor_narrower_than_smallest_dimension"] && narrow.chosen.samples.count == 1)
do { _ = try TransportAssessment(object: fridge, route: .init(width: .nan, ceiling: 2, landingWidth: 1, landingDepth: 1, rise: 0, run: 1, turnDegrees: 0)); preconditionFailure("NaN width") }
catch TransportAssessment.InputError.invalid(let field) { precondition(field == "route.width") }
func withStairsValid() -> RoomPlanDocument {
    var document = RoomPlanDocument(name: "Stiegenhaus", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls + [summaryDoor])
    document.objects = [.init(id: "s", category: "stairs", dimensions: [1.0, 2.8, 3.2], transform: summaryWalls[0].transform, confidence: "high")]
    return document
}
let scanSuggestions = TransportScanSuggestion.collect(from: [withStairsValid()])
precondition(scanSuggestions.contains { $0.kind == .door && abs($0.width - 0.8) < 1e-9 })
precondition(scanSuggestions.contains { $0.kind == .stairs && $0.width == 1.0 && $0.height == 2.8 && $0.length == 3.2 })
precondition(scanSuggestions.contains { $0.kind == .roomHeight && abs($0.height - 2.5) < 1e-9 })
print("Transport check: verdicts match the browser implementation; scan suggestions checks passed")

// Openings are placed in the wall they belong to (wall-local coordinates).
let placed = RoomPlanGeometry.openingsByWall(summaryWalls + [summaryFloor, summaryDoor, summaryWindow])
precondition(placed[summaryWalls[0].id]?.count == 1 && placed[summaryWalls[1].id]?.count == 1 && placed[summaryWalls[2].id] == nil)
let placedDoor = placed[summaryWalls[0].id]![0]
precondition(placedDoor.kind == "door" && abs((placedDoor.x1 - placedDoor.x0) - 0.8) < 1e-6 && abs(placedDoor.y0 + 1.25) < 1e-6)
print("Room geometry: opening placement checks passed")

// Manual corrections: an opening marked as wall closes its wall (no duplicate),
// corrections are validated and can be undone.
var corrected = RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls + [summaryFloor, summaryDoor, summaryWindow])
corrected.corrections = [summaryDoor.id: "wall", summaryWindow.id: "door"]
try corrected.validate()
let applied = corrected.applyingCorrections()
precondition(applied.surfaces.count == 6 && !applied.surfaces.contains { $0.id == summaryDoor.id })
precondition(applied.surfaces.first { $0.id == summaryWindow.id }?.kind == "door")
let closedSummary = RoomPlanSummary(applied)
precondition(near(closedSummary.netWallArea, 43.5) && closedSummary.doors == 1 && closedSummary.windows == 0)
corrected.corrections = ["unknown-id": "wall"]
do { try corrected.validate(); preconditionFailure("correction for unknown surface") } catch RoomPlanDocument.ValidationError.invalidSurface { }
print("Room corrections: close opening, re-classify, validation checks passed")

// Exports: DXF lines in metres on named layers; self-contained HTML.
let exportRoom = RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls + [summaryFloor, summaryDoor, summaryWindow])
let dxf = RoomExport.dxf(exportRoom)
precondition(dxf.hasPrefix("0\nSECTION") && dxf.hasSuffix("0\nEOF\n") && dxf.contains("$INSUNITS\n70\n6"))
precondition(dxf.components(separatedBy: "0\nLINE\n8\nKANTURA_WALLS\n").count - 1 == 4)
precondition(dxf.contains("4.00 m") && dxf.contains("5.00 m") && dxf.contains("KANTURA_OPENINGS"))
let exportPlan = RoomExport.plan(exportRoom)
precondition(exportPlan.walls.count == 4 && exportPlan.openings.count == 2 && abs(exportPlan.floorY) < 1e-9)
precondition(exportPlan.openings.allSatisfy { $0.bottom >= -1e-6 && $0.top <= 2.5 + 1e-6 })
let html = RoomExport.html(exportRoom, photos: [(name: "photo-001.jpg", jpeg: Data([0xFF, 0xD8, 0xFF]))])
precondition(html.hasPrefix("<!doctype html>") && html.contains("<svg") && html.contains("canvas") && html.contains("data:image/jpeg;base64,/9j/"))
precondition(!html.contains("http://") || html.contains("xmlns=\"http://www.w3.org/2000/svg\""))
precondition(!html.contains("<script src"), "the HTML file must work offline")
print("Room exports: DXF layers/units and offline HTML checks passed")

// Room extras: markers and furniture round-trip; layout conflicts.
var extras = RoomExtras()
extras.markers.append(.init(id: "m1", kind: "defect", title: "Riss", detail: "Über der Tür", status: "open", assignee: "Baumeister",
                            position: [0, 1.5, -2.4], photo: "markers/m1.jpg", createdAt: "2026-10-13T00:00:00Z", updatedAt: "2026-10-13T00:00:00Z"))
// A 1 × 0.5 m table in the middle of the 4 × 5 m test room: no conflict.
let table = RoomExtras.Furniture(id: "t1", name: "Table", manufacturer: "", category: "table", width: 1, depth: 0.5, height: 0.75, x: 0, z: 0, rotation: 0, catalog: nil, url: nil, model: nil)
extras.furniture.append(table)
try extras.validate()
let extrasFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: extrasFolder, withIntermediateDirectories: true)
try extras.write(to: extrasFolder)
precondition(RoomExtras.load(from: extrasFolder) == extras)
var badExtras = extras
badExtras.markers[0].photo = "../escape.jpg"
do { try badExtras.validate(); preconditionFailure("unsafe marker photo path") } catch RoomExtras.ValidationError.invalid { }
let layoutRoom = RoomPlanDocument(name: "Test", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls + [summaryFloor, summaryDoor])
precondition(FurnitureLayout.conflicts(of: table, in: layoutRoom, others: []).isEmpty)
// Pushed through the wall at z = −2.5 (but not in front of the door at x 0.1…0.9): hits a wall.
var intoWall = table; intoWall.x = -1.2; intoWall.z = -2.4
precondition(FurnitureLayout.conflicts(of: intoWall, in: layoutRoom, others: []).walls == 1)
// In front of the door (door 0.8 m wide → 0.8 m swing zone): blocks the door.
var blocking = table; blocking.x = 0.5; blocking.z = -2.0
let doorConflict = FurnitureLayout.conflicts(of: blocking, in: layoutRoom, others: [])
precondition(doorConflict.doors == 1 && doorConflict.walls == 0)
// Rotated 90°: corners swap width and depth.
var turned = table; turned.id = "t2"; turned.rotation = .pi / 2
let turnedCorners = FurnitureLayout.corners(turned)
precondition(abs(turnedCorners.map { $0.x }.max()! - 0.25) < 1e-9 && abs(turnedCorners.map { $0.z }.max()! - 0.5) < 1e-9)
precondition(FurnitureLayout.conflicts(of: table, in: layoutRoom, others: [turned]).furniture == 1)
try FurnitureCatalog.builtIn.validate()
let catalogJSON = #"{"format":"kantura-furniture-catalog","version":1,"name":"Test","publisher":"Me","items":[{"id":"a","name":"Sofa","manufacturer":"X","category":"sofa","width":2,"depth":0.9,"height":0.8,"model":"http://insecure"}]}"#
let insecure = try JSONDecoder().decode(FurnitureCatalog.self, from: Data(catalogJSON.utf8))
do { try insecure.validate(); preconditionFailure("only https model links") } catch FurnitureCatalog.ValidationError.invalid { }
let seen = RoomPhotoProjection.bestPhoto(showing: (0, 1.25, -2.5), photos: [grazing, frontCamera])
precondition(seen?.index == 1 && abs(seen!.u - 960) < 1e-9)
print("Room extras: markers, furniture, layout conflicts, catalogue validation checks passed")

// Photo round guidance: wall coverage and direction to the next wall.
let coverage = RoomPhotoCoverage.walls(RoomPlanDocument(name: "T", createdAt: "2026-10-13T00:00:00Z", roomId: "r", surfaces: summaryWalls), photos: [frontCamera])
precondition(coverage.count == 4 && coverage[0].fraction > 0.5 && coverage[2].fraction == 0)
// Camera at y 1.5 looking along −z: wall at −z is ahead, +z behind, +x right, −x left.
precondition(RoomPhotoCoverage.direction(to: (x: 0, y: 1, z: -3), camera: frontCamera.transform) == .ahead)
precondition(RoomPhotoCoverage.direction(to: (x: 0, y: 1, z: 3), camera: frontCamera.transform) == .behind)
precondition(RoomPhotoCoverage.direction(to: (x: 3, y: 1, z: 0), camera: frontCamera.transform) == .right)
precondition(RoomPhotoCoverage.direction(to: (x: -3, y: 1, z: 0), camera: frontCamera.transform) == .left)
print("Photo round: coverage and direction checks passed")

// Release (-O) builds drop precondition messages; print them before trapping.
func check(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition { print("FAILED line \(line): \(message())"); fflush(stdout); preconditionFailure(message(), file: file, line: line) }
}
// Library labels: rename and assign to an apartment/floor.
check(LibraryLabels.building(room: "Büro", apartment: " ", floor: "") == nil)
let labelled = LibraryLabels.building(room: "Büro", apartment: "Top 4", floor: "")!
check(labelled.name == "Top 4" && labelled.floor == LibraryLabels.placeholder && labelled.room == "Büro")
check(LibraryLabels.group(labelled) == "Top 4" && LibraryLabels.group(nil) == "")
print("Library labels checks passed")

// Stair scans: synthetic straight flight (12 risers 0.18/0.27) between two landings,
// side walls, a soffit parallel to the flight and flat ceilings 2.6 m high.
func syntheticStair(width: Double, soffit: Double, spacing sp: Double = 0.04) -> (StairMesh, [StairVec]) {
    let steps = 12, rise = 0.18, run = 0.27, flat = 1.5
    func floorAt(_ u: Double) -> Double {
        if u < flat { return 0 }
        let k = Int((u - flat) / run) + 1
        return k > steps ? -Double(steps) * rise : -Double(k) * rise
    }
    func ceilingAt(_ u: Double) -> Double {
        let end = flat + Double(steps - 1) * run
        if u < flat { return 2.6 }
        if u > end { return -Double(steps) * rise + 2.6 }
        return min(2.6, -(u - flat) / run * rise + soffit)
    }
    var mesh = StairMesh()
    var noise: UInt64 = 42
    func jitter() -> Float { noise = noise &* 6364136223846793005 &+ 1442695040888963407; return Float(Double(noise >> 33) / Double(1 << 31) - 0.5) * 0.02 }
    func add(_ x: Double, _ y: Double, _ z: Double, _ n: (Float, Float, Float)) {
        mesh.positions += [Float(x) + jitter(), Float(y) + jitter(), Float(z) + jitter()]
        mesh.normals += [n.0, n.1, n.2]
    }
    let total = flat * 2 + Double(steps) * run
    var u = 0.0
    while u <= total {
        let f = floorAt(u), c = ceilingAt(u)
        var x = -width / 2
        while x <= width / 2 { add(x, f, -u, (0, 1, 0)); add(x, c, -u, (0, -1, 0)); x += sp }
        var y = f
        while y <= c { add(-width / 2, y, -u, (1, 0, 0)); add(width / 2, y, -u, (-1, 0, 0)); y += sp }
        u += sp
    }
    for k in 1...steps {
        let z = -(flat + Double(k - 1) * run)
        var y = -Double(k - 1) * rise
        while y >= -Double(k) * rise {
            var x = -width / 2
            while x <= width / 2 { add(x, y, z, (0, 0, -1)); x += sp }
            y -= sp
        }
    }
    var path: [StairVec] = []
    u = 0
    while u <= total { path.append(StairVec(0.12 + 0.02 * sin(u * 7), floorAt(u) + 1.45, -u)); u += 0.05 }
    return (mesh, path)
}
let (stairMesh, stairPath) = syntheticStair(width: 0.9, soffit: 2.2)
let stairProfile = try StairAnalyzer.analyze(mesh: stairMesh, path: stairPath)
check(stairProfile.risers == 12, "risers \(stairProfile.risers)")
check(abs(stairProfile.riser! - 0.18) < 0.025 && abs(stairProfile.going! - 0.27) < 0.035, "riser \(stairProfile.riser!) going \(stairProfile.going!)")
check(abs(stairProfile.drop - 2.16) < 0.06, "drop \(stairProfile.drop)")
check(abs(stairProfile.minWidth! - 0.9) < 0.07, "width \(stairProfile.minWidth!)")
check(abs(stairProfile.turnDegrees) < 12 && abs(stairProfile.slopeDegrees! - 33.7) < 6, "turn \(stairProfile.turnDegrees) slope \(stairProfile.slopeDegrees!)")
check(stairProfile.minHeadroom! > 1.9 && stairProfile.minHeadroom! < 2.45, "headroom \(stairProfile.minHeadroom!)")
// Mesh file round trip and cropping.
let reread = try StairMesh(data: stairMesh.encoded())
check(reread == stairMesh)
let tri = StairMesh(positions: [0, 0, 0, 1, 0, 0, 0, 0, 1, 9, 0, 9], normals: [Float](repeating: 0, count: 12), faces: [0, 1, 2, 1, 2, 3])
let croppedTri = tri.cropped(near: [StairVec(0, 1.5, 0)], radius: 2)
check(croppedTri.vertexCount == 3 && croppedTri.faces == [0, 1, 2])
check(tri.obj().contains("f 1//1 2//2 3//3"))
// A 0.60 × 0.66 × 2.03 m fridge goes down the 0.9 m flight tilted, not upright.
let fridgeCheck = StairTransport(profile: stairProfile, mesh: stairMesh, object: .init(width: 0.60, depth: 0.66, height: 2.03), stride: 4)!
check(fridgeCheck.verdict != .blocked, "fridge \(fridgeCheck.verdict) \(fridgeCheck.worst.clearance) at \(fridgeCheck.worst.distance)")
check(fridgeCheck.handlings.contains(.tilted) || fridgeCheck.handlings.contains(.tiltedSideways))
// Same fridge, 0.55 m wide staircase: blocked by the side walls.
let (narrowMesh, narrowPath) = syntheticStair(width: 0.55, soffit: 2.2)
let narrowProfile = try StairAnalyzer.analyze(mesh: narrowMesh, path: narrowPath)
check(abs(narrowProfile.minWidth! - 0.55) < 0.07, "narrow width \(narrowProfile.minWidth!)")
let narrowCheck = StairTransport(profile: narrowProfile, mesh: narrowMesh, object: .init(width: 0.60, depth: 0.66, height: 2.03), stride: 4)!
check(narrowCheck.verdict == .blocked && narrowCheck.worst.limit == .side, "narrow \(narrowCheck.verdict) \(narrowCheck.worst.limit)")
// Document validation.
var stairDocument = StairScanDocument(name: "Treppe", createdAt: "2026-10-13T00:00:00Z", id: "s1", building: labelled, path: stairPath.map(\.array), profile: stairProfile)
try stairDocument.validate()
stairDocument.path.append([1, 2])
do { try stairDocument.validate(); preconditionFailure("path points need x, y, z") } catch StairScanDocument.ValidationError.invalid { }
print("Stair scan: profile, mesh file and appliance path checks passed")

// Building elements snap to walls (room x −2…2, z −2.5…2.5, 2.5 m high).
let beam = StructuralPlacement.make("beam", at: (0.5, -1.8), document: layoutRoom, ceiling: 2.5, name: "Beam")!
check(abs(beam.width - 5) < 1e-6 && abs(beam.x - 0.5) < 1e-6 && abs(beam.z) < 1e-6 && abs(beam.bottom - 2.2) < 1e-9, "beam \(beam)")
let beamCorners = FurnitureLayout.corners(beam)
check(abs(beamCorners.map { $0.z }.max()! - 2.5) < 1e-6 && abs(beamCorners.map { $0.x }.max()! - 0.625) < 1e-6)
let bulkhead = StructuralPlacement.make("bulkhead", at: (1.7, 0.3), document: layoutRoom, ceiling: 2.5, name: "Bulkhead")!
check(abs(bulkhead.width - 5) < 1e-6 && abs(bulkhead.x - 1.85) < 1e-6 && abs(bulkhead.z) < 1e-6 && abs(bulkhead.bottom - 2.25) < 1e-9, "bulkhead \(bulkhead)")
let pillar = StructuralPlacement.make("column", at: (-1.8, 1.0), document: layoutRoom, ceiling: 2.5, name: "Column")!
check(abs(pillar.x + 1.85) < 1e-6 && abs(pillar.z - 1) < 1e-6 && pillar.bottom == 0 && pillar.height == 2.5)
check(FurnitureLayout.conflicts(of: beam, in: layoutRoom, others: []).isEmpty)
check(FurnitureLayout.conflicts(of: pillar, in: layoutRoom, others: []).isEmpty)
var underBeam = table; underBeam.x = 0.5
check(FurnitureLayout.conflicts(of: underBeam, in: layoutRoom, others: [beam]).furniture == 0)
var wardrobe = table; wardrobe.id = "w9"; wardrobe.x = 0.5; wardrobe.height = 2.3
check(FurnitureLayout.conflicts(of: wardrobe, in: layoutRoom, others: [beam]).furniture == 1)
check(FurnitureLayout.conflicts(of: beam, in: layoutRoom, others: [wardrobe]).furniture == 1)
var withElements = RoomExtras()
withElements.furniture = [beam, pillar]
try withElements.validate()
withElements.furniture[0].structural = "wall"
do { try withElements.validate(); preconditionFailure("unknown element kind") } catch RoomExtras.ValidationError.invalid { }
let elementDXF = RoomExport.dxf(layoutRoom, labels: .init(), extras: RoomExtras(markers: [], furniture: [beam]))
check(elementDXF.contains("KANTURA_STRUCTURE") && elementDXF.contains("UK +2.2000"))
print("Building elements: placement, clearance and conflicts checks passed")

// LiDAR suggestions: a 30 cm deep beam across the 4 × 5 m room, ceiling 2.5 m.
var beamMesh = StairMesh()
for xi in stride(from: -1.95, through: 1.95, by: 0.05) {
    for zi in stride(from: -2.45, through: 2.45, by: 0.05) {
        let underBeam = xi >= 0.4 && xi <= 0.65
        beamMesh.positions += [Float(xi), Float(underBeam ? 2.2 : 2.5), Float(zi)]
        beamMesh.normals += [0, -1, 0]
        beamMesh.positions += [Float(xi), 0, Float(zi)]
        beamMesh.normals += [0, 1, 0]
    }
}
let found = StructuralDetection.suggest(mesh: beamMesh, document: layoutRoom, floorY: 0, ceiling: 2.5)
let downward = (0..<beamMesh.vertexCount).filter { beamMesh.normalY($0) < -0.7 && beamMesh.position($0).y < 2.42 }.count
let detectionWalls = StructuralPlacement.walls(layoutRoom)
check(found.count == 1, "suggestions \(found.count), vertices \(beamMesh.vertexCount), under beam \(downward), walls \(detectionWalls.count), stats \(StructuralDetection.lastStats)")
check(found[0].structural == "beam" && abs(found[0].height - 0.3) < 0.02 && abs(found[0].bottom - 2.2) < 0.02, "beam \(found[0])")
check(found[0].width > 4.5 && found[0].depth > 0.2 && found[0].depth < 0.45 && abs(found[0].x - 0.525) < 0.08, "beam size \(found[0])")
check(StructuralDetection.suggest(mesh: StairMesh(), document: layoutRoom, floorY: 0, ceiling: 2.5).isEmpty)
print("LiDAR element suggestions checks passed")
