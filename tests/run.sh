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

# name must equal the file name.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$f/good.json" "$tmp/other.json"
if err=$("$v" "$tmp/other.json" 2>&1 >/dev/null); then no "name/file mismatch rejected"
elif [[ $err == *"must equal the file name"* ]]; then ok "name/file mismatch rejected"
else no "name/file mismatch: $err"; fi

# Reserved first-party names.
for r in gtm webhooks searchconsole hello; do
  jq --arg n "$r" '.name = $n' "$f/good.json" > "$tmp/$r.json"
  if err=$("$v" "$tmp/$r.json" 2>&1 >/dev/null); then no "reserved name $r rejected"
  elif [[ $err == *"reserved for a first-party plugin"* ]]; then ok "reserved name $r rejected"
  else no "reserved name $r: $err"; fi
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

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
