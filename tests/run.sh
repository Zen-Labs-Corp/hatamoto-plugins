#!/usr/bin/env bash
export LC_ALL=C.UTF-8
# Self-test for scripts/validate-manifest.sh (offline, no --remote).
set -u
cd "$(dirname "$0")/.."
v=scripts/validate-manifest.sh
f=tests/fixtures
pass=0
failed=0

ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

# good: exit 0.
if "$v" "$f/good.json" >/dev/null 2>&1; then ok "good.json accepted"; else no "good.json accepted"; fi

# bad: non-zero exit and an expected stderr substring.
expect_reject() {
  local file=$1 want=$2 err
  if err=$("$v" "$f/$file" 2>&1 >/dev/null); then
    no "$file rejected (exit 0)"
  elif [[ $err == *"$want"* ]]; then
    ok "$file rejected: $want"
  else
    no "$file rejected but stderr lacks \"$want\": $err"
  fi
}
expect_reject bad-name.json "name must match"
expect_reject bad-commit.json "commit must be 40"
expect_reject bad-repo.json "repo must be https://github.com"
expect_reject missing-sdk.json "missing required field: sdk"
expect_reject extra-field.json "unknown field(s): price"
expect_reject bad-title.json "title must be 1 to 60"
expect_reject missing-grant.json "missing required field: archive_grant"
expect_reject bad-grant.json "archive_grant must be true"
expect_reject bad-license.json "license must be one of"

# name must equal the file name.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$f/good.json" "$tmp/other.json"
if err=$("$v" "$tmp/other.json" 2>&1 >/dev/null); then no "name/file mismatch rejected"
elif [[ $err == *"must equal the file name"* ]]; then ok "name/file mismatch rejected"
else no "name/file mismatch: $err"; fi

# Reserved first-party names (community manifests, no tier).
for r in gtm webhooks searchconsole hello; do
  jq --arg n "$r" '.name = $n' "$f/good.json" > "$tmp/$r.json"
  if err=$("$v" "$tmp/$r.json" 2>&1 >/dev/null); then no "reserved name $r rejected"
  elif [[ $err == *"reserved for a first-party plugin"* ]]; then ok "reserved name $r rejected"
  else no "reserved name $r: $err"; fi
done

# First-party tier. fp <name> <owner> writes a manifest without author.
fp() { jq --arg n "$1" --arg r "https://github.com/$2/hatamoto-plugin-$1" '.name = $n | .repo = $r | .tier = "first-party" | del(.author)' "$f/good.json" > "$tmp/$1.json"; }
for n in gtm searchconsole; do
  fp "$n" zenlabscorp
  if "$v" "$tmp/$n.json" >/dev/null 2>&1; then ok "first-party $n accepted"; else no "first-party $n accepted"; fi
done
fp gtm ZenLabsCorp
if "$v" "$tmp/gtm.json" >/dev/null 2>&1; then ok "first-party owner ZenLabsCorp accepted"; else no "first-party owner ZenLabsCorp accepted"; fi
fp acme-seo zenlabscorp
if "$v" "$tmp/acme-seo.json" >/dev/null 2>&1; then ok "first-party non-reserved name accepted"; else no "first-party non-reserved name accepted"; fi
# reject_fp <label> <want> <name> <jq filter over the first-party manifest> [owner]
reject_fp() {
  local label=$1 want=$2 n=$3 filter=$4 owner=${5:-zenlabscorp} err
  fp "$n" "$owner"
  jq "$filter" "$tmp/$n.json" > "$tmp/x.json" && mv "$tmp/x.json" "$tmp/$n.json"
  if err=$("$v" "$tmp/$n.json" 2>&1 >/dev/null); then no "$label rejected (exit 0)"
  elif [[ $err == *"$want"* ]]; then ok "$label rejected"
  else no "$label: $err"; fi
}
reject_fp "gtm first-party from acme" "tier first-party requires" gtm . acme
reject_fp "searchconsole first-party from acme" "tier first-party requires" searchconsole . acme
reject_fp "non-reserved first-party from acme" "tier first-party requires" acme-seo . acme
reject_fp "gtm from zenlabscorp without tier" "reserved for a first-party plugin" gtm 'del(.tier) | .author = "zenlabscorp"'
reject_fp "searchconsole from zenlabscorp without tier" "reserved for a first-party plugin" searchconsole 'del(.tier) | .author = "zenlabscorp"'
reject_fp "tier with author" "author must be absent" gtm '.author = "zenlabscorp"'
reject_fp "tier community" "tier must be" gtm '.tier = "community"'
reject_fp "tier junk" "tier must be" acme-seo '.tier = "x"'
reject_fp "tier non-string" "tier must be a string" acme-seo '.tier = true'
reject_fp "webhooks first-party from zenlabscorp" "reserved for a first-party plugin" webhooks .
reject_fp "hello first-party from zenlabscorp" "reserved for a first-party plugin" hello .
for o in zenlabscorp-evil zenlabscorpx zenlabscorp.evil xzenlabscorp; do
  reject_fp "look-alike owner $o" "tier first-party requires" gtm . "$o"
done
# tier on a community-owned good.json (author present, acme owner) is refused too.
jq '. + {"tier": "first-party"}' "$f/good.json" > "$tmp/good.json"
if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "community manifest with tier rejected"; else ok "community manifest with tier rejected"; fi
# author is still required without a tier.
jq 'del(.author)' "$f/good.json" > "$tmp/good.json"
if err=$("$v" "$tmp/good.json" 2>&1 >/dev/null); then no "missing author rejected"
elif [[ $err == *"missing required field: author"* ]]; then ok "missing author rejected"; else no "missing author: $err"; fi

# manifests/schema.json agrees on the same cases. Needs python3 jsonschema; a missing
# module fails the suite unless SCHEMA_TESTS_ALLOW_SKIP=1.
if python3 -c 'import jsonschema' >/dev/null 2>&1; then
  sv() { python3 - "$1" <<'PY'
import json, sys, jsonschema
s = json.load(open("manifests/schema.json"))
sys.exit(0 if jsonschema.Draft202012Validator(s).is_valid(json.load(open(sys.argv[1]))) else 1)
PY
  }
  sc() { # sc <want accept|reject> <label> <file>
    if sv "$3"; then [ "$1" = accept ] && ok "schema: $2" || no "schema: $2"
    else [ "$1" = reject ] && ok "schema: $2" || no "schema: $2"; fi
  }
  sc accept "good.json" "$f/good.json"
  fp gtm zenlabscorp; sc accept "first-party gtm" "$tmp/gtm.json"
  fp gtm ZenLabsCorp; sc accept "first-party ZenLabsCorp" "$tmp/gtm.json"
  fp gtm acme; sc reject "first-party from acme" "$tmp/gtm.json"
  for o in zenlabscorp-evil zenlabscorpx zenlabscorp.evil; do fp gtm "$o"; sc reject "look-alike $o" "$tmp/gtm.json"; done
  fp gtm zenlabscorp; jq '.author = "zenlabscorp"' "$tmp/gtm.json" > "$tmp/x.json"; sc reject "tier with author" "$tmp/x.json"
  jq '.tier = "community"' "$tmp/gtm.json" > "$tmp/x.json"; sc reject "tier community" "$tmp/x.json"
  jq 'del(.author)' "$f/good.json" > "$tmp/x.json"; sc reject "no tier, no author" "$tmp/x.json"
elif [ "${SCHEMA_TESTS_ALLOW_SKIP:-}" = 1 ]; then
  echo "skip schema tests: python3 jsonschema not found (SCHEMA_TESTS_ALLOW_SKIP=1)"
else
  no "schema tests need python3 jsonschema (set SCHEMA_TESTS_ALLOW_SKIP=1 to skip)"
fi

# archive_grant must be JSON true; every allowlisted license is accepted.
for case in '"archive_grant": false' '"archive_grant": null' '"archive_grant": 1'; do
  jq ". + {$case}" "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "rejects $case"; else ok "rejects $case"; fi
done
for l in MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC MPL-2.0 GPL-2.0 GPL-2.0-only GPL-2.0-or-later GPL-3.0 GPL-3.0-only GPL-3.0-or-later LGPL-2.1 LGPL-2.1-only LGPL-2.1-or-later LGPL-3.0 LGPL-3.0-only LGPL-3.0-or-later AGPL-3.0 AGPL-3.0-only AGPL-3.0-or-later; do
  jq --arg l "$l" '. + {license: $l}' "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then ok "accepts license $l"; else no "accepts license $l"; fi
done
for l in WTFPL Proprietary "" mit "MIT OR Apache-2.0" AGPL-1.0; do
  jq --arg l "$l" '. + {license: $l}' "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "rejects license '$l'"; else ok "rejects license '$l'"; fi
done

# title: a display name, 1 to 60 characters, no control characters, no leading or trailing space.
jq '. + {"title": "Acme SEO Helper"}' "$f/good.json" > "$tmp/good.json"
if "$v" "$tmp/good.json" >/dev/null 2>&1; then ok "accepts title"; else no "accepts title"; fi
for t in $'Dev\u00a0Tools' $'Code \U0001F468\u200d\U0001F4BB' "$(printf '\u65e5%.0s' $(seq 25))"; do
  jq --arg t "$t" '. + {title: $t}' "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then ok "accepts title $t"; else no "accepts title $t"; fi
done
for case in '"title": "a\tb"' '"title": "a "' '"title": ""' '"title": " padded"' '"title": "a\u0007b"' "\"title\": \"$(printf 'x%.0s' $(seq 61))\"" '"title": 5'; do
  jq ". + {$case}" "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "rejects $case"; else ok "rejects $case"; fi
done

# subdir traversal and homepage scheme.
for case in '"subdir": "../x"' '"subdir": "/abs"' '"homepage": "http://x.example"'; do
  jq ". + {$case}" "$f/good.json" > "$tmp/good.json"
  if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "rejects $case"; else ok "rejects $case"; fi
done
jq '. + {"subdir": "plugins/seo"}' "$f/good.json" > "$tmp/good.json"
if "$v" "$tmp/good.json" >/dev/null 2>&1; then ok "accepts nested subdir"; else no "accepts nested subdir"; fi

# scripts/check-gomod.sh: plain-module rules of the registry build.
if command -v go >/dev/null; then
  g=scripts/check-gomod.sh
  mod() { rm -rf "$tmp/m"; mkdir -p "$tmp/m"; printf 'module example.com/m\n\ngo 1.22\n' >"$tmp/m/go.mod"; }
  mod
  if "$g" "$tmp/m" >/dev/null 2>&1; then ok "gomod accepts a plain module"; else no "gomod accepts a plain module"; fi
  mod; (cd "$tmp/m" && go mod edit -replace hatamoto.dev/sdk=github.com/x/sdk@v0.1.0)
  if err=$("$g" "$tmp/m" 2>&1) ; then no "gomod rejects an sdk replace"; elif [[ $err == *"replaces hatamoto.dev/sdk"* ]]; then ok "gomod rejects an sdk replace"; else no "gomod sdk replace: $err"; fi
  mod; (cd "$tmp/m" && go mod edit -replace example.com/x=../x)
  if err=$("$g" "$tmp/m" 2>&1) ; then no "gomod rejects a local replace"; elif [[ $err == *"local-path replace"* ]]; then ok "gomod rejects a local replace"; else no "gomod local replace: $err"; fi
  mod; printf 'go 1.22\nuse .\n' >"$tmp/m/go.work"
  if err=$("$g" "$tmp/m" 2>&1) ; then no "gomod rejects go.work"; elif [[ $err == *"go.work is not allowed"* ]]; then ok "gomod rejects go.work"; else no "gomod go.work: $err"; fi
  mod; mkdir "$tmp/m/sub"; mv "$tmp/m/go.mod" "$tmp/m/sub/"; printf 'use ./sub\n' >"$tmp/m/go.work"
  if "$g" "$tmp/m/sub" "$tmp/m" >/dev/null 2>&1; then no "gomod rejects go.work at the repo root"; else ok "gomod rejects go.work at the repo root"; fi
else
  echo "skip gomod tests: go not found"
fi

# scripts/changed-manifests.sh: selection of manifests to mirror, renames included.
repo=$PWD
cm() { (cd "$tmp/cm" && "$repo/scripts/changed-manifests.sh" "$@" | tr '\0' ' '); }
cg() { git -C "$tmp/cm" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
git init -q "$tmp/cm"; mkdir -p "$tmp/cm/manifests/themes" "$tmp/cm/manifests/sub"
for n in acme-seo keep gone; do jq --arg n "$n" '.name = $n' "$f/good.json" >"$tmp/cm/manifests/$n.json"; done
for p in schema.json themes/t.json sub/x.json; do echo '{}' >"$tmp/cm/manifests/$p"; done
cg add -A; cg commit -qm one
cg mv manifests/acme-seo.json manifests/acme-seo-pro.json
jq '.name = "acme-seo-pro"' "$tmp/cm/manifests/acme-seo-pro.json" >"$tmp/x" && mv "$tmp/x" "$tmp/cm/manifests/acme-seo-pro.json"
cg rm -q manifests/gone.json
echo '{"a":1}' >"$tmp/cm/manifests/schema.json"; echo '{"a":1}' >"$tmp/cm/manifests/themes/t.json"
jq '.title = "Changed"' "$tmp/cm/manifests/keep.json" >"$tmp/x" && mv "$tmp/x" "$tmp/cm/manifests/keep.json"
cg add -A; cg commit -qm two
want="manifests/acme-seo-pro.json manifests/keep.json "
if [ "$(cm HEAD~1 HEAD)" = "$want" ]; then ok "changed manifests: rename mirrored, delete/schema/themes skipped"; else no "changed manifests: $(cm HEAD~1 HEAD)"; fi
if [ "$(cm)" = "$want" ]; then ok "all manifests: schema, themes, nested skipped"; else no "all manifests: $(cm)"; fi

# scripts/mirror-rulesets.sh: payloads of the repository rulesets.
r=scripts/mirror-rulesets.sh
if "$r" tag | jq -e '.name == "archive-tags" and .target == "tag" and .enforcement == "active"
  and .conditions.ref_name.include == ["refs/tags/src/*", "refs/tags/v*"]
  and ([.rules[].type] | sort) == ["deletion", "update"]' >/dev/null; then ok "tag ruleset payload"; else no "tag ruleset payload"; fi
if "$r" branch | jq -e '.name == "archive-main" and .target == "branch" and .enforcement == "active"
  and .conditions.ref_name.include == ["refs/heads/main"]
  and ([.rules[].type] | sort) == ["deletion", "non_fast_forward"]' >/dev/null; then ok "branch ruleset payload"; else no "branch ruleset payload"; fi
if "$r" bogus >/dev/null 2>&1; then no "ruleset kind rejected"; else ok "ruleset kind rejected"; fi

# scripts/mirror-plugin.sh: offline fixture mirrors.
bash tests/mirror.sh
case $? in
  0) ok "mirror-plugin.sh tests" ;;
  77) echo "SKIP mirror-plugin.sh tests (go not found, MIRROR_TESTS_ALLOW_SKIP=1)" ;;
  *) no "mirror-plugin.sh tests" ;;
esac

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
