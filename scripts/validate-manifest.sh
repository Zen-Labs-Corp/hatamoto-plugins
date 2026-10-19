#!/usr/bin/env bash
# Validate one manifest. Usage: validate-manifest.sh <manifests/name.json> [--remote]
#
# The rules mirror manifests/schema.json and the registry build script
# (registry/build-community.sh in the Hatamoto core repo); keep the three in sync.
# --remote (CI) also checks the repo is reachable, the commit exists, and the
# plugin.json at that commit carries the manifest name. Manifest values are only
# ever passed as quoted arguments, never evaluated.
set -euo pipefail

usage() { echo "usage: $0 <manifest.json> [--remote]" >&2; exit 2; }

[ $# -ge 1 ] && [ $# -le 2 ] || usage
file=$1
remote=0
if [ $# -eq 2 ]; then
  [ "$2" = "--remote" ] || usage
  remote=1
fi

fail=0
bad() { echo "$file: $1" >&2; fail=1; }

[ -f "$file" ] || { echo "$file: no such file" >&2; exit 1; }
if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
  echo "$file: not a JSON object" >&2
  exit 1
fi

# field <name>: the string value, or empty when absent or not a string.
field() { jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else "" end' "$file"; }
# has <name>: true when the key is present.
has() { jq -e --arg k "$1" 'has($k)' "$file" >/dev/null; }

# Unknown keys.
extra=$(jq -r '[keys[] | select(IN("name","repo","commit","subdir","author","license","sdk","homepage") | not)] | join(", ")' "$file")
[ -z "$extra" ] || bad "unknown field(s): $extra"

# Required keys, and every present key must be a string.
for k in name repo commit author license sdk; do
  has "$k" || bad "missing required field: $k"
done
for k in name repo commit subdir author license sdk homepage; do
  if has "$k" && ! jq -e --arg k "$k" '.[$k] | type == "string"' "$file" >/dev/null; then
    bad "$k must be a string"
  fi
done

name=$(field name)
repo=$(field repo)
commit=$(field commit)
subdir=$(field subdir)
author=$(field author)
license=$(field license)
sdk=$(field sdk)
homepage=$(field homepage)

if has name && ! [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  bad "name must match ^[a-z][a-z0-9-]{1,39}\$"
fi
base=$(basename "$file" .json)
if has name && [ "$name" != "$base" ]; then
  bad "name \"$name\" must equal the file name \"$base\""
fi
if has repo && ! [[ $repo =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  bad "repo must be https://github.com/<owner>/<repo>"
fi
if has commit && ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
  bad "commit must be 40 lowercase hex characters"
fi
if has subdir && [ -n "$subdir" ]; then
  if ! [[ $subdir =~ ^[A-Za-z0-9._/-]+$ ]] || [[ $subdir == /* ]] || [[ $subdir =~ (^|/)\.\.(/|$) ]]; then
    bad "subdir must use only A-Za-z0-9._/- with no leading / and no .."
  fi
fi
if has author && ! [[ $author =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]]; then
  bad "author must match ^[A-Za-z0-9][A-Za-z0-9-]{0,38}\$"
fi
if has license && [ -z "$license" ]; then
  bad "license must not be empty"
fi
if has sdk && [ -z "$sdk" ]; then
  bad "sdk must not be empty"
fi
if has homepage && ! [[ $homepage =~ ^https:// ]]; then
  bad "homepage must start with https://"
fi

# Stop before touching the network if the manifest is not well formed.
if [ "$fail" -ne 0 ]; then
  exit 1
fi

if [ "$remote" -eq 1 ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  export GIT_TERMINAL_PROMPT=0
  if ! git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1; then
    echo "$file: repo is not reachable: $repo" >&2
    exit 1
  fi
  git -C "$tmp" init -q
  if ! git -C "$tmp" fetch -q --depth 1 "$repo" "$commit" 2>/dev/null; then
    echo "$file: commit $commit not found in $repo" >&2
    exit 1
  fi
  path=plugin.json
  [ -z "$subdir" ] || path="${subdir%/}/plugin.json"
  if ! pj=$(git -C "$tmp" show "FETCH_HEAD:$path" 2>/dev/null); then
    echo "$file: no $path at commit $commit" >&2
    exit 1
  fi
  pname=$(printf '%s' "$pj" | jq -r '.name // empty' 2>/dev/null || true)
  if [ "$pname" != "$name" ]; then
    echo "$file: plugin.json name \"$pname\" does not match manifest name \"$name\"" >&2
    exit 1
  fi
  psdk=$(printf '%s' "$pj" | jq -r '.sdk // empty' 2>/dev/null || true)
  if [ "$psdk" != "$sdk" ]; then
    echo "$file: plugin.json sdk \"$psdk\" does not match manifest sdk \"$sdk\"" >&2
    exit 1
  fi
fi

echo "$file: ok"
