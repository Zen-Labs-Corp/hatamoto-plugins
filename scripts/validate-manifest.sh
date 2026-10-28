#!/usr/bin/env bash
# Validate one manifest. Usage: validate-manifest.sh <manifests/name.json> [--remote]
#
# The rules mirror manifests/schema.json and the registry build script
# (registry/build-community.sh in the Hatamoto core repo); keep the three in sync.
# The listing rules (author, name, title, description) read their word lists from
# ../policy next to this script. The registry build is to read the same files; it
# is changed separately, so until then the listing rules are enforced here only.
# --remote (CI) also checks the repo is reachable, the commit exists, and the
# plugin.json at that commit carries the manifest name. Manifest values are only
# ever passed as quoted arguments, never evaluated.
set -euo pipefail
# Count characters, not bytes, in the title check.
export LC_ALL=C.UTF-8

# License allowlist (SPDX ids); keep in sync with manifests/schema.json and the
# registry build script. GPL, LGPL and AGPL also accept -only and -or-later.
licenses=(MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC MPL-2.0)
for l in GPL-2.0 GPL-3.0 LGPL-2.1 LGPL-3.0 AGPL-3.0; do
  licenses+=("$l" "$l-only" "$l-or-later")
done

# Owners whose repos may carry tier "first-party" (space separated, lowercase,
# compared case-insensitively against the exact repo owner); keep in sync with
# manifests/schema.json and FIRST_PARTY_OWNERS in the registry build script.
FIRST_PARTY_OWNERS="zenlabscorp zen-labs-corp"

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

# Listing policy: fail closed when the directory or any list is unreadable.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pol=$here/../policy
policy_ok=1
for p in reserved-names banned-tokens banned-words brands placeholders; do
  if [ ! -r "$pol/$p.txt" ]; then bad "missing policy: $p.txt"; policy_ok=0; fi
done
[ "$policy_ok" -eq 1 ] || exit 1
# plist <list>: entries, trimmed and lowercased, without blanks and # comments.
plist() {
  jq -Rr 'ascii_downcase | gsub("\r"; "") | gsub("^\\s+|\\s+$"; "") | select(. != "" and (startswith("#") | not))' "$pol/$1.txt"
}
reserved_names=$(plist reserved-names)
banned_tokens=$(plist banned-tokens)
banned_words=$(plist banned-words)
brands=$(plist brands)
placeholders=$(plist placeholders)
# inlist <newline separated list> <word>: exact whole-line membership.
inlist() { [[ $'\n'$1$'\n' == *$'\n'"$2"$'\n'* ]]; }
# brand_owned <brand> <owner>: the brand is listed with that owner.
brand_owned() {
  local b o owners
  while read -r -a owners; do
    [ "${owners[0]:-}" = "$1" ] || continue
    for o in "${owners[@]:1}"; do [ "$o" = "$2" ] && return 0; done
  done <<<"$brands"
  return 1
}
# brand_listed <word>: the word is a brand in brands.txt.
brand_listed() {
  local b rest
  while read -r b rest; do [ "$b" = "$1" ] && return 0; done <<<"$brands"
  return 1
}
# lev1 <a> <b>: edit distance of at most 1.
lev1() {
  local a=$1 b=$2 i=0
  [ "$a" = "$b" ] && return 0
  while [ "$i" -lt "${#a}" ] && [ "$i" -lt "${#b}" ] && [ "${a:i:1}" = "${b:i:1}" ]; do i=$((i + 1)); done
  a=${a:i}; b=${b:i}
  while [ -n "$a" ] && [ -n "$b" ] && [ "${a: -1}" = "${b: -1}" ]; do a=${a%?}; b=${b%?}; done
  [ "${#a}" -le 1 ] && [ "${#b}" -le 1 ]
}
# lkey <name>: hyphens removed, 0 1 3 5 folded to o l e s.
lkey() { printf '%s' "$1" | tr -d '-' | tr '0135' 'oles'; }

# field <name>: the string value, or empty when absent or not a string.
field() { jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else "" end' "$file"; }
# has <name>: true when the key is present.
has() { jq -e --arg k "$1" 'has($k)' "$file" >/dev/null; }

# Unknown keys.
extra=$(jq -r '[keys[] | select(IN("name","repo","commit","subdir","title","author","license","sdk","homepage","archive_grant","tier") | not)] | join(", ")' "$file")
[ -z "$extra" ] || bad "unknown field(s): $extra"

# Required keys, and every present key except archive_grant must be a string.
for k in name repo commit license sdk archive_grant; do
  has "$k" || bad "missing required field: $k"
done
for k in name repo commit subdir title author license sdk homepage tier; do
  if has "$k" && ! jq -e --arg k "$k" '.[$k] | type == "string"' "$file" >/dev/null; then
    bad "$k must be a string"
  fi
done

# The grant must be the JSON value true, nothing else.
if has archive_grant && ! jq -e '.archive_grant == true' "$file" >/dev/null; then
  bad "archive_grant must be true"
fi

name=$(field name)
repo=$(field repo)
commit=$(field commit)
subdir=$(field subdir)
title=$(field title)
author=$(field author)
tier=$(field tier)
license=$(field license)
sdk=$(field sdk)
homepage=$(field homepage)

if has name && ! [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  bad "name must match ^[a-z][a-z0-9-]{1,39}\$"
fi

# Repo owner (exact, lowercased) and whether it is on the first-party allowlist.
# A file:/// repo (offline tests only) uses its parent directory as the owner.
owner=""
if [[ $repo =~ ^https://github\.com/([A-Za-z0-9._-]+)/[A-Za-z0-9._-]+$ ]]; then
  owner=${BASH_REMATCH[1]}
elif [[ $repo =~ ^file:///([A-Za-z0-9._/-]+)/[A-Za-z0-9._-]+$ ]]; then
  owner=${BASH_REMATCH[1]##*/}
fi
owner=$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')
owner_ok=0
for o in $FIRST_PARTY_OWNERS; do
  if [ -n "$owner" ] && [ "$owner" = "$o" ]; then owner_ok=1; fi
done

# tier: only "first-party", only from an allowlisted owner, never with an author.
if has tier; then
  if [ "$tier" != "first-party" ]; then
    bad "tier must be \"first-party\" when present"
  else
    [ "$owner_ok" -eq 1 ] || bad "tier first-party requires a repo owned by: $FIRST_PARTY_OWNERS"
    has author && bad "author must be absent for tier first-party"
  fi
else
  has author || bad "missing required field: author"
fi

# First-party exempt from the brand and reserved-name rules: tier first-party
# from an allowlisted owner.
fpx=0
if has tier && [ "$tier" = "first-party" ] && [ "$owner_ok" -eq 1 ]; then fpx=1; fi

# Author of a community listing must be the repo owner (case-insensitive).
if has author && ! has tier && [ "$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')" != "$owner" ]; then
  bad "author \"$author\" must equal the repo owner \"$owner\""
fi

# Reserved names. gtm and searchconsole are first-party only; webhooks and hello
# are never accepted. Keep in sync with the registry build script.
reserved_flagged=0
for reserved in webhooks hello; do
  if [ "$name" = "$reserved" ]; then bad "name \"$name\" is reserved for a first-party plugin"; reserved_flagged=1; fi
done
for reserved in gtm searchconsole; do
  if [ "$name" = "$reserved" ] && { [ "$tier" != "first-party" ] || [ "$owner_ok" -ne 1 ]; }; then
    bad "name \"$name\" is reserved for a first-party plugin"; reserved_flagged=1
  fi
done
base=$(basename "$file" .json)
if has name && [ "$name" != "$base" ]; then
  bad "name \"$name\" must equal the file name \"$base\""
fi
# Cross-kind uniqueness: a theme manifest in the same manifests/ directory.
# (Themes enforce the other direction in scripts/validate-theme-manifest.sh.)
mdir=$(cd "$(dirname "$file")" && pwd)
if has name && [ -e "$mdir/themes/$name.json" ]; then
  bad "name \"$name\" is also a theme (manifests/themes/$name.json)"
fi
# Listing rules for the name (the name pattern is checked above).
if has name && [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  IFS=- read -ra ntoks <<<"$name"
  for t in "${ntoks[@]}"; do
    if inlist "$banned_tokens" "$t"; then bad "name \"$name\" contains the banned word \"$t\""; fi
  done
  if [ "$fpx" -eq 0 ]; then
    if [ "$reserved_flagged" -eq 0 ] && inlist "$reserved_names" "$name"; then
      bad "name \"$name\" is reserved"
    fi
    if brand_listed "${ntoks[0]}" && ! brand_owned "${ntoks[0]}" "$owner"; then
      bad "name must not start with the brand \"${ntoks[0]}\""
    fi
  fi
  # Look-alikes: other manifests and, unless first-party exempt, reserved names.
  nkey=$(lkey "$name")
  look() { # look <other name>
    [ "$1" != "$name" ] || return 0
    if [ "$(lkey "$1")" = "$nkey" ] || lev1 "$name" "$1"; then bad "name \"$name\" looks like \"$1\""; fi
  }
  for sib in "$mdir"/*.json "$mdir"/themes/*.json; do
    [ -e "$sib" ] || continue
    sname=$(basename "$sib" .json)
    [ "$sname" != "$base" ] && [ "$sname" != schema ] || continue
    [[ $sname =~ ^[a-z][a-z0-9-]{1,39}$ ]] || continue
    look "$sname"
  done
  if [ "$fpx" -eq 0 ]; then
    while read -r r; do
      if [[ $r =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then look "$r"; fi
    done <<<"$reserved_names"
  fi
fi
# file:/// repos exist only for the offline tests of the mirror script.
if has repo && ! [[ $repo =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
  && ! { [ "${HATAMOTO_ALLOW_FILE_REPOS:-}" = 1 ] && [[ $repo =~ ^file:///[A-Za-z0-9._/-]+$ ]]; }; then
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
if has title; then
  if [ -z "$title" ] || [ "${#title}" -gt 60 ] || [[ $title =~ [[:cntrl:]] ]] || [[ $title == " "* ]] || [[ $title == *" " ]]; then
    bad "title must be 1 to 60 characters, no control characters, no leading or trailing space"
  fi
fi
if has author && ! [[ $author =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]]; then
  bad "author must match ^[A-Za-z0-9][A-Za-z0-9-]{0,38}\$"
fi
if has license; then
  allowed=0
  for l in "${licenses[@]}"; do
    if [ "$license" = "$l" ]; then allowed=1; fi
  done
  if [ "$allowed" -eq 0 ]; then
    bad "license must be one of: ${licenses[*]}"
  fi
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
