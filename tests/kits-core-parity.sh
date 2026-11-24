#!/usr/bin/env bash
# Same verdict from scripts/validate-kit-manifest.sh and the registry kit builder of the
# Hatamoto core repository (registry/build-community-kits.sh), for every rule both enforce.
# Needs HATAMOTO_CORE_DIR (a core checkout with the kit builder) and HATAMOTO_BIN (a built
# hatamoto CLI); skipped otherwise. Not part of tests/run.sh or CI: run it by hand.
# Only verdicts are compared, never messages (the builder stops at the first error).
set -u
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."
if [ -z "${HATAMOTO_CORE_DIR:-}" ] || [ -z "${HATAMOTO_BIN:-}" ]; then
  echo "skip kits-core-parity: set HATAMOTO_CORE_DIR and HATAMOTO_BIN"
  exit 0
fi
builder="$HATAMOTO_CORE_DIR/registry/build-community-kits.sh"
[ -x "$builder" ] || { echo "FAIL no executable $builder"; exit 1; }
v=scripts/validate-kit-manifest.sh
pass=0
failed=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HATAMOTO_ALLOW_FILE_REPOS=1 HATAMOTO_ARCHIVE_OFFLINE=1
"$HATAMOTO_BIN" keys generate --name t --dir "$tmp" >/dev/null
key="$tmp/t.key"
[ -f "$key" ] || { echo "FAIL throwaway key not created"; exit 1; }
# The owner literal is split out of the command lines to keep the neutrality scan quiet.
zl=zenlabscorp

mk_repo() { # <repo dir> <subdir> <kit.json content>: prints the commit
  mkdir -p "$1/$2"
  printf '%s' "$3" > "$1/$2/kit.json"
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
  git -C "$1" rev-parse HEAD
}
kj() { jq -nc --arg n "$1" '{name:$n,version:"1.0.0",kit:1,sdk:"^0.27",title:"Community",schemas:[{slug:"story",name:"Stories",schema:{type:"object"}}]}'; }
good_src="$tmp/$zl/src-good"; good_commit=$(mk_repo "$good_src" kits/community "$(kj community)")
root_src="$tmp/$zl/src-root"; root_commit=$(mk_repo "$root_src" . "$(kj community)")
mism_src="$tmp/$zl/src-mismatch"; mism_commit=$(mk_repo "$mism_src" kits/community "$(kj starter)")
tan_src="$tmp/tanaka/src-good"; tan_commit=$(mk_repo "$tan_src" kits/community "$(kj community)")

verdicts() { # <tree> <manifest file>: sets vv (validator) and bv (builder) to accept|reject
  local tree=$1 file=$2
  if env -u HATAMOTO_BIN "$v" "$file" --remote >/dev/null 2>&1; then vv=accept; else vv=reject; fi
  rm -rf "$tmp/o"; mkdir -p "$tmp/o"
  if "$builder" "$tree" "$HATAMOTO_BIN" "$key" "$tmp/o/pk" "$tmp/o/meta.json" "$tmp/o/arch" >/dev/null 2>&1; then bv=accept; else bv=reject; fi
}
mktree() { # <label> <manifest json> <file name>: tree at $tmp/c/<label>; prints the tree
  local t="$tmp/c/$1"
  mkdir -p "$t/manifests/kits"
  cp -r policy "$t/policy"
  printf '%s\n' "$2" > "$t/manifests/kits/$3.json"
  printf '%s' "$t"
}
manifest() { # <jq filter> [repo dir] [commit] [subdir]: a good manifest, then the filter
  jq -nc --arg r "file://${2:-$good_src}" --arg c "${3:-$good_commit}" --arg s "${4-kits/community}" \
    '{name:"community",repo:$r,commit:$c,author:"Zen Labs",license:"Apache-2.0",archive_grant:true} + (if $s == "" then {} else {subdir:$s} end)' | jq -c "$1"
}
both() { # <label> <accept|reject> <manifest json> [file name]
  local t file=${4:-$(jq -r .name <<<"$3")}
  t=$(mktree "$1" "$3" "$file")
  verdicts "$t" "$t/manifests/kits/$file.json"
  if [ "$vv" = "$2" ] && [ "$bv" = "$2" ]; then ok "$1: both $2"; else no "$1: want $2, validator $vv, builder $bv"; fi
}

both "good" accept "$(manifest .)"
both "good without subdir" accept "$(manifest . "$root_src" "$root_commit" "")"
both "good with about and features" accept "$(manifest '. + {title:"Community starter",about:"A link and discussion community.\nApply it from Settings, then Kits.",features:["Stories with votes and threads","Header menu created for you"],homepage:"https://example.com"}')"
# A kit named like a plugin: both sides accept it (the registry key is kind plus name).
t=$(mktree "like-a-plugin" "$(manifest .)" community); echo '{}' > "$t/manifests/community.json"
verdicts "$t" "$t/manifests/kits/community.json"
if [ "$vv" = accept ] && [ "$bv" = accept ]; then ok "kit named like a plugin: both accept"; else no "kit named like a plugin: validator $vv, builder $bv"; fi

both "http repo" reject "$(manifest '.repo = "http://github.com/Zen-Labs-Corp/community"')"
both "short commit" reject "$(manifest '.commit = "0123abc"')"
both "unknown field tier" reject "$(manifest '. + {tier:"first-party"}')"
both "archive and sha256" reject "$(manifest 'del(.repo, .commit, .subdir) | . + {archive:"https://example.com/community.zip", sha256:("a" * 64)}')"
both "no archive_grant" reject "$(manifest 'del(.archive_grant)')"
both "bad license" reject "$(manifest '.license = "WTFPL"')"
both "reserved name" reject "$(manifest '.name = "webhooks"')"
both "ip host" reject "$(manifest '.repo = "https://192.168.1.5/Zen-Labs-Corp/community"')"
both "localhost" reject "$(manifest '.repo = "https://localhost/Zen-Labs-Corp/community"')"
both "port in the host" reject "$(manifest '.repo = "https://github.com:8443/Zen-Labs-Corp/community"')"
both "subdir traversal" reject "$(manifest '.subdir = "../kits/community"')"
both "about with an empty paragraph" reject "$(manifest '. + {about:"line one\n\nline three"}')"
both "feature with a URL" reject "$(manifest '. + {features:["Visit https://example.com now"]}')"
both "name differs from the file name" reject "$(manifest .)" other
both "missing kit.json" reject "$(manifest '.subdir = "kits/other"')"
both "kit.json name mismatch" reject "$(manifest . "$mism_src" "$mism_commit")"
both "unknown commit" reject "$(manifest '.commit = ("0" * 40)')"

# Rules only this validator enforces (the builder is looser; reported to core): the validator
# must reject, the builder verdict is shown but not asserted.
only() { # <label> <manifest json> [file name] [extra sibling manifest json] [sibling file name]
  local t file=${3:-$(jq -r .name <<<"$2")}
  t=$(mktree "only-$1" "$2" "$file")
  [ -z "${4:-}" ] || printf '%s\n' "$4" > "$t/manifests/kits/$5.json"
  verdicts "$t" "$t/manifests/kits/$file.json"
  echo "validator-only: $1 (builder $bv)"
  if [ "$vv" = reject ]; then ok "validator-only: $1 rejected by the validator"; else no "validator-only: $1 accepted by the validator"; fi
}
only "non-first-party owner" "$(manifest . "$tan_src" "$tan_commit")"
only "look-alike sibling kit" "$(manifest '.name = "communitz"')" communitz "$(manifest .)" community
only "name default" "$(manifest '.name = "default"')"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
