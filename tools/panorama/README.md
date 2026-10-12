# Kantura panorama stitching

This optional local CPU tool stitches **overlapping photos taken by rotating around one camera centre**. It estimates real camera rotations, projects photographed pixels onto a full equirectangular sphere, and outputs a 2:1 PNG. It does not stretch a cropped panorama to fill the sphere. Unobserved directions have alpha zero and a separate zero-valued coverage mask. There is no generative filling, depth, metric scale or measurement tool.

The engine is separate from the photo-to-mesh/splat worker. This directory currently provides a CLI and an optional Docker image, **not an authenticated HTTP service or a native guided capture screen**. The browser panorama viewer opens its `panorama.png` output.

## Local use

Use Python 3.9–3.12 and a dedicated virtual environment. From this directory:

```sh
python -m venv .venv
# Activate .venv for your shell, then:
python -m pip install --only-binary=:all: -r requirements.txt
python stitch.py photos.zip output-panorama --width 2048 --timeout 600
```

The output directory must not exist. ZIP members may be JPEG, PNG or HEIC/HEIF images in subdirectories, plus optional `manifest.json`. The original archive is preserved byte-for-byte. Apple Object Capture exports are accepted as files, but **walking around an object is not the required stationary-centre panorama motion**: large translation/parallax can make such a set fail or produce ghosting.

Bounds: 2–40 photos; 32 MiB and 48 million pixels per original; 200 MiB archive; 512 MiB expanded bytes; 128 ZIP entries; 1200-pixel working-image side; even output width 512–4096 pixels; two OpenCV threads; CLI timeout 10–1800 seconds. All supplied photos must join the matched-image component. The tool fails rather than silently dropping disconnected photos. A time limit terminates the child process and removes its private staging tree. Do not run concurrent jobs with the same output directory.

Outputs are published only after successful processing:

| File | Meaning |
| --- | --- |
| `panorama.png` | Real warped/feather-blended pixels on a 2:1 RGBA canvas; transparent pixels are unknown. |
| `coverage.png` | Same-size grayscale mask: 255 observed, 0 unknown. This is coverage, not accuracy/confidence. |
| `originals.zip` | Unmodified source including original metadata. Treat it as private capture data. |
| `result.json` | Engine/version, estimated intrinsics/rotations, per-photo and output SHA-256 hashes, coverage fraction, original manifest and limitations. |

`coverageFraction` is weighted by spherical surface area, not a simple equirectangular pixel fraction. It can be below one for a successful partial panorama. `status: complete` means these artifacts were produced, not that 360° × 180° was photographed or that alignment is correct. `hasDepth: false`, `canMeasure: false` and `scaleStatus: unverified` remain explicit. In particular, match confidence and bundle adjustment are not a survey accuracy guarantee.

## Docker

From the repository root:

```sh
docker build -t kantura-panorama:0.6.0 tools/panorama
# photos.zip is in the current directory; result/ must be writable by UID 10001.
docker run --rm --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges --memory 2g --cpus 2 --pids-limit 64 \
  --tmpfs /tmp:rw,noexec,nosuid,size=128m \
  -v "$PWD/photos.zip:/input/photos.zip:ro" \
  -v "$PWD/result:/output" \
  kantura-panorama:0.6.0 /input/photos.zip /output/panorama --width 2048
```

The example uses POSIX shell paths; use absolute host paths in PowerShell. The image runs as UID/GID 10001. Create the output mount with appropriate host ownership, or use an explicitly mapped non-root host UID/GID. Linux/amd64 and Linux/arm64 wheel distributions exist for these pinned requirements, but the Docker build and Apple-Silicon container run still require their own recorded checks. No GPU is required. The runtime makes no network requests; installation downloads public packages.

## Real engine tests and remaining checks

```sh
python -m unittest -v test_stitch
python synthetic.py synthetic-photos.zip
python stitch.py synthetic-photos.zip synthetic-result --width 1024
```

On 12 October 2026, **12 tests passed** on Windows/Python 3.9 using real OpenCV 4.11.0. Eight authored perspective photos were matched and stitched; recovered relative camera rotations stayed within the test's three-degree bound. Separate known-pose projection tests checked longitude, the wrap seam, missing poles and partial horizontal coverage. An end-to-end job checked PNG alpha, preserved source bytes and artifact hashes. Real HEIC decoding and JPEG EXIF orientation passed. Security tests covered unsafe paths, links, duplicate/invalid members, byte/pixel limits, disconnected photo sets and failed-publication cleanup. These use deterministic synthetic imagery, not a real iPhone scene and not a substituted stitch worker.

A separate CLI run produced a 2048 × 1024 panorama from eight synthetic JPEGs, with 61.98% spherical coverage and transparent unobserved poles. Its PNG and mask were opened for visual inspection; the output manifest contains their byte sizes and SHA-256 values. This validates a real local path, not real-world alignment quality or the Docker image.

Still required: Docker/ARM run, real iPhone JPEG/HEIC capture sequences, translation/parallax failures, exposure changes, moving subjects, near objects, fine seams, low-texture walls and difficult light. There is no exposure compensation, graph-cut seam optimization or multiband blend in this first implementation; feathering can leave ghosts. Rotate around a stationary optical centre with steady exposure and substantial visual overlap. Photograph up/down directions if those areas should appear; the tool will not invent them. Inspect the result and coverage mask before sharing.

## Integrating a future server

Invoke the fixed CLI in a per-job private directory with administrator-chosen limits; do not accept arbitrary command flags, output paths or executable names from clients. Publish only `panorama.png`, `coverage.png`, `originals.zip` and `result.json` after exit code zero and verify the listed hashes. Apply the existing server authentication, bounded upload, cancellation, persistence and ownership policies independently. The CLI itself is not a network security boundary. Do not call an unfinished process `complete`, and never present the panorama as a measurable mesh.

Implementation uses OpenCV's public [rotation estimation API](https://docs.opencv.org/4.11.0/d7/d74/group__stitching__rotation.html), [pinned spherical projection source](https://github.com/opencv/opencv/blob/4.11.0/modules/stitching/include/opencv2/stitching/detail/warpers_inl.hpp) and [Python stitching API example](https://github.com/opencv/opencv/blob/4.11.0/samples/python/stitching_detailed.py) as API references. See [dependency notices](THIRD-PARTY.md).
