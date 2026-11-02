#!/bin/sh
# Archives MySelf, exports it signed for Developer ID, packages it as dist/MySelf-<version>.dmg, and notarizes and
# staples the DMG so Gatekeeper opens it without a warning. This is the only build with the GitHub update checker
# (DIRECT_DISTRIBUTION, plus the network entitlement it needs); App Store builds are archived from Xcode without it.
#
# One-time setup:
#   1. Xcode › Settings › Accounts › (team) › Manage Certificates › + › Developer ID Application
#   2. xcrun notarytool store-credentials myself-notary --apple-id <Apple ID> --team-id CR9Y3LFYH4
#      (password: an app-specific password from account.apple.com)
#
# Environment: TEAM_ID, NOTARY_PROFILE (default myself-notary), SKIP_NOTARIZE=1 to only sign.
set -eu

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID="${TEAM_ID:-CR9Y3LFYH4}"
NOTARY_PROFILE="${NOTARY_PROFILE:-myself-notary}"
BUILD=build
DIST=dist
ARCHIVE="$BUILD/Myself.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Myself.app"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
if [ -z "$IDENTITY" ]; then
  echo "No \"Developer ID Application\" certificate for team $TEAM_ID in the keychain." >&2
  echo "Create one in Xcode › Settings › Accounts › Manage Certificates." >&2
  exit 1
fi
echo "Signing with: $IDENTITY"

# iCloud (CloudKit) needs a provisioning profile, so the app is archived and then exported for Developer ID, which
# lets Xcode fetch the Developer ID profile and re-sign with the certificate above.
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive -project Myself.xcodeproj -scheme Myself -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" ENABLE_HARDENED_RUNTIME=YES \
  ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION' \
  | grep -E '^(\*\*|error|warning: .*error)' || true
[ -d "$ARCHIVE" ] || { echo "Archive failed: $ARCHIVE not found" >&2; exit 1; }

OPTIONS="$BUILD/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates | grep -E '^(\*\*|error)' || true

[ -d "$APP" ] || { echo "Export failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
# Outside the App Store, CloudKit must be told to use the production environment.
ENVIRONMENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -extract com\\.apple\\.developer\\.icloud-container-environment raw -o - - 2>/dev/null || true)
if [ "$ENVIRONMENT" != "Production" ]; then
  echo "The exported app's iCloud environment is \"${ENVIRONMENT:-missing}\", not Production; sync would fail for users." >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$DIST/MySelf-$VERSION.dmg"

rm -rf "$DIST/dmg" "$DMG"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname "MySelf" -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then
  echo "Skipped notarization: Gatekeeper will still warn about $DMG."
else
  echo "Notarizing (usually a few minutes)…"
  OUT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) || true
  echo "$OUT"
  if ! echo "$OUT" | grep -q "status: Accepted"; then
    ID=$(echo "$OUT" | sed -nE 's/^ *id: ([0-9a-f-]+).*/\1/p' | head -1)
    echo "Notarization failed. Details: xcrun notarytool log $ID --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1)), archs: $(lipo -archs "$APP/Contents/MacOS/Myself")"
