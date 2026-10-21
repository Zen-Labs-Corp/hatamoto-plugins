## Plugin

Name: 
Repo: 
Pinned commit: 

## Checklist

- [ ] The manifest is `manifests/<name>.json` and `<name>` matches `plugin.json`.
- [ ] `commit` is the full 40 character commit id I want reviewed and built.
- [ ] The plugin builds locally with `GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o build/plugin.wasm .`
- [ ] Every permission in `plugin.json` is needed; I explain each one below.
- [ ] `allowed_hosts` lists only the hosts the plugin calls (no `*` unless essential).
- [ ] The repo has a license file and the manifest `license` matches it.
- [ ] I grant the Hatamoto project a perpetual, irrevocable right to archive, build, sign and redistribute the source at the pinned commit and its builds, even if I later delete or change my repository.
- [ ] My plugin is licensed under one of: MIT, Apache-2.0, BSD-2/3-Clause, ISC, MPL-2.0, GPL-2.0/3.0, LGPL, AGPL-3.0
- [ ] No obfuscated or minified source, no build steps beyond `go build`.
- [ ] SDK version I built against: 

## Why each permission is needed

