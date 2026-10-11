#!/usr/bin/env bash
set -euo pipefail
ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc "$ios_dir/RTABMapApp/MeasurementGuide.swift" \
  "$ios_dir/Tests/MeasurementGuide/main.swift" -o "$test_dir/guide-tests"
"$test_dir/guide-tests" "$ios_dir/RTABMapApp/MeasurementGuide.json"
