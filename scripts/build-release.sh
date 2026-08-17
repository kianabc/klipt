#!/bin/bash
#
# Build, Developer ID sign, and (optionally) notarize Klipt.
#
#   ./scripts/build-release.sh              # build + sign + verify
#   ./scripts/build-release.sh --notarize   # ...then notarize + staple
#
# Notarization needs a stored notarytool credential. Create it once yourself:
#
#   xcrun notarytool store-credentials klipt-notary \
#     --apple-id <your-apple-id> --team-id 7CMPG6N65Y --password <app-specific-password>
#
# Override the profile name with NOTARY_PROFILE=<name> if you use a different one.

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="7CMPG6N65Y"
IDENTITY="Developer ID Application: Kian Torimi ($TEAM_ID)"
NOTARY_PROFILE="${NOTARY_PROFILE:-klipt-notary}"

ARCHIVE="build/Klipt.xcarchive"
EXPORT_DIR="build/Release-export"
APP="$EXPORT_DIR/Klipt.app"
ZIP="build/Klipt.zip"
DMG_STAGING="build/dmg-staging"
SIGN_UPDATE="build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

# Version comes from project.yml so the DMG name matches the release tag.
MARKETING_VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
DMG="build/Klipt-${MARKETING_VERSION}.dmg"

NOTARIZE=false
[[ "${1:-}" == "--notarize" ]] && NOTARIZE=true

echo "==> Checking for signing identity"
if ! security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
    echo "error: no Developer ID cert for team $TEAM_ID in the keychain." >&2
    echo "       Install it from developer.apple.com or Xcode > Settings > Accounts." >&2
    exit 1
fi

echo "==> Regenerating Xcode project"
xcodegen generate

# Build number is the commit count: monotonically increasing, which is what
# Sparkle compares to decide an update is newer. The revision pins the exact
# source a build came from; -dirty means it had uncommitted changes.
BUILD_NUMBER=$(git rev-list --count HEAD)
GIT_REVISION=$(git rev-parse --short HEAD)
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    GIT_REVISION="${GIT_REVISION}-dirty"
fi
echo "==> Build $BUILD_NUMBER ($GIT_REVISION)"

echo "==> Archiving (Release)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
    -project Klipt.xcodeproj \
    -scheme Klipt \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath build/dd \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    KLIPT_GIT_REVISION="$GIT_REVISION"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR"

echo "==> Verifying signature"
# --deep --strict walks the Sparkle framework, Updater.app and both XPC services.
codesign --verify --deep --strict --verbose=2 "$APP"

# Every nested bundle must carry the Developer ID authority, not an ad-hoc one.
echo "==> Nested code signatures"
while IFS= read -r bundle; do
    authority=$(codesign -dvv "$bundle" 2>&1 | grep "^Authority=Developer ID" || true)
    if [[ -z "$authority" ]]; then
        echo "error: $bundle is not Developer ID signed" >&2
        exit 1
    fi
    label="${bundle#"$APP"/}"
    [[ "$label" == "$bundle" ]] && label="Klipt.app"
    printf '    %-58s %s\n' "$label" "ok"
done < <(find "$APP" \( -name "*.app" -o -name "*.framework" -o -name "*.xpc" \) -print)

echo "==> Checking hardened runtime"
# Capture first rather than piping into grep -q: an early-exiting grep SIGPIPEs
# codesign, and `set -o pipefail` would report that as a failure.
signing_info=$(codesign -d --verbose=2 "$APP" 2>&1)
if ! grep -q "flags=.*runtime" <<<"$signing_info"; then
    echo "error: hardened runtime not enabled" >&2
    exit 1
fi

echo "==> Packaging"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$NOTARIZE" == true ]]; then
    echo "==> Submitting to Apple for notarization (this takes a few minutes)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling ticket"
    xcrun stapler staple "$APP"

    echo "==> Repackaging stapled app"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"

    echo "==> Gatekeeper assessment"
    spctl -a -vvv -t exec "$APP"

    # The DMG is what people actually download, so it needs its own ticket —
    # a notarized app inside an unnotarized disk image still warns on open.
    echo "==> Building $DMG"
    rm -rf "$DMG_STAGING" "$DMG"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "Klipt" -srcfolder "$DMG_STAGING" \
        -ov -format UDZO -quiet "$DMG"
    rm -rf "$DMG_STAGING"

    echo "==> Notarizing the disk image"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -vvv -t open --context context:primary-signature "$DMG"

    echo "==> Signing the appcast enclosure"
    if [[ -x "$SIGN_UPDATE" ]]; then
        "$SIGN_UPDATE" "$DMG"
        echo "    length=$(stat -f%z "$DMG")"
    else
        echo "    sign_update not found at $SIGN_UPDATE — run it manually" >&2
    fi
else
    echo
    echo "Signed but NOT notarized — Gatekeeper will still block this on other Macs."
    echo "Run './scripts/build-release.sh --notarize' once notarytool credentials are stored."
fi

echo
echo "Done: $APP"
echo "      $ZIP"
[[ -f "$DMG" ]] && echo "      $DMG"
