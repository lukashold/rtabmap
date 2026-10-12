# Panorama dependencies and provenance

Kantura's glue code follows the repository's license. The entire Python image is not one uniformly BSD-licensed product. Keep dependency notices and corresponding license obligations when distributing binaries.

| Pinned dependency | Primary license/provenance |
| --- | --- |
| OpenCV 4.11.0 via `opencv-python-headless==4.11.0.86` | [OpenCV Apache-2.0](https://github.com/opencv/opencv/blob/4.11.0/LICENSE); [Python packaging MIT](https://github.com/opencv/opencv-python/blob/86/LICENSE.txt). [Bundled third-party notices](https://github.com/opencv/opencv-python/blob/86/LICENSE-3RD-PARTY.txt) also apply, including codec libraries. |
| NumPy 1.26.4 | [BSD-3-Clause and bundled-library notices](https://github.com/numpy/numpy/blob/v1.26.4/LICENSE.txt); wheels retain their own math/runtime notices. |
| Pillow 11.3.0 | [HPND/PIL license](https://github.com/python-pillow/Pillow/blob/11.3.0/LICENSE). |
| pillow-heif 0.22.0 | Python glue is [BSD-3-Clause](https://github.com/bigcat88/pillow_heif/blob/v0.22.0/LICENSE.txt), but the installed binary wheel's `LICENSES_bundled.txt` explicitly declares **GPLv2 for the wheel**, because it bundles x265 under GPLv2. It also lists libheif and libde265 under LGPLv3. Preserve all notices and satisfy the applicable binary/source-distribution obligations; do not describe this binary dependency as BSD-only. |

The Docker recipe pins the official Python 3.11.14 slim-bookworm image index to `sha256:65a93d69fa75478d554f4ad27c85c1e69fa184956261b4301ebaf6dbb0a3543d`, resolved through the official Docker registry on 12 October 2026. Python dependency versions are exact; downloaded wheel hashes are not currently locked. The image keeps package `.dist-info` licenses rather than stripping them. Review platform-specific bundled libraries before redistributing an image. This optional CLI/container dependency set is not an audited native App Store dependency profile.

No Polycam code, packages, private endpoints or model weights are included. The texture fixture and rendered perspective photos in `synthetic.py` are generated from deterministic random colors and geometric shapes authored for this test. The real engine estimates cameras from those images; it does not consume the known fixture rotations in the end-to-end test.
