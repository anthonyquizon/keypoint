#!/bin/bash
# Builds build/Keypoint.app. Usage: ./build.sh [run | test]
set -euo pipefail
cd "$(dirname "$0")"

# ./build.sh test — compile the pure-logic sources with the tests and run them.
if [ "${1:-}" = "test" ]; then
  mkdir -p build
  swiftc -swift-version 5 -parse-as-library \
    Sources/Grid.swift Sources/KeyLayout.swift Tests/*.swift -o build/tests
  exec build/tests
fi

APP=build/Keypoint.app
pkill -x Keypoint 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Keypoint"
cp Info.plist "$APP/Contents/Info.plist"

# Sign with the "Keypoint Dev" certificate when it's in the keychain, so the
# Accessibility grant survives rebuilds. Override with CODESIGN_ID=...; set
# CODESIGN_ID=- to force ad-hoc.
DEFAULT_ID="Keypoint Dev"
if [ -z "${CODESIGN_ID:-}" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$DEFAULT_ID\""; then
  CODESIGN_ID="$DEFAULT_ID"
fi
if [ "${CODESIGN_ID:-}" = "-" ]; then CODESIGN_ID=""; fi

# Ad-hoc signature (no certificate). macOS ties the Accessibility grant to this
# signature, so each rebuild invalidates it — clear the stale entry so you get a
# fresh prompt.
codesign --force --sign "${CODESIGN_ID:--}" "$APP"
if [ -z "${CODESIGN_ID:-}" ]; then
  tccutil reset Accessibility local.keypoint >/dev/null 2>&1 || true
fi

echo "Built $APP"
if [ "${1:-}" = "run" ]; then open "$APP"; fi
