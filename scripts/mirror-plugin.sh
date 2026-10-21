#!/usr/bin/env bash
# Mirror the pinned source of one community plugin into a repo we own.
# Usage: mirror-plugin.sh <manifests/name.json>
#
# Run by .github/workflows/mirror.yml after a manifest lands on main. Creates
# <MIRROR_ORG>/<name> if needed, then pushes the pinned commit plus one commit on
# top of it that adds MIRROR.json and (when SDK_PUBLIC=true) the go mod vendor
# output. That commit gets annotated tags src/<commit> and v<version>. The core
# build (registry/build-community.sh) fetches src/<commit> and accepts the top
# commit only if its parent is the pinned commit and it touches nothing but
# vendor/ files and MIRROR.json.
#
# No plugin code runs: git, check-gomod.sh and `go mod vendor` only. Nothing is
# ever force-pushed and an existing ref is never moved. If src/<commit> already
# exists in the mirror it is verified (parent is the pinned commit, only MIRROR.json
# and vendor/ touched) and the upstream is not contacted; missing v<version> or main
# are added. A src/<commit> that fails verification is an error.
#
# Environment:
#   MIRROR_ORG    GitHub organization that owns the mirrors (required unless MIRROR_BASE)
#   GH_TOKEN      token with Administration + Contents write on that org; read once,
#                 unset, and given only to the gh create call and the push
#   SDK_PUBLIC    "true" to vendor dependencies (needs the SDK to be fetchable)
#   GOTOOLCHAIN   pinned Go toolchain for go mod vendor (default go1.27.2)
# Tests only:
#   HATAMOTO_ALLOW_FILE_REPOS=1  accept file:/// manifest repos
#   MIRROR_BASE=file:///dir MIRROR_CREATE=local  mirrors are bare repos under dir
set -euo pipefail
export LC_ALL=C.UTF-8

die() { echo "mirror-plugin: $*" >&2; exit 1; }

[ $# -eq 1 ] || { echo "usage: $0 <manifests/name.json>" >&2; exit 2; }
manifest=$1
here=$(cd "$(dirname "$0")" && pwd)

# Re-validate: grant, license, name and repo rules.
"$here/validate-manifest.sh" "$manifest" >/dev/null

field() { jq -r --arg k "$1" 'if (.[$k] | type) == "string" then .[$k] else "" end' "$manifest"; }
name=$(field name)
repo=$(field repo)
commit=$(field commit)
subdir=$(field subdir)
subdir=${subdir%/}

# Where the mirror lives.
local_mode=0
if [ -n "${MIRROR_BASE:-}" ]; then
  [ "${HATAMOTO_ALLOW_FILE_REPOS:-}" = 1 ] && [[ $MIRROR_BASE =~ ^file:///[A-Za-z0-9._/-]+$ ]] \
    || die "MIRROR_BASE is for tests only"
  [ "${MIRROR_CREATE:-}" = local ] && local_mode=1
  mirror_url="$MIRROR_BASE/$name"
else
  org=${MIRROR_ORG:-}
  [[ $org =~ ^[A-Za-z0-9._-]+$ ]] || die "MIRROR_ORG must be set to a GitHub organization name"
  mirror_url="https://github.com/$org/$name"
fi

export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_LFS_SKIP_SMUDGE=1
git_opts=(-c core.hooksPath=/dev/null -c submodule.recurse=false -c protocol.allow=never
  -c protocol.https.allow=always -c commit.gpgsign=false -c tag.gpgsign=false)
if [ "${HATAMOTO_ALLOW_FILE_REPOS:-}" = 1 ]; then git_opts+=(-c protocol.file.allow=always); fi
# The token is read once and removed from the environment, so neither git fetch
# of the upstream nor go mod vendor ever sees it. It is handed only to the gh api
# create call and to the push, where the credential helper reads it from the
# environment of that one git process: never in a URL or an argument.
token=${GH_TOKEN:-}
unset GH_TOKEN
push_opts=("${git_opts[@]}")
if [[ $mirror_url == https://* ]]; then
  [ -n "$token" ] || die "GH_TOKEN is not set"
  push_opts+=(-c credential.helper= -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f')
fi
push() { GH_TOKEN=$token git "${push_opts[@]}" -C "$1" push -q "$mirror_url" "${@:2}"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
vendor_path=${subdir:+$subdir/}vendor

export GIT_AUTHOR_NAME=hatamoto-mirror GIT_AUTHOR_EMAIL=mirror@hatamoto.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

# 1. The mirror repository: look it up by HTTP status and create it on 404.
if [ "$local_mode" -eq 1 ]; then
  [ -d "${mirror_url#file://}" ] || git init -q --bare "${mirror_url#file://}"
else
  out=$(GH_TOKEN=$token gh api -i "repos/$org/$name" 2>/dev/null || true)
  status=$(printf '%s\n' "$out" | sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p')
  case "$status" in
    200) ;;
    404)
      GH_TOKEN=$token gh api -X POST "/orgs/$org/repos" -f name="$name" -f visibility=public \
        -f description="Source archive of $repo" -F has_issues=false -F has_wiki=false >/dev/null \
        || die "cannot create $org/$name"
      echo "created $org/$name" ;;
    *) die "cannot look up $org/$name: HTTP status ${status:-unknown}" ;;
  esac
fi

# 2. An existing src/<commit> wins: verify it and finish without contacting the
# upstream, so a deleted author repository cannot break a re-run. Only refs that
# are missing (v<version>, main) are added; no existing ref is ever moved.
chk=$work/chk
git init -q "$chk"
c() { git "${git_opts[@]}" -C "$chk" "$@"; }
if c fetch -q --no-recurse-submodules "$mirror_url" "refs/tags/src/$commit" 2>/dev/null; then
  top=$(c rev-parse 'FETCH_HEAD^{commit}')
  [ "$(c rev-list --parents -n1 "$top")" = "$top $commit" ] \
    || die "$name: src/$commit in the mirror is not a single commit on top of $commit"
  while IFS= read -r p; do
    case "$p" in MIRROR.json | "$vendor_path"/*) ;; *) die "$name: src/$commit in the mirror touches $p" ;; esac
  done < <(c diff --no-renames --name-only "$commit" "$top")
  meta=$(c show "$top:MIRROR.json" 2>/dev/null) || die "$name: src/$commit in the mirror has no MIRROR.json"
  printf '%s' "$meta" | jq -e --arg n "$name" --arg c "$commit" '.name == $n and .commit == $c' >/dev/null \
    || die "$name: MIRROR.json in src/$commit does not match the manifest"
  mversion=$(printf '%s' "$meta" | jq -r '.version // empty')
  [[ $mversion =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || die "$name: MIRROR.json version is not usable in a tag"
  at=$(printf '%s' "$meta" | jq -r '.mirrored_at // empty')
  [ -z "$at" ] || export GIT_AUTHOR_DATE=$at GIT_COMMITTER_DATE=$at
  refs=()
  if ! c ls-remote --exit-code --tags "$mirror_url" "refs/tags/v$mversion" >/dev/null 2>&1; then
    c tag -a -m "$name $mversion" "v$mversion" "$top"
    refs+=("refs/tags/v$mversion")
  fi
  if ! c ls-remote --exit-code --heads "$mirror_url" refs/heads/main >/dev/null 2>&1; then
    refs+=("$top:refs/heads/main")
  fi
  if [ "${#refs[@]}" -gt 0 ]; then
    push "$chk" "${refs[@]}" || die "push to the mirror failed"
    echo "$name: already mirrored at $commit, added ${refs[*]}"
  else
    echo "$name: already mirrored at $commit"
  fi
  exit 0
fi

src=$work/src
git init -q "$src"
g() { git "${git_opts[@]}" -C "$src" "$@"; }

# 3. The pinned source, with full history so the mirror holds the author's commits.
g fetch -q --no-recurse-submodules "$repo" "$commit" 2>/dev/null || die "cannot fetch $commit from $repo"
[ "$(g rev-parse FETCH_HEAD^{commit})" = "$commit" ] || die "fetched commit is not $commit"
g checkout -q --detach FETCH_HEAD

[ -z "$(g ls-files -- '.gitmodules' '*/.gitmodules')" ] || die "submodules are not allowed"
[ ! -e "$src/MIRROR.json" ] || die "the source already has a MIRROR.json"
plug=$src
[ -z "$subdir" ] || plug=$src/$subdir
# No symlink anywhere in the chain to the plugin, and it resolves inside the clone.
walk=$src
for part in ${subdir//\// }; do
  walk=$walk/$part
  [ ! -L "$walk" ] || die "symlink in the plugin path at $part"
done
[ "$(realpath "$plug" 2>/dev/null)" = "$(realpath "$src")${subdir:+/$subdir}" ] || die "the plugin path leaves the repository"
if [ -L "$plug/plugin.json" ] || [ ! -f "$plug/plugin.json" ]; then
  die "no regular plugin.json at ${subdir:-the repository root}"
fi
[ "$(jq -r '.name // empty' "$plug/plugin.json")" = "$name" ] || die "plugin.json name does not match $name"
version=$(jq -r '.version // empty' "$plug/plugin.json")
[[ $version =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || die "plugin.json version is missing or not usable in a tag"

"$here/check-gomod.sh" "$plug" "$src"

mirrored_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 4. The mirror commit: vendor/ (optional) and MIRROR.json on top of the pinned commit.
vendored=false
if [ "${SDK_PUBLIC:-}" = true ]; then
  (cd "$plug" && GOTOOLCHAIN=${GOTOOLCHAIN:-go1.27.2} GOWORK=off go mod vendor) || die "go mod vendor failed"
  if [ -d "$src/$vendor_path" ]; then
    vendored=true
    g add -f -A -- "$vendor_path"
  fi
fi
# Vendoring must not have rewritten anything else.
[ -z "$(g status --porcelain --untracked-files=no | grep -v -F -- " $vendor_path/" || true)" ] \
  || die "go mod vendor changed files outside $vendor_path"
jq -n --arg name "$name" --arg version "$version" --arg repo "$repo" --arg commit "$commit" \
  --arg subdir "$subdir" --arg at "$mirrored_at" --argjson vendored "$vendored" \
  '{name: $name, version: $version, upstream: $repo, commit: $commit, subdir: $subdir,
    mirrored_at: $at, vendored: $vendored}' >"$src/MIRROR.json"
g add MIRROR.json

export GIT_AUTHOR_NAME=hatamoto-mirror GIT_AUTHOR_EMAIL=mirror@hatamoto.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
export GIT_AUTHOR_DATE=$mirrored_at GIT_COMMITTER_DATE=$mirrored_at
g commit -q --no-verify -m "mirror: $name $commit"
top=$(g rev-parse HEAD)
[ "$(g rev-parse HEAD^)" = "$commit" ] || die "mirror commit is not on top of $commit"

# 5. Publish: tags first-class, main only when the repo has no main yet. No --force.
g tag -a -m "source archive of $repo at $commit" "src/$commit" "$top"
refs=("refs/tags/src/$commit")
if ! g ls-remote --exit-code --tags "$mirror_url" "refs/tags/v$version" >/dev/null 2>&1; then
  g tag -a -m "$name $version" "v$version" "$top"
  refs+=("refs/tags/v$version")
else
  echo "$name: tag v$version already exists in the mirror, keeping it" >&2
fi
if ! g ls-remote --exit-code --heads "$mirror_url" refs/heads/main >/dev/null 2>&1; then
  refs+=("$top:refs/heads/main")
fi
push "$src" "${refs[@]}" || die "push to the mirror failed"
echo "$name: mirrored $commit to $name (tags: src/$commit, v$version, vendored: $vendored)"
