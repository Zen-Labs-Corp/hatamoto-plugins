#!/usr/bin/env bash
# Validate one theme manifest. Usage: validate-theme-manifest.sh <manifests/themes/name.json> [--remote]
#
# The rules mirror schemas/theme-manifest.schema.json and the registry build
# (registry/build-community-themes.sh in the Hatamoto core repo); keep them in sync.
# The optional about and features keys follow check_about_features there.
# Reserved names come from ../policy/reserved-names.txt next to this script; a missing,
# unreadable or empty list rejects. The theme build still has a hardcoded reserved list and
# will read the same file in a follow-up. --remote (CI) also fetches the source and checks that
# theme.json carries the manifest name and a screenshot under assets/ of <= 2 MiB.
# If HATAMOTO_BIN is set, the Go validator (`theme check ... --registry`) also runs.
# Manifest values are only ever passed as quoted arguments, never evaluated.
set -euo pipefail
# Title length counts characters, not bytes.
if locale -a 2>/dev/null | grep -qix 'C\.utf-\?8'; then
  export LC_ALL=C.UTF-8
elif loc=$(locale -a 2>/dev/null | grep -iE '^en_US\.utf-?8$' | head -n1) && [ -n "$loc" ]; then
  export LC_ALL=$loc
elif loc=$(locale -a 2>/dev/null | grep -iE '\.utf-?8$' | head -n1) && [ -n "$loc" ]; then
  export LC_ALL=$loc
else
  echo "warning: no UTF-8 locale found; title length may be counted in bytes" >&2
fi

# License allowlist (SPDX ids); keep in sync with scripts/validate-manifest.sh,
# manifests/schema.json and the registry build script (tests/run-themes.sh
# asserts this array equals the one in validate-manifest.sh).
licenses=(MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC MPL-2.0)
for l in GPL-2.0 GPL-3.0 LGPL-2.1 LGPL-3.0 AGPL-3.0; do
  licenses+=("$l" "$l-only" "$l-or-later")
done

# host_ok <url>: public DNS name only. No IP literal, localhost, single label,
# internal suffix, port or credentials. Keep in sync with the registry build script.
host_ok() {
  local h=${1#https://}
  h=${h%%/*}
  h=$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')
  case $h in
    ''|*@*|*:*|*\[*|*\]*) return 1 ;;
    localhost|*.localhost|*.local|*.internal|*.lan|*.home|*.corp|*.test|*.invalid) return 1 ;;
  esac
  [[ $h =~ ^[0-9.]+$ ]] && return 1
  [[ $h == *.* ]] || return 1
  return 0
}

# unzip_escape <name>: unzip treats member names as wildcard patterns; escape them.
unzip_escape() { printf '%s' "$1" | sed 's/[][*?\\]/\\&/g'; }

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

# Reserved names come from policy/reserved-names.txt next to this script's scripts/ dir.
# Fail closed, before any name check and before any network access.
# keep in sync with Hatamoto core registry/build-community-themes.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pol=$here/../policy
if [ ! -r "$pol/reserved-names.txt" ]; then bad "missing policy: reserved-names.txt"; exit 1; fi
# plist <list>: entries, trimmed and lowercased, without blank lines and "# " comments.
plist() {
  jq -Rr 'ascii_downcase | gsub("\r"; "") | gsub("^\\s+|\\s+$"; "") | select(. != "" and . != "#" and (startswith("# ") | not))' "$pol/$1.txt"
}
reserved_names=$(plist reserved-names)
[ -n "$reserved_names" ] || { bad "empty policy: reserved-names.txt"; exit 1; }
# inlist <newline separated list> <word>: exact whole-line membership.
inlist() { [[ $'\n'$1$'\n' == *$'\n'"$2"$'\n'* ]]; }
# lev1 <a> <b>: edit distance of at most 1.
# keep in sync with scripts/validate-manifest.sh and Hatamoto core registry/build-community.sh
lev1() {
  local a=$1 b=$2 i=0
  [ "$a" = "$b" ] && return 0
  while [ "$i" -lt "${#a}" ] && [ "$i" -lt "${#b}" ] && [ "${a:i:1}" = "${b:i:1}" ]; do i=$((i + 1)); done
  a=${a:i}; b=${b:i}
  while [ -n "$a" ] && [ -n "$b" ] && [ "${a: -1}" = "${b: -1}" ]; do a=${a%?}; b=${b%?}; done
  [ "${#a}" -le 1 ] && [ "${#b}" -le 1 ]
}
# lkey <name>: hyphens removed, 0 1 3 5 folded to o l e s.
# keep in sync with scripts/validate-manifest.sh and Hatamoto core registry/build-community.sh
lkey() { printf '%s' "$1" | tr -d '-' | tr '0135' 'oles'; }

# Emoji, symbols and invisible characters; the filter is a copy of the one in
# scripts/validate-manifest.sh (it explains each class). An oniguruma without a property makes
# jq fail and the check reject.
# keep in sync with scripts/validate-manifest.sh (unsafe_chars_filter)
unsafe_chars_filter='$t | test("\\p{Cf}|\\p{Co}|\\p{Cs}|\\p{So}|\\p{Sk}|\\p{Extended_Pictographic}|\\p{Emoji_Presentation}|\\p{Default_Ignorable_Code_Point}|(?![\u0640\u3005\u3031-\u3035\u303B\u309D\u309E\u30FC-\u30FE])\\p{Lm}")'

# check_about_features: the rules for the optional keys "about" (plain text, paragraphs
# separated by one newline) and "features" (a list of short lines). jq reads the manifest file
# itself (not through field, which drops NULs and trailing newlines); the only program text
# spliced in is the script's own filter constant. A jq failure rejects.
# keep in sync with Hatamoto core registry/build-community-themes.sh (check_about_features)
# and scripts/validate-manifest.sh (same function body)
check_about_features() {
  local r line
  r=$(jq -r '
    def unsafe: '"${unsafe_chars_filter#\$t | }"';
    def line_problem:
      if test("[<>]") then "must not contain < or >"
      elif (ascii_downcase | contains("://") or contains("www.")) then "must not contain a URL"
      elif . != gsub("^\\s+|\\s+$"; "") then "must not start or end with whitespace"
      elif unsafe then "must not contain emoji, symbols or invisible characters"
      else empty end;
    def has_control($keep): explode | any(. != $keep and (. < 32 or (. >= 127 and . <= 159)));
    (if has("about") then
      .about as $a
      | if ($a | type) != "string" then "about must be a string"
        elif ($a | length) < 1 or ($a | length) > 1500 then "about must be 1 to 1500 characters"
        elif ($a | has_control(10)) then "about must not contain control characters other than a newline between paragraphs"
        elif ($a | split("\n") | length) > 10 then "about must have at most 10 paragraphs"
        elif ($a | split("\n") | any(. == "")) then "about must not have an empty paragraph"
        else ($a | split("\n") | map(line_problem) | first) as $p | if $p then "about \($p)" else empty end end
    else empty end),
    (if has("features") then
      .features as $l
      | if ($l | type) != "array" or ($l | any(type != "string")) then "features must be a list of strings"
        elif ($l | length) < 1 or ($l | length) > 8 then "features must list 1 to 8 items"
        elif ($l | any(length < 1 or length > 120)) then "each feature must be 1 to 120 characters"
        elif ($l | any(has_control(-1))) then "a feature must not contain control characters"
        else ($l | map(line_problem) | first) as $p
          | if $p then "a feature \($p)"
            elif ($l | map(ascii_downcase) | unique | length) != ($l | length) then "features must not repeat an item"
            else empty end end
    else empty end)' "$file") || { bad "about and features could not be checked"; return; }
  while IFS= read -r line; do
    [ -z "$line" ] || bad "$line"
  done <<<"$r"
}

field() { jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else "" end' "$file"; }
has() { jq -e --arg k "$1" 'has($k)' "$file" >/dev/null; }

extra=$(jq -r '[keys[] | select(IN("name","author","license","homepage","subdir","repo","commit","archive","sha256","title","archive_grant","about","features") | not)] | join(", ")' "$file")
[ -z "$extra" ] || bad "unknown field(s): $extra"

for k in name author license archive_grant; do
  has "$k" || bad "missing required field: $k"
done
for k in name author license title homepage subdir repo commit archive sha256; do
  if has "$k" && ! jq -e --arg k "$k" '.[$k] | type == "string"' "$file" >/dev/null; then
    bad "$k must be a string"
  fi
done

# The grant must be the JSON value true, nothing else.
if has archive_grant && ! jq -e '.archive_grant == true' "$file" >/dev/null; then
  bad "archive_grant must be true"
fi

name=$(field name)
author=$(field author)
license=$(field license)
homepage=$(field homepage)
subdir=$(field subdir)
repo=$(field repo)
commit=$(field commit)
archive=$(field archive)
sha256=$(field sha256)
title=$(field title)

url_re='^https://([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}/[^[:space:]@]+$'
# file:// sources exist only for the offline tests (same hooks as the mirror and the builder).
repo_ok() { { [[ $1 =~ $url_re ]] && host_ok "$1"; } || { [ "${HATAMOTO_ALLOW_FILE_REPOS:-}" = 1 ] && [[ $1 =~ ^file:///[A-Za-z0-9._/-]+$ ]]; }; }
archive_ok() { { [[ $1 =~ $url_re ]] && host_ok "$1"; } || { [ "${HATAMOTO_ALLOW_FILE_ARCHIVES:-}" = 1 ] && [[ $1 =~ ^file:///[A-Za-z0-9._/-]+\.zip$ ]]; }; }

if has name && ! [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  bad "name must match ^[a-z][a-z0-9-]{1,39}\$"
fi
if has name; then
  # keep in sync with Hatamoto core registry/build-community-themes.sh
  for reserved in default webhooks hello gtm searchconsole; do
    [ "$name" != "$reserved" ] || bad "name \"$name\" is reserved"
  done
  if inlist "$reserved_names" "$name" && ! [[ $name =~ ^(default|webhooks|hello|gtm|searchconsole)$ ]]; then
    bad "name \"$name\" is reserved"
  fi
fi
base=$(basename "$file" .json)
if has name && [ "$name" != "$base" ]; then
  bad "name \"$name\" must equal the file name \"$base\""
fi
if has author && ! [[ $author =~ ^[A-Za-z0-9][A-Za-z0-9\ ._@-]{0,60}$ ]]; then
  bad "author must match ^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,60}\$"
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
if has title; then
  if [ -z "$title" ] || [ "${#title}" -gt 60 ] || [[ $title =~ [[:cntrl:]] ]] || [[ $title == " "* ]] || [[ $title == *" " ]]; then
    bad "title must be 1 to 60 characters, no control characters, no leading or trailing space"
  fi
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
  if has repo && ! repo_ok "$repo"; then
    bad "repo must be an https:// URL on a public host name (no IP, localhost, port or credentials)"
  fi
  if has commit && ! [[ $commit =~ ^[0-9a-f]{40}$ ]]; then
    bad "commit must be 40 lowercase hex characters"
  fi
else
  has archive || bad "missing required field: archive"
  has sha256 || bad "missing required field: sha256"
  has subdir && bad "subdir is not allowed with an archive source"
  if has archive && ! archive_ok "$archive"; then
    bad "archive must be an https:// URL on a public host name (no IP, localhost, port or credentials)"
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

# Look-alikes of reserved names always; of plugins and sibling themes when the file sits in
# <root>/manifests/themes/. Same filters and message as scripts/validate-manifest.sh.
# keep in sync with Hatamoto core registry/build-community-themes.sh
if has name && [[ $name =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then
  nkey=$(lkey "$name")
  look() { # look <other name>
    [ "$1" != "$name" ] || return 0
    if [ "$(lkey "$1")" = "$nkey" ] || lev1 "$name" "$1"; then bad "name \"$name\" looks like \"$1\""; fi
  }
  if [ -n "${root:-}" ]; then
    for other in "$root"/manifests/*.json "$dir"/*.json; do
      [ -e "$other" ] || continue
      oname=$(basename "$other" .json)
      [ "$oname" != "$base" ] && [ "$oname" != schema ] || continue
      [[ $oname =~ ^[a-z][a-z0-9-]{1,39}$ ]] || continue
      look "$oname"
    done
  fi
  for r in default webhooks hello gtm searchconsole; do look "$r"; done
  while read -r r; do
    if [[ $r =~ ^[a-z][a-z0-9-]{1,39}$ ]]; then look "$r"; fi
  done <<<"$reserved_names"
fi

check_about_features

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
    co="$tmp/co"
    mkdir "$co"
    git -C "$co" init -q
    if ! git -C "$co" fetch -q --depth 1 "$repo" "$commit" 2>/dev/null; then
      echo "$file: commit $commit not found in $repo" >&2
      exit 1
    fi
    prefix=""
    [ -z "$subdir" ] || prefix="${subdir%/}/"
    if ! tj=$(git -C "$co" show "FETCH_HEAD:${prefix}theme.json" 2>/dev/null); then
      echo "$file: no ${prefix}theme.json at commit $commit" >&2
      exit 1
    fi
    shot=$(printf '%s' "$tj" | jq -er '.screenshot | strings' 2>/dev/null || true)
    if [ -z "$shot" ]; then
      echo "$file: theme.json has no screenshot (required)" >&2
      exit 1
    fi
    if ! [[ $shot == assets/* ]] || [[ $shot =~ (^|/)\.\.(/|$) ]]; then
      echo "$file: screenshot $shot must be under assets/" >&2
      exit 1
    fi
    if ! shot_size=$(git -C "$co" cat-file -s "FETCH_HEAD:${prefix}${shot}" 2>/dev/null); then
      echo "$file: screenshot $shot not found" >&2
      exit 1
    fi
  else
    protos='=https'
    case $archive in file://*) protos='=file' ;; esac
    if ! curl --proto "$protos" --proto-redir '=https' --max-redirs 5 --max-filesize 67108864 --max-time 60 -fsSL -o "$tmp/a.zip" "$archive"; then
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
    tj=$(unzip -p "$tmp/a.zip" "$(unzip_escape "$tpath")")
    shot=$(printf '%s' "$tj" | jq -er '.screenshot | strings' 2>/dev/null || true)
    if [ -z "$shot" ]; then
      echo "$file: theme.json has no screenshot (required)" >&2
      exit 1
    fi
    if ! [[ $shot == assets/* ]] || [[ $shot =~ (^|/)\.\.(/|$) ]]; then
      echo "$file: screenshot $shot must be under assets/" >&2
      exit 1
    fi
    if [[ $shot == *[\*\?\[\]\\]* ]]; then
      echo "$file: screenshot $shot must not contain wildcard characters (* ? [ ] \\)" >&2
      exit 1
    fi
    wrap="${tpath%theme.json}"
    # Capture the listing first: grep -q exiting early would SIGPIPE unzip (pipefail).
    list=$(unzip -Z1 "$tmp/a.zip")
    if ! grep -Fxq -- "${wrap}${shot}" <<<"$list"; then
      echo "$file: screenshot ${wrap}${shot} declared in theme.json not found in archive" >&2
      exit 1
    fi
    # Size comes from the zip listing (uncompressed size), never by inflating.
    zlist=$(unzip -Zl "$tmp/a.zip")
    shot_size=$(awk -v want="${wrap}${shot}" '
      { n = $0; for (i = 0; i < 9; i++) sub(/^ *[^ ]+ +/, "", n) }
      n == want && $1 !~ /^d/ { print $4; exit }' <<<"$zlist")
    if ! [[ $shot_size =~ ^[0-9]+$ ]]; then
      echo "$file: cannot read size of screenshot ${wrap}${shot} from archive" >&2
      exit 1
    fi
  fi
  tname=$(printf '%s' "$tj" | jq -r '.name // empty' 2>/dev/null || true)
  if [ "$tname" != "$name" ]; then
    echo "$file: theme.json name \"$tname\" does not match manifest name \"$name\"" >&2
    exit 1
  fi
  if [ "$shot_size" -gt "$max_shot" ]; then
    echo "$file: screenshot is $shot_size bytes, limit is $max_shot" >&2
    exit 1
  fi
  if [ -n "${HATAMOTO_BIN:-}" ]; then
    if [ -n "$repo" ]; then
      git -C "$co" checkout -q FETCH_HEAD
      "$HATAMOTO_BIN" theme check "$co/${subdir%/}" --registry --expect-name "$name"
    else
      "$HATAMOTO_BIN" theme check --archive "$tmp/a.zip" --sha256 "$sha256" --registry --expect-name "$name"
    fi
  fi
fi

echo "$file: ok"
