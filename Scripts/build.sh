#!/bin/bash
# Builds MacBar.app from the Swift package.
#
# Usage:
#   Scripts/build.sh [debug|release] [--sign "Developer ID Application: Name (TEAM)"]
#
# Signing:
#   - A certificate identity is auto-detected (Developer ID first, then Apple
#     Development) unless --sign is given.
#   - Certificate signing keeps the Accessibility grant across rebuilds because
#     TCC matches the designated requirement, not the CDHash.
#   - With no certificate (or --adhoc) the bundle is signed ad-hoc. macOS then
#     records the grant against each build's CDHash, so every rebuild requires the
#     permission to be granted again. The app detects this and explains it.
#   - MACBAR_SIGN_IDENTITY / MACBAR_ADHOC=1 override the detection.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
IDENTITY="${MACBAR_SIGN_IDENTITY:-}"
APP_NAME="MacBar"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="${MACBAR_VERSION:-1.0.0}"
BUILD_NUMBER="${MACBAR_BUILD:-$(date +%Y%m%d%H%M)}"

ADHOC_ONLY="${MACBAR_ADHOC:-0}"

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) IDENTITY="$2"; shift 2 ;;
    --adhoc) ADHOC_ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Auto-detect a stable identity so development builds keep their TCC grant.
if [[ -z "$IDENTITY" && "$ADHOC_ONLY" != "1" ]]; then
  # `|| true` keeps `set -e` from aborting when no identity matches.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)"
  fi
  if [[ -n "$IDENTITY" ]]; then
    echo "==> auto-detected signing identity: $IDENTITY"
  fi
fi

echo "==> building ($CONFIGURATION)"
cd "$ROOT"
swift build -c "$CONFIGURATION"

BINARY="$BUILD_DIR/$CONFIGURATION/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
  echo "binary not found at $BINARY" >&2
  exit 1
fi

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.miyuan.macbar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>MacBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 MacBar</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.miyuan.macbar</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>macbar</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Resources: keep the icon if one exists, otherwise the app uses an SF Symbol.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> signing"
if [[ -n "$IDENTITY" ]]; then
  # --timestamp is only meaningful for Developer ID; it is harmless otherwise but
  # would fail without network access, so it is limited to Developer ID.
  if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ROOT/Resources/MacBar.entitlements" \
      --sign "$IDENTITY" "$APP_BUNDLE"
  else
    codesign --force --options runtime \
      --entitlements "$ROOT/Resources/MacBar.entitlements" \
      --sign "$IDENTITY" "$APP_BUNDLE"
  fi
  echo "    signed with: $IDENTITY"
  echo "    Accessibility grant stays valid across rebuilds."
else
  echo "    WARNING: no signing certificate found, using ad-hoc signature."
  echo "    macOS binds the Accessibility grant to this build's CDHash, so the"
  echo "    permission must be granted again after every rebuild."
  codesign --force --sign - --entitlements "$ROOT/Resources/MacBar.entitlements" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> signature identity"
codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature|CDHash" || true

echo "==> done: $APP_BUNDLE"
echo "    version $VERSION ($BUILD_NUMBER)"
