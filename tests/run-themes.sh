#!/usr/bin/env bash
# Self-test for scripts/validate-theme-manifest.sh (offline, no --remote).
# Go-backed archive negatives run only when HATAMOTO_BIN is set.
set -u
cd "$(dirname "$0")/.."
v=scripts/validate-theme-manifest.sh
f=tests/fixtures/themes
pass=0
failed=0

ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

for g in good-git-github good-git-codeberg good-archive; do
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
mutate "empty license" '.license = ""' "license must not be empty"
mutate "numeric author" '.author = 5' "author must be a string"
jq '. + {subdir: "themes/kumo"}' "$f/good-git-codeberg.json" > "$tmp/good-git-codeberg.json"
if "$v" "$tmp/good-git-codeberg.json" >/dev/null 2>&1; then ok "accepts nested subdir"; else no "accepts nested subdir"; fi

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

# Go-backed archive negatives (hostile zips) need the real binary.
if [ -n "${HATAMOTO_BIN:-}" ]; then
  if "$HATAMOTO_BIN" theme check --help >/dev/null 2>&1; then ok "HATAMOTO_BIN theme check available"; else no "HATAMOTO_BIN theme check available"; fi
else
  echo "SKIP Go-backed archive negatives (HATAMOTO_BIN not set)"
fi

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
