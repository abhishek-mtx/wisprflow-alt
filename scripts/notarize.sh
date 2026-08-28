#!/usr/bin/env bash
# Notarize a Release build of Cadence and wrap it in a stapled .dmg.
# Requires: full Xcode, Developer ID Application certificate, notarytool credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Cadence"
APP_NAME="Cadence"
BUILD_DIR="${ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/Cadence.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/Cadence.zip"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_PATH="${BUILD_DIR}/Cadence.dmg"

TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CadenceNotary}"

if [[ -z "${TEAM_ID}" ]]; then
  echo "Set TEAM_ID to your Apple Developer Team ID."
  exit 1
fi

mkdir -p "${BUILD_DIR}"

echo "==> Generating Xcode project"
(cd "${ROOT}" && xcodegen generate)

echo "==> Archiving"
xcodebuild archive \
  -project "${ROOT}/WisprFlowAlt.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Automatic \
  ENABLE_HARDENED_RUNTIME=YES

echo "==> Exporting Developer ID app"
cat > "${BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

echo "==> Zipping for notarization"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Submitting for notarization"
if [[ -n "${APPLE_ID}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "${ZIP_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "${APP_SPECIFIC_PASSWORD}" \
    --wait
else
  xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
fi

echo "==> Stapling app"
xcrun stapler staple "${APP_PATH}"

echo "==> Creating DMG"
rm -rf "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
hdiutil create -volname "Cadence" -srcfolder "${DMG_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "Done."
echo "  App: ${APP_PATH}"
echo "  DMG: ${DMG_PATH}"
echo "Share the DMG with your team. Do not send unsigned DerivedData builds."
