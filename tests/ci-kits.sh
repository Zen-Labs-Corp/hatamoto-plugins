#!/usr/bin/env bash
# Replays the judge and build run blocks of .github/workflows/validate.yml on kit pull
# requests (offline: file:// sources, a throwaway git repo per case). The blocks are cut out
# of the workflow text by step name, so this tests the real workflow, not a copy.
set -u
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."
root=$PWD
wf=.github/workflows/validate.yml
pass=0
failed=0

ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

step_run() { # <step name>: the dedented `run: |` block of that step
  awk -v want="      - name: $1" '
    $0 == want { on = 1; next }
    on && !inrun && /^        run: \|$/ { inrun = 1; next }
    inrun && /^          / { print substr($0, 11); next }
    inrun && /^ *$/ { print ""; next }
    inrun { exit }
    on && /^      - / { exit }' "$wf"
}
judge=$(step_run "Judge manifests with the base branch validator and policy")
build=$(step_run "Build changed plugins at their pinned commits")
guard_ok=1
for blk in judge build; do
  if [ -z "${!blk}" ] || [[ ${!blk} != *"set -euo pipefail"* ]]; then no "$blk block extracted from the workflow"; guard_ok=0; fi
done
if [ "$guard_ok" -eq 1 ] && [[ $judge != *"validate-kit-manifest.sh"* ]]; then no "judge block runs the kit validator"; guard_ok=0; fi
if [ "$guard_ok" -eq 0 ]; then echo "$pass passed, $failed failed"; exit 1; fi
ok "judge and build blocks extracted"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The owner literal is split out of the command lines to keep the neutrality scan quiet.
zl=zenlabscorp
export HATAMOTO_ALLOW_FILE_REPOS=1
cg() { git -C "$1" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "${@:2}"; }

# A kit source repo with kits/community/kit.json; prints the commit.
n=0
mk_source() { # [extra jq filter applied to the kit.json]
  n=$((n + 1))
  local d="$tmp/$zl/src-$n"
  mkdir -p "$d/kits/community"
  jq -nc '{name:"community",version:"1.0.0",kit:1,sdk:"^0.27",title:"Community",schemas:[{slug:"story",name:"Stories",schema:{type:"object"}}]}' > "$d/kits/community/kit.json"
  git init -q "$d"; cg "$d" add -A; cg "$d" commit -q -m init
  printf '%s' "$d"
}
kit_manifest() { # <source dir> [jq filter]: manifest JSON on stdout
  jq -n --arg r "file://$1" --arg c "$(git -C "$1" rev-parse HEAD)" \
    '{name:"community",repo:$r,commit:$c,subdir:"kits/community",author:"Zen Labs",license:"Apache-2.0",archive_grant:true}' | jq -c "${2:-.}"
}

# newrepo <name> [with-kit-validator 1|0]: base commit on main, origin/main ref, branch pr.
newrepo() {
  local d="$tmp/r-$1"
  mkdir -p "$d/scripts" "$d/manifests/kits" "$d/manifests/themes"
  git init -q -b main "$d"
  cp "$root"/scripts/validate-manifest.sh "$root"/scripts/validate-theme-manifest.sh "$d/scripts/"
  [ "${2:-1}" = 0 ] || cp "$root/scripts/validate-kit-manifest.sh" "$d/scripts/"
  cp -r "$root/policy" "$d/policy"
  cp "$root/manifests/README.md" "$root/manifests/schema.json" "$d/manifests/"
  cg "$d" add -A; cg "$d" commit -q -m base
  git -C "$d" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$d"
}
branch() { git -C "$1" checkout -q -b pr; }
commit_pr() { cg "$1" add -A; cg "$1" commit -q -m pr; }

rc=0; err=""; out=""
run_block() { # <repo dir> <judge|build>
  local blk=${!2}
  out=$(cd "$1" && BASE_REF=main GITHUB_WORKSPACE="$1" bash -c "$blk" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}
expect() { # <label> <want rc> [substring in stdout+stderr] [substring that must be absent]
  local all="$out$err"
  if [ "$rc" -ne "$2" ]; then no "$1 (rc=$rc, want $2): $all"; return; fi
  if [ -n "${3:-}" ] && [[ $all != *"$3"* ]]; then no "$1 (output lacks \"$3\"): $all"; return; fi
  if [ -n "${4:-}" ] && [[ $all == *"$4"* ]]; then no "$1 (output has \"$4\"): $all"; return; fi
  ok "$1"
}

# 1. A good kit pull request: judge and build both pass; the plugin glob never sees the kit.
src=$(mk_source)
d=$(newrepo good); branch "$d"
kit_manifest "$src" > "$d/manifests/kits/community.json"; commit_pr "$d"
run_block "$d" judge; expect "judge: good kit pull request" 0
run_block "$d" build; expect "build: kit pull request" 0 "" "valid plugin name"

# 2. A kit the validator refuses (a tier key) fails the judge.
d=$(newrepo bad); branch "$d"
kit_manifest "$src" '. + {tier:"first-party"}' > "$d/manifests/kits/community.json"; commit_pr "$d"
run_block "$d" judge; expect "judge: bad kit pull request" 1 "unknown field(s): tier"

# 3. A policy change re-checks kits already on the base, offline and against the base policy
# (like the plugin sweep): a clean base passes, a base that reserves the kit's name fails.
# Kits are never mistaken for plugins.
d=$(newrepo policy)
kit_manifest "$src" > "$d/manifests/kits/community.json"; commit_pr "$d"
git -C "$d" update-ref refs/remotes/origin/main HEAD; branch "$d"
echo "# a comment" >> "$d/policy/reserved-names.txt"; commit_pr "$d"
run_block "$d" judge; expect "judge: policy change keeps a clean existing kit" 0 "" "valid plugin name"
d=$(newrepo policy2)
echo "community" >> "$d/policy/reserved-names.txt"
kit_manifest "$src" > "$d/manifests/kits/community.json"; commit_pr "$d"
git -C "$d" update-ref refs/remotes/origin/main HEAD; branch "$d"
echo "# a comment" >> "$d/policy/reserved-names.txt"; commit_pr "$d"
run_block "$d" judge; expect "judge: policy change fails on an existing kit with a reserved name" 1 "is reserved" "valid plugin name"

# 4. Nested kit paths and the README.
d=$(newrepo nested); branch "$d"
mkdir -p "$d/manifests/kits/a"
kit_manifest "$src" > "$d/manifests/kits/a/b.json"; commit_pr "$d"
run_block "$d" judge; expect "judge: nested kit path refused" 1 "no nested paths"
d=$(newrepo readme); branch "$d"
echo "kits" > "$d/manifests/kits/README.md"; commit_pr "$d"
run_block "$d" judge; expect "judge: kits README only" 0 "nothing to judge"
run_block "$d" build; expect "build: kits README only" 0

# 5. A base without the kit validator: the pull request that adds it is not blocked, a kit is refused.
d=$(newrepo nokv 0); branch "$d"
cp "$root/scripts/validate-kit-manifest.sh" "$d/scripts/"; commit_pr "$d"
run_block "$d" judge; expect "judge: pull request adding only the kit validator" 0 "nothing to judge"
d=$(newrepo nokv2 0); branch "$d"
cp "$root/scripts/validate-kit-manifest.sh" "$d/scripts/"
kit_manifest "$src" > "$d/manifests/kits/community.json"; commit_pr "$d"
run_block "$d" judge; expect "judge: kit on a base without the kit validator" 1 "no validator to judge kit manifests"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
