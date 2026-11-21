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

normalize_short_version() {
  local version="$1"

  if [[ "$version" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0"
    return
  fi

  if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    return
  fi

  return 1
}

resolve_version() {
  local default_version="$1"
  local normalized_version

  if [[ -n "${JIN_BUNDLE_SHORT_VERSION:-}" ]]; then
    normalized_version="$(normalize_short_version "$JIN_BUNDLE_SHORT_VERSION")" || {
      echo "JIN_BUNDLE_SHORT_VERSION must be a stable marketing version like 0.87.0." >&2
      exit 1
    }
    echo "$normalized_version"
    return
  fi

  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local release_tag
    release_tag="$(git -C "$ROOT" describe --tags --exact-match --match 'v*' 2>/dev/null || true)"
    if [[ -n "$release_tag" ]]; then
      normalized_version="$(normalize_short_version "${release_tag#v}" 2>/dev/null || true)"
      if [[ -n "$normalized_version" ]]; then
        echo "$normalized_version"
        return
      fi
    fi

    release_tag="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
    if [[ -n "$release_tag" ]]; then
      normalized_version="$(normalize_short_version "${release_tag#v}" 2>/dev/null || true)"
      if [[ -n "$normalized_version" ]]; then
        echo "$normalized_version"
        return
      fi
    fi
  fi

  normalized_version="$(normalize_short_version "$default_version")" || {
    echo "Default app version must be a stable marketing version like 0.1.0." >&2
    exit 1
  }
  echo "$normalized_version"
}

require_architecture() {
  local binary_path="$1"
  local expected_arch="$2"
  local display_name="${3:-$binary_path}"
  local binary_archs

  binary_archs="$(lipo -archs "$binary_path" 2>/dev/null || true)"
  if [[ -z "$binary_archs" ]]; then
    echo "Failed to inspect architectures for $display_name: $binary_path" >&2
    exit 1
  fi
  if [[ " $binary_archs " != *" $expected_arch "* ]]; then
    echo "Error: $display_name is missing required '$expected_arch' slice ($binary_archs)." >&2
    exit 1
  fi
}

echo "Cleaning stale SwiftPM resource bundles…"
shopt -s nullglob
for bundle in \
  "$ROOT/.build/release"/*.bundle \
  "$ROOT/.build/arm64-apple-macosx/release"/*.bundle \
  "$ROOT/.build/out/Products/Release"/*.bundle; do
  rm -rf "$bundle"
done
shopt -u nullglob

ARCH="arm64"

# SwiftPM's legacy `native` build system generates Bundle.module accessors that
# search `Bundle.main.bundleURL/<Name>.bundle` (the .app root, not
# Contents/Resources) and fall back to a hardcoded `.build/...` path on the
# build machine, causing an immediate fatalError on other Macs when SwiftMath,
# Highlighter, or Jin loads resources. Always use `swiftbuild`, which resolves
# `Bundle.main.resourceURL` (Contents/Resources) and emits standard macOS
# resource bundles.
BUILD_SYSTEM_ARGS=()
if swift build --help 2>&1 | grep -Fq -- "--build-system"; then
  BUILD_SYSTEM_ARGS=(--build-system swiftbuild)
else
  echo "Error: installed Swift toolchain does not support '--build-system swiftbuild'." >&2
  echo "Use Xcode / Swift 6.3+ so Bundle.module resolves Contents/Resources in macOS .app bundles." >&2
  exit 1
fi

echo "Building (Release) for Apple Silicon…"
swift build "${BUILD_SYSTEM_ARGS[@]}" -c release --disable-sandbox --arch "$ARCH"

# Resolve the products dir AFTER building, from SwiftPM itself — its layout
# varies across SwiftPM versions/build systems, and a stale build dir must not
# shadow the fresh binary.
BUILD_OUTPUT_DIR="$(swift build "${BUILD_SYSTEM_ARGS[@]}" -c release --disable-sandbox --arch "$ARCH" --show-bin-path)"

BIN="$BUILD_OUTPUT_DIR/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "Expected binary not found: $BIN" >&2
  exit 1
fi
require_architecture "$BIN" "$ARCH" "$APP_NAME"

echo "Creating .app bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
APP_SHORT_VERSION="$(resolve_version 0.1.0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_SHORT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
APP_BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
if [[ "$APP_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi

echo "Copying app icon…"
cp "$ROOT/Packaging/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Copying SwiftPM resource bundles…"
shopt -s nullglob
copied_bundle_count=0
for bundle in "$BUILD_OUTPUT_DIR"/*.bundle; do
  bundle_name="$(basename "$bundle")"
  target_bundle="$APP_BUNDLE/Contents/Resources/$bundle_name"
  cp -R "$bundle" "$target_bundle"
  copied_bundle_count=$((copied_bundle_count + 1))
done
shopt -u nullglob

if [[ "$copied_bundle_count" -eq 0 ]]; then
  echo "Error: no SwiftPM resource bundles found in release build outputs." >&2
  exit 1
fi

echo "Verifying SwiftPM resource bundles…"
if strings "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -Fq "could not load resource bundle: from "; then
  echo "Error: packaged binary contains legacy native SwiftPM Bundle.module accessors that crash outside the build machine." >&2
  exit 1
fi

for required_bundle in Jin_Jin.bundle SwiftMath_SwiftMath.bundle Highlighter_Highlighter.bundle; do
  bundle_path="$APP_BUNDLE/Contents/Resources/$required_bundle"
  if [[ ! -f "$bundle_path/Contents/Info.plist" ]]; then
    echo "Error: required macOS resource bundle is missing or malformed: $bundle_path" >&2
    exit 1
  fi
done

echo "Embedding SwiftPM dynamic frameworks…"
shopt -s nullglob
embedded_framework_count=0
resolve_framework_binary() {
  local framework_path="$1"
  local info_plist="$framework_path/Resources/Info.plist"
  local executable_name

  executable_name="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist" 2>/dev/null || true
  )"
  if [[ -n "$executable_name" && -f "$framework_path/$executable_name" ]]; then
    echo "$framework_path/$executable_name"
    return
  fi

  local fallback_name
  fallback_name="$(basename "$framework_path" .framework)"
  if [[ -f "$framework_path/$fallback_name" ]]; then
    echo "$framework_path/$fallback_name"
    return
  fi
  if [[ -f "$framework_path/Versions/Current/$fallback_name" ]]; then
    echo "$framework_path/Versions/Current/$fallback_name"
    return
  fi

  echo ""
}

for framework in "$BUILD_OUTPUT_DIR"/*.framework; do
  framework_name="$(basename "$framework")"
  target_framework="$APP_BUNDLE/Contents/Frameworks/$framework_name"
  ditto "$framework" "$target_framework"
  framework_binary="$(resolve_framework_binary "$target_framework")"
  if [[ -z "$framework_binary" ]]; then
    echo "Failed to locate executable for embedded framework: $framework_name" >&2
    exit 1
  fi
  require_architecture "$framework_binary" "$ARCH" "embedded framework '$framework_name'"
  embedded_framework_count=$((embedded_framework_count + 1))
done
shopt -u nullglob

if [[ "$embedded_framework_count" -gt 0 ]]; then
  if ! otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -Fq "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  fi
else
  echo "Warning: no SwiftPM dynamic frameworks found in release build outputs."
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

echo "Code signing app bundle (identifier: ${BUNDLE_ID})…"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ZIP_PATH="$DIST/$APP_NAME.zip"
echo "Creating distributable zip: $ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

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
