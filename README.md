# Hatamoto plugins

The list of first-party Hatamoto plugins and themes, built and signed by the Hatamoto team.

Want to publish your own plugin or theme? Create a free developer account at
https://hatamoto.dev/developers and submit there. Pull requests adding outside
packages to this repository are no longer accepted.

## What is listed

Each file in `manifests/` pins one first-party plugin to an exact commit, with
`tier: first-party`. First-party plugins live in folders of
[`Zen-Labs-Corp/hatamoto-first-party`](https://github.com/Zen-Labs-Corp/hatamoto-first-party)
(`subdir`). Each file in `manifests/themes/` pins one first-party theme, from a git
repo owned by `Zen-Labs-Corp`. The validators here refuse anything else.

The Hatamoto team builds each listed package from its pinned commit, signs it with
the Hatamoto key and publishes it. Listed plugins and themes appear on
<https://hatamoto.dev/plugins> and <https://hatamoto.dev/themes> and install with one
click from the Hatamoto admin.

## Guides

- [WRITING.md](WRITING.md) and [WRITING-THEMES.md](WRITING-THEMES.md): write a plugin or a theme.
- [CONTRIBUTING.md](CONTRIBUTING.md) and [CONTRIBUTING-THEMES.md](CONTRIBUTING-THEMES.md): how maintainers add, update and remove a first-party listing.
- [manifests/README.md](manifests/README.md) and [manifests/schema.json](manifests/schema.json): the plugin manifest format.
- [manifests/themes/README.md](manifests/themes/README.md) and [schemas/theme-manifest.schema.json](schemas/theme-manifest.schema.json): the theme manifest format.

## Checks

Every pull request runs `.github/workflows/validate.yml`, so its required `judge` check always reports.
`judge` validates the plugin manifests a pull request changes, using the validator and `policy/` of the
base branch. When a pull request changes `policy/` or `manifests/themes/`, it re-judges every plugin
manifest with the base rules. The Hatamoto registry build for plugins (`registry/build-community.sh`
in the Hatamoto core repository) reads `policy/` from a checkout of this repository; a missing,
unreadable or empty list stops the build, so a bad policy change breaks publishing, not just PR
checks. The theme build still uses its own reserved list and will read `reserved-names.txt` in a
follow-up. The registry build is looser than the validators here: it still accepts a plugin
manifest without a tier and does not check the owner of a theme.
Run the same checks locally:

```sh
bash tests/run.sh                         # validator self-test (includes run-themes.sh)
bash tests/run-themes.sh                  # theme validator self-test only
scripts/validate-manifest.sh manifests/gtm.json --remote
scripts/validate-theme-manifest.sh manifests/themes/hanshi.json --remote
```

## Maintainer setup for the mirror

`.github/workflows/mirror.yml` needs this once:

- **Token.** A fine-grained personal access token, resource owner
  `Zen-Labs-Corp`, Repository access: All repositories, permissions
  Administration (read and write) and Contents (read and write). If the
  organization requires approval for fine-grained tokens, approve it in the
  organization settings. Give it an expiry and rotate it before it lapses.
- **Environment.** Create the environment `plugin-mirror` in this repository with
  deployment branches limited to `main`, optionally with required reviewers, and
  store the token there as the environment secret `MIRROR_TOKEN` (not as a
  repository secret). Set the variables `MIRROR_ORG` and, when the SDK is public,
  `SDK_PUBLIC=true`.
- **Rulesets.** Nothing to set up: `mirror-plugin.sh` adds two repository rulesets
  (these work on a free organization) to every mirror repo, new or existing:
  `archive-tags` (refs `src/*` and `v*`: block update and deletion) and
  `archive-main` (`main`: block deletion and non-fast-forward updates). The Admin
  token can still remove a ruleset or delete a repo, so who holds the token is the
  real control.

## License

Apache-2.0, see [LICENSE](LICENSE). Each plugin keeps its own license, stated in
its manifest.
