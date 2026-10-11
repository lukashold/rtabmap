# Kantura on your iPhone

Kantura is an independently extended RTAB-Map fork. The 0.5 preview adds guided
Object Capture, private photo datasets, local Apple photogrammetry and offline
Gaussian Splat visualization. Capture and reconstruction quality still require
real-device acceptance; a successful unsigned build is not an App Store release.

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

- Indoor dimensions: RoomPlan. Check detected walls, openings and floor contours.
- Textured LiDAR models: the existing RTAB-Map scan, including outdoor objects.
- Photo objects: Object Capture on a supported iOS 17+ device, then local reduced
  USDZ reconstruction. The original photos remain private until exported.
- Gaussian Splats: export the photo dataset and explicitly submit it to the
  optional reconstruction server. The native app opens supported `.splat` and
  Gaussian `.ply` files locally; it does not train Splats itself.

RoomPlan and textured LiDAR currently have separate captures and coordinate
origins. Photo datasets/worker models have unverified scale. Splats show a visual
appearance and are not metric surfaces. Local USDZ must be converted separately
for the browser's OBJ/GLB mesh-measurement importer. Panoramas, video/drone frame
selection, generative image-to-3D and automatic aligned whole-building geometry
remain [roadmap work](../../docs/POLYCAM-ROADMAP.md).

The guided app and desktop support 15 languages. The inherited RTAB-Map expert
menus remain in English. Check [native workflow](MEASUREMENT-WORKFLOW.md) and
[worker setup](../../tools/reconstruction/README.md) for detailed constraints.
