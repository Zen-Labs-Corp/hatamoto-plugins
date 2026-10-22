# Hatamoto plugins

The community plugin registry for [Hatamoto](https://hatamoto.dev). Each file in
`manifests/` pins one plugin, hosted in its author's own GitHub repo, to an exact
commit. First-party plugins (`gtm`, `searchconsole`) are listed the same way, from
repos under `github.com/zenlabscorp/`, with `tier: first-party` instead of an author. A merged manifest means the plugin is approved: the Hatamoto team builds
it from that commit, signs it with the Hatamoto key and publishes it. At merge a
copy of the pinned source is also archived in a repo the project owns, so removing
the author's repo does not remove an approved plugin. The copy is the source at
the pinned commit; vendored dependencies are a last resort added only when the SDK
is public, and an existing mirror is never re-vendored.

Approved plugins are listed on <https://hatamoto.dev/plugins> and install with one
click from Admin > Plugins > Browse registry.

## Themes

Themes are submitted the same way, as `manifests/themes/<name>.json`, and are
reviewed, repacked, signed and archived by the Hatamoto team. They are not
mirrored and need no SDK. Approved themes are listed on
<https://hatamoto.dev/themes>.

- [WRITING-THEMES.md](WRITING-THEMES.md): write a theme.
- [CONTRIBUTING-THEMES.md](CONTRIBUTING-THEMES.md): submit, update or remove one.
- [manifests/themes/README.md](manifests/themes/README.md) and [schemas/theme-manifest.schema.json](schemas/theme-manifest.schema.json): the theme manifest format.
- Open a theme pull request with the theme template:
  `https://github.com/zenlabscorp/hatamoto-plugins/compare/main...your-branch?template=theme.md`

> **Status:** the Hatamoto SDK (`hatamoto.dev/sdk`) is public at
> <https://github.com/zenlabscorp/hatamoto-sdk>, so plugins build outside the core
> repository today. Community submissions, for plugins and themes, open when Hatamoto core goes public.

## Guides

- [WRITING.md](WRITING.md): write a plugin in your own GitHub repo, from zero.
- [CONTRIBUTING.md](CONTRIBUTING.md): submit it for approval, update it, remove it.
- [manifests/README.md](manifests/README.md) and [manifests/schema.json](manifests/schema.json): the manifest format.

## Checks

Every pull request that touches `manifests/`, `scripts/`, `schemas/` or `tests/` runs `.github/workflows/validate.yml`.
Run the same checks locally:

```sh
bash tests/run.sh                         # validator self-test (includes run-themes.sh)
bash tests/run-themes.sh                  # theme validator self-test only
scripts/validate-manifest.sh manifests/acme-seo.json --remote
scripts/validate-theme-manifest.sh manifests/themes/acme-dark.json --remote
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
