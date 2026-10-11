# Development validation — 0.5.0 preview, 2026-10-11

## New 0.5 capture, visualization and measurement checks

The Windows run passes **125 Node tests**. These include actual HTTP transport,
reconstruction authentication and bounded streaming, Gaussian-file detection,
offline native bridge payloads, race recovery and edge/corner snapping. The Python
worker suite passes **41 tests**, including real JPEG/PNG/HEIC decoding and EXIF
rotation. Six additional workspace-cleanup tests bring the suite to 47 tests:
46 pass on Windows; the actual symbolic-link case is skipped because Windows
does not permit creating that link here. Linux CI executes that case. Cleanup
keeps the original archive, artifacts and logs and only removes the generated
work directory after a finished process. Two additional orchestration/logging
regressions bring the latest suite to 49 (48 pass on Windows, one link skip).
The Linux run passed all 47 preceding cases. The actual engine smoke identified
and corrected an OpenMVS handoff: TextureMesh now receives the existing dense
scene plus the separately exported PLY, rather than a nonexistent mesh scene.
Its process/job tests use explicitly identified fake workers; they do
not establish a successful COLMAP/OpenMVS/OpenSplat reconstruction.

The actual browser rendered the original synthetic Splat demo, downloaded it and
reopened the resulting `.splat`. Closing the Splat view preserved an existing
measurement. Two corner selections with snapping enabled produced a measurement
and displayed the corner status. This proves the interaction, not field accuracy.
The standalone native IIFE rendered its demo with its actual content security
policy over localhost, without console errors. This browser exercise does not
establish WKWebView behavior on an iPhone.

At 390 × 844, all fifteen photo-dialog translations were selected without
horizontal page overflow. Arabic was checked with the Splat preview and RTL
direction. Signing into the real local Python service correctly reported the
Windows machine's absent reconstruction engines; no completed job was fabricated.
The Docker/Xcode workflows and a separate real-engine CPU smoke workflow provide
their own commit-specific results in GitHub Actions. Native capture, scan accuracy,
real-account cloud sign-in and reconstruction visual quality remain device/hardware
acceptance work. Ten training iterations in a synthetic smoke test, if successful,
would establish the processing path only.

Historical checks below apply to their recorded revisions.

## New 0.4.1 usability checks

The Windows integration run passes **88 Node tests**, including two task-lock
regressions that cover concurrent actions and failure recovery, and a real HTTP
regression for a client-aborted video stream. Changes separate
the indoor RoomPlan guide from textured LiDAR capture, add contextual imports,
improve control contrast and touch targets, and clarify download/transport states.
Native source changes add wrapped Dynamic Type buttons, keyboard-aware RoomPlan
results, a scrollable language picker, and direct measurements for saved rooms.
Compilation does not establish native layout or physical capture usability.

The local build was exercised through the Codex in-app browser at 1280 × 720 and
390 × 844. The German home, house entry, guide chooser and all seven RoomPlan
guide steps worked. A desktop synthetic two-point distance produced 2.828 m and
survived a trip to the overview and back. A mobile three-point floor polygon
produced 2.61 m² and exposed its finish/cancel actions beside the model. These
arbitrary synthetic selections are interaction checks, not accuracy benchmarks.

The live pass found and corrected two layout defects: tall desktop sidebars pushed
the model below the viewport, and mobile settings preceded the model by over
1100 pixels. Desktop sidebars now scroll separately. Mobile tools and the model
come before settings. All 15 languages were selected at 390 pixels without
horizontal page overflow; Arabic direction and a representative screenshot were
checked. This is not native-speaker review or exhaustive translated-screen testing.

The two-floor synthetic house archive imported with its detected measurements;
switching to the first-floor bedroom replaced the room data and reset unsaved
transport values, catalogue search and results. The German video loaded with
readyState 4 and duration 86.75 s. A measurement HTML report actually downloaded.
No browser console errors were observed during this pass. A subsequent reload
exposed a server crash when an MP4 client disconnected after headers were sent.
The error handler now leaves completed/destroyed responses alone and does not
send a second set of headers. The regression reproduces the original crash and
checks successful video/health requests afterward. Opening/closing the video
dialog and reloading the actual browser also succeeded after the fix.
Sign-in to real cloud
accounts, maximum text sizes, assistive technology and a signed iPhone remain open.

Historical checks below apply to their recorded revisions.

## New 0.4 language coverage

The Windows run passes **85 Node tests**. Fifteen complete UI dictionaries,
native guides and video scripts share the same supported-language set. Coverage
checks the nine additional localized measurement/transport reports, regional
aliases (including legacy `in` to Indonesian), native/browser pack synchronization
and Arabic RTL document direction. Geometry and numeric inputs retain their axes.
All fifteen narrated H.264/AAC tutorials were completely decoded with FFmpeg.
Arabic, Hindi and Bengali text uses HarfBuzz, Unicode bidi ordering and FreeType;
the complete text sets were checked for missing glyphs and representative video
frames were inspected. Japanese uses a kana speech reading and Arabic a
vocalized reading; ordinary written captions remain unchanged.

Xcode now includes fifteen localized camera/GPS usage descriptions and declares
the supported bundle languages. CI verifies those files and all fifteen MP4s in
the app. Translations/synthetic voices need native-speaker review, the new layouts
need live browser/device review, and scan accuracy still needs physical trials.
The underlying RTAB-Map expert menus retain their upstream English strings.

## New 0.3 design, language and video checks

The Windows integration run passes **82 Node tests**, including six new tests
for MP4 delivery, byte ranges, HEAD, invalid ranges, WebVTT and complete
six-language video scripts. English is covered alongside German, French,
Spanish, Italian and Simplified Chinese in the UI, guide and report checks.
All six generated H.264/AAC videos were decoded completely with FFmpeg;
representative rendered frames were visually inspected, including Chinese
glyphs and captions. The illustrations are synthetic and do not validate scans.

The [native design build](https://github.com/lukashold/rtabmap/actions/runs/38152579818)
passed Xcode compilation before the additive bundled-video integration.
The current branch's Actions runs provide validation of that final integration
and Docker build. No signing or physical-device checks are implied.
The new desktop layout still needs a manual browser/device pass: browser
automation was unavailable during this design update. Translations and speech
still need review by native speakers.

## Recorded 0.2 validation

KANTURA is an independent development branch, not an App Store release. The
following separates implemented behavior, automated coverage, earlier preview
exercises and checks that still require a real device or external account.

## New 0.2 behavior and automated coverage

The local integration run passed **76 Node tests**: 39 existing baseline cases,
10 experience/RoomPlan cases, 14 report/DXF cases, 12 transport cases and a sequential-upload regression.
A Windows browser exercise imported a synthetic RoomPlan JSON with 10
measurements, including a 17.28 m² floor, then switched between two independent
rooms on ground/first floors while retaining a photo note and a −0.01 m reference
deviation. These synthetic checks are not field-accuracy evidence.

The [native CI run](https://github.com/lukashold/rtabmap/actions/runs/38149333091)
passed the Swift guide/RoomPlan Foundation checks, core build, Xcode app build
and unsigned IPA packaging. Signing, installation and LiDAR capture still need
the physical iPhone. The two-room browser project also survived upload and
reopening through the local server with its attached photo and reference check.
The viewer and transport form were also exercised at a 390-pixel viewport;
export buttons wrap and hidden icon labels retain accessible names.

- Native indoor RoomPlan capture exports `.kantura-room.json` and USDZ, stores a
  local library and groups separate captures by building and floor. Browser
  import uses the KANTURA schema. Conversion tests cover metre units, rigid
  column-major transforms, concave contour triangulation, invalid data and the
  deliberate absence of a floor area when no valid contour exists.
- Building archives preserve independently positioned room models, floor/name
  labels, measurements, photo notes and reference checks. Round-trip tests cover
  multiple rooms/floors and attached photos; malformed manifests, missing photos,
  unsafe paths and archive limits are rejected. No automatic spatial alignment
  or merged building plan is claimed.
- Manual 3D photo notes and reference comparisons are validated separately from
  scale calibration. Checks cover invalid coordinates, duplicate identifiers,
  unsafe image paths and reference deviations after a scale change. Source
  photos are resized for project storage; real iPhone photo-library selection
  and camera/provider behavior still need device checks.
- DXF tests cover metre units, concave floor outlines, scale application and
  text escaping. Report tests cover five languages, dimension tables, reference
  differences, optional floor plans, safe embedded photos and HTML escaping.
  Reports are downloaded HTML; PDF is created through the browser print dialog.
  These are active-room outputs, not merged building plans or certified drawings.
- Transport tests cover per-side clearance, sideways upright passage, continuous
  turn extrema, tilt transitions, uncertain versus orientation-independent blocked
  cases, finite bounds and deterministic results. Report tests recompute the
  verdict from saved inputs and validate translated assumptions, catalogue source
  matching and untrusted imported text. The estimate checks simplified rectangular
  envelopes, not collision-free movement through a full scanned staircase.
- The offline catalogue contains Bosch KGN39VLEA, Samsung RB34C600ESA/EF and LG
  GBP62PZNAC, with manufacturer URLs and a verification date of 2026-10-11.
  It does not perform live Internet lookup. Dimensions are for the unpacked
  products; Samsung's stated depth excludes its handle. The actual transported
  outline and the manufacturer's permitted handling orientation must be checked.

Run `pnpm test`, `pnpm check` and `pnpm build` from `tools/scan-workspace` to
reproduce the checks for your integration checkout. The results above describe
the tested revision; use the final integration/CI result for the release revision.

## Earlier preview baseline

The preceding preview had the following recorded checks. They establish a
baseline for the original workflow, not device validation of the new 0.2 paths.

- 39 Node tests covered distance/height, concave and vertical polygons, scale,
  calibration, project ZIP round trips, CSV/SVG, archive/path checks, OBJ/MTL,
  PLY and GLB loading, cloud request contracts and authenticated storage.
- A Windows/Edge browser exercise loaded a synthetic room, measured a distance
  and floor polygon, exported/reopened a project ZIP, and uploaded/reopened it
  through the local project library. The selected results remained 4.560 m and
  16.023 m² after round trips.
- Docker CI built the image, served the viewer, enforced authentication, saved
  and downloaded a ZIP, then read the same archive after container restart.
- Xcode 26.5 CI built the previous native app and produced an unsigned IPA;
  recovery/workflow and five-language guide checks passed. This does not prove
  that the new RoomPlan flow captures and exports correctly on an iPhone.

## Still requires real-world validation

1. Build and sign the current native revision on an Apple team, install it on
   the iPhone 17 Pro, and test camera permission, interruption/recovery, ordinary
   LiDAR scanning, RoomPlan recognition, its saved-room library and both exports.
   An unsigned IPA is not directly installable. See the [release plan](../../docs/APP-STORE-RELEASE.md).
2. Capture a real room and outdoor gate, transfer their files and compare several
   independently measured physical references. Check floor contours, openings,
   reflective/thin surfaces and coordinate alignment of imported annotations.
   Synthetic geometry and recognition confidence do not establish field accuracy.
3. Exercise multiroom save/reopen and each room's photo notes, PDF print layout,
   DXF import units in the intended CAD application, and transport input persistence
   with realistic data. Physically inspect the full transport route; the software
   does not model individual steps, railings, carriers or equipment as obstacles.
4. Register Google/Microsoft OAuth applications and verify real consent,
   upload/download, large files and interrupted uploads with the intended accounts.
   Existing API and popup tests use simulated responses. Test native Files export
   on an iPhone with the provider apps installed and signed in.
5. Check the deployed Docker revision, storage volume, access token, HTTPS and
   backup/restore procedure. Prior CI confirms its baseline; it does not verify a
   user's host, domain or provider registrations. Have native speakers review the
   fifteen translations in the actual device/browser layout before public release.

Cloud and self-host projects are explicit archive snapshots, with photos included.
There is no live synchronization, multi-user account system, server reconstruction,
automatic staircase path planning, automatic net wall area calculation, IFC/BIM
export or import of native AR measurements from RTAB-Map `.db` databases. RoomPlan
schematic captures and RTAB-Map textured scans remain separate acquisitions.

A final Alpine/Docker run exposed an upload completion race. The server now releases its upload guard after cleanup and before returning success; a 20-upload sequential regression covers this behavior.
