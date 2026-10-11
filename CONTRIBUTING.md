# Contributing to KANTURA

KANTURA is an independent RTAB-Map fork for guided room/object capture and practical measurement. Its development branch is [`kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). Contributions are welcome from developers, translators and people who can test a real LiDAR device.

**Maintainer setup:** The fork's default branch is currently `master`. In GitHub repository **Settings → Default branch**, select `kantura/main` so the KANTURA README appears on the repository home page and its issue forms become available. Contributors should target `kantura/main` for KANTURA pull requests regardless of the default branch.

[Deutsch](docs/contributing/de.md) · [Français](docs/contributing/fr.md) · [Español](docs/contributing/es.md) · [Italiano](docs/contributing/it.md) · [简体中文](docs/contributing/zh-Hans.md) · [Português](docs/contributing/pt.md) · [العربية](docs/contributing/ar.md) · [हिन्दी](docs/contributing/hi.md) · [বাংলা](docs/contributing/bn.md) · [Русский](docs/contributing/ru.md) · [日本語](docs/contributing/ja.md) · [한국어](docs/contributing/ko.md) · [Bahasa Indonesia](docs/contributing/id.md) · [Türkçe](docs/contributing/tr.md)

## Find a useful task

Read the [workspace guide](tools/scan-workspace/README.md), [feature comparison](docs/KANTURA-FEATURES.md) and [validation record](tools/scan-workspace/VALIDATION.md). Good contributions include a reproducible bug, a clearer translation, a small usability fix, a focused geometry test, or a documented device trial. Search [the fork's issues](https://github.com/lukashold/rtabmap/issues) before opening a duplicate. Explain the concrete task and expected behavior for a substantial feature before implementing it.

Use this fork for KANTURA dashboards, RoomPlan exchange, the browser workspace, tutorials and self-hosting. General RTAB-Map fixes may be proposed separately to [upstream](https://github.com/introlab/rtabmap), following its current process. Keep branded fork additions out of an upstream fix unless its maintainers request them. A contribution here does not imply upstream acceptance.

Be constructive, describe observable behavior and respect other contributors. Use samples you have permission to share. Remove private interiors, people, addresses, access tokens and account details from public reports.

## Develop the browser workspace

Use a complete checkout, Node.js 24 and pnpm 11.25.0. From the repository root:

```sh
git clone --branch kantura/main https://github.com/lukashold/rtabmap.git
cd rtabmap
git switch -c your-feature-branch
cd tools/scan-workspace
corepack enable
corepack prepare pnpm@11.25.0 --activate
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Open `http://localhost:4173`. Native tutorial data is read from `app/ios/RTABMapApp/MeasurementGuide.json`, so a tools-only checkout is insufficient. The [workspace guide](tools/scan-workspace/README.md) also covers Docker and optional storage. Keep changes focused; add meaningful tests for changed geometry, archive validation or data persistence. For a text-only fix, check the affected language/layout instead of adding a test that merely repeats the text. Record commands actually run and checks you could not run.

## Native development and device tests

iOS builds and signing require a Mac with compatible Xcode and native dependencies. See the [installation/release guide](docs/APP-STORE-RELEASE.md) and [iOS CI workflow](.github/workflows/ios.yml). With Swift available, the Foundation-only checks can be run from the repository root:

```sh
bash app/ios/Tests/run-scan-tracking-tests.sh
bash app/ios/Tests/run-measurement-guide-tests.sh
```

Passing these checks does not validate ARKit/RoomPlan capture. A useful device report includes the revision, device model, iOS version, capture mode, reproduction steps, expected/actual behavior and whether the sample is synthetic or real. For measurements, record the scan result, physical reference, method and units. Try one room and one gate when relevant; test interruption, save/reopen/export, note photos and Files providers. RoomPlan is an indoor path. Separate rooms are not automatically aligned, and the transport estimate does not perform full scanned-route collision detection.

## Translate and improve tutorials

Nine additional language packs live in `tools/scan-workspace/locales/<code>.json`.
Run `pnpm locales:sync` after editing a pack, then test and build. Arabic uses RTL;
model coordinates and numeric inputs retain their original direction. Review
translations and synthetic speech with native speakers before a public release.

Check UI wording in `tools/scan-workspace/src/i18n.js` and `experience-i18n.js`, native guide content in `app/ios/RTABMapApp/MeasurementGuide.json`, and video scripts in `tools/scan-workspace/public/videos/scripts.json`. Preserve keys, scene IDs, units, placeholders and the distinction between demonstrated and device-verified behavior. Keep captions aligned with narration. Explain your locale and proposed wording in a translation issue or PR; include a screenshot for clipped text. The video's English narration does not mean every native screen has an English KANTURA rewrite.

Video scenes are synthetic animated demonstrations, not recordings of successful device scans. Do not remove that label or turn reference checks, recognition confidence or simplified transport envelopes into accuracy/safety guarantees.

## Submit a pull request

1. Fork this repository, branch from `kantura/main`, and make a focused change in your own branch.
2. Run the relevant checks and review your diff for unrelated generated files, scans and credentials.
3. Push to your fork and open a PR against **`lukashold/rtabmap:kantura/main`**. State the problem, final behavior, validation and remaining limitations; link the issue if there is one.
4. Include UI screenshots or a short synthetic demonstration when they help review. Identify untested device/cloud paths clearly. Respond to review with small follow-up changes.

Do not include signing certificates, provisioning profiles, OAuth secrets or personal scans. Public browser OAuth client IDs are configuration, not a substitute for a real-account test.

## License and distribution

Original project code uses the repository's [BSD 3-Clause license](LICENSE). Retain copyright and third-party notices, and contribute only code/media you have the right to distribute. A new dependency needs its exact version, license and purpose documented; do not copy proprietary product assets or treat the whole native bundle as BSD.

The current native dependency audit flags `WITH_ORB_OCTREE=ON` (GPLv3 implementation), OpenCV's `OPENCV_ENABLE_NONFREE=ON`, the actual SuiteSparse/g2o components, and statically built LASzip 2.0.1/libLAS. Changing a flag requires rebuilding and checking the resulting linked components. See the [concrete release audit](docs/APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen). Store distribution additionally needs complete notices, privacy review, signing and device testing; this repository is not a completed App Store clearance.
