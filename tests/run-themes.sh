#!/usr/bin/env bash
# Self-test for scripts/validate-theme-manifest.sh (offline; --remote against local file:// sources).
# Go-backed archive negatives run only when HATAMOTO_BIN is set.
set -u
cd "$(dirname "$0")/.."
v=scripts/validate-theme-manifest.sh
f=tests/fixtures/themes
pass=0
failed=0

ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

for g in good-git-github good-git-codeberg good-archive good-title; do
  if "$v" "$f/$g.json" >/dev/null 2>&1; then ok "$g accepted"; else no "$g accepted"; fi
done

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
expect_reject bad-http-repo.json "repo must be an https://"
expect_reject bad-http-archive.json "archive must be an https://"
expect_reject bad-commit.json "commit must be 40"
expect_reject bad-sha256.json "sha256 must be 64"
expect_reject bad-both-sources.json "not both"
expect_reject bad-no-source.json "missing source"
expect_reject bad-extra-field.json "unknown field(s): sdk"
expect_reject default.json "reserved"
expect_reject bad-no-grant.json "missing required field: archive_grant"
expect_reject bad-license.json "license must be one of"
expect_reject bad-reserved.json "is reserved"
expect_reject bad-ip-host.json "public host name"
expect_reject bad-localhost.json "public host name"
expect_reject bad-port.json "public host name"
expect_reject bad-tier.json "unknown field(s): tier"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# name must equal the file name.
cp "$f/good-git-codeberg.json" "$tmp/other.json"
if err=$("$v" "$tmp/other.json" 2>&1 >/dev/null); then no "name/file mismatch rejected"
elif [[ $err == *"must equal the file name"* ]]; then ok "name/file mismatch rejected"
else no "name/file mismatch: $err"; fi

# Mutations of a good manifest.
mutate() { # <label> <jq filter> <expected substring>
  local err
  jq "$2" "$f/good-git-codeberg.json" > "$tmp/good-git-codeberg.json"
  if err=$("$v" "$tmp/good-git-codeberg.json" 2>&1 >/dev/null); then no "rejects $1"
  elif [[ $err == *"$3"* ]]; then ok "rejects $1"
  else no "rejects $1: $err"; fi
}
mutate "subdir traversal" '. + {subdir: "../x"}' "subdir must"
mutate "absolute subdir" '. + {subdir: "/abs"}' "subdir must"
mutate "http homepage" '. + {homepage: "http://x.example"}' "homepage must"
mutate "credentials in repo" '.repo = "https://user@codeberg.org/tanaka/kumo"' "repo must"
mutate "empty license" '.license = ""' "license must be one of"
mutate "grant false" '.archive_grant = false' "archive_grant must be true"
mutate "grant string" '.archive_grant = "true"' "archive_grant must be true"
mutate "long title" '. + {title: ("x" * 61)}' "title must be"
mutate "padded title" '. + {title: " x"}' "title must be"
mutate "internal suffix" '.repo = "https://git.corp/tanaka/kumo"' "public host name"
mutate "single label host" '.repo = "https://intranet/tanaka/kumo"' "public host name"
mutate "ipv6 host" '.repo = "https://[::1]/tanaka/kumo"' "public host name"
mutate "gtm name" '.name = "gtm"' "is reserved"
mutate "numeric author" '.author = 5' "author must be a string"
# Title length counts characters even under the C locale.
for n in 25 60; do
  jq --arg t "$(printf '\u65e5%.0s' $(seq "$n"))" '. + {title: $t}' "$f/good-git-codeberg.json" > "$tmp/good-git-codeberg.json"
  if LC_ALL=C "$v" "$tmp/good-git-codeberg.json" >/dev/null 2>&1; then ok "CJK title of $n chars accepted (LC_ALL=C)"; else no "CJK title of $n chars accepted (LC_ALL=C)"; fi
done
mutate "61-char CJK title" '. + {title: ("\u65e5" * 61)}' "title must be"
jq '. + {subdir: "themes/kumo"}' "$f/good-git-codeberg.json" > "$tmp/good-git-codeberg.json"
if "$v" "$tmp/good-git-codeberg.json" >/dev/null 2>&1; then ok "accepts nested subdir"; else no "accepts nested subdir"; fi

# about and features: same helper and rules as the plugin tests.
abfile() { mkdir -p "$tmp/ab"; jq "$1" "$f/good-git-codeberg.json" > "$tmp/ab/good-git-codeberg.json"; }
# about and features: 1 to 1500 characters in at most 10 newline-separated paragraphs; 1 to 8
# distinct features of 1 to 120 characters. ab <accept|reject> <label> <jq-mutation> [want]:
# a rejection must print the want substring (core's wording), also under LC_ALL=C.
ab() {
  local err
  abfile "$3"
  if err=$(LC_ALL=${ABLOC:-C.UTF-8} "$v" "$tmp/ab/good-git-codeberg.json" 2>&1 >/dev/null); then [ "$1" = accept ] && ok "about/features accepted: $2" || no "about/features accepted: $2"
  elif [ "$1" = accept ]; then no "about/features accepted: $2: $err"
  elif [[ $err == *"${4:-}"* ]]; then ok "about/features rejected: $2"
  else no "about/features rejected: $2: $err"; fi
}
x1501='([range(1501)|"x"]|join(""))'
ab accept "no fields" '.'
ab accept "both fields" '.about = "First paragraph.\nSecond paragraph." | .features = ["Fast", "Tiny"]'
ab accept "about only" '.about = "One paragraph."'
ab accept "features only" '.features = ["Fast"]'
ab accept "1500-character about" '.about = ([range(1500)|"x"]|join(""))'
ab accept "10 paragraphs" '.about = ([range(10)|"p"]|join("\n"))'
ab accept "8 features" '.features = [range(8)|"item \(.)"]'
ab accept "120-character feature" '.features = [([range(120)|"x"]|join(""))]'
ab accept "digits and CJK" '.about = "Works with 3D views.\n\u65e5\u672c\u8a9e\u3082\u4f7f\u3048\u307e\u3059" | .features = ["\u65e5\u672c\u8a9e"]'
ab reject "abstract is still unknown" '.about = "ok" | .abstract = "x"' "unknown field(s): abstract"
ab reject "about too long" ".about = $x1501" "about must be 1 to 1500"
ab reject "about empty" '.about = ""' "about must be 1 to 1500"
ab reject "about not a string" '.about = 5' "about must be a string"
ab reject "about control char" '.about = "a\u0007b"' "about must not contain control"
ab reject "about tab" '.about = "a\tb"' "about must not contain control"
ab reject "about carriage return" '.about = "a\r\nb"' "about must not contain control"
ab reject "about DEL" '.about = "a\u007fb"' "about must not contain control"
ab reject "about C1 control" '.about = "a\u0085b"' "about must not contain control"
ab reject "about url" '.about = "see https://example.test/x"' "about must not contain a URL"
ab reject "about www" '.about = "see www.example.test"' "about must not contain a URL"
ab reject "about uppercase url" '.about = "see HTTPS://example.test"' "about must not contain a URL"
ab reject "about uppercase www" '.about = "see WWW.example.test"' "about must not contain a URL"
ab reject "about angle bracket" '.about = "a <b> c"' "about must not contain < or >"
ab reject "about empty paragraph" '.about = "one\n\ntwo"' "about must not have an empty paragraph"
ab reject "about trailing newline" '.about = "one\n"' "about must not have an empty paragraph"
ab reject "about edge space" '.about = " one"' "about must not start or end with whitespace"
ab reject "about trailing space" '.about = "one "' "about must not start or end with whitespace"
ab reject "about eleven paragraphs" '.about = ([range(11)|"p"]|join("\n"))' "about must have at most 10 paragraphs"
ab reject "about emoji" '.about = "Great \ud83d\ude80 theme"' "about must not contain emoji"
ab reject "about zero-width edge" '.about = "\u200bone"' "emoji, symbols or invisible characters"
ab reject "about soft hyphen" '.about = "a\u00adb"' "emoji, symbols or invisible characters"
ab reject "about hangul filler" '.about = "a\u3164b"' "emoji, symbols or invisible characters"
ab reject "about modifier letter" '.about = "a\u02b0b"' "emoji, symbols or invisible characters"
ab reject "features not a list" '.features = "a"' "features must be a list of strings"
ab reject "features non-string item" '.features = ["a", 5]' "features must be a list of strings"
ab reject "features empty list" '.features = []' "features must list 1 to 8"
ab reject "features nine items" '.features = [range(9)|"item \(.)"]' "features must list 1 to 8"
ab reject "features long item" '.features = [([range(121)|"x"]|join(""))]' "each feature must be 1 to 120"
ab reject "features empty item" '.features = ["a", ""]' "each feature must be 1 to 120"
ab reject "features newline" '.features = ["a\nb"]' "a feature must not contain control"
ab reject "features DEL" '.features = ["a\u007fb"]' "a feature must not contain control"
ab reject "features C1 control" '.features = ["a\u0085b"]' "a feature must not contain control"
ab reject "features url" '.features = ["see https://example.test"]' "a feature must not contain a URL"
ab reject "features angle bracket" '.features = ["<b>"]' "a feature must not contain < or >"
ab reject "features edge space" '.features = ["a "]' "a feature must not start or end with whitespace"
ab reject "features duplicate" '.features = ["Fast", "fast"]' "features must not repeat an item"
ab reject "features emoji" '.features = ["Fast \ud83d\ude80"]' "a feature must not contain emoji"
ab reject "features hangul filler" '.features = ["a\u3164b"]' "emoji, symbols or invisible characters"
ab reject "features modifier letter" '.features = ["a\u02b0b"]' "emoji, symbols or invisible characters"
ab reject "features soft hyphen" '.features = ["a\u00adb"]' "emoji, symbols or invisible characters"
# Both groups are judged: a bad about and a bad feature each report.
abfile '.about = "a <b>" | .features = ["Fast", "fast"]'
err=$("$v" "$tmp/ab/good-git-codeberg.json" 2>&1 >/dev/null)
if [[ $err == *"about must not contain < or >"* && $err == *"features must not repeat an item"* ]]; then ok "about and features both reported"; else no "about and features both reported: $err"; fi

# The same verdicts under the C locale (lengths count characters).
ABLOC=C
ab accept "1500-character about (LC_ALL=C)" '.about = ([range(1500)|"x"]|join(""))'
ab accept "CJK about of 1500 characters (LC_ALL=C)" '.about = ([range(1500)|"\u65e5"]|join(""))'
ab reject "1501-character about (LC_ALL=C)" '.about = ([range(1501)|"\u65e5"]|join(""))' "about must be 1 to 1500"
ab reject "hangul filler (LC_ALL=C)" '.about = "a\u3164b"' "emoji, symbols or invisible characters"
ABLOC=C.UTF-8

# Every theme manifest of the registry keeps passing.
for m in manifests/themes/*.json; do
  [ -e "$m" ] || continue
  if "$v" "$m" >/dev/null 2>&1; then ok "registry theme $m accepted"; else no "registry theme $m accepted"; fi
done

# Archive source forbids subdir.
jq '. + {subdir: "x"}' "$f/good-archive.json" > "$tmp/good-archive.json"
if err=$("$v" "$tmp/good-archive.json" 2>&1 >/dev/null); then no "archive rejects subdir"
elif [[ $err == *"subdir is not allowed"* ]]; then ok "archive rejects subdir"
else no "archive rejects subdir: $err"; fi

# Cross-kind collision: a plugin manifest with the same name.
mkdir -p "$tmp/repo/manifests/themes"
cp "$f/good-git-codeberg.json" "$tmp/repo/manifests/themes/good-git-codeberg.json"
if "$v" "$tmp/repo/manifests/themes/good-git-codeberg.json" >/dev/null 2>&1; then ok "unique theme name accepted"; else no "unique theme name accepted"; fi
echo '{}' > "$tmp/repo/manifests/good-git-codeberg.json"
if err=$("$v" "$tmp/repo/manifests/themes/good-git-codeberg.json" 2>&1 >/dev/null); then no "plugin/theme collision rejected"
elif [[ $err == *"already used by a plugin"* ]]; then ok "plugin/theme collision rejected"
else no "plugin/theme collision: $err"; fi

# Cross-kind collision, other direction: a theme with the plugin's name.
mkdir -p "$tmp/rev/manifests/themes"
jq '.name = "rev"' "$f/good-git-codeberg.json" > "$tmp/rev/manifests/themes/rev.json"
pm=$(jq -n '{name:"rev",repo:"https://github.com/tanaka/kumo",commit:"0123456789abcdef0123456789abcdef01234567",author:"tanaka",license:"MIT",sdk:"1",archive_grant:true}')
echo "$pm" > "$tmp/rev/manifests/rev.json"
if err=$(scripts/validate-manifest.sh "$tmp/rev/manifests/rev.json" 2>&1 >/dev/null); then no "plugin rejects theme name"
elif [[ $err == *"is also a theme"* ]]; then ok "plugin rejects theme name"
else no "plugin rejects theme name: $err"; fi
rm "$tmp/rev/manifests/themes/rev.json"
if scripts/validate-manifest.sh "$tmp/rev/manifests/rev.json" >/dev/null 2>&1; then ok "plugin accepted without theme twin"; else no "plugin accepted without theme twin"; fi

# Look-alikes: a theme name next to plugins, reserved names and sibling themes.
la_theme() { # <label> <theme name> <expected substring|ok> [plugin name] [sibling theme name]
  local d="$tmp/la-$1" err
  rm -rf "$d"; mkdir -p "$d/manifests/themes"
  jq --arg n "$2" '.name = $n' "$f/good-git-codeberg.json" > "$d/manifests/themes/$2.json"
  [ -z "${4:-}" ] || echo '{}' > "$d/manifests/$4.json"
  [ -z "${5:-}" ] || jq --arg n "$5" '.name = $n' "$f/good-git-codeberg.json" > "$d/manifests/themes/$5.json"
  err=$("$v" "$d/manifests/themes/$2.json" 2>&1 >/dev/null); rc=$?
  if [ "$3" = ok ]; then
    if [ "$rc" -eq 0 ]; then ok "look-alike: $1 accepted"; else no "look-alike: $1 accepted: $err"; fi
  elif [ "$rc" -ne 0 ] && [[ $err == *"$3"* ]]; then ok "look-alike: $1 rejected"
  else no "look-alike: $1 rejected with \"$3\" (rc=$rc): $err"; fi
}
la_theme "one edit from a plugin" gtn 'looks like "gtm"' gtm
la_theme "hyphen form of a plugin" g-tm 'looks like "gtm"' gtm
la_theme "digit swap of a plugin" kum0 'looks like "kumo"' kumo
la_theme "one edit from a hardcoded reserved name" webhook 'looks like "webhooks"'
la_theme "one edit from a policy reserved name" formz 'looks like "forms"'
la_theme "exact policy reserved name" forms 'is reserved'
la_theme "one edit from a sibling theme" hanshl 'looks like "hanshi"' "" hanshi
la_theme "unrelated name beside a plugin and a theme" kumoyama ok gtm hanshi

# The theme validator reads policy/reserved-names.txt next to its own scripts/ dir; fail closed.
mkdir -p "$tmp/np/scripts" "$tmp/ep/scripts" "$tmp/ep/policy"
cp "$v" "$tmp/np/scripts/"; cp "$v" "$tmp/ep/scripts/"
: > "$tmp/ep/policy/reserved-names.txt"
for pc in np ep; do
  want="missing policy"; [ "$pc" = ep ] && want="empty policy"
  if err=$("$tmp/$pc/scripts/validate-theme-manifest.sh" "$f/good-git-codeberg.json" 2>&1 >/dev/null); then no "$pc policy rejected (exit 0)"
  elif [[ $err == *"$want"* ]]; then ok "$pc policy rejected: $want"
  else no "$pc policy rejected but stderr lacks \"$want\": $err"; fi
done

# License arrays must match the plugin validator.
arr() { # <script>: the license allowlist as a sorted list
  bash -c 'src=$(sed -n "/^licenses=(/,/^done/p" "$1"); eval "$src"; printf "%s\n" "${licenses[@]}" | sort' _ "$1"
}
if [ -n "$(arr scripts/validate-theme-manifest.sh)" ] && [ "$(arr scripts/validate-theme-manifest.sh)" = "$(arr scripts/validate-manifest.sh)" ]; then ok "license arrays match"; else no "license arrays match"; fi

# --remote against local sources (offline).
export HATAMOTO_ALLOW_FILE_REPOS=1 HATAMOTO_ALLOW_FILE_ARCHIVES=1
png=$(printf 'x%.0s' $(seq 1 100))
mk_repo() { # <dir> <with-screenshot 0|1> <theme name>
  mkdir -p "$1/assets"
  printf '{"name":"%s","screenshot":"assets/s.png"}' "$3" > "$1/theme.json"
  [ "$2" = 0 ] || printf '%s' "$png" > "$1/assets/s.png"
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.com commit -q -m init
}
remote_manifest() { # <name> <jq-args...>: manifest at $tmp/rm/manifests/themes/<name>.json
  local n=$1; shift
  mkdir -p "$tmp/rm/manifests/themes"
  jq -n "$@" --arg n "$n" '{name:$n,author:"tanaka",license:"MIT",archive_grant:true} + $extra' > "$tmp/rm/manifests/themes/$n.json"
}
mk_repo "$tmp/src-ok" 1 remok
sha=$(git -C "$tmp/src-ok" rev-parse HEAD)
remote_manifest remok --argjson extra "{\"repo\":\"file://$tmp/src-ok\",\"commit\":\"$sha\"}"
if "$v" "$tmp/rm/manifests/themes/remok.json" --remote >/dev/null 2>&1; then ok "remote git accepted"; else no "remote git accepted"; fi
mk_repo "$tmp/src-noshot" 0 remnoshot
sha=$(git -C "$tmp/src-noshot" rev-parse HEAD)
remote_manifest remnoshot --argjson extra "{\"repo\":\"file://$tmp/src-noshot\",\"commit\":\"$sha\"}"
if err=$("$v" "$tmp/rm/manifests/themes/remnoshot.json" --remote 2>&1 >/dev/null); then no "remote git missing screenshot rejected"
elif [[ $err == *"screenshot"*"not found"* ]]; then ok "remote git missing screenshot rejected"
else no "remote git missing screenshot: $err"; fi
mk_repo "$tmp/src-name" 1 other
sha=$(git -C "$tmp/src-name" rev-parse HEAD)
remote_manifest remname --argjson extra "{\"repo\":\"file://$tmp/src-name\",\"commit\":\"$sha\"}"
if err=$("$v" "$tmp/rm/manifests/themes/remname.json" --remote 2>&1 >/dev/null); then no "remote git name mismatch rejected"
elif [[ $err == *"does not match"* ]]; then ok "remote git name mismatch rejected"
else no "remote git name mismatch: $err"; fi

if command -v zip >/dev/null 2>&1; then
  mk_repo "$tmp/zsrc" 1 remzip
  (cd "$tmp/zsrc" && zip -qr "$tmp/remzip.zip" theme.json assets)
  zsha=$(sha256sum "$tmp/remzip.zip" | cut -d' ' -f1)
  remote_manifest remzip --argjson extra "{\"archive\":\"file://$tmp/remzip.zip\",\"sha256\":\"$zsha\"}"
  if "$v" "$tmp/rm/manifests/themes/remzip.json" --remote >/dev/null 2>&1; then ok "remote archive accepted"; else no "remote archive accepted"; fi
  remote_manifest remzip --argjson extra "{\"archive\":\"file://$tmp/remzip.zip\",\"sha256\":\"$(printf 'b%.0s' $(seq 1 64))\"}"
  if err=$("$v" "$tmp/rm/manifests/themes/remzip.json" --remote 2>&1 >/dev/null); then no "remote archive sha mismatch rejected"
  elif [[ $err == *"sha256 mismatch"* ]]; then ok "remote archive sha mismatch rejected"
  else no "remote archive sha mismatch: $err"; fi
  # Large archive, screenshot listed first: must not SIGPIPE into "not found".
  big_zip() { # <out.zip> <screenshot-bytes>
    python3 - "$1" "$2" "$png" <<'PY'
import sys, zipfile
out, size, png = sys.argv[1], int(sys.argv[2]), sys.argv[3].encode("latin-1")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("assets/s.png", (png + b"\0" * size)[:max(size, len(png))])
    z.writestr("theme.json", '{"name":"rembig","screenshot":"assets/s.png"}')
    for i in range(2000):
        z.writestr("assets/extra/" + "d" * 80 + "-%04d.txt" % i, "x")
PY
  }
  if command -v python3 >/dev/null 2>&1; then
    big_zip "$tmp/rembig.zip" 1000
    bsha=$(sha256sum "$tmp/rembig.zip" | cut -d' ' -f1)
    remote_manifest rembig --argjson extra "{\"archive\":\"file://$tmp/rembig.zip\",\"sha256\":\"$bsha\"}"
    if err=$("$v" "$tmp/rm/manifests/themes/rembig.json" --remote 2>&1 >/dev/null); then ok "2000-entry archive, early screenshot accepted"
    else no "2000-entry archive, early screenshot accepted: $err"; fi
    big_zip "$tmp/rembig2.zip" $((2 * 1024 * 1024 + 1))
    bsha=$(sha256sum "$tmp/rembig2.zip" | cut -d' ' -f1)
    remote_manifest rembig --argjson extra "{\"archive\":\"file://$tmp/rembig2.zip\",\"sha256\":\"$bsha\"}"
    if err=$("$v" "$tmp/rm/manifests/themes/rembig.json" --remote 2>&1 >/dev/null); then no "oversized screenshot in archive rejected"
    elif [[ $err == *"limit is"* ]]; then ok "oversized screenshot in archive rejected"
    else no "oversized screenshot in archive: $err"; fi
  fi
  # Missing declared screenshot: clear error.
  mk_repo "$tmp/zns" 0 remzns
  (cd "$tmp/zns" && zip -qr "$tmp/remzns.zip" theme.json)
  zns=$(sha256sum "$tmp/remzns.zip" | cut -d' ' -f1)
  remote_manifest remzns --argjson extra "{\"archive\":\"file://$tmp/remzns.zip\",\"sha256\":\"$zns\"}"
  if err=$("$v" "$tmp/rm/manifests/themes/remzns.json" --remote 2>&1 >/dev/null); then no "archive missing screenshot rejected"
  elif [[ $err == *"screenshot assets/s.png declared in theme.json not found in archive"* ]]; then ok "archive missing screenshot rejected"
  else no "archive missing screenshot: $err"; fi
  # Wildcard names are matched literally, never as patterns.
  mk_repo "$tmp/zwild" 1 remzwild
  printf '{"name":"remzwild","screenshot":"assets/*"}' > "$tmp/zwild/theme.json"
  (cd "$tmp/zwild" && zip -qr "$tmp/remzwild.zip" theme.json assets)
  zw=$(sha256sum "$tmp/remzwild.zip" | cut -d' ' -f1)
  remote_manifest remzwild --argjson extra "{\"archive\":\"file://$tmp/remzwild.zip\",\"sha256\":\"$zw\"}"
  if err=$("$v" "$tmp/rm/manifests/themes/remzwild.json" --remote 2>&1 >/dev/null); then no "wildcard screenshot rejected"
  elif [[ $err == *"wildcard"* ]]; then ok "wildcard screenshot rejected"
  else no "wildcard screenshot: $err"; fi
  # A decoy */theme.json-style wrapper name must not match other entries.
  mkdir -p "$tmp/zwrap/w[a]/assets" "$tmp/zwrap/wa/assets"
  printf '{"name":"remzwrap","screenshot":"assets/s.png"}' > "$tmp/zwrap/w[a]/theme.json"
  printf 'x' > "$tmp/zwrap/w[a]/assets/s.png"
  printf '{"name":"decoy","screenshot":"assets/s.png"}' > "$tmp/zwrap/wa/theme.json"
  (cd "$tmp/zwrap" && zip -qr "$tmp/remzwrap.zip" "w[a]")
  zr=$(sha256sum "$tmp/remzwrap.zip" | cut -d' ' -f1)
  remote_manifest remzwrap --argjson extra "{\"archive\":\"file://$tmp/remzwrap.zip\",\"sha256\":\"$zr\"}"
  if "$v" "$tmp/rm/manifests/themes/remzwrap.json" --remote >/dev/null 2>&1; then ok "wrapper dir with glob chars read literally"; else no "wrapper dir with glob chars read literally"; fi
else
  echo "SKIP remote archive tests (zip not installed)"
fi
unset HATAMOTO_ALLOW_FILE_REPOS HATAMOTO_ALLOW_FILE_ARCHIVES

# Go-backed archive negatives (hostile zips) need the real binary.
if [ -n "${HATAMOTO_BIN:-}" ]; then
  if "$HATAMOTO_BIN" theme check --help >/dev/null 2>&1; then ok "HATAMOTO_BIN theme check available"; else no "HATAMOTO_BIN theme check available"; fi
else
  echo "SKIP Go-backed archive negatives (HATAMOTO_BIN not set)"
fi

# schemas/theme-manifest.schema.json agrees with the validator. Needs python3 jsonschema;
# a missing module fails the suite unless SCHEMA_TESTS_ALLOW_SKIP=1.
if python3 -c 'import jsonschema' >/dev/null 2>&1; then
  sv() { python3 - "$1" <<'PY'
import json, sys, jsonschema
s = json.load(open("schemas/theme-manifest.schema.json"))
sys.exit(0 if jsonschema.Draft202012Validator(s).is_valid(json.load(open(sys.argv[1]))) else 1)
PY
  }
  # Fixtures: validator and schema must give the same verdict. The file-name rule
  # (name == basename) is outside the schema, so compare only on content-level fixtures.
  for g in good-git-github good-git-codeberg good-archive good-title; do
    if sv "$f/$g.json"; then ok "schema accepts $g"; else no "schema accepts $g"; fi
  done
  for b in bad-http-repo bad-http-archive bad-commit bad-sha256 bad-both-sources bad-no-source bad-extra-field bad-no-grant bad-license bad-reserved default bad-tier; do
    if sv "$f/$b.json"; then no "schema rejects $b"; else ok "schema rejects $b"; fi
  done
  smut() { # <label> <accept|reject> <jq filter>
    jq "$3" "$f/good-git-codeberg.json" > "$tmp/s.json"
    if sv "$tmp/s.json"; then [ "$2" = accept ] && ok "schema: $1" || no "schema: $1"
    else [ "$2" = reject ] && ok "schema: $1" || no "schema: $1"; fi
  }
  smut "subdir traversal" reject '. + {subdir: "../x"}'
  smut "subdir mid traversal" reject '. + {subdir: "a/../x"}'
  smut "absolute subdir" reject '. + {subdir: "/abs"}'
  smut "nested subdir" accept '. + {subdir: "themes/kumo"}'
  smut "dotted subdir name" accept '. + {subdir: "a..b/x"}'
  smut "plain public repo host" accept '.repo = "https://example.com/a/b"'
  smut "61-char title" reject '. + {title: ("x" * 61)}'
  smut "25 CJK title" accept '. + {title: ("\u65e5" * 25)}'
  smut "about and features" accept '. + {about: "First paragraph.\nSecond paragraph.", features: ["Fast", "Tiny"]}'
  smut "1500-character about" accept '. + {about: ([range(1500)|"x"]|join(""))}'
  smut "8 features" accept '. + {features: [range(8)|"item \(.)"]}'
  for c in '. + {about: ([range(1501)|"x"]|join(""))}' '. + {about: "a <b> c"}' '. + {about: "a\tb"}' '. + {about: ""}' '. + {about: 5}' \
    '. + {features: [range(9)|"item \(.)"]}' '. + {features: [([range(121)|"x"]|join(""))]}' '. + {features: ["a", 5]}' '. + {features: []}' '. + {features: ["a\nb"]}' '. + {features: ["<b>"]}' '. + {features: "a"}'; do
    smut "about/features: $c" reject "$c"
  done
elif [ "${SCHEMA_TESTS_ALLOW_SKIP:-}" = 1 ]; then
  echo "skip schema tests: python3 jsonschema not found (SCHEMA_TESTS_ALLOW_SKIP=1)"
else
  no "schema tests need python3 jsonschema (set SCHEMA_TESTS_ALLOW_SKIP=1 to skip)"
fi

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
