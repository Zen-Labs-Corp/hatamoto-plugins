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

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
