#!/bin/bash
# Packages the built app into a compressed DMG with a SHA256 checksum.
#
# Usage:
#   Scripts/make_dmg.sh [path/to/MacBar.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT/dist/MacBar.app}"
DIST_DIR="$(dirname "$APP_BUNDLE")"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
DMG="$DIST_DIR/MacBar-$VERSION-$BUILD.dmg"

echo "==> staging"
STAGE="$(mktemp -d)"
cp -R "$APP_BUNDLE" "$STAGE/MacBar.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<'TXT'
MacBar 安装说明
================

1. 将 MacBar.app 拖入「应用程序」文件夹，然后再打开。
   （请勿直接从 DMG 或临时目录运行，系统会把状态项当作匿名进程处理。）

2. 打开后若菜单栏没有出现 MacBar 图标：
   打开「系统设置 → 菜单栏」，在「允许在菜单栏中显示」列表里启用 MacBar。
   macOS 26 起菜单栏由系统统一托管，该开关关闭时图标不会显示。
   若已经开启仍不显示，请关闭开关再重新打开一次。

3. 授予「辅助功能」权限：
   「系统设置 → 隐私与安全性 → 辅助功能」中勾选 MacBar。
   该权限用于模拟拖拽移动菜单栏图标，是 macOS 上隐藏第三方图标的唯一可行方式。

   注意：如果你看到 MacBar 已勾选但仍提示需要授权，说明当前运行的版本
   与系统记录授权的版本不一致。请在辅助功能列表中选中 MacBar 点「−」移除，
   再点「+」重新添加当前应用，然后重新勾选。

4. 可选：在「屏幕录制」中授权 MacBar，以显示菜单栏图标的真实缩略图。
   未授权时使用应用图标代替，不影响隐藏/显示功能。

5. 点击菜单栏中的 MacBar 图标打开面板；右键图标可快速显示全部、重置布局。
   默认快捷键：⌥⌘H 切换隐藏区，⌥⌘⇧R 紧急恢复全部图标。

隐私：MacBar 完全在本机运行，不联网、不上传任何数据，配置与日志保存在
~/Library/Application Support/MacBar。

若系统提示无法验证开发者：本安装包使用 Apple Development 证书签名，未经过
公证。请在「系统设置 → 隐私与安全性」中点击「仍要打开」，或右键应用选择「打开」。
TXT

echo "==> creating $DMG"
rm -f "$DMG"
hdiutil create -volname "MacBar $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> checksums"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "==> done: $DMG"
