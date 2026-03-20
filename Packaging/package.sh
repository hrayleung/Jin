#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Jin"
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
DMG_PATH="$DIST/$APP_NAME.dmg"
RTK_VERSION="0.31.0"

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

resolve_version() {
  local default_version="$1"

  if [[ -n "${JIN_BUNDLE_SHORT_VERSION:-}" ]]; then
    echo "$JIN_BUNDLE_SHORT_VERSION"
    return
  fi

  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local release_tag
    release_tag="$(git -C "$ROOT" describe --tags --exact-match --match 'v*' 2>/dev/null || true)"
    if [[ -n "$release_tag" ]]; then
      echo "${release_tag#v}"
      return
    fi

    release_tag="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
    if [[ -n "$release_tag" ]]; then
      local commits_ahead
      commits_ahead="$(git -C "$ROOT" rev-list "${release_tag}..HEAD" --count 2>/dev/null || echo 0)"
      local short_sha
      short_sha="$(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || true)"

      if [[ -n "$commits_ahead" && "$commits_ahead" != "0" && -n "$short_sha" ]]; then
        echo "${release_tag#v}+${short_sha}.${commits_ahead}"
      else
        echo "${release_tag#v}"
      fi
      return
    fi

    local short_sha
    short_sha="$(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || true)"
    if [[ -n "$short_sha" ]]; then
      local commit_count
      commit_count="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
      echo "0.0.0+${short_sha}.${commit_count}"
      return
    fi
  fi

  echo "$default_version"
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

resolve_rtk_asset_name() {
  case "$ARCH" in
    arm64)
      echo "rtk-aarch64-apple-darwin.tar.gz"
      ;;
    x86_64)
      echo "rtk-x86_64-apple-darwin.tar.gz"
      ;;
    *)
      echo "Unsupported RTK packaging architecture: $ARCH" >&2
      exit 1
      ;;
  esac
}

resolve_rtk_asset_sha256() {
  case "$ARCH" in
    arm64)
      echo "af1d62a756415c1eac466bb3f1b0c6e6587a2574dea57d2f94924b91ece6412d"
      ;;
    x86_64)
      echo "f79b80dff6bce3592d0e422e683ecc060a6069fa581bb4c6a989617476d5f378"
      ;;
    *)
      echo "Unsupported RTK packaging architecture: $ARCH" >&2
      exit 1
      ;;
  esac
}

prepare_rtk_helper() {
  local asset_name
  asset_name="$(resolve_rtk_asset_name)"
  local expected_sha
  expected_sha="$(resolve_rtk_asset_sha256)"
  local cache_dir="$ROOT/.build/rtk-cache/v${RTK_VERSION}/$ARCH"
  local archive_path="$cache_dir/$asset_name"
  local extract_dir="$cache_dir/extracted"
  local helper_path="$extract_dir/rtk"
  local release_url="https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/$asset_name"

  mkdir -p "$cache_dir"

  if [[ ! -f "$archive_path" ]]; then
    echo "Downloading RTK helper v${RTK_VERSION}…" >&2
    curl -fsSL "$release_url" -o "$archive_path"
  fi

  local actual_sha
  actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Checksum mismatch; re-downloading RTK helper v${RTK_VERSION}…" >&2
    rm -f "$archive_path"
    curl -fsSL "$release_url" -o "$archive_path"
    actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      echo "RTK helper checksum mismatch for $asset_name" >&2
      echo "Expected: $expected_sha" >&2
      echo "Actual:   $actual_sha" >&2
      exit 1
    fi
  fi

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"

  if [[ ! -f "$helper_path" ]]; then
    echo "Expected RTK helper not found after extraction: $helper_path" >&2
    exit 1
  fi

  chmod +x "$helper_path"
  require_architecture "$helper_path" "$ARCH" "RTK helper"
  echo "$helper_path"
}

echo "Cleaning stale SwiftPM resource bundles…"
shopt -s nullglob
for bundle in "$ROOT/.build/release"/*.bundle "$ROOT/.build/arm64-apple-macosx/release"/*.bundle; do
  rm -rf "$bundle"
done

ARCH="arm64"
BUILD_OUTPUT_DIR="$ROOT/.build/$ARCH-apple-macosx/release"
RTK_HELPER_BIN="$(prepare_rtk_helper)"

echo "Building (Release) for Apple Silicon…"
swift build -c release --disable-sandbox --arch "$ARCH"

BIN="$BUILD_OUTPUT_DIR/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "Expected binary not found: $BIN" >&2
  exit 1
fi
require_architecture "$BIN" "$ARCH" "$APP_NAME"

echo "Creating .app bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks" "$APP_BUNDLE/Contents/Helpers"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$RTK_HELPER_BIN" "$APP_BUNDLE/Contents/Helpers/rtk"
chmod +x "$APP_BUNDLE/Contents/Helpers/rtk"
require_architecture "$APP_BUNDLE/Contents/Helpers/rtk" "$ARCH" "bundled RTK helper"
cp "$ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
APP_SHORT_VERSION="$(resolve_version 0.1.0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_SHORT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
APP_BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
if [[ "$APP_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi

echo "Copying app icon variants…"
for VARIANT in A B C D E; do
  cp "$ROOT/Packaging/AppIcon${VARIANT}.icns" "$APP_BUNDLE/Contents/Resources/AppIcon${VARIANT}.icns"
done

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
  echo "Warning: no SwiftPM resource bundles found in release build outputs."
fi

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
