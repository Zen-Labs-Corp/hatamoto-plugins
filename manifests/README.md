# Manifests

One file per plugin: `manifests/<name>.json`, where `<name>` equals the `name` in
the plugin's own `plugin.json`. This directory stays empty until submissions open
(see the status note in the top-level README).

```json
{
  "name": "acme-seo",
  "repo": "https://github.com/acme/hatamoto-acme-seo",
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "subdir": "",
  "author": "acme",
  "license": "MIT",
  "sdk": "^0.10"
}
```

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name without `.json` and the `name` in `plugin.json` |
| `repo` | yes | `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$` |
| `commit` | yes | full 40 character lowercase hex commit id (not a branch or tag) |
| `subdir` | no | folder of the plugin inside the repo; letters, digits, `.`, `_`, `/`, `-`; no `..`, no leading `/` |
| `author` | yes | your GitHub name, shown as "by @author"; `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$` |
| `license` | yes | SPDX id of the plugin's license, for example `MIT` or `Apache-2.0` |
| `sdk` | yes | SDK range you built against; must match `sdk` in `plugin.json` |
| `homepage` | no | an `https://` link |

No other keys are allowed. The machine-readable rules are in
[schema.json](schema.json); `scripts/validate-manifest.sh` enforces the same ones.
