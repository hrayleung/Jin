#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Jin"
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG_PATH="$DIST/$APP_NAME.dmg"

cd "$ROOT"

rm -rf "$DIST"
mkdir -p "$DIST"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

echo "Cleaning stale SwiftPM resource bundles…"
shopt -s nullglob
for bundle in "$ROOT/.build/release"/*.bundle; do
  rm -rf "$bundle"
done

echo "Building (Release)…"
swift build -c release --disable-sandbox

BIN="$ROOT/.build/release/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "Expected binary not found: $BIN" >&2
  exit 1
fi

echo "Creating .app bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Copying SwiftPM resource bundles…"
shopt -s nullglob
for bundle in "$ROOT/.build/release"/*.bundle; do
  cp -R "$bundle" "$APP_BUNDLE/"
done

if [[ "${1-}" == "dmg" ]]; then
  echo "Creating .dmg…"
  DMG_ROOT="$DIST/dmg-root"
  mkdir -p "$DMG_ROOT"
  cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -sf /Applications "$DMG_ROOT/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
  echo "Done: $DMG_PATH"
else
  echo "Done: $APP_BUNDLE"
  echo "Tip: run with 'dmg' to also create a DMG:"
  echo "  bash Packaging/package.sh dmg"
fi
