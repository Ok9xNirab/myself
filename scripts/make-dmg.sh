#!/bin/sh
# Builds a Developer ID signed Release MySelf.app, packages it as dist/MySelf-<version>.dmg, and notarizes and
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
APP="$BUILD/Build/Products/Release/Myself.app"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
if [ -z "$IDENTITY" ]; then
  echo "No \"Developer ID Application\" certificate for team $TEAM_ID in the keychain." >&2
  echo "Create one in Xcode › Settings › Accounts › Manage Certificates." >&2
  exit 1
fi
echo "Signing with: $IDENTITY"

xcodebuild -project Myself.xcodeproj -scheme Myself -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
  ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION' build | grep -E '^(\*\*|error|warning: .*error)' || true

[ -d "$APP" ] || { echo "Build failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

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
