#!/bin/bash
# Verifies that a freshly built bundle can create its menu bar status item.
#
# macOS 26 routes every status item through Control Center. A newly created item
# is registered asynchronously, so its window does not exist immediately after
# launch; this script starts the app, waits, and reports whether the item was laid
# out on screen. It is read-only and never synthesizes events.
#
# Usage:
#   Scripts/check_status_item.sh [path/to/MacBar.app] [timeout-seconds]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT/dist/MacBar.app}"
TIMEOUT="${2:-12}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

BINARY="$APP_BUNDLE/Contents/MacOS/MacBar"
LOG="$(mktemp)"

"$BINARY" --show-panel > "$LOG" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

FINDER='
import Cocoa
let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let pid = Int32(CommandLine.arguments[1])!
var found = false
for info in infos where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
    if (info[kCGWindowLayer as String] as? Int) == 25 {
        found = true
        print("status item: bounds=\(info[kCGWindowBounds as String] ?? [:]) onscreen=\(info[kCGWindowIsOnscreen as String] ?? false)")
    }
}
exit(found ? 0 : 1)
'

FINDER_FILE="$(mktemp -t macbar-status-finder).swift"
printf '%s\n' "$FINDER" > "$FINDER_FILE"

echo "==> waiting up to ${TIMEOUT}s for the status item of pid $PID"
STATUS=1
for _ in $(seq 1 "$TIMEOUT"); do
  sleep 1
  if swift "$FINDER_FILE" "$PID"; then
    STATUS=0
    break
  fi
done

echo
echo "==> app diagnostics"
grep -E "^(SMOKE|RESULT)" "$LOG" || true

if [[ $STATUS -ne 0 ]]; then
  echo
  echo "RESULT: FAIL status item was not laid out within ${TIMEOUT}s"
  echo "On macOS 26 this can happen when the menu bar is full or when Control Center hides the app."
  echo "Check System Settings > Menu Bar and remove some menu bar items."
  exit 1
fi

echo
echo "RESULT: OK status item is on screen"
