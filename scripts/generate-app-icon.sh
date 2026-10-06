#!/usr/bin/env bash
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT="$ROOT/Sources/OATSchedule/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

xcrun swift "$ROOT/scripts/generate-app-icon.swift" "$OUTPUT"
test -s "$OUTPUT"

echo "App icon ready: $OUTPUT"
