# Kit manifests

One JSON file per first-party kit: `manifests/kits/<name>.json`. The file name must
equal the `name` field, and the `name` in the source's `<subdir>/kit.json` (kit
format 1). The name must not be one of the reserved names `default`, `webhooks`,
`hello`, `gtm`, `searchconsole`, or the names in `policy/reserved-names.txt`.

A kit may share its name with a plugin or a theme: the registry key is the kind
plus the name. Look-alike names are checked against sibling kits and the reserved
names only, not against plugins or themes.

Only first-party kits are listed here: the source must be a git repo owned by
`Zen-Labs-Corp` or `zenlabscorp`. A kit from any other owner, host or an archive
source is refused with a pointer to https://hatamoto.dev/developers.

Schema: `schemas/kit-manifest.schema.json`. Validate with
`scripts/validate-kit-manifest.sh manifests/kits/<name>.json [--remote]`.

## Fields

| Field | Rule |
|---|---|
| `name` | required, `^[a-z][a-z0-9-]{1,39}$`, same as `name` in `kit.json` |
| `title` | optional, 1 to 60 characters, no control characters, no leading or trailing space |
| `about` | optional. Plain text, never HTML or Markdown. 1 to 1500 characters in at most 10 paragraphs separated by a single newline (no empty paragraph, no leading or trailing space in a paragraph, no control character other than that newline). Do not put a trailing newline at the end. |
| `features` | optional, 1 to 8 distinct short lines of 1 to 120 characters each (duplicates are compared without case). Human text for the kit page, not package names. |
| `repo` | required, `https://github.com/<owner>/<repo>` with owner `Zen-Labs-Corp` or `zenlabscorp` (compared without case; the owner must match exactly) |
| `commit` | required, full 40 character lowercase hex SHA |
| `subdir` | optional, path of the kit inside the repo (default: the repo root) |
| `author` | required, display name, `^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,60}$` |
| `license` | required, one of the allowlist below, same as plugins and themes |
| `archive_grant` | required, must be the JSON value `true`: you allow Hatamoto to repack, sign and redistribute the kit |
| `homepage` | optional, `https://` |

`about` and `features` follow the same rules as for plugins and themes: neither may
contain `<`, `>` or a URL (`://`, `www.`), and emoji, symbols and invisible
characters are refused.

No other fields are allowed. A kit has no `tier`, `sdk` or `screenshot`, and no
archive source: `archive` and `sha256` are refused because a zip has no provable
owner.

## License allowlist

MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, MPL-2.0, and GPL-2.0, GPL-3.0,
LGPL-2.1, LGPL-3.0, AGPL-3.0 (each also as `-only` and `-or-later`).

## Host rules

The host of `repo` must be a lowercase public DNS name: no IP address,
`localhost`, single label host, port or credentials, and none of the suffixes
`.local .internal .localhost .lan .home .corp .test .invalid`. In practice the
owner rule narrows it to `github.com`.

## Release and listing

Release a kit by tagging its source repo `kit-<name>/v<version>`, then list the
tagged commit here. Kits are never mirrored. The Hatamoto registry build
(`registry/build-community-kits.sh` in the core repository) fetches the pinned
commit, builds and signs `<name>.kit.hmp`.

## Checks

- `scripts/validate-kit-manifest.sh manifests/kits/<name>.json --remote` fetches the
  pinned commit and checks that `<subdir>/kit.json` carries the manifest name and kit
  format 1. If `HATAMOTO_BIN` is set it also runs `hatamoto kit check`.
- CI judges a changed kit manifest with the kit validator of `main`, never the one in
  the pull request.
- `bash tests/run-kits.sh` runs the validator tests offline.

## Validator and registry build

The owner rule, the look-alike check and the name `default` are enforced by this
validator only. The registry build enforces the remaining rules and gives the same
verdicts (`tests/kits-core-parity.sh` compares them when a core checkout and a built
CLI are at hand).
