# RoomPlan measurement presentation

Kantura uses one presentation path for a newly captured room and a saved room.
`RoomPlanDocument.Surface.displayMeasurements` derives the following values from
the existing `kantura-room-plan` version 1 data:

| Surface | Displayed measurement | Source |
| --- | --- | --- |
| Wall, door, window, opening | Width in metres | Local `dimensions[0]` (X) |
| Wall, door, window, opening | Height in metres | Local `dimensions[1]` (Y) |
| Floor | Area in square metres | Area of the detected `polygonCorners` outline |

Width and height describe bounding extents, including for nonrectangular surfaces.
They are not world-axis spans. Kantura does not label the third dimension as wall
or floor thickness. A missing or degenerate floor outline displays an unavailable
message; the app never substitutes the area of the bounding rectangle. Concave
planar outlines retain their actual polygon area.

Recognition confidence concerns the identified element type. It is not a
dimensional accuracy estimate. Dimensions still need comparison with a physical
reference. These display changes provide neither a sensor accuracy certification
nor automatic alignment between rooms.

## Localization contract

The `roomPlan` dictionary has five new keys in all 15 guides:

| Key | Purpose |
| --- | --- |
| `dimensionWidth` | Label for local X extent |
| `dimensionHeight` | Label for local Y extent |
| `dimensionArea` | Label for detected floor area |
| `areaUnavailable` | Missing or unusable floor outline explanation |
| `confidenceHelp` | Separates recognition confidence from measurement accuracy |

The existing `verify` text now explains bounding extents instead of three
unlabelled lengths. Each dictionary contains 61 keys. The nine additional locale
packs and the bundled native guide remain synchronized; video scripts are
unchanged. These keys are UI strings, not additions to the interchange schema.
`displayMeasurements` is computed and is not serialized; JSON remains version 1.

## Sources and evidence limits

Apple documents [`dimensions`](https://developer.apple.com/documentation/roomplan/capturedroom/surface/dimensions)
as a surface's bounding box and [`polygonCorners`](https://developer.apple.com/documentation/roomplan/capturedroom/surface/polygoncorners)
as a polygon expressed in local plane coordinates.
[`confidence`](https://developer.apple.com/documentation/roomplan/capturedroom/surface/confidence)
concerns certainty in the surface category.

Apple's [WWDC22 RoomPlan session](https://developer.apple.com/videos/play/wwdc2022/10127/)
describes architectural surfaces as two-dimensional planar structures. The
[WWDC23 update](https://developer.apple.com/videos/play/wwdc2023/10192/)
explains polygon representations for nonuniform walls and completed floors.
The public API pages, these sessions, and Apple's basic capture sample do not
explicitly promise the component-to-label mapping. The X-width/Y-height
convention matches Kantura's existing browser converter and the independent
developer's implementation in [Apple Developer Forums thread 713409](https://developer.apple.com/forums/thread/713409).
That forum contribution is additional implementation evidence, not a formal
Apple API guarantee. Representative captures should still be checked on-device.

Foundation regression cases in `app/ios/Tests/MeasurementGuide/main.swift` cover
local-axis values under rotation, all four vertical surface types, a concave
floor, missing and degenerate outlines, invalid dimensions, and unchanged JSON
serialization. Run `app/ios/Tests/run-measurement-guide-tests.sh` with Swift on
macOS; the Node integration tests check all 15 language dictionaries and their
native/browser synchronization.
