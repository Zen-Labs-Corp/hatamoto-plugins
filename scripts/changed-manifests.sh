#!/usr/bin/env bash
# Print (NUL separated) the plugin manifests to mirror.
# Usage: changed-manifests.sh [<before> <after>]
# With two commits: manifests added or modified between them. Renames are turned
# into delete + add (--no-renames) so a renamed manifest is mirrored. Without
# arguments: every tracked manifest. Theme, schema and nested files are skipped.
set -euo pipefail
if [ $# -eq 2 ]; then
  git diff --no-renames -z --name-only --diff-filter=AM "$1" "$2" -- 'manifests/*.json'
else
  git ls-files -z -- 'manifests/*.json'
fi | while IFS= read -r -d '' f; do
  case "$f" in
    manifests/schema.json | manifests/themes/*) ;;
    manifests/*/*) ;;
    *) printf '%s\0' "$f" ;;
  esac
done
