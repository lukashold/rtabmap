# Development validation — 0.6.0 preview

Recorded 12 October 2026. Source revision:
[`73f838608859abc13917d5a590ef514fe55537be`](https://github.com/lukashold/rtabmap/commit/73f838608859abc13917d5a590ef514fe55537be).
Local follow-up checks also include the not-yet-published panorama 2–40-image
regression and UI reset after that source commit. The head-specific CI results
below remain attached to their actual revision.

Kantura is an independent development fork, not a signed App Store release.
A passing build, a completed processing job, visually plausible geometry and
accurate physical measurements are separate claims.

## Current revision: completed local checks and running CI

| Check | Recorded result | Scope and limits |
| --- | --- | --- |
| Windows web suite, local follow-up | **152 Node tests passed** | Includes the new 2–40-image panorama-input regression, archive/model handling, authentic HTTP/proxy boundaries, mode/provenance handling, measurement policy, persisted camera warnings, Splat/panorama contracts and 15-language coverage. This count includes changes after the published commit; it does not establish live-browser rendering or device behavior. |
| Windows reconstruction suite, latest root run with isolated codecs | **85 cases: 82 passed, 3 skipped** | This supersedes the earlier environment's 78 passes/7 skips. Remaining environment/platform skips are explicit; this is not an all-85-executed result. The separate backend environment also reported three skips; do not sum the runs. |
| Independent fixture/evaluator suite | **10 tests passed** | Known synthetic cameras, similarity alignment, distinct/nonperiodic fixture checks, camera-collapse diagnostics and invalid-mesh reporting. Does not reconstruct the new fixture. |
| [Web/Docker CI 38208881346](https://github.com/lukashold/rtabmap/actions/runs/38208881346) | **Passed: 151 Node tests and workflow checks** | Published `73f8386` source; the newer local 152-test follow-up is not included in this run. |
| [iOS CI 38208881351](https://github.com/lukashold/rtabmap/actions/runs/38208881351) | **Pending at this report revision** | Current full unsigned app build and native checks; even success would not install or test the physical iPhone. |
| [Shared reconstruction CI 38208881350](https://github.com/lukashold/rtabmap/actions/runs/38208881350) | **Running; Linux contract/evaluator steps passed** | The 85-case reconstruction suite and 10 evaluator checks passed their CI steps. Engine build and subsequent real private-service/FFmpeg/mesh/Splat/video/panorama/generation/distinct-fixture work remain pending. No completed end-to-end result is claimed. |
| New 0.6 browser UI walkthrough | **Blocked** | Browser control returned a protocol/security error. Historical live checks below are not a new pass of the current four-mode interface or persistent-warning layout. |

Skipped tests remain visible. Process/queue tests use explicitly named fake
workers where appropriate; those test job lifecycle and artifact contracts,
not COLMAP, OpenMVS, OpenSplat or neural inference. The actual engine checks below
are recorded separately. Local code can implement a behavior while its final CI
or interactive acceptance remains pending.

## Confirmed 0.6 checks at the earlier `64f73de` revision

- [iOS run 38207033828](https://github.com/lukashold/rtabmap/actions/runs/38207033828) passed the full unsigned native build. It is evidence for that revision, not a signed installation, camera session or the newer head.
- [Web run 38207033794](https://github.com/lukashold/rtabmap/actions/runs/38207033794) passed **150 Node tests** and the viewer Docker build. The published head has 151 tests; the current local follow-up has 152.
- [Capture-engine run 38207033832](https://github.com/lukashold/rtabmap/actions/runs/38207033832) passed actual standalone **offline Docker panorama and TripoSR generation**. Its result artifacts are `11728160275` and `11727738474`. These are real engine runs, not fake-worker artifacts, and do not by themselves validate the shared API/proxy/browser path.

The panorama engine also passed 12 local Python checks using actual OpenCV,
including independent synthetic camera estimation, projection/seam behavior,
transparent unobserved regions, archive limits, HEIC/EXIF handling and preserved
original bytes. An actual eight-image CLI run produced a 2048 × 1024 spherical
PNG with approximately 61.98% observed solid-angle coverage. The service artifact
validator accepted that result's 2:1 shape, binary mask, exact alpha/mask agreement,
coverage calculation and hashes. Coverage is not depth or a measurement score.
Nine targeted Node checks cover the separate panorama viewer contract; they do
not replace an interactive WebGL test on the user's device.

TripoSR performed real inference with pinned code/weights and exported generated
geometry. It estimates unseen surfaces and uses arbitrary scale. Neither the
input being a real photograph nor a valid GLB proves the model's shape matches
the object. The generated-project policy keeps metric measurement and calibration
disabled. Inference appearance still needs human inspection on representative
inputs. Model availability and `hardwareValidated` are not interchangeable.

## Reconstruction quality: preserve the negative result

The periodic synthetic fixture has produced grossly incorrect camera geometry
although real mesh/Splat files were created. A more recent intermediate camera
evaluation recorded **3.7853170185965115** position RMSE and **83.59131004796656°**
median rotation error; **15 of 16** known opposing view pairs collapsed to nearly
the same estimated camera position. Position errors are in the synthetic scene's
units (cube side = 2), not demonstrated physical metres or iPhone error figures.
This result is **rejected for quality and unsuitable as measurement evidence**.

The older stored baseline is separate and unchanged: position RMSE
`3.7868876970054273`, position p95 `4.2006735602448275`, median rotation
`86.06900374959443°` and rotation p95 `179.59316083666428°`.
[Fixture definitions and criteria](../validation/QUALITY-FIXTURES.md) retain both
the difficult periodic case and a new distinct-texture case with identical
geometry/cameras. Known truth is outside the input ZIP and is not supplied to
the reconstruction engine. The distinct fixture's actual reconstruction and
quality outcome remain pending in the shared CI run above. An easier successful
case would not erase the periodic failure or establish real room/gate accuracy.

The evaluator now preserves camera results when a mesh has fewer than ten
sampled vertices in the expected cube region. It reports `mesh.valid:false`,
`too-few-cube-region-vertices`, actual counts, null distance statistics and zero
face coverage, rather than throwing away the entire evaluation. Invalid mesh
geometry cannot receive `qualityAccepted:true`. Criteria have not been relaxed
to turn the known failure green. The default evaluator writes adverse reports
without failing the CLI so multiple results can be collected; only the explicit
`--require-quality` gate exits nonzero on rejection. A green collection job must
therefore not be called a geometric quality pass without reading its reports.

The current browser source persists camera-quality warnings through project
save/import. Ambiguous camera positions or insufficient parallax block metric
measurement and calibration; a known reference cannot repair wrong geometry.
Repeated-view warnings alone do not block reference calibration. This behavior
has automated policy/archive coverage; its current visual presentation still
needs the blocked live-browser acceptance. No warning means only that these
heuristics did not flag a problem, not that the model is accurate.

## Reproduce the relevant checks

From `tools/scan-workspace`, with Node.js 24 and pnpm 11.25.0:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
```

From the repository root, in an environment with the matching dependencies:

```sh
python -m unittest discover -s tools/reconstruction/test -v
python -m unittest discover -s tools/validation/test -v
python -m unittest discover -s tools/panorama -p test_stitch.py -v
python -m unittest discover -s tools/generation/test -v
```

Read skip reasons, not only process exit status. The [reconstruction workflow](../../.github/workflows/reconstruction.yml)
runs actual container engines and a real job API separately from those unit tests.
The [API contract](../reconstruction/API.md) and engine READMEs describe limits,
original-data retention, generated provenance and artifact checks. No substitute
geometry is manufactured for a failed reconstruction. A job can still have
structurally valid output and fail independent scene-quality evaluation.

## Historical checks — earlier revisions only

These retain useful evidence without claiming that the new 0.6 screens or modes
received the same live acceptance.

- **0.5:** 130 Windows Node tests; 51 Python cases, 50 passed and one Windows symlink skip. [CPU run 38172402005](https://github.com/lukashold/rtabmap/actions/runs/38172402005), `fea9a0f`, built real COLMAP/OpenMVS/OpenSplat and processed 32 original synthetic images. Mesh/Splat downloads matched declared bytes and SHA-256. A real C++ exporter regression checked one/two texture atlases after the OpenMVS OBJ fix. Ten Splat iterations proved the path, not useful reconstruction quality. The later quality findings above supersede any inference that output existence meant accurate geometry.
- **0.5 browser:** synthetic Splat rendering/download/reimport, the actual trained Splat artifact, subject-focus camera framing and edge/corner selections worked. Closing the Splat view preserved a measurement. The native IIFE rendered over localhost under its CSP; this did not exercise iPhone WKWebView. The photo dialog switched all 15 languages at 390 × 844 without horizontal overflow, including Arabic RTL. The local service honestly reported missing Windows engines.
- **0.5 native:** [run 38169729389](https://github.com/lukashold/rtabmap/actions/runs/38169729389), `83de2ed`, passed Swift/native Foundation checks and unsigned packaging. This is superseded for build coverage by the recorded 0.6 run, never by a physical-device claim.
- **0.4.1 usability:** 88 Node tests. Live browser at 1280 × 720 and 390 × 844 exercised German entry/RoomPlan guidance, a synthetic 2.828 m distance, a 2.61 m² floor polygon, two-floor archive import, room switching, report download and video playback. All 15 languages were selected without horizontal overflow. Sidebar/mobile ordering and an MP4 client-disconnection server error were fixed and rechecked. These were synthetic interaction checks.
- **0.4 languages:** 85 Node tests; fifteen dictionaries/guides/video scripts synchronized, Arabic RTL and aliases covered. All fifteen narrated synthetic H.264/AAC videos fully decoded, representative frames/glyphs inspected. Japanese kana and Arabic vocalized speech readings are separate from ordinary captions. This was not native-speaker or assistive-technology acceptance. RTAB-Map expert menus retain English.
- **0.3:** 82 Node tests and six-language video delivery/caption coverage. [Native design run 38152579818](https://github.com/lukashold/rtabmap/actions/runs/38152579818) passed before subsequent video integration; this remains historical build evidence only.
- **0.2:** 76 Node tests. A synthetic RoomPlan import showed 10 dimensions and 17.28 m² floor area; separate rooms retained a photo note and −0.01 m reference deviation across switching and server archive roundtrip. [Native run 38149333091](https://github.com/lukashold/rtabmap/actions/runs/38149333091) passed Foundation/core/app build and unsigned packaging. Tests covered genuine-contour floor areas, project roundtrips, notes/references, DXF/report output and conservative transport envelopes. A 20-upload sequential regression covered a later upload-guard race.
- **Initial preview:** 39 Node tests; synthetic model and archive/server roundtrips retained selected 4.560 m and 16.023 m² results. Docker checked authenticated persistence across restart; earlier Xcode CI produced an unsigned IPA. These values are chosen synthetic measurements, not real scan accuracy.

## Still requires physical or deployment-specific acceptance

1. Sign the current build with an Apple team, install it on the iPhone 17 Pro and exercise camera permissions, interruptions, recovery, LiDAR, RoomPlan, saved-room exports, guided photo sets, Apple Object Capture/local photogrammetry, video, panorama and the one-image source path. An unsigned IPA is not directly installable. Native preview heuristics do not validate 3D quality. See the [release plan](../../docs/APP-STORE-RELEASE.md).
2. Capture a real room and outdoor gate twice, use several independent physical references, inspect floor/door/window contours and thin or reflective parts, and publish deviations. Check calibration and scale against those references. Neither synthetic geometry nor RoomPlan category confidence establishes accuracy. Native GPU/WKWebView, CUDA and native Apple MPS remain unvalidated on the intended hardware.
3. Complete the current browser pass: actual panorama/Splat/generated results, all four jobs, cancellation, persistent warnings, saved/reopened provenance, narrow screens, keyboard, RTL, zoom and error recovery. Exercise VoiceOver/Dynamic Type and have native speakers review all 15 languages. The new automated tests do not fill the blocked UI check.
4. Register Microsoft/Google clients and verify real consent, upload/download, large-file/interruption behavior and provider revocation. Test native Files with installed, signed-in providers. Cloud unit tests use simulated responses; no real-account success is claimed.
5. Check the user's deployed Compose revision, HTTPS/token configuration, worker capability status, RAM/disk behavior, originals/artifacts, restart and both storage volumes' backup/restore. The optional generation build needs pinned weights/Torch and a suitable memory allowance. CI on another host does not validate that deployment.
6. Check room archives, real photo notes, PDF printing, CAD/DXF metre units and saved transport inputs. The transport calculation is a simplified envelope check, not a collision path through a scanned staircase. Separate room/etage organization is not spatial alignment; drone inputs are not GPS-georeferenced.

Cloud and self-host saves are explicit archive snapshots, including photos.
Four reconstruction job modes are implemented; their completed common-API
acceptance remains pending as recorded above. There is no automatic native cloud
synchronization, personal multi-user account system, registered whole-building
alignment, automatic staircase path planner, automatic net wall area calculation,
IFC/BIM export or reconstruction of RTAB-Map `.db` files by this photo worker.
RoomPlan schematic captures and RTAB-Map textured scans remain separate sessions.
