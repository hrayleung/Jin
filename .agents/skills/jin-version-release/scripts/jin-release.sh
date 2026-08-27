#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  jin-release.sh context <version>
  jin-release.sh publish <version> <notes-file>

Environment:
  DRY_RUN=1            Print the publish flow without changing repo/release state
  REPLACE_EXISTING=1   Delete an existing release/tag before republishing
  SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Unsupported version '$version'. Expected MAJOR.MINOR.PATCH."
}

run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" ]] || die "Could not resolve repository root from $SCRIPT_DIR"
cd "$REPO_ROOT"

SUBCOMMAND="${1:-}"
VERSION="${2:-}"
NOTES_FILE="${3:-}"
REPLACE_EXISTING="${REPLACE_EXISTING:-0}"
DRY_RUN="${DRY_RUN:-0}"
TAG=""
APPCAST_BIN=""
SOURCE_HEAD=""
SOURCE_COUNT=""

[[ "$REPLACE_EXISTING" == "0" || "$REPLACE_EXISTING" == "1" ]] || die "REPLACE_EXISTING must be 0 or 1."
[[ "$DRY_RUN" == "0" || "$DRY_RUN" == "1" ]] || die "DRY_RUN must be 0 or 1."

resolve_appcast_bin() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST}" ]]; then
    APPCAST_BIN="$SPARKLE_GENERATE_APPCAST"
  elif command -v generate_appcast >/dev/null 2>&1; then
    APPCAST_BIN="$(command -v generate_appcast)"
  elif [[ -x "tmp/sparkle-derived-data/Build/Products/Release/generate_appcast" ]]; then
    APPCAST_BIN="tmp/sparkle-derived-data/Build/Products/Release/generate_appcast"
  else
    die "No generate_appcast binary found. Build Sparkle tooling or set SPARKLE_GENERATE_APPCAST."
  fi
}

common_preflight() {
  validate_version "$VERSION"
  TAG="v$VERSION"

  require_cmd git
  require_cmd gh
  require_cmd rg
  require_cmd security
  require_cmd xmllint

  gh auth status
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "master" ]] || die "Release must run from master."
  [[ -z "$(git status --porcelain)" ]] || die "Working tree must be clean."

  git fetch origin master --tags --prune
  git merge-base --is-ancestor origin/master HEAD || die "HEAD is behind origin/master. Pull latest master first."

  SOURCE_HEAD="$(git rev-parse HEAD)"
  SOURCE_COUNT="$(git rev-list --count "$SOURCE_HEAD")"

  test -f Packaging/package.sh || die "Packaging/package.sh not found."
  test -f Packaging/Info.plist || die "Packaging/Info.plist not found."
  test -f docs/appcast.xml || die "docs/appcast.xml not found."
  rg -n "SUPublicEDKey" Packaging/Info.plist >/dev/null
  security find-generic-password -a ed25519 -s https://sparkle-project.org -w >/dev/null
  resolve_appcast_bin
}

write_context() {
  local prev_tag prev_tag_date prs_file context_file template_file compare_url

  common_preflight
  prev_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  [[ -n "$prev_tag" ]] || die "No existing release tag found."
  prev_tag_date="$(git log -1 --format=%cI "$prev_tag")"
  compare_url="https://github.com/hrayleung/Jin/compare/$prev_tag...$TAG"

  prs_file="/tmp/jin-release-$VERSION-merged-prs.json"
  context_file="/tmp/jin-release-$VERSION-context.txt"
  template_file="/tmp/jin-release-notes-$VERSION.template.md"

  gh pr list --state merged --limit 200 \
    --search "base:master merged:>=$prev_tag_date" \
    --json number,title,mergedAt,url > "$prs_file"

  cat > "$context_file" <<EOF
VERSION=$VERSION
TAG=$TAG
PREV_TAG=$prev_tag
PREV_TAG_DATE=$prev_tag_date
COMPARE_URL=$compare_url
PRS_FILE=$prs_file
EOF

  cat > "$template_file" <<EOF
## What's Changed
- <bullet 1>
- <bullet 2>

**Full Changelog**: $compare_url
EOF

  echo "Context written:"
  echo "  $context_file"
  echo "  $prs_file"
  echo "  $template_file"
  echo "Compare URL: $compare_url"
}

validate_notes_file() {
  [[ -n "$NOTES_FILE" ]] || die "Publish requires a notes file path."
  [[ -f "$NOTES_FILE" ]] || die "Notes file not found: $NOTES_FILE"
  grep -Fx "## What's Changed" "$NOTES_FILE" >/dev/null || die "Notes file must contain '## What's Changed'."
  grep -E "^\*\*Full Changelog\*\*: https://github.com/hrayleung/Jin/compare/.+\.\.\.v${VERSION}$" "$NOTES_FILE" >/dev/null || die "Notes file must contain the Full Changelog line for v$VERSION."
}

handle_existing_release_state() {
  local local_tag_exists=0 remote_tag_exists=0 release_exists=0

  git rev-parse --verify "$TAG" >/dev/null 2>&1 && local_tag_exists=1 || true
  git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1 && remote_tag_exists=1 || true
  gh release view "$TAG" >/dev/null 2>&1 && release_exists=1 || true

  if [[ "$local_tag_exists" -eq 1 || "$remote_tag_exists" -eq 1 || "$release_exists" -eq 1 ]]; then
    [[ "$REPLACE_EXISTING" == "1" ]] || die "Version $VERSION already exists. Set REPLACE_EXISTING=1 to republish safely."

    if [[ "$release_exists" -eq 1 ]]; then
      run_cmd gh release delete "$TAG" --yes
    fi
    if [[ "$local_tag_exists" -eq 1 ]]; then
      run_cmd git tag -d "$TAG"
    fi
    if [[ "$remote_tag_exists" -eq 1 ]]; then
      run_cmd git push --delete origin "$TAG"
    fi
  fi
}

package_release() {
  run_cmd bash -lc "cd '$REPO_ROOT' && JIN_BUNDLE_SHORT_VERSION='$VERSION' bash Packaging/package.sh"
  run_cmd mv -f "$REPO_ROOT/dist/Jin.zip" "$REPO_ROOT/dist/Jin-$VERSION.zip"

  [[ "$(git rev-parse HEAD)" == "$SOURCE_HEAD" ]] || die "HEAD changed during packaging. Restart release flow."

  local short_version build_number
  short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/dist/Jin.app/Contents/Info.plist")"
  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$REPO_ROOT/dist/Jin.app/Contents/Info.plist")"
  [[ "$short_version" == "$VERSION" ]] || die "Bundle short version $short_version does not match $VERSION."
  [[ "$build_number" == "$SOURCE_COUNT" ]] || die "Bundle build number $build_number does not match source count $SOURCE_COUNT."
}

sign_appcast() {
  local key_file
  key_file="$(mktemp /tmp/jin-sparkle-key.XXXXXX)"

  security find-generic-password -a ed25519 -s https://sparkle-project.org -w > "$key_file"
  if ! "$APPCAST_BIN" dist -o docs/appcast.xml \
    --ed-key-file "$key_file" \
    --download-url-prefix "https://github.com/hrayleung/Jin/releases/download/$TAG/" \
    --link "https://github.com/hrayleung/Jin/releases" \
    --maximum-versions 10; then
    rm -f "$key_file"
    die "generate_appcast failed."
  fi
  rm -f "$key_file"

  xmllint --noout docs/appcast.xml
  local version_items first_title first_url
  version_items="$(xmllint --xpath "count(/rss/channel/item[title='$VERSION'])" docs/appcast.xml 2>/dev/null | awk '{printf "%d", $1}')"
  [[ "$version_items" -eq 1 ]] || die "Expected exactly one appcast item for $VERSION, got $version_items."

  first_title="$(xmllint --xpath "string(/rss/channel/item[1]/title)" docs/appcast.xml)"
  first_url="$(xmllint --xpath "string(/rss/channel/item[1]/enclosure/@url)" docs/appcast.xml)"
  [[ "$first_title" == "$VERSION" ]] || die "First appcast item is not $VERSION."
  [[ "$first_url" == "https://github.com/hrayleung/Jin/releases/download/$TAG/Jin-$VERSION.zip" ]] || die "First appcast enclosure URL does not match $TAG asset."
  rg -n "sparkle:edSignature|Jin-$VERSION.zip" docs/appcast.xml
}

commit_appcast_update() {
  local commit_message_file
  git add docs/appcast.xml
  git diff --cached --quiet && die "docs/appcast.xml did not change."

  commit_message_file="$(mktemp /tmp/jin-release-commit-msg.XXXXXX)"

  cat > "$commit_message_file" <<EOF
Publish v$VERSION so Sparkle can serve the new stable build

Update the signed appcast entry to point at the v$VERSION archive built
from $SOURCE_HEAD and keep the release metadata aligned with the repo
publish flow.

Constraint: Sparkle appcast entries must include sparkle:edSignature
Constraint: Release asset name must remain Jin-$VERSION.zip
Confidence: high
Scope-risk: moderate
Directive: Do not republish v$VERSION without REPLACE_EXISTING=1 and a fresh signed appcast
Tested: Packaging/package.sh build, appcast signature validation
Not-tested: End-user Sparkle upgrade flow after publication
EOF

  if ! git commit -F "$commit_message_file"; then
    rm -f "$commit_message_file"
    die "git commit failed."
  fi
  rm -f "$commit_message_file"
}

publish_release() {
  validate_notes_file
  common_preflight

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run: validated preflight and notes file. Planned publish flow:"
    echo "  - delete existing release/tag if REPLACE_EXISTING=1 and v$VERSION already exists"
    echo "  - build with JIN_BUNDLE_SHORT_VERSION=$VERSION"
    echo "  - rename dist/Jin.zip to dist/Jin-$VERSION.zip"
    echo "  - sign docs/appcast.xml with $APPCAST_BIN"
    echo "  - commit the appcast update, tag $TAG, push master + $TAG"
    echo "  - create gh release $TAG with notes from $NOTES_FILE"
    exit 0
  fi

  handle_existing_release_state
  package_release
  sign_appcast
  commit_appcast_update

  git tag -a "$TAG" -m "$TAG"
  local tag_commit tag_parent
  tag_commit="$(git rev-parse "$TAG^{}")"
  tag_parent="$(git rev-parse "$tag_commit^")"
  [[ "$tag_parent" == "$SOURCE_HEAD" ]] || die "Tag parent $tag_parent does not match packaged source commit $SOURCE_HEAD."

  git push origin master
  git push origin "$TAG"

  gh release create "$TAG" "dist/Jin-$VERSION.zip" \
    --title "Jin v$VERSION" \
    --notes-file "$NOTES_FILE"

  xmllint --noout docs/appcast.xml
  rg -n "sparkle:edSignature|Jin-$VERSION.zip" docs/appcast.xml
  gh release view "$TAG" --json tagName,name,targetCommitish,assets,publishedAt,url

  local appcast_length asset_size
  appcast_length="$(xmllint --xpath "string(/rss/channel/item[title='$VERSION'][1]/enclosure/@length)" docs/appcast.xml)"
  asset_size="$(gh release view "$TAG" --json assets -q '.assets[] | select(.name=="Jin-'"$VERSION"'.zip") | .size')"
  [[ -n "$asset_size" ]] || die "Release asset Jin-$VERSION.zip not found."
  [[ "$appcast_length" == "$asset_size" ]] || die "Appcast length ($appcast_length) != release asset size ($asset_size)."

  echo "Published $TAG successfully."
}

case "$SUBCOMMAND" in
  context)
    [[ -n "$VERSION" ]] || {
      usage
      exit 1
    }
    write_context
    ;;
  publish)
    [[ -n "$VERSION" && -n "$NOTES_FILE" ]] || {
      usage
      exit 1
    }
    publish_release
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
