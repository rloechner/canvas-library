#!/usr/bin/env bash
# notarize.sh — Submit a Release artifact to Apple notarization and staple the ticket.
#
# Prerequisites:
#   1. Build & sign first:  ./scripts/build-release.sh
#   2. Apple Developer account with Developer ID certificates
#   3. Credentials (never commit secrets):
#
# Option A — environment variables:
#   export APPLE_ID="your-apple-id@example.com"
#   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # App-Specific Password from appleid.apple.com
#   export TEAM_ID="44N969GC55"
#
# Option B — Keychain profile (recommended):
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#     --apple-id "$APPLE_ID" \
#     --team-id "$TEAM_ID" \
#     --password "$APP_SPECIFIC_PASSWORD"
#   export NOTARY_PROFILE="AC_PASSWORD"
#
# Usage:
#   ./scripts/notarize.sh                    # auto-pick latest dist/*.dmg or dist/*.zip
#   ./scripts/notarize.sh path/to/App.dmg
#   ./scripts/notarize.sh path/to/App.app    # zips temp for submit, staples .app
#
# Apple docs: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT}/dist"
TEAM_ID="${TEAM_ID:-44N969GC55}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

pick_artifact() {
  if [[ $# -ge 1 && -e "$1" ]]; then
    echo "$1"
    return
  fi
  local candidate
  candidate="$(ls -t "${DIST_DIR}"/*.dmg 2>/dev/null | head -n 1 || true)"
  if [[ -z "${candidate}" ]]; then
    candidate="$(ls -t "${DIST_DIR}"/*.zip 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "${candidate}" ]]; then
    # Fall back to export app from last build-release
    if [[ -d "${ROOT}/build/release/export" ]]; then
      candidate="$(find "${ROOT}/build/release/export" -maxdepth 1 -name '*.app' -type d | head -n 1 || true)"
    fi
  fi
  if [[ -z "${candidate}" ]]; then
    echo "error: no artifact found. Pass a path or run ./scripts/build-release.sh first." >&2
    exit 1
  fi
  echo "${candidate}"
}

ARTIFACT="$(pick_artifact "${@:-}")"
echo "==> Artifact: ${ARTIFACT}"

SUBMIT_PATH="${ARTIFACT}"
STAPLE_TARGET=""
TMP_ZIP=""

cleanup() {
  if [[ -n "${TMP_ZIP}" && -f "${TMP_ZIP}" ]]; then
    rm -f "${TMP_ZIP}"
  fi
}
trap cleanup EXIT

if [[ -d "${ARTIFACT}" && "${ARTIFACT}" == *.app ]]; then
  # notarytool wants a zip/dmg/pkg for .app bundles
  TMP_ZIP="$(mktemp -t canvaslibrary-notary).zip"
  echo "==> Zipping .app for submission…"
  ditto -c -k --keepParent "${ARTIFACT}" "${TMP_ZIP}"
  SUBMIT_PATH="${TMP_ZIP}"
  STAPLE_TARGET="${ARTIFACT}"
elif [[ "${ARTIFACT}" == *.dmg ]]; then
  STAPLE_TARGET="${ARTIFACT}"
elif [[ "${ARTIFACT}" == *.zip ]]; then
  # Zip of an app: staple is applied to the .app after unzip, or re-zip flow.
  # We staple the zip's contained app if we can unpack next to dist.
  STAPLE_TARGET=""
else
  echo "error: unsupported artifact type (expect .app, .dmg, or .zip): ${ARTIFACT}" >&2
  exit 1
fi

auth_args=()
if [[ -n "${NOTARY_PROFILE}" ]]; then
  echo "==> Using notarytool Keychain profile: ${NOTARY_PROFILE}"
  auth_args=(--keychain-profile "${NOTARY_PROFILE}")
else
  # Placeholders — set via environment; do not hardcode secrets.
  : "${APPLE_ID:?Set APPLE_ID (Apple ID email) or NOTARY_PROFILE}"
  : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD or NOTARY_PROFILE}"
  : "${TEAM_ID:?Set TEAM_ID (default 44N969GC55)}"
  echo "==> Using APPLE_ID / APP_SPECIFIC_PASSWORD / TEAM_ID from environment"
  auth_args=(
    --apple-id "${APPLE_ID}"
    --password "${APP_SPECIFIC_PASSWORD}"
    --team-id "${TEAM_ID}"
  )
fi

echo "==> Submitting to Apple notary service (this can take several minutes)…"
# Example (documented placeholders only — values come from env/profile above):
#   xcrun notarytool submit "$SUBMIT_PATH" \
#     --apple-id "your-apple-id@example.com" \
#     --password "xxxx-xxxx-xxxx-xxxx" \
#     --team-id "44N969GC55" \
#     --wait
xcrun notarytool submit "${SUBMIT_PATH}" \
  "${auth_args[@]}" \
  --wait

echo "==> Submission complete."

if [[ -n "${STAPLE_TARGET}" ]]; then
  echo "==> Stapling notarization ticket to ${STAPLE_TARGET}…"
  xcrun stapler staple "${STAPLE_TARGET}"
  xcrun stapler validate "${STAPLE_TARGET}"
  echo "==> Staple OK."
else
  echo "note: artifact is a zip; staple the .app after unzip, e.g.:"
  echo "  unzip -q \"${ARTIFACT}\" -d /tmp/staple-out"
  echo "  xcrun stapler staple /tmp/staple-out/*.app"
  echo "  # then re-package if needed"
fi

# Optional Gatekeeper check on stapled app/dmg
if [[ -n "${STAPLE_TARGET}" ]]; then
  echo "==> Gatekeeper assessment…"
  spctl --assess --type open --context context:primary-signature --verbose=4 "${STAPLE_TARGET}" 2>&1 \
    || spctl --assess --type execute --verbose=4 "${STAPLE_TARGET}" 2>&1 \
    || echo "note: re-check after distributing the stapled artifact."
fi

echo ""
echo "Notarization finished for: ${ARTIFACT}"
