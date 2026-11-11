# Maintaining the first-party plugin listing

This repository lists first-party Hatamoto plugins only. Only the Hatamoto team adds,
updates or removes a plugin listing here.

If you want to publish your own plugin, create a free developer account at
https://hatamoto.dev/developers and follow
[Part 2 of the plugin guide](https://github.com/Zen-Labs-Corp/hatamoto/blob/main/docs/PLUGINS_WRITE_AND_SUBMIT.md#part-2-publish-your-plugin).
Pull requests that add a plugin from an outside author are not accepted, and the
validator in this repository refuses such a manifest. To write a plugin first, read
[WRITING.md](WRITING.md). Themes have their own page:
[CONTRIBUTING-THEMES.md](CONTRIBUTING-THEMES.md).

## How a listing works

1. The plugin lives in a folder of `Zen-Labs-Corp/hatamoto-first-party` (or another
   public repo owned by `Zen-Labs-Corp`).
2. A maintainer adds one small manifest here that pins a commit.
3. CI checks the manifest and a maintainer reviews the code at that commit.
4. A merge is the approval. The release manager builds the plugin from the pinned
   commit, signs it with the Hatamoto key and publishes a new registry index.

Everything is built from source; binaries are never accepted. A manifest that points
at `Zen-Labs-Corp/hatamoto-first-party` is not mirrored, because that repo already
belongs to the project. A manifest that points at another repo is mirrored to
`github.com/Zen-Labs-Corp/<name>` when it merges (see the mirror setup in the
[README](README.md)).

## The manifest

Add `manifests/<name>.json`, where `<name>` is the `name` in the plugin's `plugin.json`.
This is the shape of a real entry (see `manifests/gtm.json`):

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
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name and the `name` in `plugin.json` |
| `repo` | yes | `https://github.com/<owner>/<repo>` with owner `Zen-Labs-Corp` or `zenlabscorp` |
| `commit` | yes | full 40 character lowercase hex commit id |
| `subdir` | no | plugin folder inside the repo; no `..`, no leading `/` |
| `tier` | yes | must be `first-party` |
| `title` | no | display name for the directory card, 1 to 40 characters; see the rules below; without it the card shows `name` |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be `true`: the grant to archive, build, sign and redistribute the source at the pinned commit and its builds |
| `sdk` | yes | SDK range the plugin was built against; matches `plugin.json` |
| `author` | no | not allowed: a first-party listing has no author |
| `homepage` | no | an `https://` link |
| `about` | no | longer text for the plugin page; see the rules below |
| `features` | no | list of 1 to 8 short lines for the plugin page; see the rules below |

No other keys are allowed. See [manifests/schema.json](manifests/schema.json).
Check the file before you push:

```sh
scripts/validate-manifest.sh manifests/gtm.json --remote
```

`--remote` also fetches the repo and confirms the commit exists and that `plugin.json`
at that commit has the same name and `sdk`. It also checks the `description` in that
`plugin.json` against the rules below.

## Rules the validator enforces

CI rejects a manifest that breaks these rules. The word lists are plain text in
[policy/](policy/).

- **Tier and owner.** `tier` must be present and equal to `first-party`. The repo owner
  must be `zenlabscorp` or `zen-labs-corp`, compared without case and as the exact
  owner (`Zen-Labs-Corp-evil` does not count). `author` must be absent. A manifest
  that breaks one of these is refused with a pointer to
  https://hatamoto.dev/developers.
- **Name.** No part of the name (split at `-`) may be a banned word from
  [policy/banned-tokens.txt](policy/banned-tokens.txt), such as `beta`, `dev` or `plugin`.
  `webhooks` and `hello` are never accepted; `gtm` and `searchconsole` are accepted
  here and nowhere else. The name may not look like another listing, plugin or theme
  (one character apart, or equal once `-` is removed and `0 1 3 5` are read as
  `o l e s`), and a plugin and a theme cannot share a name. First-party listings are
  exempt from the generic reserved names in
  [policy/reserved-names.txt](policy/reserved-names.txt) and from the brand rule
  for names.
- **Title.** At most 40 characters, only letters, digits, spaces and
  `. , : & / | + ' ! ? -`, at most one of `: , & / | +` or a spaced hyphen
  (` - `; `--` counts as one too), one script only (Han with Kana or Hangul counts as
  one), and no word from [policy/banned-words.txt](policy/banned-words.txt).
  Look-alike letters (for example Cyrillic `а`) are read as the Latin letter when the
  words are checked. Invisible filler characters (such as the Hangul filler) and
  modifier letters (such as `ˢ`) are refused; `々` and `ー` stay. The brand rule and
  the rule that a title shares a word with the name do not apply to first-party
  listings.
- **About and features** (optional). Plain text, never HTML or Markdown. `about` is 1 to
  1500 characters in at most 10 paragraphs separated by a single newline (no empty
  paragraph, no leading or trailing space in a paragraph, no control character other
  than that newline). `features` is a list of 1 to 8 distinct items of 1 to 120
  characters each (no control character, no leading or trailing space; duplicates are
  compared without case). Neither may contain `<`, `>` or a URL (`://`, `www.`), and
  emoji, symbols and invisible characters are refused. Do not put a trailing newline at
  the end of `about`. The same rules apply to theme manifests.
- **Description** (in `plugin.json`, checked with `--remote`). 20 to 160 characters, at
  most two sentence endings, no URL or domain, only letters, digits, spaces and ASCII
  punctuation (no combining marks, fullwidth forms, emoji or symbols), not the title or
  the name, not a placeholder from
  [policy/placeholders.txt](policy/placeholders.txt), at most three brands, and no
  banned word except `free` and `plugin`. Brands written as `str-ipe` or `g00gle` count,
  and so do look-alike letters. A domain written with non-ASCII letters, or with `。`
  after a Latin letter and a non-CJK word after it, counts as a domain. The
  `plugin.json` must be one JSON object whose keys are lowercase identifiers
  (`description`, not `Description`).
- **Pin.** `commit` is a full commit id, never a branch or a tag. `license` is on the
  allowlist and `archive_grant` is the JSON value `true`.

## Review criteria

A maintainer reads the source at the pinned commit. We look for:

- **Pinned source.** The commit exists in the public repo and is what should ship.
- **Reproducible build.** It builds from a clean checkout with the recipe in
  WRITING.md, no `replace` for the SDK, no local-path `replace`, no `go.work`, no
  `go generate`, no network use at build time beyond fetching Go modules. The Go
  version in `go.mod` must not exceed the pinned toolchain (currently go1.27.3); the
  build never downloads a newer one. CI checks these rules with
  `scripts/check-gomod.sh`.
- **Justified permissions.** Each entry in `permissions` is needed for a feature the
  description promises.
- **Minimal `allowed_hosts`.** Exact hosts, not `*`, unless the plugin must call URLs
  the site owner configures (and then say so in the PR).
- **Readable code.** No obfuscated, minified or encoded blobs, no hidden behaviour, no
  data sent anywhere the description does not mention.
- **License and grant.** The repo has a license file that matches the manifest and is
  on the allowlist, and both checkboxes of the PR template are ticked.

## How the checks run

The `judge` job runs only code from `main`: the validator and `policy/` of `main`, not
the copies in the change under review. A rule change therefore applies to the next
change after it merges, and edits to the workflow or scripts are covered by
maintainer review. Change `policy/` in its own PR. The job reports on every PR; a PR
that changes `policy/` or `manifests/themes/` makes it re-judge every plugin manifest
with the rules of `main`.

## After the merge

The release manager builds the plugin from the pinned commit, signs it with the
Hatamoto key, keeps every signed build and publishes a new registry index. The plugin
then shows up in Browse registry on every Hatamoto server and on
<https://hatamoto.dev/plugins>. Publishing is done by a person with the signing key,
so it can lag the merge by a little.

A mirror is created only for a manifest that points outside
`Zen-Labs-Corp/hatamoto-first-party`. It carries two repository rulesets,
`archive-tags` (the `src/*` and `v*` tags cannot be updated or deleted) and
`archive-main` (`main` cannot be deleted or force-pushed). Re-running the mirror is
safe: an existing `src/<commit>` is verified and kept. It adds `vendor/` only as a
last resort, and only while the maintainers have `SDK_PUBLIC=true`.

## Updating a plugin

Change `commit` (and `sdk` if it changed) in the existing manifest. Bump `version` in
`plugin.json` first, so servers can tell the new build from the old one. The review
looks at the changes since the previous commit.

## Removing a plugin

Delete the manifest. After it merges the release manager publishes an index without
the plugin. Archived source and signed builds are not deleted (that is what the grant
covers). Copies already installed keep working until each site owner removes them. If
a plugin is found to be harmful, maintainers may remove its manifest without notice
and publish immediately.

## Sign your commits (DCO)

Every commit must carry a `Signed-off-by: Your Name <you@example.com>` trailer whose
email matches the commit author, certifying the
[Developer Certificate of Origin](https://developercertificate.org/). Use
`git commit -s`; fix existing commits with `git rebase --signoff origin/main`.
CI runs `scripts/check-dco.sh` and fails the change without it.

## Security and conduct

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
