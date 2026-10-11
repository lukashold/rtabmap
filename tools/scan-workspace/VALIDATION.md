# Development validation — 0.3 preview, 2026-10-11

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
   five translations in the actual device/browser layout before public release.

Cloud and self-host projects are explicit archive snapshots, with photos included.
There is no live synchronization, multi-user account system, server reconstruction,
automatic staircase path planning, automatic net wall area calculation, IFC/BIM
export or import of native AR measurements from RTAB-Map `.db` databases. RoomPlan
schematic captures and RTAB-Map textured scans remain separate acquisitions.

A final Alpine/Docker run exposed an upload completion race. The server now releases its upload guard after cleanup and before returning success; a 20-upload sequential regression covers this behavior.
