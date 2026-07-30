#!/bin/bash
#
# Archive the app and upload the build to App Store Connect.
#
# Everything lands in build/, which is gitignored - never stage it (a stray
# `git add -A` once swept 2822 derived-data files into the repo).
#
# Prereqs: ASC_KEY_ID and ASC_ISSUER_ID in the environment, and the matching
# AuthKey_<KEY_ID>.p8 in ~/.appstoreconnect/private_keys/ (where altool looks
# for it on its own - it takes the key id, not a path).
#
# Usage:
#   scripts/archive-and-upload.sh              # archive, export, validate, upload
#   scripts/archive-and-upload.sh --dry-run    # stop after validation
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Tearoff.xcodeproj"
SCHEME="Tearoff"
TEAM_ID="A6H72TGWNL"
ARCHIVE="build/Tearoff.xcarchive"
EXPORT_DIR="build/export"

: "${ASC_KEY_ID:?ASC_KEY_ID is not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" App/Info.plist)
WIDGET_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" TearoffWidgets/Info.plist)

# A mismatch here is rejected at upload, after the slow part has already run.
if [ "$BUILD" != "$WIDGET_BUILD" ]; then
  echo "ERROR app build ($BUILD) and widget build ($WIDGET_BUILD) differ - fix project.yml and re-run xcodegen" >&2
  exit 1
fi

echo "==> Archiving $VERSION ($BUILD)"
# The project is generated, so regenerate first: a file added under App/ since
# the last run is otherwise silently missing from the target.
xcodegen generate
rm -rf "$ARCHIVE" "$EXPORT_DIR"

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"

echo "==> Exporting .ipa"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"

IPA=$(find "$EXPORT_DIR" -name '*.ipa' -maxdepth 1 | head -1)
[ -n "$IPA" ] || { echo "ERROR no .ipa produced in $EXPORT_DIR" >&2; exit 1; }

echo "==> Validating $IPA"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [ "${1:-}" = "--dry-run" ]; then
  echo "Validated $VERSION ($BUILD). Stopping before upload (--dry-run)."
  exit 0
fi

echo "==> Uploading"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded $VERSION ($BUILD)."
echo "Processing takes ~5-15 min. Once it finishes, attach the build to the"
echo "$VERSION version in App Store Connect, add release notes, then run:"
echo "  python3 scripts/asc-submit-for-review.py --apply"
