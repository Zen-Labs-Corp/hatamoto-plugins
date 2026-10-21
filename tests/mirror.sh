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

# Without go nothing can be tested: fail, so CI cannot go green without running
# these. MIRROR_TESTS_ALLOW_SKIP=1 turns that into a skip (exit 77).
if ! command -v go >/dev/null; then
  if [ "${MIRROR_TESTS_ALLOW_SKIP:-}" = 1 ]; then echo "skip mirror tests: go not found"; exit 77; fi
  echo "FAIL mirror tests need go (set MIRROR_TESTS_ALLOW_SKIP=1 to skip)"; exit 1
fi

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
elif [[ $err == *"touches extra.txt"* ]]; then ok "differing content under src/<commit> rejected"
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

# --- re-run after the upstream is deleted, and completing missing refs ----
upstream "$tmp/up/kappa" kappa 1.0.0
ksha=$(git -C "$tmp/up/kappa" rev-parse HEAD)
manifest kappa "$tmp/up/kappa" "$ksha"
"$m" "$tmp/manifests/kappa.json" >/dev/null 2>&1
km=$tmp/mirrors/kappa
rm -rf "$tmp/up/kappa"
kbefore=$(git -C "$km" for-each-ref --format='%(refname) %(objectname)')
if "$m" "$tmp/manifests/kappa.json" >/dev/null 2>&1; then ok "re-run succeeds from the mirror after the upstream is deleted"; else no "re-run after upstream deleted"; fi
[ "$kbefore" = "$(git -C "$km" for-each-ref --format='%(refname) %(objectname)')" ] && ok "no ref changed on that re-run" || no "refs changed after upstream deleted"
ktop=$(git -C "$km" rev-parse "src/$ksha^{commit}")
git -C "$km" tag -d v1.0.0 >/dev/null
git -C "$km" update-ref -d refs/heads/main
srctag=$(git -C "$km" rev-parse "src/$ksha")
if "$m" "$tmp/manifests/kappa.json" >/dev/null 2>&1 \
  && [ "$(git -C "$km" rev-parse v1.0.0^{commit})" = "$ktop" ] && [ "$(git -C "$km" rev-parse main)" = "$ktop" ]; then
  ok "missing v<version> and main are restored from the mirror"; else no "missing refs restored"; fi
[ "$srctag" = "$(git -C "$km" rev-parse "src/$ksha")" ] && ok "src tag untouched while completing refs" || no "src tag moved"

# --- an existing main is never moved --------------------------------------
upstream "$tmp/up/lambda" lambda 1.0.0
lsha=$(git -C "$tmp/up/lambda" rev-parse HEAD)
manifest lambda "$tmp/up/lambda" "$lsha"
git init -q --bare "$tmp/mirrors/lambda"
git clone -q "$tmp/up/lambda" "$tmp/lseed"
echo x >"$tmp/lseed/other.txt"; gi -C "$tmp/lseed" add -A; gi -C "$tmp/lseed" commit -qm unrelated
git -C "$tmp/lseed" push -q "$tmp/mirrors/lambda" HEAD:refs/heads/main
lmain=$(git -C "$tmp/mirrors/lambda" rev-parse main)
if "$m" "$tmp/manifests/lambda.json" >/dev/null 2>&1 && [ "$(git -C "$tmp/mirrors/lambda" rev-parse main)" = "$lmain" ] \
  && git -C "$tmp/mirrors/lambda" rev-parse -q --verify "refs/tags/src/$lsha" >/dev/null; then
  ok "existing main kept, src tag added"; else no "existing main must not move"; fi

# --- tampered existing src/<commit>: wrong parent -------------------------
upstream "$tmp/up/mu" mu 1.0.0
musha=$(git -C "$tmp/up/mu" rev-parse HEAD)
manifest mu "$tmp/up/mu" "$musha"
git init -q "$tmp/museed"
echo '{"name":"mu"}' >"$tmp/museed/MIRROR.json"; gi -C "$tmp/museed" add -A; gi -C "$tmp/museed" commit -qm orphan
gi -C "$tmp/museed" tag -a -m t "src/$musha"
git init -q --bare "$tmp/mirrors/mu"
git -C "$tmp/museed" push -q "$tmp/mirrors/mu" "refs/tags/src/$musha"
if err=$("$m" "$tmp/manifests/mu.json" 2>&1); then no "wrong-parent src tag rejected"
elif [[ $err == *"not a single commit on top of"* ]]; then ok "wrong-parent src tag rejected"
else no "wrong-parent: $err"; fi

# --- go mod vendor misbehaviour, token scope (fake go in front of PATH) ---
realgo=$(command -v go)
mkdir -p "$tmp/fakebin"
cat >"$tmp/fakebin/go" <<FAKE
#!/usr/bin/env bash
env >"$tmp/go-env.txt"
[ -z "\${FAKE_GO_TOUCH:-}" ] || echo '// tampered' >>"\$FAKE_GO_TOUCH"
exec "$realgo" "\$@"
FAKE
chmod +x "$tmp/fakebin/go"
upstream "$tmp/up/nu" nu 1.0.0
nsha=$(git -C "$tmp/up/nu" rev-parse HEAD)
manifest nu "$tmp/up/nu" "$nsha"
if err=$(PATH=$tmp/fakebin:$PATH SDK_PUBLIC=true FAKE_GO_TOUCH=main.go "$m" "$tmp/manifests/nu.json" 2>&1); then no "go mod vendor outside vendor/ rejected"
elif [[ $err == *"changed files outside"* ]]; then ok "go mod vendor outside vendor/ rejected"
else no "vendor outside: $err"; fi
git -C "$tmp/mirrors/nu" rev-parse -q --verify "refs/tags/src/$nsha" >/dev/null 2>&1 && no "nothing pushed after the vendor failure" || ok "nothing pushed after the vendor failure"
PATH=$tmp/fakebin:$PATH SDK_PUBLIC=true GH_TOKEN=sekret-token-value "$m" "$tmp/manifests/nu.json" >/dev/null 2>&1
if [ -s "$tmp/go-env.txt" ] && ! grep -q 'GH_TOKEN\|sekret-token-value' "$tmp/go-env.txt"; then ok "GH_TOKEN absent from the go mod vendor environment"; else no "GH_TOKEN reached go mod vendor"; fi

# --- plugin in a subdirectory, vendored under the subdir ------------------
mkdir -p "$tmp/up/sigma/plugins/sigma"
git init -q "$tmp/up/sigma"
printf '{"name":"sigma","version":"0.2.0","sdk":"^0.10"}\n' >"$tmp/up/sigma/plugins/sigma/plugin.json"
printf 'package main\n\nimport "example.com/dep"\n\nfunc main() { _ = dep.Hi() }\n' >"$tmp/up/sigma/plugins/sigma/main.go"
printf 'module example.com/sigma\n\ngo 1.22\n\nrequire example.com/dep v1.0.0\n' >"$tmp/up/sigma/plugins/sigma/go.mod"
(cd "$tmp/up/sigma/plugins/sigma" && go mod tidy >/dev/null 2>&1)
gi -C "$tmp/up/sigma" add -A; gi -C "$tmp/up/sigma" commit -qm init
ssha=$(git -C "$tmp/up/sigma" rev-parse HEAD)
manifest sigma "$tmp/up/sigma" "$ssha" '.subdir = "plugins/sigma"'
if out=$(SDK_PUBLIC=true "$m" "$tmp/manifests/sigma.json" 2>&1); then
  sm=$tmp/mirrors/sigma
  stop=$(git -C "$sm" rev-parse "src/$ssha^{commit}")
  git -C "$sm" cat-file -e "$stop:plugins/sigma/vendor/modules.txt" 2>/dev/null && ok "subdir plugin vendored under the subdir" || no "subdir vendor path"
  [ -z "$(git -C "$sm" diff --name-only "$ssha" "$stop" | grep -vE '^(plugins/sigma/vendor/|MIRROR\.json$)')" ] && ok "subdir mirror commit touches only <subdir>/vendor/ and MIRROR.json" || no "subdir mirror commit paths"
  git -C "$sm" show "$stop:MIRROR.json" | jq -e '.subdir == "plugins/sigma"' >/dev/null && ok "MIRROR.json records the subdir" || no "MIRROR.json subdir"
else no "subdir run: $out"; fi

# --- a symlink in the subdir chain is refused -----------------------------
mkdir -p "$tmp/up/tau/real"
git init -q "$tmp/up/tau"
printf '{"name":"tau","version":"1.0.0","sdk":"^0.10"}\n' >"$tmp/up/tau/real/plugin.json"
printf 'module example.com/tau\n\ngo 1.22\n' >"$tmp/up/tau/real/go.mod"
ln -s real "$tmp/up/tau/link"
gi -C "$tmp/up/tau" add -A; gi -C "$tmp/up/tau" commit -qm init
tsha=$(git -C "$tmp/up/tau" rev-parse HEAD)
manifest tau "$tmp/up/tau" "$tsha" '.subdir = "link"'
if err=$("$m" "$tmp/manifests/tau.json" 2>&1); then no "symlinked subdir refused"
elif [[ $err == *"symlink"* ]]; then ok "symlinked subdir refused"; else no "symlinked subdir: $err"; fi

# Fail when cases silently disappear.
want=34
if [ $((pass + failed)) -ne "$want" ]; then no "expected $want cases, ran $((pass + failed))"; fi

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
