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
# ever force-pushed and an existing tag is never moved. Re-running on identical
# content is a no-op; differing content under an existing src/<commit> fails.
#
# Environment:
#   MIRROR_ORG    GitHub organization that owns the mirrors (required unless MIRROR_BASE)
#   GH_TOKEN      token with Administration + Contents write on that org; read from
#                 the environment only, never put in a URL or an argument
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
# The helper text is run by git with GH_TOKEN in its environment; the token is
# not part of any argument or URL.
push_opts=("${git_opts[@]}")
if [[ $mirror_url == https://* ]]; then
  [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set"
  push_opts+=(-c credential.helper= -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f')
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src=$work/src
git init -q "$src"
g() { git "${git_opts[@]}" -C "$src" "$@"; }

# 1. The pinned source, with full history so the mirror holds the author's commits.
g fetch -q --no-recurse-submodules "$repo" "$commit" 2>/dev/null || die "cannot fetch $commit from $repo"
[ "$(g rev-parse FETCH_HEAD^{commit})" = "$commit" ] || die "fetched commit is not $commit"
g checkout -q --detach FETCH_HEAD

[ -z "$(g ls-files -- '.gitmodules' '*/.gitmodules')" ] || die "submodules are not allowed"
[ ! -e "$src/MIRROR.json" ] || die "the source already has a MIRROR.json"
plug=$src
[ -z "$subdir" ] || plug=$src/$subdir
if [ -L "$plug" ] || [ -L "$plug/plugin.json" ] || [ ! -f "$plug/plugin.json" ]; then
  die "no regular plugin.json at ${subdir:-the repository root}"
fi
[ "$(jq -r '.name // empty' "$plug/plugin.json")" = "$name" ] || die "plugin.json name does not match $name"
version=$(jq -r '.version // empty' "$plug/plugin.json")
[[ $version =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || die "plugin.json version is missing or not usable in a tag"

"$here/check-gomod.sh" "$plug" "$src"

# 2. Existing mirror state, so a re-run reuses the recorded time and compares.
if [ "$local_mode" -eq 1 ]; then
  [ -d "${mirror_url#file://}" ] || git init -q --bare "${mirror_url#file://}"
elif [[ $mirror_url == https://* ]]; then
  if ! err=$(gh api "repos/$org/$name" 2>&1 >/dev/null); then
    [[ $err == *"HTTP 404"* ]] || die "cannot look up $org/$name: $err"
    gh api -X POST "/orgs/$org/repos" -f name="$name" -f visibility=public \
      -f description="Source archive of $repo" -F has_issues=false -F has_wiki=false >/dev/null \
      || die "cannot create $org/$name"
    echo "created $org/$name"
  fi
fi

mirrored_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
existing=0
if g fetch -q --no-recurse-submodules "$mirror_url" "refs/tags/src/$commit" 2>/dev/null; then
  existing=1
  old=$(g show "$(g rev-parse 'FETCH_HEAD^{commit}'):MIRROR.json" 2>/dev/null | jq -r '.mirrored_at // empty') || old=
  [ -z "$old" ] || mirrored_at=$old
  old_tree=$(g rev-parse 'FETCH_HEAD^{tree}')
  # The fetch moved FETCH_HEAD; the checkout still has the source.
fi

# 3. The mirror commit: vendor/ (optional) and MIRROR.json on top of the pinned commit.
vendored=false
vendor_path=${subdir:+$subdir/}vendor
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

if [ "$existing" -eq 1 ]; then
  if [ "$(g rev-parse 'HEAD^{tree}')" = "$old_tree" ]; then
    echo "$name: already mirrored at $commit"
    exit 0
  fi
  die "$name: src/$commit already exists in the mirror with different content (archive is append-only)"
fi

# 4. Publish: tags first-class, main only when the repo has no main yet. No --force.
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
git "${push_opts[@]}" -C "$src" push -q "$mirror_url" "${refs[@]}" || die "push to the mirror failed"
echo "$name: mirrored $commit to $name (tags: src/$commit, v$version, vendored: $vendored)"
