# Single-image 3D generation with TripoSR

This separate CPU CLI creates an **AI-generated object** from one foreground
photograph using the actual TripoSR neural model. Unseen surfaces are inferred.
It does not measure the photographed object, reconstruct a room, or produce
Gaussian splats. Generated geometry must not be used for measurements or fitting
parts, even after a reference length has been entered.

The runtime calls `TSR`, loads the pinned checkpoint with
`torch.load(weights_only=True)`, runs neural inference, and extracts a colored
mesh using the real CPU `torchmcubes` extension. There is no depth extrusion,
placeholder mesh, or fallback model when inference fails. No HTTP endpoint or
automatic upload is included in this standalone CLI.

## Build in Docker

Run from the repository root, preferably on a Linux CI/build host with at least
20 GiB of free disk. Do not download checkpoints separately onto the iPhone or
Windows workspace.

```sh
docker build --platform linux/amd64 -t kantura-generation:local tools/generation
```

The image contains CPU PyTorch 2.6.0, pinned TripoSR/torchmcubes source, dependencies,
and a 1.677 GB checkpoint. Build downloads are verified against committed SHA-256
values. The DINO image encoder needs only its pinned architecture configuration:
its trained weights are already in the TripoSR checkpoint. Model bytes are also
verified at inference startup. No weights are accepted from the uploaded image.

The first build compiles the CPU extension and downloads models; allow several
minutes and several GiB of Docker storage. Apple Silicon uses `linux/amd64`
emulation, which can be substantially slower. CPU runtime is machine-dependent;
budget minutes, not the upstream A100 GPU timings. Start with 96 grid resolution,
2 CPU threads and a 12 GiB memory allowance on a host with at least 16 GiB RAM.
These are planning allowances, not a measured performance guarantee. Actual
engine smoke execution is separate from the fast unit tests.

## Input and private execution

Use a transparent PNG showing **one isolated object**, with the object fully
visible. Alpha bounds are centered at 85% of a 512×512 neutral-grey input. There
is no automatic background-removal model. For a centered object already isolated
on a plain background in a JPEG or opaque PNG, explicitly pass
`--foreground-isolated`. This flag records your confirmation; it does not
algorithmically verify segmentation or image quality.

Limits: PNG/JPEG, 25 MiB, 16 megapixels, 64–8192 pixels per side, one still frame.
Large backgrounds, rooms, thin or reflective objects, and hidden surfaces can
produce poor or invented geometry. Improving extraction resolution does not add
evidence for unseen surfaces or establish physical scale.

The input and output paths must be absolute. The output directory must be empty.
The following example is for a POSIX shell; replace the two host paths with your
own. Using the current host UID makes the output writable without changing the
container's source or model directories.

```sh
mkdir -p /absolute/result
docker run --rm --network none --read-only --tmpfs /tmp:size=512m \
  --cpus 2 --memory 12g --pids-limit 256 \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,source=/absolute/foreground.png,target=/input.png,readonly \
  --mount type=bind,source=/absolute/result,target=/output \
  kantura-generation:local --input /input.png --output /output \
  --resolution 96 --threads 2
```

The process prints JSON progress stages and exits nonzero on failure. Interrupting
the process stops generation. A result is complete only when `generation.json`
exists with `status: "complete"`. Files written before interruption are partial
work. Use a new empty output directory to retry; existing files are never
overwritten. Ordinary failures write `generation-error.json` and preserve the
original input for recovery.

## Output

- `model.zip`: browser-ready archive containing exactly `model.glb` and
  `rtab-measure.json`, marked `source: "generated"`, uncalibrated, with empty
  measurement/check/note arrays and `metricMeasurementsAllowed: false`.
- `generated-model.glb`, `.obj`, `.ply`: colored geometry, each with generated
  provenance in its supported metadata/comments. The GLB/PLY retain vertex colors;
  OBJ vertex colors use the commonly supported vertex-color extension.
- `generation.json`: source/weight revision and SHA-256, input/output hashes,
  preprocessing, arbitrary scale, resolution, elapsed time, and limitations.
- `Original/input.png` or `.jpg`: exact original bytes, possibly including EXIF
  and location metadata. Keep private unless you choose to share them.
- `prepared-input.png`: the derived, oriented and composited model input.

Only the compact `model.zip` is intended for Kantura's browser project import.
Originals and the other mesh formats remain outside it. Model coordinates are
converted from upstream Z-up to right-handed Y-up; units remain **arbitrary**.
No metric dimension or area is certified or inferred by this conversion.

## Optional integration into another Docker image

`install-runtime.sh /absolute/code/directory` installs the exact engine into
`/opt/kantura-generation-env`, `/opt/triposr`, `/opt/torchmcubes-src`, and
`/opt/kantura-models` during the Docker build. The parent image must provide
Ubuntu 22.04 amd64, Python 3.10 with venv/dev, compiler, CMake, Ninja, Git,
CA certificates and libgomp1. `BUILD_JOBS` defaults to 2. Installation requires
fresh source directories and runs import and contract tests; `runtime.json`
records completion. This marker is not evidence of an actual neural model run.

Invoke `/opt/kantura-generation-env/bin/python /absolute/code/generate.py` in a
worker subprocess. Set `PYTHONPATH=/opt/triposr`,
`KANTURA_MODEL_DIR=/opt/kantura-models`, `HF_HUB_OFFLINE=1` and
`TRANSFORMERS_OFFLINE=1`. **Remove the parent worker's `LD_LIBRARY_PATH`** before
launching: its C++ LibTorch may use a different ABI from Python Torch. Keep model
directories read-only and isolate upload/output paths. No CUDA runtime is used.

## Validation

```sh
python -m unittest discover -s tools/generation/test -v
```

Input/provenance/downloader tests need Pillow. Export tests additionally need
NumPy and Trimesh and are always enabled in the Docker image. They use explicitly
synthetic export fixtures, never claim to prove inference quality. Source patching
fails if the pinned upstream lines differ; the model architecture is unchanged.

For a genuine offline CPU smoke run after building, use the upstream example
already included in the pinned source image and an empty mounted output folder:

```sh
docker run --rm --network none --cpus 2 --memory 12g \
  --user "$(id -u):$(id -g)" \
  --mount type=bind,source=/absolute/empty-smoke,target=/output \
  kantura-generation:local --input /opt/triposr/examples/chair.png \
  --output /output --foreground-isolated --resolution 96 --threads 2
```

Require `generation.json`, finite nonempty geometry and all output hashes; inspect
the resulting appearance separately. A valid mesh export alone does not show that
it resembles the source object. See [THIRD-PARTY.md](THIRD-PARTY.md) for licenses
and pinned primary sources.
