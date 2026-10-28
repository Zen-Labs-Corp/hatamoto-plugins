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
expect_reject bad-title.json "title must be 1 to 40"
expect_reject bad-title-separators.json "more than one separator"
expect_reject bad-title-script.json "title mixes scripts"
expect_reject bad-title-words.json 'banned word "best"'
expect_reject missing-grant.json "missing required field: archive_grant"
expect_reject bad-grant.json "archive_grant must be true"
expect_reject bad-author.json 'author "google" must equal the repo owner "acme"'
expect_reject bad-name-brand.json 'name must not start with the brand "stripe"'
expect_reject bad-name-reserved.json 'name "seo" is reserved'
expect_reject bad-name-token.json 'contains the banned word "beta"'
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
fp gtm Zen-Labs-Corp
if "$v" "$tmp/gtm.json" >/dev/null 2>&1; then ok "first-party owner Zen-Labs-Corp accepted"; else no "first-party owner Zen-Labs-Corp accepted"; fi
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
for o in zenlabscorp-evil zenlabscorpx zenlabscorp.evil xzenlabscorp zen-labs-corp-evil zen-labs-corpx xzen-labs-corp; do
  reject_fp "look-alike owner $o" "tier first-party requires" gtm . "$o"
done
# tier on a community-owned good.json (author present, acme owner) is refused too.
jq '. + {"tier": "first-party"}' "$f/good.json" > "$tmp/good.json"
if "$v" "$tmp/good.json" >/dev/null 2>&1; then no "community manifest with tier rejected"; else ok "community manifest with tier rejected"; fi
# author is still required without a tier.
jq 'del(.author)' "$f/good.json" > "$tmp/good.json"
if err=$("$v" "$tmp/good.json" 2>&1 >/dev/null); then no "missing author rejected"
elif [[ $err == *"missing required field: author"* ]]; then ok "missing author rejected"; else no "missing author: $err"; fi

# Author must equal the repo owner, case-insensitively; a listed brand owner may use the brand.
jq '.author = "ACME"' "$f/good.json" > "$tmp/good.json"
if "$v" "$tmp/good.json" >/dev/null 2>&1; then ok "author compared case-insensitively"; else no "author compared case-insensitively"; fi
for n in acme-stripe; do
  jq --arg n "$n" '.name = $n' "$f/good.json" > "$tmp/$n.json"
  if "$v" "$tmp/$n.json" >/dev/null 2>&1; then ok "accepts name $n"; else no "accepts name $n"; fi
done
jq '.name = "google-sync" | .repo = "https://github.com/Zen-Labs-Corp/x"' "$f/good.json" | jq '.author = "zen-labs-corp"' > "$tmp/google-sync.json"
if "$v" "$tmp/google-sync.json" >/dev/null 2>&1; then ok "brand owner may use the brand"; else no "brand owner may use the brand"; fi
jq '.name = "google-sync"' "$f/good.json" > "$tmp/google-sync.json"
if "$v" "$tmp/google-sync.json" >/dev/null 2>&1; then no "brand rejected for another owner"; else ok "brand rejected for another owner"; fi

# Look-alike names against sibling manifests (themes included) and reserved names.
mkdir -p "$tmp/lk/themes"
jq '.name = "acme-sync"' "$f/good.json" > "$tmp/lk/acme-sync.json"
jq '.name = "gtm" | .tier = "first-party" | .repo = "https://github.com/Zen-Labs-Corp/x" | del(.author)' "$f/good.json" > "$tmp/lk/gtm.json"
echo '{}' > "$tmp/lk/themes/sumi-ink.json"
lk() { # lk <accept|reject> <name>
  jq --arg n "$2" '.name = $n' "$f/good.json" > "$tmp/lk/$2.json"
  if "$v" "$tmp/lk/$2.json" >/dev/null 2>&1; then [ "$1" = accept ] && ok "look-alike: accepts $2" || no "look-alike: accepts $2"
  else [ "$1" = reject ] && ok "look-alike: rejects $2" || no "look-alike: rejects $2"; fi
}
if "$v" "$tmp/lk/gtm.json" >/dev/null 2>&1; then ok "look-alike: an existing manifest is not its own look-alike"; else no "look-alike: self"; fi
lk accept acme-other
for n in gtn acme-synk acme-syn acmesync acme-sync2 acm3-sync sumi-ink2 l0gin; do lk reject "$n"; done

# Fail closed without the policy lists.
mkdir -p "$tmp/root/scripts" "$tmp/root2/scripts" "$tmp/root2/policy"
cp scripts/validate-manifest.sh "$tmp/root/scripts/"
cp scripts/validate-manifest.sh "$tmp/root2/scripts/"
cp policy/*.txt "$tmp/root2/policy/"; rm "$tmp/root2/policy/brands.txt"
for r in root root2; do
  if err=$("$tmp/$r/scripts/validate-manifest.sh" "$f/good.json" 2>&1 >/dev/null); then no "$r: missing policy rejected"
  elif [[ $err == *"missing policy"* ]]; then ok "$r: missing policy rejected"
  else no "$r: missing policy: $err"; fi
done

# Every manifest of the registry keeps passing (schema.json is not a manifest).
for m in manifests/*.json; do
  [ "$m" = manifests/schema.json ] && continue
  if "$v" "$m" >/dev/null 2>&1; then ok "registry manifest $m accepted"; else no "registry manifest $m accepted"; fi
done

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
  fp gtm Zen-Labs-Corp; sc accept "first-party Zen-Labs-Corp" "$tmp/gtm.json"
  fp gtm zen-labs-corp; sc accept "first-party zen-labs-corp" "$tmp/gtm.json"
  for o in zen-labs-corp-evil zen-labs-corpx zen-labs.corp xzen-labs-corp; do fp gtm "$o"; sc reject "look-alike $o" "$tmp/gtm.json"; done
  jq --arg t "$(printf 'x%.0s' $(seq 40))" '.title = $t' "$f/good.json" > "$tmp/x.json"; sc accept "40-character title" "$tmp/x.json"
  jq --arg t "$(printf 'x%.0s' $(seq 41))" '.title = $t' "$f/good.json" > "$tmp/x.json"; sc reject "41-character title" "$tmp/x.json"
  fp gtm acme; sc reject "first-party from acme" "$tmp/gtm.json"
  for o in zenlabscorp-evil zenlabscorpx zenlabscorp.evil; do fp gtm "$o"; sc reject "look-alike $o" "$tmp/gtm.json"; done
  fp gtm zenlabscorp; jq '.author = "zenlabscorp"' "$tmp/gtm.json" > "$tmp/x.json"; sc reject "tier with author" "$tmp/x.json"
  jq '.tier = "community"' "$tmp/gtm.json" > "$tmp/x.json"; sc reject "tier community" "$tmp/x.json"
  jq 'del(.author)' "$f/good.json" > "$tmp/x.json"; sc reject "no tier, no author" "$tmp/x.json"
  for r in webhooks hello gtm searchconsole; do
    jq --arg n "$r" '.name = $n' "$f/good.json" > "$tmp/x.json"; sc reject "community reserved name $r" "$tmp/x.json"
  done
  for r in webhooks hello; do fp "$r" zenlabscorp; sc reject "first-party reserved name $r" "$tmp/$r.json"; done
  fp searchconsole zenlabscorp; sc accept "first-party searchconsole" "$tmp/searchconsole.json"
  fp searchconsole acme; sc reject "first-party searchconsole from acme" "$tmp/searchconsole.json"
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

# title: a display name, 1 to 40 characters, one script, no symbols; community titles share a word with the name.
# tt <accept|reject> <title> [first-party]: good.json (or a first-party gtm) with that title.
tt() {
  local m=good
  mkdir -p "$tmp/tt"
  if [ -n "${3:-}" ]; then m=gtm; fp gtm zenlabscorp; jq --arg t "$2" '.title = $t' "$tmp/gtm.json" > "$tmp/tt/gtm.json"
  else jq --arg t "$2" '.title = $t' "$f/good.json" > "$tmp/tt/good.json"; fi
  if "$v" "$tmp/tt/$m.json" >/dev/null 2>&1; then [ "$1" = accept ] && ok "title accepted: $2" || no "title accepted: $2"
  else [ "$1" = reject ] && ok "title rejected: $2" || no "title rejected: $2"; fi
}
for t in "Good Helper" "Good" "Acme Sync for Stripe Good" "Good 1 Tools" "Good: Helper" "Good Helper!" "Good-Helper"; do tt accept "$t"; done
x40=$(printf 'x%.0s' $(seq 36)); tt accept "Good $(printf 'x%.0s' $(seq 35))"
tt reject "Good $x40"
tt reject "Good $(printf 'x%.0s' $(seq 37))"
tt reject "Lead Delivery: HubSpot, Zapier, Webhooks & Email"
tt reject "Moksa Subscriptions 定期定額"
tt reject "Best Good Plugin"
tt reject "Good #1 Helper"
tt reject "Good Free Helper"
tt reject "Good PRO"
tt reject "Hatamoto Good"
tt reject "Good Wordpress"
tt reject "Stripe Good"
tt reject "Helper Tools"
tt reject "Good A: B: C"
tt reject "Good & Co, Helper"
tt reject "Good Helper$(printf '\u200b')"
tt reject "Good$(printf '\u202e')Helper"
tt reject "Good $(printf '\U0001F468\u200d\U0001F4BB')"
tt reject "Good $(printf '\U0001F600')"
tt reject "Good (Helper)"
tt reject "Good [Helper]"
tt reject "Good {Helper}"
tt reject "Good <Helper>"
tt reject "Good $(printf '\uff08x\uff09')"
tt reject "Good $(printf '\u300cx\u300d')"
tt reject "Good Dev$(printf '\u00a0')Tools"
tt reject "Good $(printf '\u0430')bc"
tt reject "Good Caf$(printf 'e\u0301')"
tt reject "Good $(printf '\uff42\uff45\uff53\uff54')"
tt reject "Good Tools $(printf '\u2605')"
tt reject "Good $(printf '\u0928\u092e\u0938\u094d\u0924\u0947')"
# Look-alike letters and digit-only words: a title is compared after folding to ASCII.
nm() { # nm <accept|reject> <name> <title> <want>
  jq --arg n "$2" --arg t "$3" '.name = $n | .title = $t' "$f/good.json" > "$tmp/tt/$2.json"
  if err=$("$v" "$tmp/tt/$2.json" 2>&1 >/dev/null); then [ "$1" = accept ] && ok "title accepted: $3" || no "title accepted: $3"
  elif [ "$1" = accept ]; then no "title accepted: $3: $err"
  elif [[ $err == *"$4"* ]]; then ok "title rejected: $3"
  else no "title rejected: $3: $err"; fi
}
mkdir -p "$tmp/tt"
nm reject pay-1 "$(printf '\u0430\u0440\u0440\u04cf\u0435') 1" "share a word"
nm reject pay-1 "$(printf '\u0261oogle') 1" 'must not start with the brand "google"'
nm reject acme-sync "Acme Sync PREM$(printf '\u0130')UM" 'banned word "premium"'
nm reject name-1 "Other 1" "share a word"
nm accept name-1 "Name 1" ""
# A brand is refused as a prefix of the first name token and of the first title word.
nm reject stripecheckout "Stripecheckout" 'title must not start with the brand "stripe"'
nm reject stripecheckout "Stripecheckout" 'name must not start with the brand "stripe"'
# First-party titles still get the character, script and word rules, but need not share a word.
tt accept "Google Tag Manager" fp
tt accept "$(printf '\u65e5\u672c\u8a9e\u306e\u30bf\u30a4\u30c8\u30eb\u30fc')" fp
tt accept "$(printf '\u6f22\u5b57 \ud55c\uae00')" fp
tt accept "$(printf '\u65e5%.0s' $(seq 25))" fp
tt reject "$(printf '\u3072\u3089\u304c\u306a \ud55c\uae00')" fp
tt reject "Tag $(printf '\u0416')" fp
tt reject "Best Tag Manager" fp
tt reject "Tag (Manager)" fp
tt reject "Tag: Manager, Pro" fp
tt reject "$(printf 'x%.0s' $(seq 41))" fp
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

# Description rules: --remote reads plugin.json at the pinned commit (file:/// repos, offline).
# rd <accept|reject> <label> <plugin.json description as JSON, or "-" for none> [want]
rd() {
  local want=$1 label=$2 desc=$3 msg=${4:-} dir="$tmp/rd/own/descy" err
  rm -rf "$dir" "$tmp/rd/manifests"; mkdir -p "$dir" "$tmp/rd/manifests"
  if [ "$desc" = "-" ]; then jq -n '{name: "descy", sdk: "^0.10"}' > "$dir/plugin.json"
  else jq -n --argjson d "$desc" '{name: "descy", sdk: "^0.10", description: $d}' > "$dir/plugin.json"; fi
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
  jq --arg r "file://$dir" --arg c "$(git -C "$dir" rev-parse HEAD)" \
    '.name = "descy" | .repo = $r | .commit = $c | .author = "own" | .title = "Descy Tools"' "$f/good.json" > "$tmp/rd/manifests/descy.json"
  if err=$(HATAMOTO_ALLOW_FILE_REPOS=1 "$v" "$tmp/rd/manifests/descy.json" --remote 2>&1 >/dev/null); then
    [ "$want" = accept ] && ok "description accepted: $label" || no "description accepted: $label"
  elif [ "$want" = accept ]; then no "description accepted: $label: $err"
  elif [[ $err == *"$msg"* ]]; then ok "description rejected: $label"
  else no "description rejected: $label: $err"; fi
}
rd accept "plain sentence" '"Adds a contact page to a site."'
rd accept "two sentences" '"Adds a contact page. Works with any theme."'
rd accept "free and plugin allowed" '"A free plugin that adds a contact page."'
rd accept "two brands" '"Sends form entries to Slack and Zapier."'
rd accept "Japanese" '"お問い合わせページをサイトに追加します。簡単に使えます。"'
rd reject "missing" - "must be a string"
rd reject "not a string" '5' "must be a string"
rd reject "too short" '"Too short."' "20 to 160"
rd reject "too long" "\"$(printf 'a%.0s' $(seq 161))\"" "20 to 160"
rd reject "three terminators" '"Adds a page. Works well. Is fast!"' "terminators"
rd reject "fullwidth terminators" '"サイトに追加します。簡単です。使えます。"' "terminators"
rd reject "URL scheme" '"Docs at http://example.com for the page"' "URL"
rd reject "www" '"Visit www example and www.example for more"' "URL"
rd reject "bare domain" '"Adds a contact page, see example.com now"' "URL"
rd reject "emoji" "\"Adds a contact page $(printf '\U0001F600') to a site\"" "emoji"
rd reject "zero width" "\"Adds a contact$(printf '\u200b') page to a site\"" "emoji, symbols or invisible"
rd reject "control character" '"Adds a contact page\nto a site today"' "control characters"
rd reject "placeholder" '"One sentence a site owner will read in the plugin directory."' "placeholder"
rd reject "placeholder, other case" '"  one SENTENCE a site owner will read in the plugin directory.  "' "placeholder"
rd reject "equals the title" '"descy tools"' "equal the title"
rd reject "four brands" '"Connects Slack, Zapier, Notion and Github now"' "more than 3 brands"
rd reject "banned word" '"The best contact page for your site"' 'banned word "best"'
rd reject "banned word #1" '"Adds a contact page, rated #1 by users"' 'banned word "#1"'

# validate.yml: the judge job runs no pull request code and fails closed.
wf=.github/workflows/validate.yml
judge=$(awk '/^  judge:/{on=1;print;next} on && /^  [a-z]+:/{exit} on{print}' "$wf")
if [ -n "$judge" ] && ! grep -Eq 'tests/|scripts/validate-(theme-)?manifest\.sh "\$f"|scripts/check' <<<"$judge"; then ok "judge job runs no pull request code"; else no "judge job runs no pull request code"; fi
if grep -q 'diff-filter=AMRT' <<<"$judge" && grep -q '100644' <<<"$judge"; then ok "judge job lists type changes and requires regular files"; else no "judge job lists type changes and requires regular files"; fi
if grep -q 'exit 1' <<<"$judge" && ! grep -q 'fetch_trusted\|return 1\|return 0' <<<"$judge"; then ok "judge job stops when a base file is missing"; else no "judge job stops when a base file is missing"; fi

# Description look-alikes: combining marks, fullwidth forms and other symbols are refused.
rd reject "combining marks" "\"Fr$(printf '\u0301')ee and pr$(printf '\u0301')emium tooling for your team\"" "may contain only"
rd reject "fullwidth letters" "\"$(printf '\uff26\uff52\uff45\uff45') tooling for your team and your site\"" "may contain only"
rd reject "dot leader" "\"Visit example$(printf '\u2024')com for the page now\"" "may contain only"
rd reject "Cyrillic brand look-alike" "\"Works with Stripe, PayPal, Slack, N$(printf '\u043e')tion and Z$(printf '\u0430')pier\"" "more than 3 brands"
rd reject "Cyrillic banned word" "\"The b$(printf '\u0435')st contact page for your site\"" 'banned word "best"'
rd accept "apostrophe and dash" '"Adds a contact page, it\u0027s fast - and simple."'

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

# tests/run-themes.sh: theme manifest validator tests (a failure here fails this suite).
if bash tests/run-themes.sh; then ok "run-themes.sh tests"; else no "run-themes.sh tests"; fi

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
