#!/usr/bin/env bash
# Build Tearoff for the iOS Simulator and print everything a driver needs to
# launch + control it: the .app path, the bundle id, and the simulator UDID.
#
# Usage:
#   .claude/skills/run-tearoff/build.sh [udid]
#
# If no UDID is given, uses the first booted "iPhone" simulator, or boots
# "iPhone 17 Pro" if none is booted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

UDID="${1:-}"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1 || true)"
fi
if [ -z "$UDID" ]; then
  echo "No booted simulator found — booting iPhone 17 Pro..." >&2
  UDID="$(xcrun simctl list devices available | grep 'iPhone 17 Pro (' | grep -o '[0-9A-F-]\{36\}' | head -1)"
  xcrun simctl boot "$UDID"
  open -a Simulator --args -CurrentDeviceUDID "$UDID"
  xcrun simctl bootstatus "$UDID" -b
fi

echo "Using simulator: $UDID" >&2

# project.yml is the source of truth (per CLAUDE.md) — Tearoff.xcodeproj is
# gitignored and regenerated. Skip if a stale .xcodeproj is already present
# and up to date, but regenerating is cheap and always safe.
xcodegen generate >&2

xcodebuild -project Tearoff.xcodeproj -scheme Tearoff -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" build \
  2>&1 | tail -20 >&2

DERIVED="$(xcodebuild -project Tearoff.xcodeproj -scheme Tearoff -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_PATH="$DERIVED/Tearoff.app"
BUNDLE_ID="com.tearoff.app"

echo "Installing + launching..." >&2
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >&2

# Machine-readable summary on stdout for a driver/agent to parse.
cat <<EOF
UDID=$UDID
APP_PATH=$APP_PATH
BUNDLE_ID=$BUNDLE_ID
EOF
