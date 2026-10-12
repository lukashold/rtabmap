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
