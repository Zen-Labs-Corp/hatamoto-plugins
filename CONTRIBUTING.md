# Submit a plugin

> **Status:** the SDK (`hatamoto.dev/sdk`) is public, so you can build and test a
> plugin today. Community submissions open when Hatamoto core goes public; until
> then pull requests that add community manifests will not be merged.

Approved plugins are listed at <https://hatamoto.dev/plugins> and install with
one click from Admin > Plugins > Browse registry. To write one first, read
[WRITING.md](WRITING.md).

## How it works

1. You keep your plugin in your own public GitHub repo.
2. You open a pull request here that adds one small manifest pinning a commit.
3. CI checks the manifest. A maintainer reviews your code at that commit.
4. A merge is the approval. CI copies the source at your pinned commit into a
   repo owned by the Hatamoto project (vendored Go dependencies are added only when
   the SDK is public; the source copy is what matters): a copy is kept at `github.com/<archive>/<name>` (the archive organization is
   `Zen-Labs-Corp`). The release manager builds from that copy, signs
   the result with the Hatamoto key and publishes it.

We never accept binaries. Everything is built from the source you pinned. By
submitting you grant the project the right to keep that copy and its signed
builds and to redistribute them, even if you later delete or change your repo
(see the checklist in the pull request template).

## The manifest

Add `manifests/<name>.json`, where `<name>` is the `name` in your `plugin.json`:

```json
{
  "name": "acme-seo",
  "repo": "https://github.com/acme/hatamoto-acme-seo",
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "subdir": "",
  "title": "Acme SEO Helper",
  "author": "acme",
  "license": "MIT",
  "archive_grant": true,
  "sdk": "^0.11"
}
```

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `^[a-z][a-z0-9-]{1,39}$`; equals the file name and the `name` in `plugin.json` |
| `repo` | yes | `https://github.com/<owner>/<repo>` |
| `commit` | yes | full 40 character lowercase hex commit id |
| `subdir` | no | plugin folder inside the repo; no `..`, no leading `/` |
| `title` | no | display name for the directory card, 1 to 40 characters, no control characters, no leading or trailing space, and the rules under [Listing rules](#listing-rules); without it the card shows `name` |
| `author` | yes | your GitHub name, which must equal the owner of `repo` (compared without case), shown as "by @author" (the maintainer-only `tier` field, see [manifests/README.md](manifests/README.md), replaces it for first-party plugins and is not available to community authors) |
| `license` | yes | SPDX id from the allowlist: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `MPL-2.0`, `GPL-2.0`, `GPL-3.0`, `LGPL-2.1`, `LGPL-3.0`, `AGPL-3.0` (GPL, LGPL and AGPL also as `-only` or `-or-later`) |
| `archive_grant` | yes | must be `true`: your perpetual, irrevocable grant to archive, build, sign and redistribute the source at the pinned commit and its builds |
| `sdk` | yes | SDK range you built against; matches `plugin.json`; declare `^0.11` unless your users run Hatamoto v0.31.0 or later (older hosts refuse `^0.12`) |
| `homepage` | no | an `https://` link |

No other keys are allowed. See [manifests/schema.json](manifests/schema.json).
Check your file before you push:

```sh
scripts/validate-manifest.sh manifests/acme-seo.json --remote
```

`--remote` also fetches your repo and confirms the commit exists and that
`plugin.json` at that commit has the same name. It also checks the `description`
in that `plugin.json` against the listing rules below.

## Listing rules

CI rejects a manifest that breaks these rules. The word lists are plain text in
[policy/](policy/); read them before you choose a name.

- **Author.** `author` equals the GitHub owner of `repo`.
- **Name.** No part of the name (split at `-`) may be a banned word such as
  `beta`, `dev`, `pro` or `plugin`, and the name may not be on
  [policy/reserved-names.txt](policy/reserved-names.txt) (generic words such as
  `seo` or `forms`). It may not start with a brand from
  [policy/brands.txt](policy/brands.txt) unless you own it (`acme-stripe` is
  fine, `stripe-checkout` is not), and it may not look like another listing or a
  reserved name (one character apart, or equal once `-` is removed and `0 1 3 5`
  are read as `o l e s`).
- **Title.** At most 40 characters, at most one of `: , & / | +`, no brackets,
  emoji or symbols, one script only (Han with Kana or Hangul counts as one), no
  word from [policy/banned-words.txt](policy/banned-words.txt), no brand as the
  first word, and it shares a word with the name.
- **Description** (in `plugin.json`). 20 to 160 characters, at most two
  sentence endings, no URL or domain, no emoji, not the title or the name, not a
  placeholder from [policy/placeholders.txt](policy/placeholders.txt), at most
  three brands, and no banned word except `free` and `plugin`.

Reviewers also check what a script cannot:

- One listing per product. Ship betas as prerelease versions and a suite as one
  plugin.
- No listing that only points elsewhere ("install from npm").
- A paid external service is stated in the description.
- No near-duplicates from the same author.
- A second rejection for spam closes your future pull requests.

The CI job that judges your manifest runs only code from `main`: the validator
and `policy/` of `main`, not the copies in your pull request. Edits to the
workflow or scripts are covered by maintainer review. Change the policy in its
own pull request.

## The pull request

Fork this repo, add your manifest, and open a PR. Fill in the template: it asks
you to justify each permission. One plugin per PR.

CI runs the validator from `main` on your manifest and, once the SDK is public, builds your
plugin at the pinned commit with
`GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared`.

## Review criteria

A maintainer reads the source at the pinned commit. We look for:

- **Pinned source.** The commit exists in the public repo and is what you want
  shipped. Branches and tags are not accepted, only commit ids.
- **Reproducible build.** It builds from a clean checkout with the recipe in
  WRITING.md, no `replace` for the SDK, no local-path `replace`, no `go.work`, no
  `go generate`, no network use at build time beyond fetching Go modules. The Go
  version in `go.mod` must not exceed the pinned toolchain (currently go1.27.3);
  the build never downloads a newer one. CI checks these rules with
  `scripts/check-gomod.sh`.
- **Justified permissions.** Each entry in `permissions` is needed for a
  feature the description promises.
- **Minimal `allowed_hosts`.** Exact hosts, not `*`, unless the plugin must call
  URLs the owner configures (and then say so in the PR).
- **Readable code.** No obfuscated, minified or encoded blobs, no hidden
  behaviour, no data sent anywhere the description does not mention.
- **License and grant.** The repo has a license file, it matches the manifest and is on the allowlist, and both PR checkboxes (the archive grant and the license) are ticked.
- **Fit.** The plugin works, has tests, and does not duplicate a first-party
  plugin (for example `gtm` or `searchconsole`) without good reason. The names
  on [policy/reserved-names.txt](policy/reserved-names.txt), including `gtm`,
  `searchconsole`, `webhooks` and `hello`, cannot be used.

Reviewers may ask for changes. Push fixes to your repo and update `commit` in
the PR.

## After the merge

CI mirrors your pinned commit to
`github.com/<archive>/<name>`. The release manager builds your plugin from that
copy, signs it with the Hatamoto key, keeps every signed build, and publishes a
new registry index.

The mirror adds `vendor/` only as a last resort, and only while the maintainers
have `SDK_PUBLIC=true`. A mirror made before that is not re-vendored later: the
source copy at your commit is the archive, and the build can fetch dependencies
itself. Re-running the mirror is safe: an existing `src/<commit>` is verified and
kept, and the upstream repo is not needed for it.

Each mirror repo carries two repository rulesets, `archive-tags` (the `src/*` and
`v*` tags cannot be updated or deleted) and `archive-main` (`main` cannot be
deleted or force-pushed). The Admin token of the archive organization could still
remove a ruleset or delete a repo, so custody of that token is the real control.

Your plugin then shows up in Browse registry on every Hatamoto server and as a
card on <https://hatamoto.dev/plugins>, labelled "Community" and "by @author".
Publishing is done by a person with the signing key, so it can lag the merge by a
little.

## Updating a plugin

Open a new PR that changes `commit` (and `sdk` if it changed) in your existing
manifest. Bump `version` in `plugin.json` first, so servers can tell the new build from
the old one. The review looks at the
changes since the previous commit.

## Removing a plugin

Open a PR that deletes your manifest. After it merges the release manager
publishes an index without the plugin. The archived source and signed builds are
not deleted (that is what the grant covers). Copies already installed keep working until
each site owner removes them. If a plugin is found to be harmful, maintainers may
remove its manifest without notice and publish immediately.

## Sign your commits (DCO)

Every commit in a pull request must carry a `Signed-off-by: Your Name <you@example.com>`
trailer whose email matches the commit author, certifying the
[Developer Certificate of Origin](https://developercertificate.org/). Use
`git commit -s`; fix existing commits with `git rebase --signoff origin/main`.
CI runs `scripts/check-dco.sh` and fails the pull request without it.

## Security and conduct

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
