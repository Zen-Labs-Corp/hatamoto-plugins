#!/usr/bin/env bash
# Validate one theme manifest. Usage: validate-theme-manifest.sh <manifests/themes/name.json> [--remote]
#
# The rules mirror schemas/theme-manifest.schema.json and the registry build
# (keep them in sync). --remote (CI) also fetches the source and checks that
# theme.json carries the manifest name and that any screenshot is <= 2 MiB.
# If HATAMOTO_BIN is set, the Go validator (`theme check --registry`) also runs.
# Manifest values are only ever passed as quoted arguments, never evaluated.
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

field() { jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else "" end' "$file"; }
has() { jq -e --arg k "$1" 'has($k)' "$file" >/dev/null; }

extra=$(jq -r '[keys[] | select(IN("name","author","license","homepage","subdir","repo","commit","archive","sha256") | not)] | join(", ")' "$file")
[ -z "$extra" ] || bad "unknown field(s): $extra"

for k in name author license; do
  has "$k" || bad "missing required field: $k"
done
for k in name author license homepage subdir repo commit archive sha256; do
  if has "$k" && ! jq -e --arg k "$k" '.[$k] | type == "string"' "$file" >/dev/null; then
    bad "$k must be a string"
  fi
done

name=$(field name)
author=$(field author)
license=$(field license)
homepage=$(field homepage)
subdir=$(field subdir)
repo=$(field repo)
commit=$(field commit)
archive=$(field archive)
sha256=$(field sha256)

url_re='^https://[A-Za-z0-9.-]+(:[0-9]+)?/[^[:space:]@]+$'

if has name && ! [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  bad "name must match ^[a-z][a-z0-9-]{1,39}\$"
fi
if has name && [ "$name" = "default" ]; then
  bad "name \"default\" is reserved"
fi
base=$(basename "$file" .json)
if has name && [ "$name" != "$base" ]; then
  bad "name \"$name\" must equal the file name \"$base\""
fi
if has author && ! [[ $author =~ ^[A-Za-z0-9][A-Za-z0-9\ ._@-]{0,60}$ ]]; then
  bad "author must match ^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,60}\$"
fi
if has license && [ -z "$license" ]; then
  bad "license must not be empty"
fi
if has homepage && ! [[ $homepage =~ ^https:// ]]; then
  bad "homepage must start with https://"
fi
if has subdir; then
  if ! [[ $subdir =~ ^[A-Za-z0-9._/-]+$ ]] || [[ $subdir == /* ]] || [[ $subdir =~ (^|/)\.\.(/|$) ]]; then
    bad "subdir must use only A-Za-z0-9._/- with no leading / and no .."
  fi
fi

# Exactly one source.
git_src=0; arc_src=0
{ has repo || has commit; } && git_src=1
{ has archive || has sha256; } && arc_src=1
if [ "$git_src" -eq 1 ] && [ "$arc_src" -eq 1 ]; then
  bad "use either repo+commit or archive+sha256, not both"
elif [ "$git_src" -eq 0 ] && [ "$arc_src" -eq 0 ]; then
  bad "missing source: give repo+commit or archive+sha256"
elif [ "$git_src" -eq 1 ]; then
  has repo || bad "missing required field: repo"
  has commit || bad "missing required field: commit"
  if has repo && ! [[ $repo =~ $url_re ]]; then
    bad "repo must be an https:// URL without credentials"
  fi
  if has commit && ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
    bad "commit must be 40 lowercase hex characters"
  fi
else
  has archive || bad "missing required field: archive"
  has sha256 || bad "missing required field: sha256"
  has subdir && bad "subdir is not allowed with an archive source"
  if has archive && ! [[ $archive =~ $url_re ]]; then
    bad "archive must be an https:// URL without credentials"
  fi
  if has sha256 && ! [[ $sha256 =~ ^[a-f0-9]{64}$ ]]; then
    bad "sha256 must be 64 lowercase hex characters"
  fi
fi

# Cross-kind uniqueness: only when the file sits in <root>/manifests/themes/.
dir=$(cd "$(dirname "$file")" && pwd)
if [ "$(basename "$dir")" = "themes" ] && [ "$(basename "$(dirname "$dir")")" = "manifests" ]; then
  root=$(dirname "$(dirname "$dir")")
  if has name && [ -e "$root/manifests/$name.json" ]; then
    bad "name \"$name\" is already used by a plugin (manifests/$name.json)"
  fi
fi

# Stop before touching the network if the manifest is not well formed.
[ "$fail" -eq 0 ] || exit 1

if [ "$remote" -eq 1 ]; then
  export GIT_TERMINAL_PROMPT=0
  max_shot=2097152
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tj=""
  shot_size=""
  if [ -n "$repo" ]; then
    case $repo in file://*) [ "${HATAMOTO_ALLOW_FILE_REPOS:-}" = 1 ] || { echo "$file: file:// repos are not allowed" >&2; exit 1; } ;; esac
    git -C "$tmp" init -q
    if ! git -C "$tmp" fetch -q --depth 1 "$repo" "$commit" 2>/dev/null; then
      echo "$file: commit $commit not found in $repo" >&2
      exit 1
    fi
    prefix=""
    [ -z "$subdir" ] || prefix="${subdir%/}/"
    if ! tj=$(git -C "$tmp" show "FETCH_HEAD:${prefix}theme.json" 2>/dev/null); then
      echo "$file: no ${prefix}theme.json at commit $commit" >&2
      exit 1
    fi
    shot=$(printf '%s' "$tj" | jq -r '.screenshot // empty' 2>/dev/null || true)
    if [ -n "$shot" ]; then
      if ! shot_size=$(git -C "$tmp" cat-file -s "FETCH_HEAD:${prefix}${shot}" 2>/dev/null); then
        echo "$file: screenshot $shot not found" >&2
        exit 1
      fi
    fi
  else
    if ! curl --proto '=https' --max-redirs 3 --max-filesize 20971520 --max-time 60 -fsSL -o "$tmp/a.zip" "$archive"; then
      echo "$file: cannot download $archive" >&2
      exit 1
    fi
    got=$(sha256sum "$tmp/a.zip" | cut -d' ' -f1)
    if [ "$got" != "$sha256" ]; then
      echo "$file: sha256 mismatch (got $got)" >&2
      exit 1
    fi
    # Wrapper-dir tolerant: theme.json at the root or exactly one directory down.
    tpath=$(unzip -Z1 "$tmp/a.zip" | awk '$0=="theme.json" || $0 ~ /^[^\/]+\/theme\.json$/' | head -n1)
    if [ -z "$tpath" ]; then
      echo "$file: no theme.json in archive" >&2
      exit 1
    fi
    tj=$(unzip -p "$tmp/a.zip" "$tpath")
    shot=$(printf '%s' "$tj" | jq -r '.screenshot // empty' 2>/dev/null || true)
    if [ -n "$shot" ]; then
      wrap="${tpath%theme.json}"
      shot_size=$(unzip -l "$tmp/a.zip" "${wrap}${shot}" 2>/dev/null | awk 'END{ if (NR > 0) print $1 }')
      [[ $shot_size =~ ^[0-9]+$ ]] || { echo "$file: screenshot $shot not found in archive" >&2; exit 1; }
    fi
  fi
  tname=$(printf '%s' "$tj" | jq -r '.name // empty' 2>/dev/null || true)
  if [ "$tname" != "$name" ]; then
    echo "$file: theme.json name \"$tname\" does not match manifest name \"$name\"" >&2
    exit 1
  fi
  if [ -n "$shot_size" ] && [ "$shot_size" -gt "$max_shot" ]; then
    echo "$file: screenshot is $shot_size bytes, limit is $max_shot" >&2
    exit 1
  fi
  if [ -n "${HATAMOTO_BIN:-}" ]; then
    if [ -n "$repo" ]; then
      "$HATAMOTO_BIN" theme check --registry --expect-name "$name" --repo "$repo" --commit "$commit" ${subdir:+--subdir "$subdir"}
    else
      "$HATAMOTO_BIN" theme check --registry --expect-name "$name" --archive "$archive" --sha256 "$sha256"
    fi
  fi
fi

echo "$file: ok"
