# Reconstruction API v1

Private HTTP service. All `/api/reconstruction/*` requests require `Authorization: Bearer <RECONSTRUCTION_TOKEN>` (at least 32 characters). The trusted front-end proxy may substitute its internal token after checking its own `SERVER_TOKEN`. No CORS or redirects. JSON errors use `{ "error": "code" }`.

`GET /health` is a public liveness probe, not evidence that a reconstruction succeeded.

## Capabilities

`GET /api/reconstruction/capabilities` returns:

```json
{
  "version": 1,
  "modes": [
    { "id": "mesh", "available": true, "engine": "COLMAP + OpenMVS", "accelerator": "cpu" },
    { "id": "splat", "available": true, "engine": "COLMAP + OpenSplat", "accelerator": "cpu" }
  ],
  "input": { "contentType": "application/zip", "extensions": [".jpg", ".jpeg", ".png", ".heic", ".heif"], "minImages": 8, "maxImages": 250 },
  "video": { "available": true, "contentTypes": ["video/mp4", "video/quicktime"], "durationSeconds": 180, "maxWidth": 4096, "maxHeight": 4096, "candidateFrames": 360 },
  "profiles": ["auto", "uav"],
  "limits": { "uploadBytes": 209715200, "artifactBytes": 209715200, "expandedBytes": 1073741824, "maxQueuedJobs": 4 },
  "scaleStatus": "unverified",
  "hardwareValidated": false
}
```

Availability reflects installed executables/dependencies, not a tested physical reconstruction. CPU is supported but can be extremely slow. `accelerator` is the configured OpenSplat device (`cpu`, `cuda`, or native `mps`); the initial OpenMVS path uses CPU. `hardwareValidated` remains false in this development release.

## Submit and inspect

`POST /api/reconstruction/jobs?mode=mesh&profile=auto&name=My%20room` with `Content-Type: application/zip` and an accurate `Content-Length`. Upload body: ZIP of overlapping photographs, optionally the native `manifest.json` below. Returns **202**:

```json
{
  "job": {
    "id": "134c6a1d-dc64-4384-a0ce-31294a3fe618",
    "name": "My room", "mode": "mesh", "status": "queued", "stage": "queued",
    "createdAt": "2026-10-11T12:00:00Z", "updatedAt": "2026-10-11T12:00:00Z",
    "scaleStatus": "unverified", "imageCount": 36, "inputType": "photos", "captureProfile": "auto",
    "source": { "format": "kantura-photo-dataset", "version": 1, "captureMode": "object", "source": "apple-object-capture", "scaleStatus": "unverified" },
    "artifacts": [], "error": null
  }
}
```

`GET /api/reconstruction/jobs` returns `{ "jobs": [...] }`, newest first. `GET /api/reconstruction/jobs/<uuid>` returns `{ "job": {...} }`.

Status: `queued`, `running`, `complete`, `failed`, `cancelled`. Stage is informational: `queued`, `preparing`, `extracting`, `features`, `matching`, `mapping`, `undistorting`, `dense`, `meshing`, `refining`, `texturing`, `training`, `validating`, then final status. There is no invented percentage. Failure exposes a bounded error code/message, not private worker logs. Restart marks an interrupted running job `failed` with `interrupted`; queued work resumes.

`POST /api/reconstruction/jobs/<uuid>/cancel` has an empty body and returns `{ "job": {...} }`. It terminates the worker process tree. Terminal jobs are left unchanged. Cancelled/failed jobs never expose partial artefacts.

Native dataset metadata is preserved in the job/result manifest, but cannot establish metric scale or camera poses:

```json
{"format":"kantura-photo-dataset","version":1,"id":"capture-id","name":"Capture","createdAt":"2026-10-11T12:00:00Z","source":"apple-object-capture","captureMode":"object","scaleStatus":"unverified","images":[{"file":"Images/IMG_0001.HEIC","bytes":123456}]}
```

At least eight actual images are required (the example omits the remaining entries). Paths and byte counts must match the ZIP. HEIC is decoded to JPEG for these workers; Apple metadata is retained in the original private ZIP, not interpreted as metric registration. Metadata conversion is best effort. Video is a separate raw-body input type described below. Panorama stitching and native USDZ are not photo-ZIP input.

## Successful output

`complete` is assigned only after the real worker exits successfully and the service validates a result manifest, checksums, non-empty geometry and the required files. Each artifact has:

```json
{"name":"mesh.zip","mediaType":"application/zip","bytes":12500000,"sha256":"64-lowercase-hex-characters","url":"/api/reconstruction/jobs/134c6a1d-dc64-4384-a0ce-31294a3fe618/artifacts/mesh.zip"}
```

Fixed artifact allowlist:

| Mode | Required | Optional |
| --- | --- | --- |
| mesh | `mesh.zip`, `model.ply`, `reconstruction.json` | `cameras.json` (current worker always writes it), `photos.zip` (video only) |
| splat | `splat.ply`, `cameras.json`, `reconstruction.json` | `photos.zip` (video only) |

`GET /api/reconstruction/jobs/<uuid>/artifacts/<name>` streams an authenticated attachment. Each file is capped at **200 MiB (209715200 bytes)**, matching the current viewer's compressed-import limit; larger results fail explicitly and need a smaller source set/settings, not truncated downloads. The whole photo ZIP is validated before admission. Video admission validates size and the ISO-BMFF header; actual probing/decoding occurs in the queued worker. The maximum expanded input is 1 GiB; result ZIP expanded size is capped at 500 MiB. The `model.ply` is a mesh, while `splat.ply` requires a Gaussian-splat renderer and must not be treated as an ordinary metric surface. Logs, source uploads, intermediate databases and arbitrary paths are never artifact routes.

Useful HTTP errors: 400 `invalid_mode`, `invalid_name`, `invalid_archive`, `invalid_manifest`, `unsupported_image`, `too_few_images`; 401 `unauthorized`; 404 `not_found`; 409 `busy`, `not_complete`; 411 `length_required`; 413 `too_large`; 415 `unsupported_media_type`; 503 `worker_unavailable`, `storage_full`. Photo registration can legitimately fail; no fallback mesh is fabricated.

## Video and aerial-photo input

Use the same POST endpoint with `Content-Type: video/mp4` or `video/quicktime`,
accurate `Content-Length`, and the raw local file body. `mode` remains `mesh` or
`splat`; `inputType: video` and `imageCount: null` describe a queued video until
frames have actually been selected. Modern MP4/MOV files must begin with an
ISO-BMFF `ftyp` atom; legacy MOV layouts are not accepted. Supported video codecs
are H.264, HEVC and MPEG-4, 4–180 seconds, up to 4096 pixels per side / 16,777,216
pixels, and at most 240 fps. Audio is ignored. The upload limit remains 200 MiB.

The decoder applies quarter-turn rotation metadata, samples the complete clip
at up to 2 fps (at most 360 candidates), and selects at most 250 frames using
uniform timeline bins, a sharpness/detail proxy, exposure and near-duplicate
rejection. At least eight usable frames must remain. Thresholds, rejected
candidate numbers/reasons and selected frames are recorded; there is no invented
camera trajectory. Approximate sample timestamps are explicitly labelled
`fps-filter-timeline-estimate`. A successful video job also publishes `photos.zip`
with selected JPEGs and a compatible `kantura-photo-dataset` manifest. It can be
reused as ordinary photo input. `input.video` remains private and unchanged.

`profile=auto` is the default; `profile=uav` labels an overlapping aerial capture
and records that GPS/altitude metadata is preserved only in the original input.
The UAV profile does not turn GPS metadata into camera poses, establish scale,
apply georeferencing, or promise a drone-specific reconstruction engine. Both
profiles follow the same reconstruction pipeline. Operators can inspect EXIF
lens grouping and quality diagnostics before accepting a result.

Additional errors: `invalid_profile`, `unsupported_video`, `video_duration`,
`video_dimensions`, `too_few_usable_frames`, `invalid_camera_policy`,
`invalid_sfm_model`, `insufficient_validation_views`. Malformed/short/static
videos fail explicitly; no replacement photos or geometry are fabricated.

## Quality and camera diagnostics

`reconstruction.json.registration` reports registered/input image counts and
fraction, sparse points, observations, mean track length, full COLMAP intrinsics,
and sparse-point reprojection error in pixels (mean, median, p95). Models above
100,000 sparse points use a bounded deterministic sample with a reported stride.
Low reprojection error alone does not prove correct geometry: repeated textures,
symmetric scenes and wrong feature matches can produce internally consistent
but incorrect reconstructions.

Each image has a 64-bit difference hash, Laplacian variance on a 128×128 grayscale
resample, exposure fractions and dimensions. Photo ZIPs retain all images and
report blur/detail/near-duplicate warnings; video selection can reject frames.
These are image diagnostics, not dimensional accuracy scores. `cameraGrouping`
records `auto`, `single` or `per-image` policy and its evidence.

For either mode, `cameras.json` is an array of
`{id,img_name,width,height,fx,fy,position:[x,y,z],rotation:[[...],[...],[...]]}`.
`position` is the camera center in the output's arbitrary similarity frame;
`rotation` maps camera coordinates to world coordinates. Camera axes are
**right/down/forward**. Match by `img_name`, not array index or engine-specific
`id`. Mesh intrinsics describe the registered pre-undistortion images (full
models remain in `registration.cameraModels`); OpenSplat exports its processed
image intrinsics. OpenSplat undoes its internal OpenGL Y/Z flip before publishing; the mesh export
reads the COLMAP convention directly.
No metric pose is injected and `scaleStatus` remains `unverified`.

Optional `training` diagnostics report actual OpenSplat loss samples (first
1,000 logged samples plus `lastLoss`), downscale factor and, when enabled,
withheld-image validation loss/PSNR. The deterministic withheld frame is excluded
only from splat appearance training; SfM uses all images. These are appearance
checks, not independent camera or measurement validation. Absent/nonfinite
engine metrics remain null rather than receiving fabricated scores.
