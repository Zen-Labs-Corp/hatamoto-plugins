# Manifests

One file per first-party plugin: `manifests/<name>.json`, where `<name>` equals the
`name` in the plugin's own `plugin.json`. Only first-party plugins are listed here:
a manifest without `tier: first-party`, or from another owner, is refused. Outside
authors publish at https://hatamoto.dev/developers.

Themes live in [themes/](themes/README.md), one `manifests/themes/<name>.json` each,
with their own format and checks.

```json
{
  "name": "gtm",
  "repo": "https://github.com/Zen-Labs-Corp/hatamoto-first-party",
  "commit": "077051fd84adad2277990b25e8a8fdee3c4c6a50",
  "subdir": "plugins/gtm",
  "title": "Google Tag Manager",
  "license": "Apache-2.0",
  "sdk": "^0.8",
  "archive_grant": true,
  "tier": "first-party"
}
```

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name without `.json` and the `name` in `plugin.json` |
| `repo` | yes | `https://github.com/<owner>/<repo>` with owner `Zen-Labs-Corp` or `zenlabscorp` (compared without case; the owner must match exactly) |
| `commit` | yes | full 40 character lowercase hex commit id (not a branch or tag) |
| `subdir` | no | folder of the plugin inside the repo; letters, digits, `.`, `_`, `/`, `-`; no `..`, no leading `/` |
| `author` | no | not allowed: a first-party listing has no author |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be the JSON value `true`: the owner grants the Hatamoto project a perpetual, irrevocable right to archive, build, sign and redistribute the source at the pinned commit and its builds |
| `sdk` | yes | SDK range the plugin was built against; must match `sdk` in `plugin.json` |
| `homepage` | no | an `https://` link |
| `about` | no | longer text for the plugin page. Plain text, never HTML or Markdown. `about` is 1 to 1500 characters in at most 10 paragraphs separated by a single newline (no empty paragraph, no leading or trailing space in a paragraph, no control character other than that newline). `features` is a list of 1 to 8 distinct items of 1 to 120 characters each (no control character, no leading or trailing space; duplicates are compared without case). Neither may contain `<`, `>` or a URL (`://`, `www.`), and emoji, symbols and invisible characters are refused. Both are optional. Do not put a trailing newline at the end of `about`. |
| `features` | no | short bullet list for the plugin page; same rules, see `about` |
| `tier` | yes | must be `first-party`. The `repo` owner must be `Zen-Labs-Corp` or `zenlabscorp` and `author` must be absent. A missing or different tier is refused with a pointer to https://hatamoto.dev/developers |

The names `gtm` and `searchconsole` are reserved for first-party manifests from
`Zen-Labs-Corp` or `zenlabscorp`; `webhooks` and `hello` are reserved and never accepted.

No other keys are allowed. The machine-readable rules are in
[schema.json](schema.json); `scripts/validate-manifest.sh` enforces the same ones.
