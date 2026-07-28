#!/usr/bin/env bash
# build-release.sh — Build, Developer ID–sign, and package Canvas Library for distribution.
#
# Usage (from repo root or anywhere):
#   ./scripts/build-release.sh
#   ./scripts/build-release.sh --zip          # zip only (skip DMG)
#   ./scripts/build-release.sh --dmg          # DMG only (default prefers DMG, falls back to zip)
#
# Signing identity:
#   Developer ID Application: Ryan Loechner (44N969GC55)
#
# Notarization (optional next step — secrets must NOT live in this repo):
#   After packaging, run ./scripts/notarize.sh with credentials from the environment
#   or Keychain. Example placeholders for notarytool (do not commit real values):
#
#   export APPLE_ID="your-apple-id@example.com"
#   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # appleid.apple.com → App-Specific Passwords
#   export TEAM_ID="44N969GC55"
#   # Or store a profile once:
#   # xcrun notarytool store-credentials "AC_PASSWORD" \
#   #   --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD"
#   ./scripts/notarize.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM_ID="44N969GC55"
SIGN_IDENTITY="Developer ID Application: Ryan Loechner (44N969GC55)"
SCHEME="CanvasLibrary"
PROJECT=""
TARGET_NAME="CanvasLibrary"
PRODUCT_DISPLAY_NAME="Canvas Library"
DIST_DIR="${ROOT}/dist"
# Keep intermediate builds outside iCloud Desktop/Documents — codesign rejects
# resource forks / Finder metadata that File Provider attaches under those trees.
BUILD_DIR="${CANVAS_LIBRARY_BUILD_DIR:-/tmp/CanvasLibrary-release}"
ARCHIVE_FORMAT="auto" # auto | dmg | zip

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip) ARCHIVE_FORMAT="zip"; shift ;;
    --dmg) ARCHIVE_FORMAT="dmg"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ -d "${ROOT}/CanvasLibrary.xcodeproj" ]]; then
  PROJECT="${ROOT}/CanvasLibrary.xcodeproj"
else
  echo "error: CanvasLibrary.xcodeproj not found in ${ROOT}" >&2
  exit 1
fi

echo "==> Project:  ${PROJECT}"
echo "==> Scheme:   ${SCHEME}"
echo "==> Team:     ${TEAM_ID}"
echo "==> Identity: ${SIGN_IDENTITY}"

mkdir -p "${DIST_DIR}" "${BUILD_DIR}"

# Clean derived products for this Release build.
rm -rf "${BUILD_DIR}/DerivedData" "${BUILD_DIR}/export"
mkdir -p "${BUILD_DIR}/DerivedData" "${BUILD_DIR}/export"

echo "==> Build dir: ${BUILD_DIR}"
echo "==> Building Release (macOS)…"
# Sign during build so Swift stdlib copy is signed; re-sign deep afterward.
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  -destination "platform=macOS" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

APP_SRC="${BUILD_DIR}/DerivedData/Build/Products/Release/${TARGET_NAME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
  # Fallback: find the built .app under Products/Release
  APP_SRC="$(find "${BUILD_DIR}/DerivedData/Build/Products/Release" -maxdepth 1 -name '*.app' -type d | head -n 1 || true)"
fi
if [[ -z "${APP_SRC}" || ! -d "${APP_SRC}" ]]; then
  echo "error: built .app not found under ${BUILD_DIR}/DerivedData/Build/Products/Release" >&2
  exit 1
fi

APP_NAME="$(basename "${APP_SRC}")"
APP_DEST="${BUILD_DIR}/export/${APP_NAME}"
rm -rf "${APP_DEST}"
# ditto preserves content cleanly; prefer over cp -R for bundles
ditto "${APP_SRC}" "${APP_DEST}"

strip_xattrs() {
  local target="$1"
  /usr/bin/xattr -cr "${target}" 2>/dev/null || true
  /usr/bin/find "${target}" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
  # Some attributes reappear if the tree sits under iCloud; strip common offenders.
  /usr/bin/xattr -dr com.apple.FinderInfo "${target}" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.fileprovider.fpfs#P "${target}" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.provenance "${target}" 2>/dev/null || true
}

echo "==> Stripping extended attributes…"
strip_xattrs "${APP_DEST}"

echo "==> Codesigning ${APP_NAME} with Developer ID (deep, runtime, timestamp)…"
# Re-sign nested code first, then the app bundle (hardened runtime required for notarization).
codesign --force --deep --options runtime --timestamp \
  --sign "${SIGN_IDENTITY}" \
  "${APP_DEST}"

echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "${APP_DEST}"
spctl --assess --type execute --verbose=4 "${APP_DEST}" 2>&1 || {
  echo "note: spctl assess may fail until the app is notarized; codesign verify passed."
}

# Marketing version for artifact names
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_DEST}/Contents/Info.plist" 2>/dev/null || echo "1.0")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_DEST}/Contents/Info.plist" 2>/dev/null || echo "1")"
SAFE_NAME="$(echo "${PRODUCT_DISPLAY_NAME}" | tr ' ' '-')"
ARTIFACT_BASE="${SAFE_NAME}-${VERSION}"

package_zip() {
  local zip_path="${DIST_DIR}/${ARTIFACT_BASE}.zip"
  echo "==> Creating zip: ${zip_path}"
  rm -f "${zip_path}"
  ditto -c -k --keepParent "${APP_DEST}" "${zip_path}"
  echo "    ${zip_path}"
}

package_dmg() {
  local dmg_path="${DIST_DIR}/${ARTIFACT_BASE}.dmg"
  local vol_name="${PRODUCT_DISPLAY_NAME}"
  local stage="${BUILD_DIR}/dmg-stage"
  echo "==> Creating DMG: ${dmg_path}"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  ditto "${APP_DEST}" "${stage}/${APP_NAME}"
  # Optional Applications symlink for drag-install UX
  ln -sf /Applications "${stage}/Applications"
  rm -f "${dmg_path}"
  hdiutil create \
    -volname "${vol_name}" \
    -srcfolder "${stage}" \
    -ov -format UDZO \
    "${dmg_path}"
  rm -rf "${stage}"
  echo "    ${dmg_path}"
}

case "${ARCHIVE_FORMAT}" in
  zip)
    package_zip
    ;;
  dmg)
    package_dmg
    ;;
  auto)
    if package_dmg; then
      :
    else
      echo "warn: DMG creation failed; falling back to zip" >&2
      package_zip
    fi
    ;;
esac

echo ""
echo "Done."
echo "  App:     ${APP_DEST}"
echo "  Dist:    ${DIST_DIR}/"
echo "  Signed:  ${SIGN_IDENTITY}"
echo ""
echo "Next (notarization — credentials via env / Keychain only):"
echo "  export APPLE_ID=\"your-apple-id@example.com\""
echo "  export APP_SPECIFIC_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
echo "  export TEAM_ID=\"${TEAM_ID}\""
echo "  ./scripts/notarize.sh"
echo ""
echo "  # Or with a stored notarytool profile:"
echo "  # xcrun notarytool store-credentials \"AC_PASSWORD\" \\"
echo "  #   --apple-id \"\$APPLE_ID\" --team-id \"\$TEAM_ID\" --password \"\$APP_SPECIFIC_PASSWORD\""
echo "  # NOTARY_PROFILE=AC_PASSWORD ./scripts/notarize.sh"
