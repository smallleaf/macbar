#!/bin/bash
# Submits the built app for notarization and staples the ticket.
#
# Prerequisites:
#   xcrun notarytool store-credentials "macbar-notary" \
#     --apple-id "<apple-id>" --team-id "<TEAM>" --password "<app-specific-password>"
#
# Usage:
#   Scripts/notarize.sh [path/to/MacBar.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT/dist/MacBar.app}"
PROFILE="${MACBAR_NOTARY_PROFILE:-macbar-notary}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  echo "run Scripts/build.sh release --sign 'Developer ID Application: ...' first" >&2
  exit 1
fi

echo "==> verifying signature"
codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --type execute --verbose "$APP_BUNDLE" || true

echo "==> creating archive"
ZIP="$(mktemp -d)/MacBar.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"

echo "==> submitting to notary service (profile: $PROFILE)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> stapling"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> gatekeeper check"
spctl --assess --type execute --verbose "$APP_BUNDLE"
echo "==> notarized: $APP_BUNDLE"
