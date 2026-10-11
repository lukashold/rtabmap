# Development validation — 2026-10-11

The current preview is an independent Kantura branch, not an App Store release.

- 39 Node tests cover distance/height, concave and vertical polygons, scale,
  calibration, project ZIP roundtrips, CSV/SVG export, archive/path checks,
  OBJ/MTL, PLY and GLB loading, cloud request contracts and authenticated storage.
- Browser exercise on Windows/Edge: load synthetic room, click a two-point
  distance, trace a floor polygon, export a project ZIP, reopen it, connect to the
  local server, upload and reopen from the project library. The same two values
  were retained (4.560 m and 16.023 m² for the manually selected test points).
- Docker CI built the image, served the viewer, enforced authentication, saved and
  downloaded a ZIP, and read the same archive after restarting the container.
- Xcode 26.5 CI built the native app and produced an unsigned IPA. Swift checks
  for scan recovery and the five tutorial languages / workflow states passed.

The sample room is synthetic. These checks do not establish field measurement
accuracy. Test a real room and gate on the iPhone and compare several lengths
with a physical reference before relying on the results.

Google and Microsoft API operations and popup error handling are tested with
simulated responses. Real OAuth registration, consent, upload and download with
actual accounts remain unverified. Native Files provider export also needs a
real iPhone with the corresponding provider apps signed in.

Cloud projects are complete archives. Native AR measurements are not imported
from RTAB-Map databases into the browser; the browser stores its own annotations.
There is no automatic RoomPlan conversion, automatic wall classification, server
reconstruction, multi-user account system or live synchronization in this version.
