#!/usr/bin/env bash
set -euo pipefail
ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -O "$ios_dir/RTABMapApp/MeasurementGuide.swift" \
  "$ios_dir/RTABMapApp/RoomPlanDocument.swift" \
  "$ios_dir/RTABMapApp/RoomPlanSummary.swift" \
  "$ios_dir/RTABMapApp/RoomPhotoSet.swift" \
  "$ios_dir/RTABMapApp/TransportAssessment.swift" \
  "$ios_dir/RTABMapApp/RoomExport.swift" \
  "$ios_dir/RTABMapApp/RoomExtras.swift" \
  "$ios_dir/RTABMapApp/PhotoDataset.swift" \
  "$ios_dir/RTABMapApp/MediaDataset.swift" \
  "$ios_dir/RTABMapApp/PhotoQuality.swift" \
  "$ios_dir/RTABMapApp/SplatDocument.swift" \
  "$ios_dir/RTABMapApp/StairScan.swift" \
  "$ios_dir/Tests/MeasurementGuide/main.swift" -o "$test_dir/guide-tests"
"$test_dir/guide-tests" "$ios_dir/RTABMapApp/MeasurementGuide.json"
