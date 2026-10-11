# Kantura — Scan. See. Measure.

<img src="https://raw.githubusercontent.com/lukashold/rtabmap/kantura/main/tools/scan-workspace/public/kantura.svg" width="96" alt="Kantura logo">

A public community fork of RTAB-Map for practical room and object measurement with iPhone LiDAR, an indoor RoomPlan workflow and a self-hosted desktop viewer.

**Development lives on [kantura/main](https://github.com/lukashold/rtabmap/tree/kantura/main).** Clone that branch for the Kantura app and Docker workspace. This default-branch page is the community entry point.

## Try Kantura

- [iPhone build, signing and installation](https://github.com/lukashold/rtabmap/blob/kantura/main/app/ios/MEASUREMENT-WORKFLOW.md)
- [Desktop viewer and measurements](https://github.com/lukashold/rtabmap/blob/kantura/main/tools/scan-workspace/README.md)
- [Docker self-hosting and project storage](https://github.com/lukashold/rtabmap/blob/kantura/main/tools/scan-workspace/README-server.md)
- [Fifteen offline video tutorials](https://github.com/lukashold/rtabmap/blob/kantura/main/tools/scan-workspace/public/videos)
- [Feature scope and remaining work](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/KANTURA-FEATURES.md) · [Validation record](https://github.com/lukashold/rtabmap/blob/kantura/main/tools/scan-workspace/VALIDATION.md)

The guided dashboard, room workflow, viewer, reports and tutorials support **15 languages**. Arabic has RTL presentation. The underlying RTAB-Map expert menus retain upstream English strings. This is a development preview; native signing, device trials and the dependency-license review remain part of release preparation.

## Build it together

Developers, translation reviewers, designers and owners of LiDAR devices are welcome. Help with clear measurement workflows, real-device reference checks, missing translations, accessible layouts, or documented bugs. Submit focused pull requests against **lukashold/rtabmap:kantura/main**.

[English](https://github.com/lukashold/rtabmap/blob/kantura/main/CONTRIBUTING.md) · [Deutsch](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/de.md) · [Français](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/fr.md) · [Español](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/es.md) · [Italiano](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/it.md) · [简体中文](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/zh-Hans.md) · [Português](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/pt.md) · [العربية](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/ar.md) · [हिन्दी](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/hi.md) · [বাংলা](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/bn.md) · [Русский](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/ru.md) · [日本語](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/ja.md) · [한국어](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/ko.md) · [Bahasa Indonesia](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/id.md) · [Türkçe](https://github.com/lukashold/rtabmap/blob/kantura/main/docs/contributing/tr.md)

```sh
git clone --branch kantura/main https://github.com/lukashold/rtabmap.git
cd rtabmap
```

Read the contributor guide before opening a PR. Reviewers can propose edits in their own language; no English-only contribution requirement applies. Do not upload private interiors or credentials. Bug/feature/translation forms are prepared; the repository owner still needs to enable Issues in GitHub Settings.

Kantura is independent of Metaroom and Polycam. Original code uses the repository's BSD license; linked native components and speech resources have separate notices.

---

## RTAB-Map upstream documentation

rtabmap
=======

[![RTAB-Map Logo](https://raw.githubusercontent.com/introlab/rtabmap/master/guilib/src/images/RTAB-Map100.png)](http://introlab.github.io/rtabmap)

[![Release][release-image]][releases]
[![Downloads][downloads-image]][downloads]
[![codecov](https://codecov.io/gh/introlab/rtabmap/graph/badge.svg?token=mPwvfZMOia)](https://codecov.io/gh/introlab/rtabmap)
[![License][license-image]][license]

[release-image]: https://img.shields.io/github/v/release/introlab/rtabmap?color=green&style=flat
[releases]: https://github.com/introlab/rtabmap/releases

[downloads-image]: https://img.shields.io/github/downloads/introlab/rtabmap/total?label=downloads
[downloads]: https://github.com/introlab/rtabmap/releases

[license-image]: https://img.shields.io/badge/license-BSD-green.svg?style=flat
[license]: https://github.com/introlab/rtabmap/blob/master/LICENSE

RTAB-Map library and standalone application.

 * For more information (e.g., papers, major updates), visit [RTAB-Map's home page](http://introlab.github.io/rtabmap).
 * For installation instructions and examples, visit [RTAB-Map's wiki](https://github.com/introlab/rtabmap/wiki).
 * For the C++ API of the library, see the [API documentation](https://introlab.github.io/rtabmap/api/latest/), which also lists all [parameters](https://introlab.github.io/rtabmap/api/latest/parameters.html) and [command-line tools](https://introlab.github.io/rtabmap/api/latest/tools.html).

To use RTAB-Map under ROS, visit the [rtabmap](http://wiki.ros.org/rtabmap) page on the ROS wiki.

### Acknowledgements
This project is supported by [IntRoLab - Intelligent / Interactive / Integrated / Interdisciplinary Robot Lab](https://introlab.3it.usherbrooke.ca/), Sherbrooke, Québec, Canada.

<a href="https://introlab.3it.usherbrooke.ca/">
<img src="https://github.com/introlab/16SoundsUSB/blob/master/images/IntRoLab.png" alt="IntRoLab" height="100">
</a>

#### CI Latest

| | Build |
|---|---|
| Desktop | [![Linux](https://github.com/introlab/rtabmap/actions/workflows/cmake-linux.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/cmake-linux.yml) [![Windows](https://github.com/introlab/rtabmap/actions/workflows/cmake-windows.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/cmake-windows.yml) [![macOS](https://github.com/introlab/rtabmap/actions/workflows/cmake-macos.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/cmake-macos.yml) |
| ROS | [![CMake ROS](https://github.com/introlab/rtabmap/actions/workflows/cmake-ros.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/cmake-ros.yml) [![Docker ROS](https://github.com/introlab/rtabmap/actions/workflows/docker-ros.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/docker-ros.yml) |
| Mobile | [![Android](https://github.com/introlab/rtabmap/actions/workflows/android.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/android.yml) [![iOS](https://github.com/introlab/rtabmap/actions/workflows/ios.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/ios.yml) |
| Quality | [![Coverage](https://github.com/introlab/rtabmap/actions/workflows/coverage.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/coverage.yml) [![Documentation](https://github.com/introlab/rtabmap/actions/workflows/docs.yml/badge.svg)](https://github.com/introlab/rtabmap/actions/workflows/docs.yml) |
 
 #### ROS Binaries
 
 `ros-$ROS_DISTRO-rtabmap`
 
| | Distro | Ubuntu | Released | In apt | Build |
|---|---|---|---|---|---|
| ROS 1 | Noetic (EOL) | 20.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Fnoetic%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/noetic/distribution.yaml) | [![apt](https://img.shields.io/ros/v/noetic/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#noetic) |  |
| ROS 2 | Humble | 22.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Fhumble%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/humble/distribution.yaml) | [![apt](https://img.shields.io/ros/v/humble/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#humble) | [![build](http://build.ros2.org/buildStatus/icon?job=Hbin_uJ64__rtabmap__ubuntu_jammy_amd64__binary)](http://build.ros2.org/job/Hbin_uJ64__rtabmap__ubuntu_jammy_amd64__binary/) |
| ROS 2 | Iron (EOL) | 22.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Firon%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/iron/distribution.yaml) | [![apt](https://img.shields.io/ros/v/iron/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#iron) |  |
| ROS 2 | Jazzy | 24.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Fjazzy%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/jazzy/distribution.yaml) | [![apt](https://img.shields.io/ros/v/jazzy/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#jazzy) | [![build](http://build.ros2.org/buildStatus/icon?job=Jbin_uN64__rtabmap__ubuntu_noble_amd64__binary)](http://build.ros2.org/job/Jbin_uN64__rtabmap__ubuntu_noble_amd64__binary/) |
| ROS 2 | Kilted | 24.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Fkilted%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/kilted/distribution.yaml) | [![apt](https://img.shields.io/ros/v/kilted/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#kilted) | [![build](http://build.ros2.org/buildStatus/icon?job=Kbin_uN64__rtabmap__ubuntu_noble_amd64__binary)](http://build.ros2.org/job/Kbin_uN64__rtabmap__ubuntu_noble_amd64__binary/) |
| ROS 2 | Lyrical | 26.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Flyrical%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/lyrical/distribution.yaml) | [![apt](https://img.shields.io/ros/v/lyrical/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#lyrical) | [![build](http://build.ros2.org/buildStatus/icon?job=Lbin_uR64__rtabmap__ubuntu_resolute_amd64__binary)](http://build.ros2.org/job/Lbin_uR64__rtabmap__ubuntu_resolute_amd64__binary/) |
| ROS 2 | Rolling | 26.04 | [![released](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fros%2Frosdistro%2Fmaster%2Frolling%2Fdistribution.yaml&query=%24.repositories.rtabmap.release.version&label=%20)](https://github.com/ros/rosdistro/blob/master/rolling/distribution.yaml) | [![apt](https://img.shields.io/ros/v/rolling/rtabmap?label=%20)](https://index.ros.org/p/rtabmap/#rolling) | [![build](http://build.ros2.org/buildStatus/icon?job=Rbin_uR64__rtabmap__ubuntu_resolute_amd64__binary)](http://build.ros2.org/job/Rbin_uR64__rtabmap__ubuntu_resolute_amd64__binary/) |
| Docker | [rtabmap](https://hub.docker.com/r/introlab3it/rtabmap) | | | ![Docker Pulls](https://img.shields.io/docker/pulls/introlab3it/rtabmap.svg?label=pulls) | |

*Released* is the version bloomed into [rosdistro](https://github.com/ros/rosdistro); *In apt* is what `apt install` actually gives you today. They differ while a release is waiting on a buildfarm sync.
