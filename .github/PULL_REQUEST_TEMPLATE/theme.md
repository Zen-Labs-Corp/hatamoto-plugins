Outside authors: publish at https://hatamoto.dev/developers. Pull requests adding outside packages are not accepted.

## Theme

Name: 
Source (repo and pinned commit): 

## Checklist

- [ ] The manifest is `manifests/themes/<name>.json` and `<name>` matches the `name` in `theme.json`.
- [ ] The name is not reserved and no plugin (`manifests/<name>.json`) or other theme uses it.
- [ ] The source is a git repo, `repo` plus a full 40 character lowercase `commit`, owned by `Zen-Labs-Corp` (or `zenlabscorp`) on github.com. No archive source, no `tier` field.
- [ ] I ran `hatamoto theme check <folder> --registry` and it passes.
- [ ] I ran `scripts/validate-theme-manifest.sh manifests/themes/<name>.json --remote` and it passes.
- [ ] `theme.json` names a screenshot under `assets/` that is a truthful picture of this theme: PNG, WebP or JPEG (never SVG), at most 2 MiB, 640 to 2560 by 360 to 1600 pixels.
- [ ] The theme loads nothing from another host (no remote CSS, fonts, images or scripts) and has no analytics, trackers or hidden calls home.
- [ ] No obfuscated or encoded blobs in templates or scripts, and no SDK or Go code.
- [ ] The repo has a license file and the manifest `license` matches it.
- [ ] `archive_grant` is `true`: the project may repack, sign and redistribute the theme at the pinned source and its builds.
- [ ] Fonts and images shipped with the theme are licensed for redistribution.

## Notes for the reviewer

