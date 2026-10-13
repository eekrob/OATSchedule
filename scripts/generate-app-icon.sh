#!/usr/bin/env bash
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT="$ROOT/Sources/OATSchedule/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

# Xcode build phases inherit SDKROOT=iphonesimulator/iphoneos. The icon
# generator itself is a macOS command-line Swift script, so explicitly remove
# the target SDK environment and run it with the macOS SDK.
env -u SDKROOT -u SWIFT_EXEC xcrun --sdk macosx swift   "$ROOT/scripts/generate-app-icon.swift"   "$OUTPUT"

test -s "$OUTPUT"

echo "App icon ready: $OUTPUT"
