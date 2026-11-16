#!/bin/bash
# Builds build/Keypoint.app. Usage: ./build.sh [run]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Keypoint.app
pkill -x Keypoint 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Keypoint"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. macOS ties the Accessibility grant to this signature, so each
# rebuild invalidates it — clear the stale entry so you get a fresh prompt.
codesign --force --sign "${CODESIGN_ID:--}" "$APP"
if [ -z "${CODESIGN_ID:-}" ]; then
  tccutil reset Accessibility local.keypoint >/dev/null 2>&1 || true
fi

echo "Built $APP"
if [ "${1:-}" = "run" ]; then open "$APP"; fi
