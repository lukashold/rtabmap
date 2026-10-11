#!/usr/bin/env bash
set -euo pipefail
cd /opt/kantura
: "${BUILD_JOBS:=2}"
: "${GPU_RUNTIME:=CPU}"
: "${CUDA_ARCHITECTURES:=75;80;86;89}"
case "$GPU_RUNTIME" in CPU) TORCH_FLAVOR=cpu;; CUDA) TORCH_FLAVOR=cuda; command -v nvcc;; *) echo 'Only CPU/CUDA container builds are supported' >&2; exit 1;; esac
TORCH_URL=$(python3 -c 'import json,sys; print(json.load(open("pins.json"))["libtorch"][sys.argv[1]])' "$TORCH_FLAVOR")
# Fail at the download before expensive C++ compilation. No disabled TLS checks.
curl --fail --location --retry 3 --output /tmp/libtorch.zip "$TORCH_URL"
sha256sum /tmp/libtorch.zip > libtorch-download.sha256
if [ "$TORCH_FLAVOR" = cpu ]; then
    EXPECTED=$(python3 -c 'import json; print(json.load(open("pins.json"))["libtorch"]["cpuSha256"])')
    printf '%s  /tmp/libtorch.zip\n' "$EXPECTED" | sha256sum --check -
fi
unzip -q /tmp/libtorch.zip -d /opt/kantura
rm /tmp/libtorch.zip
mkdir -p sources
python3 - <<'PY'
import json, pathlib, subprocess
pins=json.load(open('pins.json'))
for name in ['colmap','openmvs','opensplat','vcglib']:
    spec=pins['sources'][name]
    folder=pathlib.Path('sources')/name
    subprocess.run(['git','init',str(folder)],check=True)
    subprocess.run(['git','-C',str(folder),'remote','add','origin',spec['repository']],check=True)
    subprocess.run(['git','-C',str(folder),'fetch','--depth','1','origin',spec['revision']],check=True)
    subprocess.run(['git','-C',str(folder),'checkout','--detach','FETCH_HEAD'],check=True)
    actual=subprocess.check_output(['git','-C',str(folder),'rev-parse','HEAD'],text=True).strip()
    if actual != spec['revision']: raise RuntimeError('Revision mismatch: '+name)
PY
cmake -S sources/colmap -B /tmp/build-colmap -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DCUDA_ENABLED=OFF -DGUI_ENABLED=OFF -DOPENGL_ENABLED=OFF -DTESTS_ENABLED=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/build-colmap --parallel "$BUILD_JOBS"
cmake --install /tmp/build-colmap
cmake -S sources/openmvs -B /tmp/build-openmvs -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DVCG_ROOT=/opt/kantura/sources/vcglib -DOpenMVS_USE_CUDA=OFF \
    -DOpenMVS_USE_OPENGL=OFF -DOpenMVS_USE_BREAKPAD=OFF -DOpenMVS_USE_PYTHON=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/build-openmvs --parallel "$BUILD_JOBS"
cmake --install /tmp/build-openmvs
cmake -S sources/opensplat -B /tmp/build-opensplat -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=/opt/kantura/libtorch -DGPU_RUNTIME="$GPU_RUNTIME" \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES" -DOPENSPLAT_BUILD_VISUALIZER=OFF \
    -DOPENSPLAT_USE_PCH=OFF -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/build-opensplat --parallel "$BUILD_JOBS"
cmake --install /tmp/build-opensplat
printf '/opt/kantura/libtorch/lib\n/usr/local/lib\n' > /etc/ld.so.conf.d/kantura.conf
ldconfig
# Retain exact corresponding source, pinned PoseLib and licenses in the image.
cp -a /tmp/build-colmap/_deps/poselib-src sources/poselib
dpkg-query -W > os-packages.txt
python3 -m pip freeze > python-packages.txt
printf '%s\n' "$GPU_RUNTIME" > build-device.txt
rm -rf /tmp/build-colmap /tmp/build-openmvs /tmp/build-opensplat
