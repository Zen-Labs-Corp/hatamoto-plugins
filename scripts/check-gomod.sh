#!/usr/bin/env bash
# Check that a plugin builds from a plain module, as the Hatamoto registry build
# requires. Usage: check-gomod.sh <source-dir> [<repo-root>]
#
# Refuses: a go.work or go.work.sum in the source dir or the repo root, a replace
# of hatamoto.dev/sdk (to any target), and a local-path replace. Mirrors
# registry/build-community.sh in the Hatamoto core repo; keep them in sync.
set -euo pipefail

[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: $0 <source-dir> [<repo-root>]" >&2; exit 2; }
src=$1 root=${2:-$1}

bad() { echo "$src: $1" >&2; exit 1; }

for d in "$src" "$root"; do
  for w in go.work go.work.sum; do
    if [ -e "$d/$w" ] || [ -L "$d/$w" ]; then bad "$w is not allowed in the source or the repository root"; fi
  done
done
[ -f "$src/go.mod" ] || bad "no go.mod"
# The pinned toolchain keeps this read from downloading another Go.
gomod=$(cd "$src" && GOTOOLCHAIN=local GOWORK=off go mod edit -json) || bad "unreadable go.mod"
jq -e '[.Replace[]? | select(.Old.Path == "hatamoto.dev/sdk")] | length == 0' <<<"$gomod" >/dev/null \
  || bad "go.mod replaces hatamoto.dev/sdk"
jq -e '[.Replace[]? | select(.New.Path | startswith(".") or startswith("/"))] | length == 0' <<<"$gomod" >/dev/null \
  || bad "go.mod has a local-path replace directive"
