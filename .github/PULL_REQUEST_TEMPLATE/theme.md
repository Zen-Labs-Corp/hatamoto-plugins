## Theme

Name: 
Source (repo and pinned commit, or archive URL and sha256): 

## Checklist

- [ ] The manifest is `manifests/themes/<name>.json` and `<name>` matches the `name` in `theme.json`.
- [ ] The name is not reserved and no plugin (`manifests/<name>.json`) or other theme uses it.
- [ ] I gave exactly one source: a full 40 character lowercase `commit` with `repo`, or the `sha256` (64 lowercase hex) of exactly the zip at `archive`.
- [ ] I ran `hatamoto theme check <folder> --registry` (or `--archive ... --sha256 ... --registry`) and it passes.
- [ ] I ran `scripts/validate-theme-manifest.sh manifests/themes/<name>.json --remote` and it passes.
- [ ] `theme.json` names a screenshot under `assets/` that is a truthful picture of this theme: PNG, WebP or JPEG (never SVG), at most 2 MiB, 640 to 2560 by 360 to 1600 pixels.
- [ ] The theme loads nothing from another host (no remote CSS, fonts, images or scripts) and has no analytics, trackers or hidden calls home.
- [ ] No obfuscated or encoded blobs in templates or scripts, and no SDK or Go code.
- [ ] The repo or zip has a license file and the manifest `license` matches it.
- [ ] I grant the Hatamoto project a perpetual, irrevocable right to repack, sign and redistribute the theme at the pinned source and its builds, even if I later delete or change my repository or zip (`archive_grant` is `true`).
- [ ] My theme is licensed under one of: MIT, Apache-2.0, BSD-2/3-Clause, ISC, MPL-2.0, GPL-2.0/3.0, LGPL-2.1/3.0, AGPL-3.0
- [ ] Fonts and images I ship are licensed for redistribution.

## Notes for the reviewer

