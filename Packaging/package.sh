#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Jin"
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG_PATH="$DIST/$APP_NAME.dmg"

cd "$ROOT"

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git ls-files dist | head -n 1)" ]]; then
    echo "Warning: dist/ is tracked by git in this checkout."
    echo "This script will rewrite dist/ and dirty your working tree."
    echo "Fix (once): git rm -r --cached dist && git commit -m \"chore: stop tracking dist\""
    echo
  fi
fi

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
cp "$ROOT/Packaging/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Copying SwiftPM resource bundles…"
shopt -s nullglob
copied_bundle_count=0
for bundle_dir in "$ROOT/.build/release" "$ROOT/.build/$(uname -m)-apple-macosx/release"; do
  for bundle in "$bundle_dir"/*.bundle; do
    bundle_name="$(basename "$bundle")"
    target_bundle="$APP_BUNDLE/Contents/Resources/$bundle_name"
    if [[ -e "$target_bundle" ]]; then
      continue
    fi
    cp -R "$bundle" "$target_bundle"
    copied_bundle_count=$((copied_bundle_count + 1))
  done
done
shopt -u nullglob

if [[ "$copied_bundle_count" -eq 0 ]]; then
  echo "Warning: no SwiftPM resource bundles found in release build outputs."
fi

echo "Preparing for ad-hoc code signing…"
chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
if [[ -z "${BUNDLE_ID:-}" ]]; then
  echo "Failed to resolve CFBundleIdentifier from Info.plist." >&2
  exit 1
fi

codesign --remove-signature "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
codesign --remove-signature "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Code signing app bundle (identifier: $BUNDLE_ID)…"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

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
