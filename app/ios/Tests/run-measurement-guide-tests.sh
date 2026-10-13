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
  "$ios_dir/Tests/MeasurementGuide/main.swift" -o "$test_dir/guide-tests" 2> "$test_dir/compile.log" || {
  # Surface compiler errors as workflow annotations (readable via the API).
  grep -E "error:" "$test_dir/compile.log" | head -20 | sed 's/^/::error::/'
  cat "$test_dir/compile.log"
  exit 1
}
"$test_dir/guide-tests" "$ios_dir/RTABMapApp/MeasurementGuide.json" > "$test_dir/run.log" 2>&1 || {
  status=$?
  tail -5 "$test_dir/run.log" | sed 's/^/::error::/'
  cat "$test_dir/run.log"
  exit $status
}
cat "$test_dir/run.log"
