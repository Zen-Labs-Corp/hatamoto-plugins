# Theme manifests

One JSON file per community theme: `manifests/themes/<name>.json`. The file name
must equal the `name` field. The name must be unique across plugins and themes
(a plugin in `manifests/` with the same name is refused, and the reverse), and
not one of the reserved names `default`, `webhooks`, `hello`, `gtm`,
`searchconsole`.

Schema: `schemas/theme-manifest.schema.json`. Validate with
`scripts/validate-theme-manifest.sh manifests/themes/<name>.json [--remote]`.

Pick exactly one source.

## Git source

| Field | Rule |
|---|---|
| `repo` | `https://` URL of a public repo on any host with a public DNS name (see Host rules) |
| `commit` | full 40 character lowercase hex SHA |
| `subdir` | optional, path of the theme inside the repo |

## Archive source

| Field | Rule |
|---|---|
| `archive` | `https://` URL of a `.zip` (see Host rules) |
| `sha256` | 64 character lowercase hex digest of the exact zip bytes |

## Common fields

| Field | Rule |
|---|---|
| `name` | `^[a-z][a-z0-9-]{1,39}$`, same as `name` in `theme.json` |
| `author` | display name, `^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,60}$` |
| `license` | one of the allowlist below, same as plugins |
| `archive_grant` | must be the JSON value `true`: you allow Hatamoto to repack, sign and redistribute the theme |
| `title` | optional, 1 to 60 characters, no control characters, no leading or trailing space |
| `homepage` | optional, `https://` |
| `about` | optional. Plain text, never HTML or Markdown. `about` is 1 to 1500 characters in at most 10 paragraphs separated by a single newline (no empty paragraph, no leading or trailing space in a paragraph, no control character other than that newline). `features` is a list of 1 to 8 distinct items of 1 to 120 characters each (no control character, no leading or trailing space; duplicates are compared without case). Neither may contain `<`, `>` or a URL (`://`, `www.`), and emoji, symbols and invisible characters are refused. Both are optional. Do not put a trailing newline at the end of `about`. |
| `features` | optional, short bullet list for the theme page; same rules, see `about` |

No other fields are allowed. Themes need no `sdk` field and have no `tier`.

## License allowlist

MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, MPL-2.0, and GPL-2.0, GPL-3.0,
LGPL-2.1, LGPL-3.0, AGPL-3.0 (each also as `-only` and `-or-later`).

## Host rules

The host of `repo` and `archive` must be a lowercase public DNS name: no IP
address, `localhost`, single label host, port or credentials, and none of the
suffixes `.local .internal .localhost .lan .home .corp .test .invalid`.

## Screenshot

`theme.json` must declare `"screenshot": "assets/<file>"` (png, webp or jpeg,
at most 2 MiB). With `--remote` the validator fetches the source and checks that
the file exists under `assets/`, and that `theme.json` carries the manifest name.
If `HATAMOTO_BIN` is set it also runs `hatamoto theme check --registry`.
Git hosts must allow fetching a commit by SHA (GitHub and Codeberg do).
