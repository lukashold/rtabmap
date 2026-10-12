# Reconstruction engine provenance

Exact releases, commit IDs and base-image digests are in [pins.json](pins.json).
The wrapper is part of the RTAB-Map/Kantura source distribution under its existing
repository license. This does **not** relicense the external engines or make this
combined server image a BSD-only distribution.

| Component | Upstream license/reference | Role |
| --- | --- | --- |
| COLMAP 3.11.1 | [BSD-3-Clause license](https://github.com/colmap/colmap/blob/682ea9ac4020a143047758739259b3ff04dabe8d/COPYING.txt) | CPU feature matching, sparse registration and undistortion |
| OpenMVS v2.3.0 | [AGPL-3.0 license](https://github.com/cdcseacave/openMVS/blob/ce03889e2055a3d6cbcae9dd5a93b5eeea94b909/LICENSE) | CPU dense reconstruction, surface and texture generation |
| OpenSplat v1.2.2 | [AGPL-3.0 and third-party notices](https://github.com/WebODM/OpenSplat/blob/62fd86fe3b62644b65890557ad9bf397abdc7cfb/LICENSE.txt) | Actual Gaussian-splat optimization |
| VCG 2023.12 | [Exact source and its per-file notices](https://github.com/cnr-isti-vclab/vcglib/tree/6ac9e0c647a63e0e037813a1e92bd050d13efc85) | OpenMVS mesh dependency; not assumed BSD-only |
| PoseLib | [Exact source](https://github.com/PoseLib/PoseLib/tree/8028473d92c9347794a0e3d3541863b5cbb15743) | COLMAP dependency, SHA256 pinned by upstream CMake |
| LibTorch 2.2.1 | [PyTorch license and third-party notices](https://github.com/pytorch/pytorch/blob/v2.2.1/LICENSE) | OpenSplat tensor runtime; versioned CPU/CUDA upstream binary |
| FFmpeg / ffprobe 4.4.2, Ubuntu `7:4.4.2-0ubuntu0.22.04.1` | [Ubuntu source package](https://launchpad.net/ubuntu/+source/ffmpeg/7:4.4.2-0ubuntu0.22.04.1), [FFmpeg license/build notices](https://ffmpeg.org/legal.html) | Bounded local video probing, autorotation and JPEG frame decoding; enabled codec libraries have additional terms |
| Pillow 11.3.0 | [Pillow license](https://github.com/python-pillow/Pillow/blob/11.3.0/LICENSE) | JPEG/PNG decoding and orientation |
| pillow-heif 0.22.0 | [BSD-3-Clause wrapper and dependency notices](https://github.com/bigcat88/pillow_heif/tree/v0.22.0) | HEIC/HEIF decoding through libheif; underlying codecs have their own licenses |

The image retains engine/VCG/PoseLib source trees with original licenses at
`/opt/kantura/sources`, build scripts, pins and package inventories. LibTorch and
Python wheel notices remain installed. Inspect the actual libheif/codec wheel
contents and distribution obligations, rather than inferring codec licensing
from the Python wrapper's BSD license. The optional CUDA base also carries NVIDIA
runtime/toolkit terms; it is not an entirely open-source OS image.

When distributing or operating a modified AGPL engine, preserve its notices and
provide the corresponding source for the deployed version as required by its
license. Publish the actual wrapper/build changes and exact revisions, and make
the source information available to service users. Retaining sources in a private
container alone is not a claim that every distribution obligation is satisfied.
This inventory is not a completed legal audit and does not clear the separate
iOS App Store binary. No Polycam implementation is used by this service.

The CPU/CUDA base images and engine commits are immutable pins. Ubuntu package
repositories are not snapshot-pinned. The CPU LibTorch archive has a verified,
enforced SHA256 pin; the optional CUDA archive is versioned and its downloaded
hash is recorded, but has not been independently verified. The build records
installed package versions. Therefore this is not advertised as a bit-for-bit
reproducible or fully audited supply chain.

## Local OpenMVS correction

The pinned v2.3.0 source is built with
[`patches/openmvs-single-texture-obj.patch`](patches/openmvs-single-texture-obj.patch).
Its OBJ exporter read `faceTexindices[idxFace]` after `SceneTexture` had released
that optional array for a single atlas. The one-line patch calls the existing
`GetFaceTextureIndex` accessor, which returns zero for the implicit single atlas.
This is the narrow textured-mesh equivalent of the later upstream
[OBJ export fix cd688d2](https://github.com/cdcseacave/openMVS/commit/cd688d2a068881184e963926e5e867595cb7eafb).
It changes no geometry, UV coordinates, photos or reconstruction parameters.

The build verifies the exact source revision and patch SHA256 in
[`patches/manifest.json`](patches/manifest.json), compiles OpenMVS with the patch,
and runs [`patches/obj-export-regression.cpp`](patches/obj-export-regression.cpp)
against the actual OBJ exporter for one and two atlases. It checks exported
geometry, UVs, material references and texture files. This regression is separate
from the real multi-photo reconstruction smoke test. The base-engine layer stays
cached; [`openmvs-patch.sh`](openmvs-patch.sh) rebuilds only OpenMVS.

The image retains the original notices, modified source, test and patch under
`/opt/kantura`. Output `reconstruction.json` records both `engines` and
`enginePatches`, including the patch digest. The patch is distributed with the
OpenMVS source under the same AGPL terms; the upstream code is not relicensed.

The pinned OpenMVS RGB-atlas material writer also hard-codes `Tr 1.000000`,
which MTL readers such as Three.js interpret as fully transparent. After a
successful TextureMesh run, the worker changes that exact line to `d 1.000000`
in only its newly generated `.mtl` outputs before packaging `mesh.zip`. These
RGB atlases are opaque; no geometry, UVs, image pixels or original input archive
are changed. `materialNormalization` in `reconstruction.json` records the rule,
affected files and material counts (null for splats). This does not change how
the viewer interprets user-imported MTL files or partially transparent materials.

## Video and diagnostic source references

The Docker recipe pins the FFmpeg binary package version explicitly and records
it in `/opt/kantura/ffmpeg-package.txt`; its dependencies still use the Ubuntu
repository rather than a snapshot. Installed copyright notices remain under
`/usr/share/doc/ffmpeg`. Do not infer LGPL-only terms for a distro build with
GPL-enabled codecs. Corresponding Ubuntu source and its packaging are linked
above; the web/iOS viewer does not embed this server binary.

CLI choices are based on the official [FFmpeg options](https://ffmpeg.org/ffmpeg.html),
[MOV demuxer options](https://ffmpeg.org/ffmpeg-formats.html#mov_002fmp4_002f3gp),
[pinned OpenMVS RefineMesh options](https://github.com/cdcseacave/openMVS/blob/ce03889e2055a3d6cbcae9dd5a93b5eeea94b909/apps/RefineMesh/RefineMesh.cpp),
and [pinned OpenSplat validation options](https://github.com/WebODM/OpenSplat/blob/62fd86fe3b62644b65890557ad9bf397abdc7cfb/opensplat.cpp).
Camera diagnostics read the documented pinned COLMAP binary model layout and
its SQLite image-to-camera relation. Coordinate conventions were checked against
OpenSplat's pinned `colmap.cpp` and `input_data.cpp`, including the export-time
Y/Z flip. No external learned model, camera pose or metric reference is embedded
in these diagnostic calculations.

## Optional capture runtimes

The shared job service invokes project-owned sibling adapters. Panorama notices
and exact OpenCV/NumPy/Pillow pins are in [../panorama/THIRD-PARTY.md](../panorama/THIRD-PARTY.md).
The optional TripoSR/torchmcubes/model runtime preserves source, weights and
notices described in [../generation/THIRD-PARTY.md](../generation/THIRD-PARTY.md).
Its Python environment is isolated from the reconstruction engine's LibTorch.
These packages are not included merely by enabling a UI option; generation
requires the explicit optional Docker build.

The actual pillow-heif 0.22.0 binary-wheel `LICENSES_bundled.txt` identifies its
x265-enabled binary distribution as GPLv2 and lists libheif/libde265 LGPLv3
components. The BSD wrapper license does not describe the wheel as a whole.
Preserve the installed wheel's complete notices and corresponding source
information when distributing images; do not describe this combined image as
BSD-only or LGPL-only. This remains a dependency inventory, not legal clearance.
