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
  "limits": { "uploadBytes": 209715200, "artifactBytes": 209715200, "expandedBytes": 1073741824, "maxQueuedJobs": 4 },
  "scaleStatus": "unverified",
  "hardwareValidated": false
}
```

Availability reflects installed executables/dependencies, not a tested physical reconstruction. CPU is supported but can be extremely slow. `accelerator` is the configured OpenSplat device (`cpu`, `cuda`, or native `mps`); the initial OpenMVS path uses CPU. `hardwareValidated` remains false in this development release.

## Submit and inspect

`POST /api/reconstruction/jobs?mode=mesh&name=My%20room` with `Content-Type: application/zip` and an accurate `Content-Length`. Upload body: ZIP of overlapping photographs, optionally the native `manifest.json` below. Returns **202**:

```json
{
  "job": {
    "id": "134c6a1d-dc64-4384-a0ce-31294a3fe618",
    "name": "My room", "mode": "mesh", "status": "queued", "stage": "queued",
    "createdAt": "2026-10-11T12:00:00Z", "updatedAt": "2026-10-11T12:00:00Z",
    "scaleStatus": "unverified", "imageCount": 36,
    "source": { "format": "kantura-photo-dataset", "version": 1, "captureMode": "object", "source": "apple-object-capture", "scaleStatus": "unverified" },
    "artifacts": [], "error": null
  }
}
```

`GET /api/reconstruction/jobs` returns `{ "jobs": [...] }`, newest first. `GET /api/reconstruction/jobs/<uuid>` returns `{ "job": {...} }`.

Status: `queued`, `running`, `complete`, `failed`, `cancelled`. Stage is informational: `queued`, `preparing`, `features`, `matching`, `mapping`, `undistorting`, `dense`, `meshing`, `texturing`, `training`, `validating`, then final status. There is no invented percentage. Failure exposes a bounded error code/message, not private worker logs. Restart marks an interrupted running job `failed` with `interrupted`; queued work resumes.

`POST /api/reconstruction/jobs/<uuid>/cancel` has an empty body and returns `{ "job": {...} }`. It terminates the worker process tree. Terminal jobs are left unchanged. Cancelled/failed jobs never expose partial artefacts.

Native dataset metadata is preserved in the job/result manifest, but cannot establish metric scale or camera poses:

```json
{"format":"kantura-photo-dataset","version":1,"id":"capture-id","name":"Capture","createdAt":"2026-10-11T12:00:00Z","source":"apple-object-capture","captureMode":"object","scaleStatus":"unverified","images":[{"file":"Images/IMG_0001.HEIC","bytes":123456}]}
```

At least eight actual images are required (the example omits the remaining entries). Paths and byte counts must match the ZIP. HEIC is decoded to JPEG for these workers; Apple metadata is retained in the original private ZIP, not interpreted as metric registration. Metadata conversion is best effort. Video, panorama stitching and native USDZ are separate capture/output routes, not accepted as photo-ZIP input here.

## Successful output

`complete` is assigned only after the real worker exits successfully and the service validates a result manifest, checksums, non-empty geometry and the required files. Each artifact has:

```json
{"name":"mesh.zip","mediaType":"application/zip","bytes":12500000,"sha256":"64-lowercase-hex-characters","url":"/api/reconstruction/jobs/134c6a1d-dc64-4384-a0ce-31294a3fe618/artifacts/mesh.zip"}
```

Fixed artifact allowlist:

| Mode | Required | Optional |
| --- | --- | --- |
| mesh | `mesh.zip`, `model.ply`, `reconstruction.json` | none |
| splat | `splat.ply`, `cameras.json`, `reconstruction.json` | none |

`GET /api/reconstruction/jobs/<uuid>/artifacts/<name>` streams an authenticated attachment. Each file is capped at **200 MiB (209715200 bytes)**, matching the current viewer's compressed-import limit; larger results fail explicitly and need a smaller source set/settings, not truncated downloads. The whole ZIP is validated before admission. The maximum expanded input is 1 GiB; result ZIP expanded size is capped at 500 MiB. The `model.ply` is a mesh, while `splat.ply` requires a Gaussian-splat renderer and must not be treated as an ordinary metric surface. Logs, source uploads, intermediate databases and arbitrary paths are never artifact routes.

Useful HTTP errors: 400 `invalid_mode`, `invalid_name`, `invalid_archive`, `invalid_manifest`, `unsupported_image`, `too_few_images`; 401 `unauthorized`; 404 `not_found`; 409 `busy`, `not_complete`; 411 `length_required`; 413 `too_large`; 415 `unsupported_media_type`; 503 `worker_unavailable`, `storage_full`. Photo registration can legitimately fail; no fallback mesh is fabricated.
