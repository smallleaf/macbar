#!/bin/bash
# Runs the verification suite: unit tests, build, and the headless self-check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> unit tests"
swift test

echo
echo "==> release build"
swift build -c release

echo
echo "==> app bundle"
Scripts/build.sh release "$@"

echo
echo "==> runtime self-check (read-only)"
"$ROOT/dist/MacBar.app/Contents/MacOS/MacBar" --self-check

echo
echo "==> all checks finished"
