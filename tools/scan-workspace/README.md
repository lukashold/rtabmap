# KANTURA measurement workspace

A browser workspace for measuring room scans and outdoor objects such as gates. Open a textured model, inspect it, mark distances or polygon areas, and save the model together with its measurements. The interface and the seven-step tutorial support German, French, Spanish, Italian and Simplified Chinese.

KANTURA is an independently developed RTAB-Map fork; the current source branch is [kantura/main](https://github.com/lukashold/rtabmap/tree/kantura/main). This workspace is its optional browser companion. It does not reconstruct RTAB-Map databases, run LiDAR capture in the browser, automatically recognize rooms, or promise survey-grade accuracy. The workflow takes inspiration from [Metaroom's guided capture](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/), with original interface code and content.

## Start on a computer

Use Node.js 24 and pnpm 11.25.0. Run from this directory in a complete repository checkout:

```sh
corepack enable
corepack prepare pnpm@11.25.0 --activate
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Open `http://localhost:4173`. The server binds to the local computer by default. A modern browser with WebGL is required. The built `dist` directory can also be served by an ordinary static HTTP server. Do not open `index.html` with `file://`; the app loads configuration and modules over HTTP. The build needs `app/ios/RTABMapApp/MeasurementGuide.json`, so copying only this tools directory before building is insufficient.

## Self-host with Docker

From the repository root:

```sh
docker compose -f tools/scan-workspace/compose.yaml up --build -d
```

Open `http://localhost:8090`. This serves the interface and tutorial pages on your own computer. See [server storage and deployment](README-server.md) for the optional persistent project library, its access token, volume, API and reverse-proxy configuration. Static-only hosting and server-side project storage are separate deployment choices.

The compose port is bound to `127.0.0.1`. For access from another computer, configure the documented reverse proxy and HTTPS on your own domain. Do not publish a write-enabled project library without access protection. The operator supplies public OAuth client IDs if direct cloud buttons are required; Docker does not create Microsoft or Google registrations.

## Measure a scan

1. On iPhone, capture in normal Mapping with LiDAR enabled. Save the original `.db`.
2. Assemble an optimized textured mesh and export the OBJ ZIP including its MTL and images. Use the iOS Files export to save to an installed, signed-in OneDrive or Google Drive provider, or transfer the ZIP another way.
3. Open that ZIP in the workspace. Confirm the unit and up axis; RTAB-Map models normally use metres and Z up. Inspect holes, duplicated surfaces and thin gate parts before measuring.
4. Select **Distance** and click two points. The result includes straight-line length, horizontal distance and height difference.
5. Select **Floor area**, click the floor corners in order, then finish. Top view and hiding the roof help. Concave outlines are supported; crossed outlines and duplicate points are rejected. Floor points must be approximately horizontal. Use **Surface area** for a planar wall or gate face.
6. Compare several distances against tape measurements. Calibration uses a known reference distance to change the global scale. It cannot repair local warping. Export a project ZIP before closing the page.

These are manually selected polygons, not automatic wall recognition or a RoomPlan/BIM export. An SVG is a drawing of the selected floor outlines. A textured surface shows visual context; its appearance alone does not establish geometric accuracy.

## Files and limits

| Input/output | Support |
| --- | --- |
| OBJ ZIP | One OBJ model, optional MTL and bundled texture images |
| Separate OBJ + assets | Select the OBJ, MTL and image files together |
| PLY | Mesh or point cloud; vertex colours when present |
| GLB | Self-contained binary glTF supported by the bundled loader; unsupported compression extensions need conversion first |
| `.rtabmeasure.zip` | Model assets plus the versioned `rtab-measure.json` measurement manifest |
| CSV | Measurement results in explicit metric units |
| SVG | Manually traced floor contours, lengths and areas |
| RTAB-Map `.db` | Keep as original; reconstruct/export with RTAB-Map before opening here |

Input is limited to **200 MiB** compressed/selected data, **500 MiB** declared and actual uncompressed ZIP content, and 2,000 ZIP entries. Exactly one model per import is accepted. The viewer limits geometry to 10 million vertices; memory limits of individual computers can be lower. Assets with unsafe paths, ambiguous references or external URLs are rejected. Large scans may need simplification in RTAB-Map before import.

## OneDrive integration

The iOS Files route works through the installed provider app and does not need OAuth IDs in this project. The web workspace additionally supports explicit upload/list/open of its project ZIPs through Microsoft Graph.

1. Register an application in [Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app). For the configured `common` authority, enable accounts in any organizational directory **and personal Microsoft accounts**.
2. Add the **Single-page application** platform with `http://localhost:4173/auth.html` for development, `http://localhost:8090/auth.html` for the default Docker URL, and the exact production URL, for example `https://scan.example.org/auth.html`. Use the same hostname when opening the app. See [redirect URI setup](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri).
3. Add the Microsoft Graph **delegated** permission `Files.ReadWrite.AppFolder`. The application uses `/me/drive/special/approot`; access is confined to its app folder. This works with home and work/school OneDrive, subject to the organization's consent policy. See [app folder permissions](https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder).
4. Copy the **Application (client) ID** into the workspace's cloud configuration, or provide `MICROSOFT_CLIENT_ID` to the server/container. Do not create or enter a client secret for this browser application.
5. Connect, upload a project, refresh the list and reopen it to verify geometry, textures, scale and measurements.

MSAL Browser 5 uses the bundled `auth.html` redirect bridge. Serve it without `Cross-Origin-Opener-Policy`; a reverse proxy must preserve that requirement. Microsoft explains the constraint in its [redirect bridge guide](https://learn.microsoft.com/en-us/entra/msal/javascript/browser/redirect-bridge).

## Google Drive integration

1. Create a Google Cloud project, enable the Google Drive API, configure the OAuth consent screen/audience, and add your test account while the application is in testing.
2. Create an OAuth client of type **Web application**. Add the exact authorized JavaScript origins: `http://localhost`, `http://localhost:4173`, `http://localhost:8090`, and your production origin such as `https://scan.example.org`. Origins contain no path. This implementation uses the GIS token popup, so it does not use a Google `auth.html` callback. See [Google client-ID setup](https://developers.google.com/identity/oauth2/web/guides/get-google-api-clientid).
3. Configure `https://www.googleapis.com/auth/drive.file` as the requested scope. It provides limited per-file access and is classified as non-sensitive; public deployment still needs the applicable OAuth branding/verification steps. See [Google Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).
4. Copy the public client ID ending in `.apps.googleusercontent.com` into cloud configuration, or provide `GOOGLE_CLIENT_ID` to the server/container. Do not enter a client secret.
5. Connect, upload a project and reopen it after refreshing the list. The app marks its created files with `appProperties.rtabMeasure=1` and lists these project packages. It does not include a Google Picker or enumerate arbitrary Drive folders.

Use the same origin throughout setup and testing; `localhost` and `127.0.0.1` are different origins. Allow the sign-in popup. For an existing raw scan in either provider, download/synchronize it and use **Open file**. Project uploads create timestamped files instead of replacing existing files.

## Data flow and operating status

Opening and measuring a local model happens in the browser. Downloaded project ZIPs contain the model and measurements; closing an unsaved browser session loses those edits. Cloud uploads occur only after the user chooses to upload. Optional self-host storage similarly requires an explicit save.

OAuth access tokens are kept in browser memory. Public client IDs and the chosen language may be saved in browser storage. Signing in contacts the selected identity provider; scans uploaded to a cloud provider are governed by that provider and account. Disconnecting clears this app's cached credentials; use the provider's account settings to revoke a grant completely. Server library storage and operator responsibilities are described in [README-server.md](README-server.md).

Cloud adapters have automated tests with simulated API responses. Real provider registration, consent, upload/download, large-file behavior and network interruption need validation against the deployment's actual accounts. An interrupted upload is reported as an error; automatic cross-session recovery is not implemented. Native camera behavior and measurement accuracy require real-device tests. No credentials, App Store approval or accuracy certification are supplied by this repository.

## Development

`pnpm test` covers measurement geometry, scale/calibration, ZIP parsing and project round trips, CSV escaping, server behavior and cloud request boundaries. `pnpm check` checks JavaScript syntax; `pnpm build` produces the static assets. Keep the tutorial source in `app/ios/RTABMapApp/MeasurementGuide.json` consistent with the actual native and desktop flows. See the [German measurement walkthrough](../../app/ios/MEASUREMENT-WORKFLOW.md) and [independent App Store release plan](../../docs/APP-STORE-RELEASE.md).

The repository's [BSD license](../../LICENSE) applies to project code; preserve bundled dependency notices when distributing the web build. Native iOS dependencies need a separate license audit before store distribution; the current dependency script enables components beyond the repository's BSD code.
