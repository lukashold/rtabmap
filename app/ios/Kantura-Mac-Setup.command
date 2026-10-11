#!/bin/bash
# Run on an Apple Silicon Mac: bash Kantura-Mac-Setup.command
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dieses Setup muss auf deinem MacBook ausgeführt werden."
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Bitte das Terminal nativ auf dem Mac mit Apple-Chip starten (ohne Rosetta)."
  exit 1
fi
for tool in git cmake curl unzip xcodebuild node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Fehlt: $tool. Xcode, CMake und Node.js 24 zuerst installieren."
    echo "Node.js: https://nodejs.org"
    exit 1
  fi
done
if [[ "$(node -p 'process.versions.node.split(".")[0]')" != "24" ]]; then
  echo "Dieses Setup benötigt Node.js 24 für den gebündelten Offline-Splat-Viewer."
  echo "Bitte Node.js 24 von https://nodejs.org installieren und erneut starten."
  exit 1
fi
if ! xcodebuild -version | head -n 1 | grep -Eq '^Xcode 26\.5([[:space:]]|$)'; then
  echo "Dieses Setup verwendet Bibliotheken für Xcode 26.5."
  echo "Bitte Xcode 26.5 auswählen oder die Quellbau-Anleitung in docs/APP-STORE-RELEASE.md nutzen."
  exit 1
fi
xcrun --sdk iphoneos --show-sdk-path >/dev/null
echo "Die vorgebauten VTK-Bibliotheken setzen iOS 26.5 voraus."
echo "Für ältere iOS-Versionen bitte die Quellbau-Anleitung verwenden."

setup_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checkout_dir="$setup_dir/kantura"
if [[ -e "$checkout_dir" ]]; then
  echo "Der Ordner existiert bereits: $checkout_dir"
  echo "Es wird nichts überschrieben. Vorhandenes Xcode-Projekt weiterverwenden."
  exit 1
fi

git clone --branch kantura/main --single-branch \
  https://github.com/lukashold/rtabmap.git "$checkout_dir"
cd "$checkout_dir"

# Run the exact package manager without a global installation or sudo. npm keeps
# its normal package cache; the dependency graph is fixed by pnpm-lock.yaml.
pnpm_cmd=(npm exec --yes --package=pnpm@11.25.0 -- pnpm)
echo "Erzeuge den lokalen iPhone-Splat-Viewer mit Node.js 24 und pnpm 11.25.0."
pushd tools/scan-workspace >/dev/null
if [[ "$("${pnpm_cmd[@]}" --version)" != "11.25.0" ]]; then
  echo "Die erwartete pnpm-Version 11.25.0 konnte nicht gestartet werden."
  exit 1
fi
"${pnpm_cmd[@]}" install --frozen-lockfile
"${pnpm_cmd[@]}" build:native-splat
popd >/dev/null
test -s app/ios/RTABMapApp/SplatViewerAssets/index.html
test -s app/ios/RTABMapApp/SplatViewerAssets/viewer.js
test -s app/ios/RTABMapApp/SplatViewerAssets/THIRD-PARTY-LICENSES.txt

bash app/ios/Tests/run-scan-tracking-tests.sh
bash app/ios/Tests/run-measurement-guide-tests.sh

# The same upstream archive and extraction layout used by the iOS CI workflow.
download_dir="$(mktemp -d)"
trap 'rm -rf -- "$download_dir"' EXIT
curl --fail --location --retry 2 \
  https://github.com/introlab/rtabmap/releases/download/0.23.1/libraries-ios-xcode26.5.zip \
  --output "$download_dir/deps.zip"
mkdir "$download_dir/extracted"
unzip -q "$download_dir/deps.zip" -d "$download_dir/extracted"
library_source="$download_dir/extracted"
if [[ -d "$library_source/Libraries" ]]; then
  library_source="$library_source/Libraries"
fi
test -d "$library_source/include"
test -d "$library_source/lib"
mkdir -p app/ios/RTABMapApp/Libraries
cp -R "$library_source"/. app/ios/RTABMapApp/Libraries/

cd app/ios/RTABMapApp
./install_deps.sh
open ../RTABMapApp.xcodeproj
printf '\nProjekt geöffnet. Jetzt in Xcode dein Signing-Team, eine eigene Bundle-ID\nund das verbundene iPhone auswählen, dann Product > Run.\n'
