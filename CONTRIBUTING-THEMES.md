# Submit a theme

> **Status:** you can write and check a theme today with the `hatamoto` binary.
> Community submissions open when Hatamoto core goes public, the same moment as
> plugin submissions; until then pull requests that add theme manifests will not
> be merged.

Approved themes are listed at <https://hatamoto.dev/themes> and install with one
click from Admin > Settings > Theme > Browse registry. To write one first, read
[WRITING-THEMES.md](WRITING-THEMES.md). Submitting a plugin instead? See
[CONTRIBUTING.md](CONTRIBUTING.md).

## How it works

1. You keep your theme in your own public repo, or as a zip on a public https
   URL.
2. You open a pull request here that adds one small manifest in
   `manifests/themes/` pinning a git commit or a zip archive and its sha256.
3. CI checks the manifest. A maintainer reviews your theme at that pin.
4. A merge is the approval. After the merge the release manager fetches the pin,
   repacks it, signs the result with the Hatamoto key and publishes it. Every
   signed build is kept.

We never accept binaries or pre-signed packages. The registry builds from the
files you pinned. There is nothing to compile and no author code runs during the
build. By submitting you grant the project the right to repack, sign and
redistribute your theme and its builds (the `archive_grant` field below).

## The manifest

Add `manifests/themes/<name>.json`, where `<name>` is the `name` in your
`theme.json`. Use one of two shapes.

A git source:

```json
{
  "name": "kumo",
  "repo": "https://codeberg.org/tanaka/hatamoto-kumo",
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "subdir": "",
  "title": "Kumo",
  "author": "tanaka",
  "license": "MIT",
  "archive_grant": true,
  "homepage": "https://example.com/kumo"
}
```

An archive source:

```json
{
  "name": "kumo",
  "archive": "https://example.com/downloads/kumo-0.1.0.zip",
  "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "author": "tanaka",
  "license": "MIT",
  "archive_grant": true
}
```

Give exactly one source, never both. Fields common to both:

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name and the `name` in `theme.json`; not reserved and unique across plugins and themes (see below) |
| `title` | no | display name for the directory card, 1 to 60 characters, no control characters, no leading or trailing space; without it the card shows `name` |
| `author` | yes | your name or handle, shown as "by author"; letters, digits, space and `. _ @ -`, starting with a letter or digit, at most 61 characters |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be `true`: your perpetual, irrevocable grant to repack, sign and redistribute the theme at that pin and its builds |
| `homepage` | no | an `https://` link |

Git source:

| Field | Required | Rule |
|---|---|---|
| `repo` | yes | an `https://` URL on any public host (GitHub, Codeberg, GitLab, your own server) |
| `commit` | yes | full 40 character lowercase hex commit id |
| `subdir` | no | theme folder inside the repo; only letters, digits, `.`, `_`, `-` and `/`; no `..`, no leading `/` |

Archive source:

| Field | Required | Rule |
|---|---|---|
| `archive` | yes | an `https://` URL of a `.zip` |
| `sha256` | yes | 64 lowercase hex characters, the hash of exactly the file at `archive` |

`subdir` is not allowed with an archive. No other keys are allowed; in
particular there is no `tier` for themes: yours is listed as Community. See
[schemas/theme-manifest.schema.json](schemas/theme-manifest.schema.json).

**Hosts.** The `repo` and `archive` hosts must be public DNS names reached over
`https`. IP addresses, `localhost`, single-label names, internal suffixes
(`.local`, `.internal`, `.lan`, `.home`, `.corp`, `.test`, `.invalid`), ports and
credentials in the URL are refused.

**Names.** `default`, `webhooks`, `hello`, `gtm` and `searchconsole` are
reserved. A name is unique across plugins and themes together: if
`manifests/<name>.json` (a plugin) exists, you cannot use `<name>` for a theme,
and the other way round.

**Archives.** For an archive source:

- It must be a zip file and its sha256 must match the pin. Get the hash with
  `sha256sum theme.zip` (on macOS `shasum -a 256 theme.zip`). The CI check
  downloads at most 20 MiB, so keep the zip below that.
- `theme.json` sits at the top of the zip, or inside exactly one wrapper folder
  (what `zip -r` of a folder gives you); that one folder is stripped.
- It follows the same safety limits as any package: entry count, sizes,
  compression ratio, safe file names, no links or encrypted entries (see
  `docs/PACKAGES.md` in the Hatamoto core repository).
- Host it somewhere that keeps serving the same bytes. Put the version in the
  file name and never overwrite a published zip; a changed file no longer matches
  its sha256.

Check your file before you push, in a clone of this repo:

```sh
scripts/validate-theme-manifest.sh manifests/themes/kumo.json --remote
```

`--remote` also fetches your source, confirms that `theme.json` there has the
same name, that it names a screenshot under `assets/`, and that the screenshot
exists and is at most 2 MiB. When the `HATAMOTO_BIN` environment variable points
at a `hatamoto` binary it also runs `hatamoto theme check ... --registry
--expect-name <name>` on the fetched theme. Run `hatamoto theme check --registry`
yourself in any case, as in [WRITING-THEMES.md](WRITING-THEMES.md#5-check-it-for-the-registry).

## The pull request

Fork this repo, add your manifest, and open a PR using the theme template
(`?template=theme.md`). Fill it in: it asks about the source pin, the license,
the archive grant and the screenshot. One theme per PR.

CI runs the validator on your manifest and, when a `hatamoto` binary is
configured for it, `theme check --registry` on your theme at the pin.

## Review criteria

A maintainer reads the theme at the pinned commit or in the pinned zip. We look
for:

- **Pinned source.** The commit exists in the public repo, or the zip downloads
  and matches its sha256. Branches and tags are not accepted, only commit ids.
- **Passes the checks.** `hatamoto theme check --registry` passes, and the theme
  installs and renders on a current Hatamoto.
- **No remote assets, no trackers.** CSS, fonts, images and scripts come from
  `assets/`. No `<link>`, `<script>`, `@import` or `url()` pointing at another
  host, no analytics, no beacons, no hidden calls home.
- **Readable templates.** No obfuscated, minified-only or encoded blobs in
  templates or scripts, and no hidden behaviour. Minified third-party libraries
  are fine when the plain source and license ship with them.
- **Truthful screenshot.** It shows this theme, and what a site owner gets when
  they install it.
- **License and grant.** The repo or zip has a license file, it matches the
  manifest and is on the allowlist, `archive_grant` is `true`, and the PR
  checkboxes are ticked. Fonts and images you ship must be licensed for
  redistribution too.
- **Fit.** The theme works, and does not duplicate an existing one without a good
  reason. The reserved names cannot be used.

Reviewers may ask for changes. Push fixes to your repo and update `commit` (or
`archive` and `sha256`) in the PR.

## After the merge

The release manager fetches the pin, repacks the theme, signs it with the
Hatamoto key and publishes a new registry index. Your own signature, if the
package had one, is ignored: the published package carries the first-party
signature only. Every signed build is kept, so an index can always be rebuilt
from them. The theme then shows up in Browse registry on every Hatamoto server
and as a card with your screenshot at <https://hatamoto.dev/themes>, labelled
"Community" and "by author". Publishing is done by a person with the signing key,
so it can lag the merge by a little.

**Themes are not mirrored.** Unlike plugins, a theme source is not copied to a
repository owned by the project. The registry keeps the signed builds, not a copy
of your repository or zip. If your repo or URL disappears, versions already
published stay installable, but a new build of that pin fails until you restore
the source or submit a new pin.

## Updating a theme

Open a new PR that changes `commit` (or `archive` and `sha256`) in your existing
manifest. Bump `version` in `theme.json` first, so servers can tell the new build
from the old one. The review looks at what changed since the previous pin.

## Removing a theme

Open a PR that deletes your manifest. After it merges the release manager
publishes an index without the theme. Copies already installed keep working until
each site owner removes them, and the signed builds already made are not deleted
(that is what the grant covers). If a theme is found to be harmful, maintainers
may remove its manifest without notice and publish immediately.
