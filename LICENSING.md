# Licensing

**KANTURA is open source under the [BSD 3-Clause License](LICENSE)** — the same
license as [RTAB-Map](https://github.com/introlab/rtabmap), on which it is based.

In short, you may use, change, sell and redistribute KANTURA, in source or
binary form (including App Store builds and closed products), as long as:

1. the copyright notices and the license text are kept with the source, and
2. binary distributions reproduce them in their documentation or an
   in-app "Licenses" screen, and
3. the names of the copyright holders and contributors (RTAB-Map, Université
   de Sherbrooke, KANTURA) are not used to endorse derived products without
   permission.

The software is provided without warranty. Measurements made with it are not
certified surveys.

*Deutsch, unverbindliche Zusammenfassung:* KANTURA steht unter der BSD-3-Clause-Lizenz.
Du darfst den Code nutzen, ändern, verkaufen und weitergeben – auch in App-Store- oder
geschlossenen Produkten –, solange Copyright-Hinweise und Lizenztext erhalten bleiben
und die Namen der Rechteinhaber nicht ohne Zustimmung für Werbung genutzt werden.
Keine Gewährleistung; Messwerte sind kein amtliches Aufmaß.

## What the BSD license covers — and what it does not

| Part | License |
| --- | --- |
| Everything in this repository written for RTAB-Map or KANTURA (C++ core, iOS app, Android app, browser workspace `tools/scan-workspace`, server wrappers, tests, docs) | BSD-3-Clause ([LICENSE](LICENSE)) unless a file states otherwise |
| `corelib/src/opencv/ORBextractor.cc` and related ORB-SLAM-derived files | GPLv3 per their file headers. Only built with `WITH_ORB_OCTREE=ON`. **Switch it off for App Store / closed builds.** |
| Prebuilt native iOS dependencies (OpenCV, PCL, g2o, GTSAM, SuiteSparse, libLAS/LASzip, …) | Their own licenses. Use `OPENCV_ENABLE_NONFREE=OFF` and review the profile in [docs/APP-STORE-RELEASE.md](docs/APP-STORE-RELEASE.md) before a store release. |
| iOS Swift package [Zip](https://github.com/marmelroy/Zip) | MIT |
| Browser workspace packages (three.js, fflate, MSAL, Gaussian Splats 3D, esbuild) | MIT — see `tools/scan-workspace/pnpm-lock.yaml` |
| Optional reconstruction server (`tools/reconstruction`): COLMAP, **OpenMVS (AGPL-3.0)**, **OpenSplat (AGPL-3.0)**, LibTorch, FFmpeg … | Separate Docker service. The AGPL engines keep their license; when you run a modified version as a public service you must offer its source. See [THIRD-PARTY.md](tools/reconstruction/THIRD-PARTY.md). |
| Panorama and image-to-3D tools (`tools/panorama`, `tools/generation`) | OpenCV Apache-2.0, TripoSR MIT, torchmcubes MPL-2.0, model weights with their own terms — see their THIRD-PARTY files |

The AGPL/GPL components are **not** part of the iPhone app or the browser
workspace. Keeping them in separate, optional services is what lets the app
itself stay under a permissive license.

## Contributions

By submitting a contribution you agree that it is licensed under the
BSD 3-Clause License of this repository (inbound = outbound). Only submit code
you wrote yourself or that is available under a compatible license, and say so
in the pull request. Do not submit code, assets or text copied from other
products (for example decompiled apps or product screenshots); see
[docs/INDEPENDENT-IMPLEMENTATION.md](docs/INDEPENDENT-IMPLEMENTATION.md).

## Name and logo

The BSD license covers the code, not the name. "KANTURA" and its logo identify
this project; forks that are distributed publicly should use their own name and
icon so users are not confused about who publishes them.
