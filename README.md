# Hatamoto plugins

The community plugin registry for [Hatamoto](https://hatamoto.dev). Each file in
`manifests/` pins one plugin, hosted in its author's own GitHub repo, to an exact
commit. A merged manifest means the plugin is approved: the Hatamoto team builds
it from that commit, signs it with the Hatamoto key and publishes it.

Approved plugins are listed on <https://hatamoto.dev/plugins> and install with one
click from Admin > Plugins > Browse registry.

> **Status:** the Hatamoto SDK (`hatamoto.dev/sdk`) becomes fetchable when Hatamoto
> core goes public. Submissions open at that time. Until then you can read the
> guides, but plugins cannot yet be built outside the core repository.

## Guides

- [WRITING.md](WRITING.md): write a plugin in your own GitHub repo, from zero.
- [CONTRIBUTING.md](CONTRIBUTING.md): submit it for approval, update it, remove it.
- [manifests/README.md](manifests/README.md) and [manifests/schema.json](manifests/schema.json): the manifest format.

## Checks

Every pull request that touches `manifests/` runs `.github/workflows/validate.yml`.
Run the same checks locally:

```sh
bash tests/run.sh                         # validator self-test
scripts/validate-manifest.sh manifests/acme-seo.json --remote
```

## License

Apache-2.0, see [LICENSE](LICENSE). Each plugin keeps its own license, stated in
its manifest.
