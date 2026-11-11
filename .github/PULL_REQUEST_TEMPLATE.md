Outside authors: publish at https://hatamoto.dev/developers. Pull requests adding outside packages are not accepted.

Maintainers adding or changing a first-party theme: use the theme template (`?template=theme.md`).

## Plugin

Name: 
Repo: 
Pinned commit: 

## Checklist

- [ ] The manifest is `manifests/<name>.json` and `<name>` matches `plugin.json`.
- [ ] `tier` is `first-party` and there is no `author`.
- [ ] `repo` is `https://github.com/Zen-Labs-Corp/<repo>` (or `zenlabscorp`).
- [ ] `commit` is the full 40 character commit id to be reviewed and built.
- [ ] The manifest follows the rules in CONTRIBUTING.md (Rules the validator enforces).
- [ ] I ran `scripts/validate-manifest.sh manifests/<name>.json --remote` and it passes.
- [ ] The plugin builds locally with `GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o build/plugin.wasm .`
- [ ] Every permission in `plugin.json` is needed; each one is explained below.
- [ ] `allowed_hosts` lists only the hosts the plugin calls (no `*` unless essential).
- [ ] The repo has a license file and the manifest `license` matches it.
- [ ] `archive_grant` is `true`: the project may archive, build, sign and redistribute the source at the pinned commit and its builds.
- [ ] No obfuscated or minified source, no build steps beyond `go build`.
- [ ] SDK version built against: 

## Why each permission is needed

