# Theme manifests

One JSON file per community theme: `manifests/themes/<name>.json`. The file name
must equal the `name` field, and the name must not collide with a plugin in
`manifests/` or with the built-in `default` theme.

Schema: `schemas/theme-manifest.schema.json`. Validate with
`scripts/validate-theme-manifest.sh manifests/themes/<name>.json [--remote]`.

Pick exactly one source.

## Git source

| Field | Rule |
|---|---|
| `repo` | `https://` URL of a public repo, no credentials |
| `commit` | full 40 character lowercase hex SHA |
| `subdir` | optional, path of the theme inside the repo |

## Archive source

| Field | Rule |
|---|---|
| `archive` | `https://` URL of a `.zip`, no credentials |
| `sha256` | 64 character lowercase hex digest of the exact zip bytes |

## Common fields

| Field | Rule |
|---|---|
| `name` | `^[a-z][a-z0-9-]{1,39}$`, same as `name` in `theme.json` |
| `author` | display name, `^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,60}$` |
| `license` | SPDX id or short license name |
| `homepage` | optional, `https://` |

No other fields are allowed. Themes need no `sdk` field.
