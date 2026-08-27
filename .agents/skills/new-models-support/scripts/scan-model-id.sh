#!/usr/bin/env bash
# Grep an exact model ID across Jin Sources + Tests.
# Usage: bash .agents/skills/new-models-support/scripts/scan-model-id.sh 'gpt-5.6-sol'
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <model-id> [extra rg args...]" >&2
  exit 2
fi

needle=$1
shift

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$script_dir
while [[ "$repo_root" != "/" && ! -f "$repo_root/Package.swift" ]]; do
  repo_root=$(dirname "$repo_root")
done
if [[ ! -f "$repo_root/Package.swift" ]]; then
  echo "Could not find Jin repo root from $script_dir" >&2
  exit 1
fi

cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg (ripgrep) is required" >&2
  exit 1
fi

echo "# repo: $repo_root"
echo "# id:   $needle"
echo

rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!dist/**' \
  --glob '!.swiftpm/**' \
  --glob '!**/node_modules/**' \
  -g '*.swift' \
  -e "$needle" \
  Sources Tests \
  "$@"
