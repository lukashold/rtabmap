#!/usr/bin/env bash
# Optional Docker build step; never invoked when handling a user upload.
# Usage: bash /absolute/tools/generation/install-runtime.sh /absolute/tools/generation
# Requires Ubuntu 22.04 amd64, python3-venv/dev, cmake, ninja-build, git,
# build-essential, ca-certificates, and libgomp1 supplied by the parent image.
set -euo pipefail
generation_code="${1:?Pass the absolute generation code directory}"
generation_env="${GENERATION_ENV:-/opt/kantura-generation-env}"
case "$generation_code" in /*) ;; *) echo 'Code path must be absolute' >&2; exit 2 ;; esac
case "$generation_env" in /*) ;; *) echo 'Environment path must be absolute' >&2; exit 2 ;; esac
test "$(uname -m)" = x86_64
test -f "$generation_code/pins.json"
test ! -e /opt/triposr
test ! -e /opt/torchmcubes-src
# Avoid accidentally linking Python Torch to the reconstruction worker's
# separate C++ LibTorch. The calling Docker shell retains its own environment.
unset LD_LIBRARY_PATH CUDA_HOME CUDA_PATH
python3 -m venv "$generation_env"
export PATH="$generation_env/bin:$PATH"
python -m pip install --no-cache-dir torch==2.6.0+cpu --index-url https://download.pytorch.org/whl/cpu
python -m pip install --no-cache-dir -r "$generation_code/requirements.txt"
git init /opt/triposr
git -C /opt/triposr remote add origin https://github.com/VAST-AI-Research/TripoSR.git
git -C /opt/triposr fetch --depth=1 origin 107cefdc244c39106fa830359024f6a2f1c78871
git -C /opt/triposr checkout --detach FETCH_HEAD
test "$(git -C /opt/triposr rev-parse HEAD)" = 107cefdc244c39106fa830359024f6a2f1c78871
git init /opt/torchmcubes-src
git -C /opt/torchmcubes-src remote add origin https://github.com/tatsy/torchmcubes.git
git -C /opt/torchmcubes-src fetch --depth=1 origin 879926d0ef58e6ce0ac2630fdecb5e53af7ed3ff
git -C /opt/torchmcubes-src checkout --detach FETCH_HEAD
test "$(git -C /opt/torchmcubes-src rev-parse HEAD)" = 879926d0ef58e6ce0ac2630fdecb5e53af7ed3ff
# Explicitly keep this engine CPU-only even when a parent image has nvcc.
CMAKE_PREFIX_PATH="$(python -c 'import torch; print(torch.utils.cmake_prefix_path)')" \
  CMAKE_ARGS="-DCMAKE_CUDA_COMPILER=NOTFOUND" CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS:-2}" \
  python -m pip install --no-cache-dir --no-build-isolation --no-deps /opt/torchmcubes-src
python "$generation_code/patch_vendor.py" /opt/triposr
python "$generation_code/download_models.py" --output /opt/kantura-models
python -m pip freeze > "$generation_code/installed-packages.txt"
export PYTHONPATH=/opt/triposr
export KANTURA_DINO_CONFIG=/opt/kantura-models/dino-config.json
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
python -c 'import torch, torchmcubes; from tsr.system import TSR; assert torch.__version__ == "2.6.0+cpu"; assert not torch.cuda.is_available(); assert not torchmcubes.HAS_CUDA; print("Pinned offline CPU inference imports passed")'
python -m unittest discover -s "$generation_code/test" -v
python - "$generation_code" "$generation_env" <<'PY'
import json, pathlib, sys
code, environment = pathlib.Path(sys.argv[1]), sys.argv[2]
pins = json.loads((code / 'pins.json').read_text())
(code / 'runtime.json').write_text(json.dumps({
    'engine': 'TripoSR', 'device': 'cpu', 'python': environment + '/bin/python',
    'weightsDirectory': '/opt/kantura-models', 'pins': pins,
    'validated': 'imports-and-contract-tests; real inference is checked separately in CI'
}, indent=2) + '\n')
PY
