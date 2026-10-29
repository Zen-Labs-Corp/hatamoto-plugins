# Manifests

One file per plugin: `manifests/<name>.json`, where `<name>` equals the `name` in
the plugin's own `plugin.json`. Submissions are not open yet
(see the status note in the top-level README).

Themes live in [themes/](themes/README.md), one `manifests/themes/<name>.json` each,
with their own format and checks.

```json
{
  "name": "acme-seo",
  "repo": "https://github.com/acme/hatamoto-acme-seo",
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "subdir": "",
  "author": "acme",
  "license": "MIT",
  "archive_grant": true,
  "sdk": "^0.11"
}
```

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name without `.json` and the `name` in `plugin.json` |
| `repo` | yes | `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$` |
| `commit` | yes | full 40 character lowercase hex commit id (not a branch or tag) |
| `subdir` | no | folder of the plugin inside the repo; letters, digits, `.`, `_`, `/`, `-`; no `..`, no leading `/` |
| `author` | yes, unless `tier` is `first-party` | your GitHub name, shown as "by @author"; `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`; must be absent when `tier` is set |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be the JSON value `true`: the author grants the Hatamoto project a perpetual, irrevocable right to archive, build, sign and redistribute the source at the pinned commit and its builds |
| `sdk` | yes | SDK range you built against; must match `sdk` in `plugin.json`; declare `^0.11` unless your users run Hatamoto v0.31.0 or later (older hosts refuse `^0.12`) |
| `homepage` | no | an `https://` link |
| `about` | no | longer text for the plugin page. Plain text, never HTML or Markdown. `about` is 1 to 1500 characters in at most 10 paragraphs separated by a single newline (no empty paragraph, no leading or trailing space in a paragraph, no control character other than that newline). `features` is a list of 1 to 8 distinct items of 1 to 120 characters each (no control character, no leading or trailing space; duplicates are compared without case). Neither may contain `<`, `>` or a URL (`://`, `www.`), and emoji, symbols and invisible characters are refused. Both are optional. Do not put a trailing newline at the end of `about`. |
| `features` | no | short bullet list for the plugin page; same rules, see `about` |
| `tier` | no, maintainers only | the only allowed value is `first-party`; accepted only when `repo` is under `https://github.com/Zen-Labs-Corp/` (or the project's former GitHub owner, kept until nothing pins it; owner match is exact, case-insensitive) and `author` is absent. Community authors leave it out |

The names `gtm` and `searchconsole` are accepted only as `first-party` manifests
from `Zen-Labs-Corp` or `zenlabscorp`; `webhooks` and `hello` are reserved and never accepted.

No other keys are allowed. The machine-readable rules are in
[schema.json](schema.json); `scripts/validate-manifest.sh` enforces the same ones.
