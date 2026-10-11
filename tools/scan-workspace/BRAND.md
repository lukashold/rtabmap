# Kantura

Kantura is the independent measurement-oriented fork experience built on RTAB-Map.
The name combines the ideas of an edge (German **Kante**) and a contour.
The open room corner represents spatial capture; the mint dimension line represents measurement.

- Ink: `#251A40`
- Mint: `#70EDC5`
- Paper: `#F7F4FF`
- Interface accent: `#7050CE`

`public/kantura.svg` is the editable vector master. The iOS `KanturaIcon`
asset catalog contains opaque PNG exports of the same geometry, without rounded
corners baked into the icon. Original source and icon geometry are provided under
the repository's BSD-3-Clause license. Preserve RTAB-Map and dependency notices.

The name is a working product name. A preliminary web search on 2026-10-11 did
not identify a scanning app with this name; this does not reserve the name in App
Store Connect or establish trademark clearance. Complete that check before a
public commercial release.

The Xcode scheme remains `RTABMapApp` for build compatibility. Kantura's display
name and bundle identifier distinguish the fork from the upstream app.
