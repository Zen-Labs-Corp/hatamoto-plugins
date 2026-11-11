# Maintaining the first-party theme listing

This repository lists first-party Hatamoto themes only. Only the Hatamoto team adds,
updates or removes a theme listing here.

If you want to publish your own theme, create a free developer account at
https://hatamoto.dev/developers and follow
[Part 2 of the theme guide](https://github.com/Zen-Labs-Corp/hatamoto/blob/main/docs/THEMES_WRITE_AND_SUBMIT.md#part-2-publish-your-theme).
Pull requests that add a theme from an outside author are not accepted, and the
validator in this repository refuses such a manifest. To write a theme first, read
[WRITING-THEMES.md](WRITING-THEMES.md). Plugins have their own page:
[CONTRIBUTING.md](CONTRIBUTING.md).

## How a listing works

1. The theme lives in a git repo owned by `Zen-Labs-Corp` (today
   `Zen-Labs-Corp/hatamoto-themes`, one folder per theme).
2. A maintainer adds one small manifest in `manifests/themes/` that pins a commit.
3. CI checks the manifest and a maintainer reviews the theme at that pin.
4. A merge is the approval. After the merge the release manager fetches the pin,
   repacks it, signs the result with the Hatamoto key and publishes it. Every signed
   build is kept.

Binaries and pre-signed packages are never accepted. The registry builds from the
files that were pinned. There is nothing to compile and no author code runs during
the build.

## The manifest

Add `manifests/themes/<name>.json`, where `<name>` is the `name` in the theme's
`theme.json`. This is the shape of a real entry (see `manifests/themes/hanshi.json`):

```json
{
  "name": "hanshi",
  "title": "Hanshi",
  "repo": "https://github.com/Zen-Labs-Corp/hatamoto-themes",
  "commit": "58c342cb09ccf39bd65f3f0ff3df4651619495b5",
  "subdir": "themes/hanshi",
  "author": "Zen Labs",
  "license": "Apache-2.0",
  "archive_grant": true,
  "homepage": "https://github.com/Zen-Labs-Corp/hatamoto-themes/tree/main/themes/hanshi"
}
```

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name and the `name` in `theme.json`; not reserved and unique across plugins and themes (see below) |
| `repo` | yes | `https://github.com/<owner>/<repo>` with owner `Zen-Labs-Corp` or `zenlabscorp` |
| `commit` | yes | full 40 character lowercase hex commit id |
| `subdir` | no | theme folder inside the repo; only letters, digits, `.`, `_`, `-` and `/`; no `..`, no leading `/` |
| `title` | no | display name for the directory card, 1 to 60 characters, no control characters, no leading or trailing space; without it the card shows `name` |
| `author` | yes | the name shown as "by author"; letters, digits, space and `. _ @ -`, starting with a letter or digit, at most 61 characters |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be `true`: the grant to repack, sign and redistribute the theme at that pin and its builds |
| `homepage` | no | an `https://` link |
| `about` | no | longer text for the theme page; same rules as for plugins, see [CONTRIBUTING.md](CONTRIBUTING.md#rules-the-validator-enforces) |
| `features` | no | list of 1 to 8 short lines; same rules as for plugins |

There is no `tier` field for themes: the owner of `repo` is what makes a theme
first-party, and the key is refused as unknown. No other keys are allowed. See
[schemas/theme-manifest.schema.json](schemas/theme-manifest.schema.json).

## Rules the validator enforces

- **Owner and source.** The source must be a git repo, `repo` plus `commit`, at
  `https://github.com/<owner>/<repo>` with owner `Zen-Labs-Corp` or `zenlabscorp`,
  compared without case and as the exact owner (`Zen-Labs-Corp-evil` does not count).
  Archive sources (`archive` and `sha256`) and other hosts are refused with a pointer
  to https://hatamoto.dev/developers, because an archive has no provable owner.
- **Hosts.** The URL must be a public DNS name reached over `https`. IP addresses,
  `localhost`, single-label names, internal suffixes (`.local`, `.internal`, `.lan`,
  `.home`, `.corp`, `.test`, `.invalid`), ports and credentials in the URL are
  refused.
- **Names.** `default`, `webhooks`, `hello`, `gtm` and `searchconsole` are reserved,
  and so are the names in [policy/reserved-names.txt](policy/reserved-names.txt). A
  name may not look like a plugin, another theme or a reserved name (one character
  apart, or equal after folding hyphens and `0 1 3 5` read as `o l e s`). A name is
  unique across plugins and themes together: if `manifests/<name>.json` (a plugin)
  exists, `<name>` cannot be a theme, and the other way round.
- **Pin and grant.** `commit` is a full commit id, never a branch or a tag. `license`
  is on the allowlist and `archive_grant` is the JSON value `true`.

Check the file before you push, in a clone of this repo:

```sh
scripts/validate-theme-manifest.sh manifests/themes/hanshi.json --remote
```

`--remote` also fetches the source, confirms that `theme.json` there has the same
name, that it names a screenshot under `assets/`, and that the screenshot exists and
is at most 2 MiB. When the `HATAMOTO_BIN` environment variable points at a
`hatamoto` binary it also runs `hatamoto theme check ... --registry --expect-name
<name>` on the fetched theme. Run `hatamoto theme check --registry` yourself in any
case, as in [WRITING-THEMES.md](WRITING-THEMES.md#5-check-it-for-the-registry).

## Review criteria

A maintainer reads the theme at the pinned commit. We look for:

- **Pinned source.** The commit exists in the public repo. Branches and tags are not
  accepted, only commit ids.
- **Passes the checks.** `hatamoto theme check --registry` passes, and the theme
  installs and renders on a current Hatamoto.
- **No remote assets, no trackers.** CSS, fonts, images and scripts come from
  `assets/`. No `<link>`, `<script>`, `@import` or `url()` pointing at another host, no
  analytics, no beacons, no hidden calls home.
- **Readable templates.** No obfuscated, minified-only or encoded blobs in templates
  or scripts, and no hidden behaviour. Minified third-party libraries are fine when
  the plain source and license ship with them.
- **Truthful screenshot.** It shows this theme, and what a site owner gets when they
  install it.
- **License and grant.** The repo has a license file that matches the manifest and is
  on the allowlist, `archive_grant` is `true`, and the checkboxes of the PR template
  are ticked. Fonts and images shipped with the theme must be licensed for
  redistribution too.
- **Fit.** The theme works, and does not duplicate an existing one without a good
  reason.

## After the merge

The release manager fetches the pin, repacks the theme, signs it with the Hatamoto key
and publishes a new registry index. Every signed build is kept, so an index can always
be rebuilt from them. The theme then shows up in Browse registry on every Hatamoto
server and as a card with its screenshot at <https://hatamoto.dev/themes>. Publishing
is done by a person with the signing key, so it can lag the merge by a little.

**Themes are not mirrored.** Unlike plugins, a theme source is not copied to a
repository owned by the project. The registry keeps the signed builds, not a copy of
the repository. If the repo disappears, versions already published stay installable,
but a new build of that pin fails until the source is restored or a new pin is listed.

## Updating a theme

Change `commit` in the existing manifest. Bump `version` in `theme.json` first, so
servers can tell the new build from the old one. The review looks at what changed since
the previous pin.

## Removing a theme

Delete the manifest. After it merges the release manager publishes an index without the
theme. Copies already installed keep working until each site owner removes them, and the
signed builds already made are not deleted. If a theme is found to be harmful,
maintainers may remove its manifest without notice and publish immediately.

## Sign your commits (DCO)

Every commit must carry a `Signed-off-by: Your Name <you@example.com>` trailer whose
email matches the commit author. Use `git commit -s`; see [CONTRIBUTING.md](CONTRIBUTING.md#sign-your-commits-dco).
