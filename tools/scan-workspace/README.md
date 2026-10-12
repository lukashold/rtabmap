# KANTURA measurement workspace — 0.6.0 preview

A browser workspace for measuring room scans and outdoor objects such as gates. Import a KANTURA RoomPlan capture or a textured model, organize separate rooms by building and floor, add measurements and photo notes, and save a portable project archive. The guided interface, tutorial, reports and animated videos support 15 languages: German, English, French, Spanish, Italian, Simplified Chinese, Portuguese, Arabic, Hindi, Bengali, Russian, Japanese, Korean, Indonesian and Turkish.

Version 0.6.0 adds guided native photo/video/panorama inputs, a local panorama
viewer, real spherical stitching, bounded video-frame selection and optional
single-image 3D generation. The browser submits all four processing modes through
one private queue. The native camera stores original inputs; it does not perform
TripoSR generation or OpenSplat training on the phone. See the
[Polycam capability roadmap](../../docs/POLYCAM-ROADMAP.md),
[capture quality guide](../../docs/CAPTURE-QUALITY.md) and
[independent implementation rules](../../docs/INDEPENDENT-IMPLEMENTATION.md).

Implementation and acceptance are separate. The recorded 0.6 baseline has
[152 web tests and a viewer Docker build](https://github.com/lukashold/rtabmap/actions/runs/38209256050),
an [unsigned full iOS build](https://github.com/lukashold/rtabmap/actions/runs/38208881351)
and [real offline panorama/TripoSR Docker runs](https://github.com/lukashold/rtabmap/actions/runs/38207033832).
The [combined real-service run](https://github.com/lukashold/rtabmap/actions/runs/38210549928) passed all seven synthetic jobs and 88 Linux server tests; the distinct-texture quality fixture passed, while the periodic fixture remains rejected. Neither result establishes physical iPhone accuracy.
The combined service run includes the corrected video decoder and isolated Python
runtime detection. It confirms that CI host, not every deployment or interactive
browser/device flow.
Signed device, actual scan quality and cloud-account checks remain open. Later runs
and current totals are recorded in [VALIDATION.md](VALIDATION.md).

## Local coordinate review (web development preview)

Choose **Check coordinates** on the home page, or in a measurable project's tools.
The advanced dialog calculates locally and has all 15 interface languages.

For room/floor registration, place at least three manual 3D photo notes on shared
physical corners, named A/B/C in the same order in both captures. They must not all
lie on a straight line. The active project's notes are prefilled in metres in its
centred Y-up viewer frame. Export the anchor JSON from the reference capture and
paste it as the target in the source capture. Labels do not automatically match
or reorder points. Without overlapping identifiable points, do not invent a fit.
The rigid fit reports a column-major source-to-target matrix and every residual;
it never fits scale or a reflection. A supplied tolerance checks those pairs only;
without one, the candidate remains explicitly unreviewed. Uncalibrated photo or
suspect/generated model contexts cannot supply metric anchors.

The GPS tab converts an explicitly entered WGS84 point relative to an explicitly
entered origin: ECEF → ENU → viewer [east, up, -north]. Ellipsoidal height is
mandatory; MSL/orthometric/unknown EXIF height is rejected. Optional uncertainty
estimates remain attached to each input; no combined precision is invented.
This single-point converter does not georeference a photograph or a scan.

Anchor/candidate JSON preserves source/target frames, labels and synthetic-example
provenance. Candidates always retain `metricAccuracyValidated:false`,
`appliedToModel:false` and `automaticBuildingMerge:false`. The dialog changes no
models and saves nothing to a server. Its controlled mathematical/input tests do
not establish physical surveying accuracy or current visual-browser acceptance.

## Optional edge and corner assistance

Enable **Snap to edges/corners** when selecting measurement points. Assistance is
off by default, uses a 12-CSS-pixel radius and shows the proposed/selected point.
It uses static mesh boundaries and creases of at least 30 degrees in world space,
excluding coplanar triangle diagonals and straight tessellation vertices. Mesh
boundaries may also be holes or scan artifacts: assistance does not recognize
architectural components or correct scan errors. Existing measurements are not
silently changed. Disable assistance for free point selection.

Extraction is capped at 100,000 triangles and 20,000 eligible edge segments. If a
model exceeds those limits, no partial snap index is used. Point clouds, skinned
or instanced meshes, morph targets and partial triangle draw ranges remain freely
measurable without assistance. Clipped/occluded points are filtered, with a bounded
visibility-check budget. Dense scenes still need real-device performance tests.

## Reconstruction modes and Gaussian splats

The splat viewer is separate from the measurement model. It reads validated
`.splat` or supported Gaussian `.ply` files with anisotropic scales, rotation and
opacity; ordinary PLY meshes retain the original import path. The renderer shows
the base spherical-harmonic color, retaining the original file for download.
Splats have no trustworthy selectable mesh surface and do not automatically
establish metric scale, so the splat view does not expose measurement tools.

Camera framing implementation: `splat-focus.js` reads at most 8192 evenly spaced
position samples from the canonical splat records. It linearly interpolates the
5th and 95th percentiles independently on each axis to frame the central area.
This explicit **Zoom to subject** action changes only the camera; it neither
removes points nor changes positions, Gaussian sizes or original file bytes.
The initial/full-view action retains the complete bounds including Gaussian
scales, and the focus view's far plane still accommodates that full extent.

Choose the processing mode explicitly. Reconstruction jobs require a configured
private worker, its access token and an explicit upload. The same-origin proxy
keeps the internal worker address and token out of public configuration. A static
viewer alone does not provide these jobs.

| Mode | Input | Result and measurement boundary |
| --- | --- | --- |
| Photo mesh | 8–250 overlapping JPEG/PNG/HEIC/HEIF photos in a ZIP, or supported MP4/MOV | COLMAP/OpenMVS textured OBJ ZIP and PLY; scale starts unverified |
| Gaussian splat | The same photo/video input | Actual OpenSplat Gaussian PLY; a separate visual view without measurement tools |
| Photos → 360° | 2–40 overlapping photos in a ZIP, rotating about the same camera center | OpenCV spherical PNG plus coverage mask and exact original ZIP; no depth or measurements |
| Single image → AI 3D | One JPEG/PNG, at most 20 MiB | Optional TripoSR generated model; unseen sides are inferred, with measurement and calibration disabled |

The **aerial/UAV profile** labels mesh/splat input. It uses the same pipeline;
GPS metadata does not establish georeferencing, physical scale or a flight plan.
Video accepts H.264/HEVC/MPEG-4 in modern MP4/MOV, 4–180 seconds, at most 4096
pixels per side and 200 MiB. The worker selects frames using timeline coverage,
image-detail/exposure checks and duplicate rejection; selected JPEGs are also
exported. It does not invent camera motion. Full limits and output allowlists
are in the [API contract](../reconstruction/API.md).

No job is complete merely because upload or queueing succeeded. The worker must
finish and pass artifact, geometry, provenance and checksum validation. Completed
files can still contain a poor reconstruction. Inspect camera/quality warnings,
original photos and the model before accepting it. The periodic synthetic test
scene produced incorrect camera geometry and is **not quality accepted**; more
training or one reference length does not repair that failure.

Photo geometry needs a known reference before metric measurement is enabled.
Warnings about inconsistent camera positions or insufficient viewpoint motion
also block calibration and measurement; recapture the scene. Repeated-view
warnings alone allow a reference check/calibration but call for more varied views.
Warnings are retained with the project. These safeguards are heuristics, not a
certificate that an unflagged model is accurate. See [capture checks](../../docs/CAPTURE-QUALITY.md).

### Local panorama view and actual stitching

Open an existing equirectangular JPEG/PNG with exactly 2:1 aspect ratio in the
separate panorama view (at most 32 MiB and 8192 × 4096 pixels). Mouse, touch and
keyboard turn the view about a fixed center. Up to eight images are separate
viewpoints, not a registered virtual tour. Opening these files is local and does
not upload them. Unknown regions of stitched PNGs remain transparent.

For a new panorama, upload the overlapping photo ZIP in **Photos → 360°**. Rotate
in place; walking around an object belongs to photo mesh/splat capture. The real
stitcher places observations on a full spherical canvas and leaves missing
sky/floor directions empty. It does not stretch a cropped image or fill missing
regions with AI. The result preserves the original ZIP and a coverage mask;
coverage is not depth or an accuracy score. See [stitcher details](../panorama/README.md).

### Optional generated 3D

Use a transparent PNG with visible foreground, or explicitly confirm that an
opaque JPEG/PNG already shows an isolated object on a plain neutral background.
This confirmation is not automatic background removal. The server must have
TripoSR enabled at build time; the default image leaves it unavailable. It adds
about 1.68 GB of pinned weights plus an isolated CPU Torch runtime; 12 GiB memory
is a planning allowance, not a measured performance promise. Runtime processing
uses installed models offline. See [server setup](README-server.md).

A camera photograph is the original input; the resulting geometry is still
**AI-generated**, including unseen sides. Its arbitrary units cannot be converted
into reliable object dimensions with one known length. The generated-project
archive preserves that provenance when saved/reopened. Measurement, calibration,
metric reporting and fitting decisions are unavailable for this mode. Notes and
visual inspection remain useful. This mode never substitutes for a failed scan.

## Learn and contribute

Choose **Learn** to watch the locally hosted video in the selected interface language. All 15 MP4s include narrated animated examples and burned-in captions; downloadable WebVTT/SRT captions and the text transcript are included. These are original synthetic examples, not recordings of a real scan. The native dashboard plays the same bundled MP4s offline. Voices are synthetic and many use simpler formant voices. See [video sources and regeneration](../../docs/video-voices.md).

The overview offers separate paths for rooms, houses and outdoor models. Open a project or try the synthetic example, then return to the overview without losing the current measurements. [Contributor instructions](../../CONTRIBUTING.md) are available in all 15 languages, with issue forms prepared for bugs, features and translations. The repository owner must enable Issues in GitHub Settings.

The 0.4.1 usability pass separates RoomPlan and textured LiDAR instructions, explains each import path, places measurement tools and the model first on narrow screens, and improves contrast, touch targets, dialog names and visible error states. Live browser checks cover synthetic measurements, house import, room switching, report download and all 15 language switches at a 390-pixel viewport. Signed iPhone capture, native accessibility and independent beginner acceptance remain open. See the [MetaRoom comparison and acceptance checklist](../../docs/usability-review.md).

The nine additional language packs are in `locales/<code>.json`; run `pnpm locales:sync` after editing to update the native guide and video scripts. Arabic uses RTL while models and numeric controls retain their coordinate conventions. Portuguese currently uses European terminology, Chinese uses Simplified Chinese and Arabic uses Modern Standard Arabic. These 15 choices combine the user's existing languages with broad regional coverage; they are not an official ranking of languages. The underlying RTAB-Map expert menus retain upstream English strings.

KANTURA is an independently developed RTAB-Map fork; the current source branch is [kantura/main](https://github.com/lukashold/rtabmap/tree/kantura/main). This workspace is its optional browser companion. Automatic indoor surface recognition runs in the native iOS RoomPlan mode; the browser imports its results. It does not capture LiDAR, reconstruct RTAB-Map databases, automatically align separate rooms, or promise survey-grade accuracy. The workflow takes inspiration from [Metaroom's guided capture](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/), with original interface code and content. See the [feature comparison and remaining work](../../docs/KANTURA-FEATURES.md) and [validation status](VALIDATION.md).

## Start on a computer

Use Node.js 24 and pnpm 11.25.0. Run from this directory in a complete repository checkout:

```sh
corepack enable
corepack prepare pnpm@11.25.0 --activate
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Open `http://localhost:4173`. The server binds to the local computer by default. A modern browser with WebGL is required. The built `dist` directory can also be served by an ordinary static HTTP server. Do not open `index.html` with `file://`; the app loads configuration and modules over HTTP. The build needs `app/ios/RTABMapApp/MeasurementGuide.json`, so copying only this tools directory before building is insufficient.

## Self-host with Docker

From the repository root:

```sh
docker compose -f tools/scan-workspace/compose.yaml up --build -d
```

Open `http://localhost:8090`. This serves the interface and tutorial pages on your own computer. See [server storage and deployment](README-server.md) for the optional persistent project library, its access token, volume, API and reverse-proxy configuration. Static-only hosting and server-side project storage are separate deployment choices.

The compose port is bound to `127.0.0.1`. For access from another computer, configure the documented reverse proxy and HTTPS on your own domain. Do not publish a write-enabled project library without access protection. The operator supplies public OAuth client IDs if direct cloud buttons are required; Docker does not create Microsoft or Google registrations.

## Capture indoor rooms with RoomPlan

This flow requires the KANTURA development app on a supported LiDAR iPhone/iPad with iOS 17 or later. Installing the official upstream RTAB-Map App Store app does not install these fork additions. Follow the [signing and installation plan](../../docs/APP-STORE-RELEASE.md) on the Mac; the Docker server does not install or sign an iPhone app.

1. Choose **Automatic room plan** in KANTURA, start capture and follow the camera guidance while walking slowly around one indoor room. Show walls, floor, doors and windows from different angles.
2. Finish capture and inspect the detected elements, their dimensions and recognition confidence. Check physical reference dimensions. Confidence is a recognition signal, not a measurement accuracy certificate.
3. Enter the building/project, floor and room name, then choose **Save and export**. KANTURA stores a local copy in its `KanturaRooms` library and exports two files: `.kantura-room.json` for this workspace and `.usdz` for a compatible 3D viewer.
4. **Saved room plans** groups captures by building and floor and opens the detected dimensions, 3D preview and export. Capture the next room separately. Each capture has its own coordinate origin; grouping does not join them into one spatial model.
5. Transfer the JSON through Files, OneDrive, Google Drive or another route. On the computer choose **Open file** and select the `.kantura-room.json` alone. The workspace generates a schematic model with imported element dimensions and valid captured floor contours. Use **Add room** for subsequent individual room files, then switch rooms in the room list. Edit building, floor and room labels as needed.
6. Save the workspace as a `.kantura-building.zip`. It includes the independent room models, names, floors and annotations. Reopen this archive to resume. Opening another file replaces the workspace after the unsaved-change prompt; **Add room** appends a room instead.

RoomPlan creates schematic geometry without photographic textures. The browser supports the KANTURA JSON schema, not arbitrary Apple `CapturedRoom` JSON or USDZ import. A missing or invalid floor contour is not invented. Windows and doors are separate classified surfaces; their areas are not automatically subtracted from gross wall areas. Retain the native exports as originals. Textured RTAB-Map scans and RoomPlan captures are separate acquisitions and are not automatically registered together.

## Measure a textured scan or outdoor gate

1. On iPhone, capture in normal Mapping with LiDAR enabled. Save the original `.db`.
2. Assemble an optimized textured mesh and export the OBJ ZIP including its MTL and images. Use the iOS Files export to save to an installed, signed-in OneDrive or Google Drive provider, or transfer the ZIP another way.
3. Open that ZIP in the workspace. Confirm the unit and up axis; RTAB-Map models normally use metres and Z up. Inspect holes, duplicated surfaces and thin gate parts before measuring.
4. Select **Distance** and click two points. The result includes straight-line length, horizontal distance and height difference.
5. Select **Floor area**, click the floor corners in order, then finish. Top view and hiding the roof help. Concave outlines are supported; crossed outlines and duplicate points are rejected. Floor points must be approximately horizontal. Use **Surface area** for a planar wall or gate face.
6. Compare several distances against tape measurements. **Reference check** stores a selected distance and its known physical length, showing the difference in metres and percent. This check does not change the scale. **Calibration** changes the global scale using a known reference; it cannot repair local warping. Save the project archive before closing the page.

These mesh measurements use manually selected points and polygons. Automatic indoor recognition belongs to the separate RoomPlan flow above. An SVG or DXF draws the room's available floor outlines, including valid imported RoomPlan floors. A textured surface shows visual context; its appearance alone does not establish geometric accuracy. Use the ordinary LiDAR/RTAB-Map scan mode for an outdoor gate, then check thin or reflective parts against physical measurements.

## Photo notes, reports and CAD

- Choose **Add note**, click a position on the model, and enter a title, type and description. Attach a JPEG, PNG or WebP photo if useful. Photos are resized to at most 1,600 pixels on the longest side and stored as JPEG inside the project archive. Input photos are limited to 12 MiB and 50 megapixels. A photo note is manually placed; it is not an automatically localized camera frame or an additional geometric measurement.
- **Report / PDF** downloads a self-contained HTML report for the active room. Open that downloaded file, choose **Print / save as PDF**, and select the browser's PDF destination. The report includes measurements, reference comparisons, the available floor plan and embedded note photos. A recorded transport check is recalculated from its stored inputs and included with assumptions and clearance results. There is no automatic server-side PDF conversion.
- **DXF** exports the active room's floor outlines as closed polylines with separate dimension lines and labels in metres. These labels are not associative CAD dimensions: editing a contour in CAD does not update them. Check CAD import units. SVG and the report are schematic drawings; printing does not establish a fixed drawing scale.
- Export each room's report/DXF separately. The building archive preserves the whole collection; it does not produce a merged floor plan or BIM model.

## Refrigerator and staircase transport estimate

Choose **Check transport** and either search the built-in manufacturer catalogue or enter the actual outer dimensions manually. The catalogue contains exactly three model entries, checked against manufacturer pages on 2026-10-11: Bosch **KGN39VLEA**, Samsung **RB34C600ESA/EF**, and LG **GBP62PZNAC**. It is an offline catalogue, not an automatic Internet search. Follow the source link and match the complete model suffix. For unlisted models, use the manufacturer's data sheet and a physical check.

Enter all lengths in **metres**: object width, depth and height; the narrowest clear passage width; minimum clear height; landing width and depth; a matched rise and horizontal run from the same straight stair section; turn angle in degrees; and clearance **per side**. For example, 600 mm is 0.600 m and a 0.05 m margin reserves 5 cm on each side. Select the optional stair tilt check and run the estimate. The preview slider shows the sampled envelopes. A single step pair (for example 0.18 m rise and 0.28 m horizontal depth) or a matched flight pair gives the slope; do not enter a sloping length or mix different sections. Only this slope is used, not individual step geometry or the total route length.

The calculation tests upright/sideways rectangular envelopes, a centred turn on a rectangular landing, and optionally tilting along the stair slope including its transition. **Possible in the tested envelope** means that simplified sufficient condition fits. **Further checking needed** means the tested paths do not establish a fit; a translated turn or another orientation may still work. **Passage too small** is reserved for the minimum object dimension plus the chosen margins exceeding a mandatory passage width or clear height.

This is not a collision simulation through the scanned staircase. Individual steps, railings, sloped ceilings, people and transport equipment are not represented as obstacles. Measure every bottleneck, allow for handles, hinges, packaging and equipment, and check the manufacturer's allowed transport orientation. In particular, Samsung's listed depth excludes the handle; LG's packaged dimensions differ from its catalogue object dimensions. The estimate is not a guarantee of access or safe handling.

With a room open, the most recently calculated transport inputs belong to that room and are preserved when you save its project archive. The report recalculates the result from those stored inputs. Editing form fields alone does not update the recorded assessment: run the calculation again, then save/export. Route dimensions are entered manually; they are not automatically extracted from the scan.

## Files and limits

| Input/output | Support |
| --- | --- |
| OBJ ZIP | One OBJ model, optional MTL and bundled texture images |
| Separate OBJ + assets | Select the OBJ, MTL and image files together |
| PLY | Mesh or point cloud; vertex colours when present |
| GLB | Self-contained binary glTF supported by the bundled loader; unsupported compression extensions need conversion first |
| `.kantura-room.json` | One KANTURA RoomPlan capture: metre-based surfaces, dimensions, transforms, confidence and optional building/floor labels |
| `.kantura-building.zip` | Up to 100 independently positioned rooms and their assets, floors, measurements, notes, reference checks and recorded transport inputs |
| `.rtabmeasure.zip` | Existing single-room project archives remain readable |
| CSV | Measurement results in explicit metric units |
| SVG / DXF | Active room floor contours, lengths and areas; DXF uses metre units |
| HTML report / PDF | Download an offline report, then use the browser's print-to-PDF function |
| USDZ | Native RoomPlan export for compatible viewers; not an input to this browser workspace |
| RTAB-Map `.db` | Keep as original; reconstruct/export with RTAB-Map before opening here |
| Gaussian `.ply` / `.splat` | Separate splat view; no mesh measurements |
| 2:1 JPEG/PNG panorama | Separate spherical view, up to 32 MiB and 8192 × 4096; no depth |
| Photo ZIP / MP4 / MOV | Explicit worker job input, not direct measurement-model import |
| Single JPEG/PNG for AI 3D | Explicit optional generated job; resulting project retains generated provenance |

Input is limited to **200 MiB** compressed/selected data, **500 MiB** declared and actual uncompressed ZIP content, and 2,000 ZIP entries. A raw scan import contains one model; a building archive can contain up to 100 independent room models under the same total archive limits. Add individual scans with **Add room**; nesting a building archive as one room is unsupported. RoomPlan exchange accepts at most 150 surfaces and 100 contour points per surface. The viewer limits geometry to 10 million vertices; memory limits of individual computers can be lower. Assets with unsafe paths, ambiguous references or external URLs are rejected. Large scans may need simplification in RTAB-Map before import.

## OneDrive integration

The iOS Files route works through the installed provider app and does not need OAuth IDs in this project. The web workspace additionally supports explicit upload/list/open of its project ZIPs through Microsoft Graph.

1. Register an application in [Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app). For the configured `common` authority, enable accounts in any organizational directory **and personal Microsoft accounts**.
2. Add the **Single-page application** platform with `http://localhost:4173/auth.html` for development, `http://localhost:8090/auth.html` for the default Docker URL, and the exact production URL, for example `https://scan.example.org/auth.html`. Use the same hostname when opening the app. See [redirect URI setup](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri).
3. Add the Microsoft Graph **delegated** permission `Files.ReadWrite.AppFolder`. The application uses `/me/drive/special/approot`; access is confined to its app folder. This works with home and work/school OneDrive, subject to the organization's consent policy. See [app folder permissions](https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder).
4. Copy the **Application (client) ID** into the workspace's cloud configuration, or provide `MICROSOFT_CLIENT_ID` to the server/container. Do not create or enter a client secret for this browser application.
5. Connect, upload a project, refresh the list and reopen it to verify geometry, textures, scale and measurements.

MSAL Browser 5 uses the bundled `auth.html` redirect bridge. Serve it without `Cross-Origin-Opener-Policy`; a reverse proxy must preserve that requirement. Microsoft explains the constraint in its [redirect bridge guide](https://learn.microsoft.com/en-us/entra/msal/javascript/browser/redirect-bridge).

## Google Drive integration

1. Create a Google Cloud project, enable the Google Drive API, configure the OAuth consent screen/audience, and add your test account while the application is in testing.
2. Create an OAuth client of type **Web application**. Add the exact authorized JavaScript origins: `http://localhost`, `http://localhost:4173`, `http://localhost:8090`, and your production origin such as `https://scan.example.org`. Origins contain no path. This implementation uses the GIS token popup, so it does not use a Google `auth.html` callback. See [Google client-ID setup](https://developers.google.com/identity/oauth2/web/guides/get-google-api-clientid).
3. Configure `https://www.googleapis.com/auth/drive.file` as the requested scope. It provides limited per-file access and is classified as non-sensitive; public deployment still needs the applicable OAuth branding/verification steps. See [Google Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).
4. Copy the public client ID ending in `.apps.googleusercontent.com` into cloud configuration, or provide `GOOGLE_CLIENT_ID` to the server/container. Do not enter a client secret.
5. Connect, upload a project and reopen it after refreshing the list. The app marks its created files with `appProperties.rtabMeasure=1` and lists these project packages. It does not include a Google Picker or enumerate arbitrary Drive folders.

Use the same origin throughout setup and testing; `localhost` and `127.0.0.1` are different origins. Allow the sign-in popup. For an existing raw scan in either provider, download/synchronize it and use **Open file**. Project uploads create timestamped files instead of replacing existing files.

## Data flow and operating status

Opening and measuring a local model happens in the browser. Downloaded building ZIPs contain room models, measurements and photo notes; closing an unsaved browser session loses those edits. Cloud uploads occur only after the user chooses to upload. Optional self-host storage similarly requires an explicit save. Notes and their attached photos are included when the archive is uploaded or shared; review them before sharing. Manufacturer links open external websites when selected, but catalogue filtering itself does not send the search query online.

OAuth access tokens are kept in browser memory. Public client IDs and the chosen language may be saved in browser storage. Signing in contacts the selected identity provider; scans uploaded to a cloud provider are governed by that provider and account. Disconnecting clears this app's cached credentials; use the provider's account settings to revoke a grant completely. Server library storage and operator responsibilities are described in [README-server.md](README-server.md).

Cloud adapters have automated tests with simulated API responses. Real provider registration, consent, upload/download, large-file behavior and network interruption need validation against the deployment's actual accounts. An interrupted upload is reported as an error; automatic cross-session recovery is not implemented. Native camera behavior and measurement accuracy require real-device tests. No credentials, App Store approval or accuracy certification are supplied by this repository.

## Development

`pnpm test` covers measurement geometry, scale/calibration, RoomPlan conversion, multiroom archive round trips, photo-note/reference validation, CSV/SVG/DXF/report export, transport envelopes, server behavior and cloud request boundaries. `pnpm check` checks JavaScript syntax; `pnpm build` produces the static assets. See [VALIDATION.md](VALIDATION.md) for the distinction between automated checks, earlier preview exercises and pending real-device/provider checks. Keep tutorial content in `app/ios/RTABMapApp/MeasurementGuide.json` consistent with the native and desktop flows. See the [German measurement walkthrough](../../app/ios/MEASUREMENT-WORKFLOW.md) and [independent App Store release plan](../../docs/APP-STORE-RELEASE.md).

The repository's [BSD license](../../LICENSE) applies to project code. Preserve
bundled web notices and inspect each engine/model's separate license before
distribution. OpenMVS/OpenSplat and bundled HEIC codec binaries are not uniformly
BSD-licensed. See [worker licenses](../reconstruction/THIRD-PARTY.md),
[panorama licenses](../panorama/THIRD-PARTY.md) and
[generation code/weights](../generation/THIRD-PARTY.md). Native dependencies also
need a separate App Store audit; the current build is not a cleared release.
