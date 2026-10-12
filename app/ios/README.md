# Kantura on your iPhone

Kantura is an independently extended RTAB-Map fork. Source version **0.6.0,
build 4** includes RoomPlan, textured LiDAR, Object Capture, general scene photos,
video, panorama photo sequences and single-image AI input. The app preserves
originals and lets you explicitly export them for desktop/server processing.
Capture and reconstruction quality still require real-device acceptance; a
successful unsigned build is not an App Store release or a claim of Polycam parity.

## Apple Silicon Mac

Install the Xcode version selected in [the iOS workflow](../../.github/workflows/ios.yml)
and Node.js 24. Download [Kantura-Mac-Setup.command](Kantura-Mac-Setup.command),
then run `bash Kantura-Mac-Setup.command` in Terminal. The helper creates a fresh
checkout, installs the pinned workspace dependencies, builds the offline Splat
assets and prepares the native RTAB-Map dependencies before opening Xcode.
It refuses to overwrite an existing checkout.

In Xcode select your Apple signing team, a unique bundle identifier and your
connected iPhone, then Product → Run. Complete Apple's signing/device prompts
on your Mac and phone. No public TestFlight invitation or App Store download is
available yet. See [the release checklist](../../docs/APP-STORE-RELEASE.md).

## Capture and results

| Entry | Native result and next step |
| --- | --- |
| RoomPlan | On a supported iOS 17+ LiDAR device: detected walls, doors, windows, openings and available floor outlines; labelled width/height or polygon area, USDZ and neutral JSON export. |
| House / floor / room library | Named rooms are saved locally and can be exported again. Floors group independent rooms; they do not align their coordinate systems. |
| LiDAR scan | Existing RTAB-Map depth-plus-camera capture, original `.db`, textured mesh reconstruction and export; suitable for inspecting rooms or outdoor objects such as gates. |
| Photo object | Guided Apple Object Capture on a supported iOS 17+ device, private images and, when `PhotogrammetrySession.isSupported`, local USDZ at Apple's `.reduced` detail. No higher-detail selection is currently offered on iOS. |
| Room / outdoor / Gaussian Splat photos | General photo capture without an object bounding box. Resume a private dataset and export original JPEGs with metadata as ZIP for the optional server's mesh or Splat processing. |
| Video | Record up to three minutes with microphone permission, or import MOV/MP4/M4V up to 2 GiB. Preserve/export the original; frame selection and reconstruction run on the server. |
| Panorama photo sequence | Capture up to 36 original photos, with guidance for 20–36 overlapping views around the same camera position. Export ZIP for server stitching; a complete 360° panorama is not guaranteed. |
| Panorama import | Import an existing 2:1 equirectangular JPEG/PNG, up to 32 MiB and 8192 × 4096 pixels. Export it to the browser panorama viewer. |
| Single photo for AI | Capture one original or import JPEG/PNG up to 20 MiB and 16 megapixels. Export the image, then explicitly choose the browser's AI mode and confirm foreground isolation. Optional TripoSR generates unobserved geometry; the result is not a measured scan. |
| Open Splat | View supported `.splat` or Gaussian `.ply` files offline, up to 32 MiB. The app does not train Splats locally. |

General scene photos use one physical rear wide-angle camera at **1×**, with
continuous autofocus and autoexposure. A grayscale preview bounded to 128 pixels
per side supplies warnings for very dark/bright regions, low contrast or weak
edges. These indicators do not establish sharpness, overlap, motion or measurement
accuracy. Original photos are neither re-encoded nor automatically deleted.

The native scene library keeps originals locally, excluded from automatic backup.
Files export is explicit; there is no native automatic server upload. Photos may
retain location metadata, and recorded videos contain audio. The server accepts
at most **200 MiB per upload**, so a larger archived video or photo ZIP needs a
smaller copy before submission. Keeping an original locally does not mean that
every server decoder or reconstruction mode accepts it.

RoomPlan and textured LiDAR currently have separate captures and coordinate
origins. Photo datasets/worker models have unverified scale. Splats show a visual
appearance and are not metric surfaces. Panoramas have no recovered depth, and
AI-generated models must not be used for measurements, even with a supplied
reference length. Local USDZ must be converted separately for the browser's
OBJ/GLB mesh-measurement importer. Georeferencing, automatic whole-building
alignment and automatic RoomPlan-to-texture alignment remain separate
[roadmap work](../../docs/POLYCAM-ROADMAP.md).

The guided app and desktop support 15 languages. The inherited RTAB-Map expert
menus remain in English. Check [native workflow](MEASUREMENT-WORKFLOW.md) and
[worker setup](../../tools/reconstruction/README.md) for detailed constraints.

## Validation record

The 0.6 native snapshot passed the complete unsigned iOS app/IPA build and
Foundation checks in [iOS run 38207033828](https://github.com/lukashold/rtabmap/actions/runs/38207033828).
The standalone offline Docker panorama and actual TripoSR inference checks
passed in [capture-mode run 38207033832](https://github.com/lukashold/rtabmap/actions/runs/38207033832).
These are specific CI results, not tests of the camera on an iPhone. Standalone
engine checks also do not establish that every route in the combined HTTP job
service has passed; consult the reconstruction workflow for that separate result.
Room/gate field scans, control measurements, real-device Splat rendering and
operator-specific cloud sign-in remain acceptance work.
