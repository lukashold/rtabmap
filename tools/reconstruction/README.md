# Kantura photo reconstruction service

Real, separate reconstruction programs behind a private queued HTTP API:

1. Decode overlapping JPEG/PNG/HEIC photos; retain the original ZIP privately.
2. COLMAP extracts/matches features, estimates cameras and sparse 3D points.
3. **Mesh:** OpenMVS computes dense geometry, a surface and an OBJ with textures.
4. **Gaussian splat:** OpenSplat optimizes actual 3D Gaussians from the registered
   images/points and writes a splat PLY and cameras JSON.

No output is invented when registration, reconstruction or training fails. A
successful process exit is insufficient: expected files, geometry headers,
manifest and SHA256 values are validated before status becomes `complete`.
Photogrammetry produces an **unverified scale**. Apple capture metadata is retained
in the private original archive; it is not treated as a metric pose or a RoomPlan
registration. Splat appearance does not establish a measurable solid surface.

See [API.md](API.md) for the exact integration contract and [THIRD-PARTY.md](THIRD-PARTY.md)
for licenses and source provenance. This service is optional and independent of
the existing viewer/project-storage server.

## Build on Windows/Linux Docker

The initial image deliberately targets **linux/amd64**. Build context is this
directory, not the repository root. Allow substantial disk, RAM and build time;
C++ compilation and reconstruction are not lightweight web-server tasks.

```sh
docker build --platform linux/amd64 -t kantura-reconstruction:0.5.0 .
docker volume create kantura-reconstruction
docker run --rm -i --platform linux/amd64 kantura-reconstruction:0.5.0 python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Save a generated token in a private environment file, for example:

```text
RECONSTRUCTION_TOKEN=replace-with-your-generated-token
WORKER_DEVICE=cpu
WORKER_THREADS=2
IMAGE_MAX_SIDE=1600
SPLAT_ITERATIONS=1000
```

```sh
docker run --name kantura-reconstruction --init --platform linux/amd64 \
  --env-file .env --read-only --tmpfs /tmp:rw,noexec,nosuid,size=1g \
  --cap-drop ALL --security-opt no-new-privileges \
  -p 127.0.0.1:4180:4180 -v kantura-reconstruction:/data \
  kantura-reconstruction:0.5.0
```

Only loopback is published. Use the existing trusted Kantura proxy or an HTTPS
reverse proxy for other devices. Never publish the token in browser config or a
URL. All people with this service token can see all its jobs; this is not a
multi-tenant service. Data is under `/data`, outside any static document root.
The container runs as UID/GID 10001. For a bind mount, provision that directory's
permissions before starting it.

The official CPU LibTorch archive was downloaded completely on 11 October 2026
(182,681,505 bytes); its SHA256 is pinned and checked before extraction. The
official redirect is followed with normal TLS verification. Docker image
compilation and real reconstruction are still pending validation. Pins are
upstream commits and registry digests, not evidence of a successful engine run.

## NVIDIA option

Use the exact CUDA image digest from [pins.json](pins.json), for example:

```sh
docker build --platform linux/amd64 -t kantura-reconstruction:0.5.0-cuda \
  --build-arg BASE_IMAGE=nvidia/cuda:12.1.1-devel-ubuntu22.04@sha256:7012e535a47883527d402da998384c30b936140c05e2537158c80b8143ee7425 \
  --build-arg GPU_RUNTIME=CUDA .
```

Run with an appropriate NVIDIA Container Toolkit setup, `--gpus all` and
`WORKER_DEVICE=cuda`. The build architectures default to `75;80;86;89`; choose
the correct architecture/toolkit for the actual card when necessary. This image
accelerates **OpenSplat**, while COLMAP registration and OpenMVS in this pipeline
remain CPU builds. CUDA on a Windows host requires a compatible Docker/WSL2/NVIDIA
configuration. A visible NVIDIA card on the host alone does not prove container
access. No GPU reconstruction has been validated in the Windows development run.

## Apple Silicon Mac

Docker does not expose Apple's Metal GPU to this Linux image. Running
`--platform linux/amd64` on an Apple-chip Mac uses CPU emulation and may be far too
slow for useful training. Do not advertise it as native Apple GPU support.

OpenSplat's [official build instructions](https://github.com/WebODM/OpenSplat/tree/62fd86fe3b62644b65890557ad9bf397abdc7cfb#macos)
describe native Metal/MPS support. A native Python service can use separately
installed COLMAP/OpenMVS/OpenSplat executables on `PATH`, with OpenSplat built from
the pinned revision using `-DGPU_RUNTIME=MPS` and the Metal toolchain available.
Install the Python dependencies into a virtual environment, then:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
DATA_DIR=/your/private/kantura-data RECONSTRUCTION_TOKEN=your-long-token WORKER_DEVICE=mps python service.py
```

`WORKER_DEVICE=mps` is rejected outside macOS; a native build and real training
must still be tested on the actual Mac. Record the installed engine revisions and
linked Torch version. Homebrew's current version is not automatically the pinned
version. The bundled `pins.json` describes the container recipe; native operators
must document any deviation before treating its version labels as deployment
evidence.

## Inputs and outputs

Use 8–250 overlapping still photos from one scene, ideally with many repeatable
surface features, changing camera position and stable illumination. A textureless
wall, rotating object with an inconsistent background, reflective gate or badly
blurred photos may not register. The minimum is an admission rule, not a quality
promise. Unrelated photos are expected to fail.

Native ZIPs can include a `kantura-photo-dataset` v1 `manifest.json`; the file list
and byte counts must match. Paths, duplicate/case-colliding names, symlinks,
encryption, unsupported entries and oversized archives are rejected. Original
filenames are never executed or used as extraction destinations. Worker input
images are re-encoded to generated JPEG names, with EXIF orientation applied;
embedded Apple depth/pose metadata is not consumed as a calibration source.

The service accepts at most 200 MiB compressed input and 1 GiB expanded input.
Individual images are limited to 50 MiB and 60 million pixels. The worker selects
the largest COLMAP component and requires at least six registered cameras and
60% of the submitted photographs; otherwise it fails. Discarded components and
registered-image counts are recorded in `reconstruction.json`.

Only fixed output names can be downloaded, only after completion. Each output is
at most 200 MiB, and a mesh ZIP expands to at most 500 MiB. `mesh.zip` contains the
textured OBJ/MTL/images; `model.ply` is the untextured surface. `splat.ply` requires
a Gaussian renderer, not an ordinary PLY point/mesh loader. `cameras.json` contains
reconstructed camera views in the output coordinate frame. The result manifest
preserves input provenance and states `scaleStatus: unverified`.

## Queue, cancellation and persistence

One worker process runs per service. Up to four unfinished jobs are admitted, and
one upload is streamed at a time. Status is `queued`, `running`, `complete`,
`failed` or `cancelled`; named stages replace invented progress percentages.
Cancellation terminates the process group/tree. Partial outputs never become
downloadable. On restart, queued work resumes and interrupted running work is
marked failed, rather than being incorrectly reported complete.

Each job retains its state, original archive, logs and final artifacts. Generated
`/data/<UUID>/work` intermediates are removed after completion, failure or
cancellation, once the worker has exited; shutdown also waits for the worker
before cleanup. Startup retries cleanup for already terminal jobs. Paths are
checked against that exact private job directory, and symlinks are not followed.
If cleanup cannot be completed, files remain for a later retry. Jobs interrupted
by an unclean service restart retain their scratch because an orphaned worker
could still be using it; stop any remaining workers before manually removing
that job's `work` directory. The default time limit is two hours (`JOB_TIMEOUT_SECONDS`); the private
work budget is 8 GiB per job and logs are capped at 8 MiB. Admission reserves free
disk headroom. During processing, the worker supervisor also checks the data
volume's free space on every monitoring pass (normally 0.25 seconds); if it falls
below the 2 GiB reserve, it terminates the worker with `storage_full` and removes
only generated scratch after the process exits. Concurrent host writes can still
consume free space between checks. These limits are safeguards, not a guarantee against OS out-of-memory
termination. Set Docker/host memory and CPU limits appropriate to the machine.

Original photos, final/partial artifacts, logs and job records are never
automatically deleted. No public delete endpoint is implemented. Back up
the data volume. To remove a job, stop the service first and remove only that job's
UUID directory under the private data root. Unfinished upload folders have no
published `state.json`; an operator can remove them while stopped. Retention,
quotas across completed jobs and per-user identities remain integration work.

## Verification: keep contract and reconstruction tests separate

Run the contract/API tests with Python 3.9 or newer:

```sh
python -m unittest discover -s test -v
```

On 11 October 2026, 50 of 51 tests passed locally on Windows with Python 3.9
and the pinned `requirements.txt` dependencies; the filesystem-symlink cleanup
case skipped because this Windows account cannot create symlinks. It runs in
Linux CI. The suite includes six scratch-retention/process-lifecycle checks and
four actual JPEG/PNG/HEIC decode/orientation/resize/error checks. Codec checks
explicitly skip if those dependencies are missing. The process tests
use an explicitly named **FakeWorker** to exercise queue transitions,
failure, cancellation, artifact admission and persistence. Their small geometry
fixtures are test data, never a replacement for reconstruction, and cannot be
enabled by an HTTP request or production environment switch.

A real engine smoke test uses the built image and a real/procedural photo dataset:

```sh
docker run --rm --platform linux/amd64 -v /absolute/private/job:/job \
  -e IMAGE_MAX_SIDE=512 -e SPLAT_ITERATIONS=10 -e WORKER_THREADS=2 \
  kantura-reconstruction:0.5.0 python3 /opt/kantura/worker.py --job-dir /job --mode splat
```

The mounted job folder must contain `input.zip` and no pre-existing `work` or
`artifacts`. Use a fresh folder to test `--mode mesh`. Ten iterations test the
engine/output route only; the default is 1,000 and neither establishes good visual
quality automatically. Configuration is trusted-admin input, not a set of command
flags exposed to web users. Record the actual image digest, dataset provenance,
commands, registration rate and rendered result. Physical photo quality, device
workflow, metric calibration, GPU/MPS speed and maximum-size behavior remain
separate tests. No real-engine test result is claimed by the unit suite.
