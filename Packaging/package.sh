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

echo "Cleaning stale SwiftPM resource bundles…"
shopt -s nullglob
for bundle in "$ROOT/.build/release"/*.bundle "$ROOT/.build/"*-apple-macosx/release/*.bundle; do
  rm -rf "$bundle"
done

ARCHS=(arm64 x86_64)
BUILD_OUTPUT_DIRS=()
ARCH_BINARIES=()

echo "Building (Release) for Apple Silicon + Intel…"
for arch in "${ARCHS[@]}"; do
  echo "Building ($arch)…"
  swift build -c release --disable-sandbox --arch "$arch"

  arch_bin="$ROOT/.build/$arch-apple-macosx/release/$APP_NAME"
  if [[ ! -f "$arch_bin" ]]; then
    echo "Expected binary not found for $arch: $arch_bin" >&2
    exit 1
  fi

  ARCH_BINARIES+=("$arch_bin")
  BUILD_OUTPUT_DIRS+=("$ROOT/.build/$arch-apple-macosx/release")
done

UNIVERSAL_BIN="$DIST/$APP_NAME-universal"
echo "Creating universal binary…"
lipo -create "${ARCH_BINARIES[@]}" -output "$UNIVERSAL_BIN"
universal_archs="$(lipo -archs "$UNIVERSAL_BIN")"
for arch in "${ARCHS[@]}"; do
  if [[ " $universal_archs " != *" $arch "* ]]; then
    echo "Error: arch '$arch' missing from universal binary: $universal_archs" >&2
    exit 1
  fi
done
echo "Universal binary architectures: $universal_archs"
BIN="$UNIVERSAL_BIN"

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

echo "Copying app icon variants…"
for VARIANT in A B C D; do
  cp "$ROOT/Packaging/AppIcon${VARIANT}.icns" "$APP_BUNDLE/Contents/Resources/AppIcon${VARIANT}.icns"
done

echo "Copying SwiftPM resource bundles…"
shopt -s nullglob
copied_bundle_count=0
for bundle_dir in "${BUILD_OUTPUT_DIRS[@]}"; do
  for bundle in "$bundle_dir"/*.bundle; do
    bundle_name="$(basename "$bundle")"
    target_bundle="$APP_BUNDLE/Contents/Resources/$bundle_name"
    # SwiftPM resource bundles are architecture-independent; first copy wins.
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

for bundle_dir in "${BUILD_OUTPUT_DIRS[@]}"; do
  for framework in "$bundle_dir"/*.framework; do
    framework_name="$(basename "$framework")"
    target_framework="$APP_BUNDLE/Contents/Frameworks/$framework_name"
    if [[ -e "$target_framework" ]]; then
      continue
    fi
    ditto "$framework" "$target_framework"
    framework_binary="$(resolve_framework_binary "$target_framework")"
    if [[ -z "$framework_binary" ]]; then
      echo "Failed to locate executable for embedded framework: $framework_name" >&2
      exit 1
    fi
    framework_archs="$(lipo -archs "$framework_binary" 2>/dev/null || true)"
    if [[ -z "$framework_archs" ]]; then
      echo "Failed to inspect framework architectures: $framework_binary" >&2
      exit 1
    fi
    for arch in "${ARCHS[@]}"; do
      if [[ " $framework_archs " != *" $arch "* ]]; then
        echo "Error: embedded framework '$framework_name' is missing '$arch' slice ($framework_archs)." >&2
        exit 1
      fi
    done
    embedded_framework_count=$((embedded_framework_count + 1))
  done
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

echo "Code signing app bundle (identifier: $BUNDLE_ID)…"
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
