#!/usr/bin/env bash
set -euo pipefail
cd /opt/kantura
: "${BUILD_JOBS:=2}"
# Deliberately follows the cached base-engine build: only OpenMVS is rebuilt.
# Preserve the patch and corresponding modified source alongside all licenses.
python3 - <<'PY'
import hashlib, json, pathlib, subprocess
manifest = json.load(open('patches/manifest.json'))
for item in manifest['openmvs']:
    patch = pathlib.Path('patches') / item['file']
    if hashlib.sha256(patch.read_bytes()).hexdigest() != item['sha256']:
        raise RuntimeError('OpenMVS patch digest mismatch')
    revision = subprocess.check_output(['git', '-C', 'sources/openmvs', 'rev-parse', 'HEAD'], text=True).strip()
    if revision != item['baseRevision']:
        raise RuntimeError('OpenMVS patch base revision mismatch')
    subprocess.run(['git', '-C', 'sources/openmvs', 'apply', '--check', str(patch.resolve())], check=True)
    subprocess.run(['git', '-C', 'sources/openmvs', 'apply', str(patch.resolve())], check=True)
PY
cat >> sources/openmvs/CMakeLists.txt <<'CMAKE'

# Kantura regression: export real textured geometry with one/two atlases.
cxx_executable_with_flags(KanturaOBJRegression "Tests" "${cxx_default}" "MVS;${OpenMVS_EXTRA_LIBS}" "/opt/kantura/patches/obj-export-regression.cpp")
ENABLE_TESTING()
ADD_TEST(NAME KanturaOBJRegression COMMAND $<TARGET_FILE:KanturaOBJRegression>)
CMAKE
cmake -S sources/openmvs -B /tmp/build-openmvs-patched -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DVCG_ROOT=/opt/kantura/sources/vcglib -DOpenMVS_USE_CUDA=OFF \
    -DOpenMVS_USE_OPENGL=OFF -DOpenMVS_USE_BREAKPAD=OFF -DOpenMVS_USE_PYTHON=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/build-openmvs-patched --parallel "$BUILD_JOBS"
mkdir -p /tmp/kantura-obj-regression
ctest --test-dir /tmp/build-openmvs-patched --output-on-failure -R '^KanturaOBJRegression$'
cmake --install /tmp/build-openmvs-patched
ldconfig
rm -rf /tmp/build-openmvs-patched /tmp/kantura-obj-regression
