#!/usr/bin/env bash
export LC_ALL=C.UTF-8
# Offline self-test for scripts/mirror-plugin.sh: fixture upstream repos and bare
# mirror repos under a temp dir, no network, no token.
set -u
cd "$(dirname "$0")/.."
root=$PWD
pass=0
failed=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; failed=$((failed + 1)); }

if ! command -v go >/dev/null; then echo "skip mirror tests: go not found"; exit 0; fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HATAMOTO_ALLOW_FILE_REPOS=1 MIRROR_CREATE=local MIRROR_BASE=file://$tmp/mirrors
export GOTOOLCHAIN=local GOWORK=off GOFLAGS=-mod=mod GOPROXY=file://$tmp/proxy GOSUMDB=off
unset SDK_PUBLIC GH_TOKEN
m=scripts/mirror-plugin.sh
gi() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }

# upstream <dir> <name> <version> [dep]: a plugin repo with one commit.
upstream() {
  mkdir -p "$1"
  git init -q "$1"
  printf 'module example.com/%s\n\ngo 1.22\n' "$2" >"$1/go.mod"
  printf '{"name":"%s","version":"%s","sdk":"^0.10"}\n' "$2" "$3" >"$1/plugin.json"
  printf 'package main\n\nfunc main() {}\n' >"$1/main.go"
  gi -C "$1" add -A
  gi -C "$1" commit -qm init
}
# manifest <name> <repo-dir> <commit> [jq filter]: manifests/<name>.json from good.json.
manifest() {
  mkdir -p "$tmp/manifests"
  jq --arg n "$1" --arg r "file://$2" --arg c "$3" '.name = $n | .repo = $r | .commit = $c' \
    "tests/fixtures/good.json" | jq "${4:-.}" >"$tmp/manifests/$1.json"
}

# --- basic mirror ---------------------------------------------------------
upstream "$tmp/up/alpha" alpha 1.2.3
sha=$(git -C "$tmp/up/alpha" rev-parse HEAD)
manifest alpha "$tmp/up/alpha" "$sha"
mir=$tmp/mirrors/alpha
out=$(GH_TOKEN=sekret-token-value "$m" "$tmp/manifests/alpha.json" 2>&1)
if [ $? -eq 0 ]; then ok "mirrors a plugin"; else no "mirrors a plugin: $out"; fi
case "$out" in *sekret-token-value*) no "token leaked into output" ;; *) ok "no token in output" ;; esac
[ "$(git -C "$mir" rev-parse "refs/tags/src/$sha^{commit}^")" = "$sha" ] && ok "top commit parent is the pinned commit" || no "top commit parent"
[ "$(git -C "$mir" cat-file -t "src/$sha")" = tag ] && ok "src/<commit> is an annotated tag" || no "src tag annotated"
[ "$(git -C "$mir" cat-file -t v1.2.3)" = tag ] && ok "v<version> is an annotated tag" || no "version tag annotated"
[ "$(git -C "$mir" rev-parse "src/$sha^{commit}")" = "$(git -C "$mir" rev-parse v1.2.3^{commit})" ] && ok "both tags name the mirror commit" || no "tags differ"
if git -C "$mir" show "src/$sha^{commit}:MIRROR.json" | jq -e --arg c "$sha" --arg r "file://$tmp/up/alpha" \
  '.name == "alpha" and .version == "1.2.3" and .upstream == $r and .commit == $c and .vendored == false and (.mirrored_at | length > 0)' >/dev/null; then
  ok "MIRROR.json fields, vendored false without SDK_PUBLIC"; else no "MIRROR.json fields"; fi
[ "$(git -C "$mir" diff --name-only "$sha" "src/$sha^{commit}")" = MIRROR.json ] && ok "mirror commit adds only MIRROR.json when unvendored" || no "mirror commit paths"
[ "$(git -C "$mir" rev-parse main)" = "$(git -C "$mir" rev-parse "src/$sha^{commit}")" ] && ok "main created on first mirror" || no "main created"

# --- idempotence ----------------------------------------------------------
before=$(git -C "$mir" for-each-ref --format='%(refname) %(objectname)')
if "$m" "$tmp/manifests/alpha.json" >/dev/null 2>&1; then ok "re-run on identical content exits 0"; else no "re-run exits 0"; fi
[ "$before" = "$(git -C "$mir" for-each-ref --format='%(refname) %(objectname)')" ] && ok "re-run changes no ref" || no "re-run changes refs"

# --- differing content under an existing src tag --------------------------
upstream "$tmp/up/beta" beta 2.0.0
bsha=$(git -C "$tmp/up/beta" rev-parse HEAD)
manifest beta "$tmp/up/beta" "$bsha"
git clone -q "$tmp/up/beta" "$tmp/seed"
echo x >"$tmp/seed/extra.txt"
gi -C "$tmp/seed" add -A
gi -C "$tmp/seed" commit -qm other
gi -C "$tmp/seed" tag -a -m other "src/$bsha"
git init -q --bare "$tmp/mirrors/beta"
git -C "$tmp/seed" push -q "$tmp/mirrors/beta" "refs/tags/src/$bsha"
tag_before=$(git -C "$tmp/mirrors/beta" rev-parse "src/$bsha")
if err=$("$m" "$tmp/manifests/beta.json" 2>&1); then no "differing content rejected"
elif [[ $err == *"append-only"* ]]; then ok "differing content under src/<commit> rejected"
else no "differing content: $err"; fi
[ "$tag_before" = "$(git -C "$tmp/mirrors/beta" rev-parse "src/$bsha")" ] && ok "tag not moved" || no "tag moved"
[ -z "$(git -C "$tmp/mirrors/beta" tag -l 'v*')" ] && ok "nothing else pushed after the refusal" || no "extra tags pushed"

# --- v<version> already present elsewhere is kept -------------------------
upstream "$tmp/up/gamma" gamma 3.0.0
gsha=$(git -C "$tmp/up/gamma" rev-parse HEAD)
manifest gamma "$tmp/up/gamma" "$gsha"
git init -q --bare "$tmp/mirrors/gamma"
git -C "$tmp/up/gamma" push -q "$tmp/mirrors/gamma" "HEAD:refs/heads/old"
git -C "$tmp/up/gamma" tag v3.0.0
git -C "$tmp/up/gamma" push -q "$tmp/mirrors/gamma" refs/tags/v3.0.0
if "$m" "$tmp/manifests/gamma.json" >/dev/null 2>&1 \
  && [ "$(git -C "$tmp/mirrors/gamma" rev-parse v3.0.0)" = "$gsha" ] \
  && git -C "$tmp/mirrors/gamma" rev-parse -q --verify "refs/tags/src/$gsha" >/dev/null; then
  ok "existing v<version> tag kept, src tag added"; else no "existing v<version> tag"; fi

# --- missing grant, bad license -------------------------------------------
manifest delta "$tmp/up/alpha" "$sha" 'del(.archive_grant)'
if "$m" "$tmp/manifests/delta.json" >/dev/null 2>&1; then no "missing grant refused"; else ok "missing grant refused"; fi
[ ! -e "$tmp/mirrors/delta" ] && ok "no mirror created for a refused manifest" || no "mirror created for a refused manifest"

# --- plugin.json name mismatch --------------------------------------------
manifest epsilon "$tmp/up/alpha" "$sha"
if "$m" "$tmp/manifests/epsilon.json" >/dev/null 2>&1; then no "name mismatch refused"; else ok "name mismatch refused"; fi

# --- vendoring (SDK_PUBLIC=true) ------------------------------------------
# A module proxy on disk with one dependency, so go mod vendor has work to do.
dep=$tmp/proxy/example.com/dep/@v
mkdir -p "$dep" "$tmp/depsrc/example.com/dep@v1.0.0"
printf 'module example.com/dep\n\ngo 1.22\n' >"$tmp/depsrc/example.com/dep@v1.0.0/go.mod"
printf 'package dep\n\nfunc Hi() string { return "hi" }\n' >"$tmp/depsrc/example.com/dep@v1.0.0/dep.go"
(cd "$tmp/depsrc" && python3 -c 'import zipfile;z=zipfile.ZipFile("'"$dep"'/v1.0.0.zip","w");[z.write(p) for p in ("example.com/dep@v1.0.0/go.mod","example.com/dep@v1.0.0/dep.go")]')
cp "$tmp/depsrc/example.com/dep@v1.0.0/go.mod" "$dep/v1.0.0.mod"
echo '{"Version":"v1.0.0","Time":"2024-01-01T00:00:00Z"}' >"$dep/v1.0.0.info"
echo v1.0.0 >"$dep/list"
upstream "$tmp/up/zeta" zeta 0.1.0
printf 'package main\n\nimport "example.com/dep"\n\nfunc main() { _ = dep.Hi() }\n' >"$tmp/up/zeta/main.go"
printf 'module example.com/zeta\n\ngo 1.22\n\nrequire example.com/dep v1.0.0\n' >"$tmp/up/zeta/go.mod"
(cd "$tmp/up/zeta" && go mod tidy >/dev/null 2>&1)
gi -C "$tmp/up/zeta" add -A
gi -C "$tmp/up/zeta" commit -qm dep
zsha=$(git -C "$tmp/up/zeta" rev-parse HEAD)
manifest zeta "$tmp/up/zeta" "$zsha"
if out=$(SDK_PUBLIC=true "$m" "$tmp/manifests/zeta.json" 2>&1); then
  zm=$tmp/mirrors/zeta
  top=$(git -C "$zm" rev-parse "src/$zsha^{commit}")
  git -C "$zm" show "$top:MIRROR.json" | jq -e '.vendored == true' >/dev/null && ok "vendored:true with SDK_PUBLIC=true" || no "vendored flag"
  git -C "$zm" cat-file -e "$top:vendor/modules.txt" 2>/dev/null && ok "vendor/modules.txt in the mirror commit" || no "vendor/modules.txt"
  [ -z "$(git -C "$zm" diff --name-only "$zsha" "$top" | grep -vE '^(vendor/|MIRROR\.json$)')" ] && ok "mirror commit touches only vendor/ and MIRROR.json" || no "mirror commit paths (vendored)"
else
  no "vendoring run: $out"
fi

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
