# Write a Hatamoto theme in your own repo

> **Status:** everything on this page works today with the `hatamoto` binary.
> Community submissions to this registry open when Hatamoto core goes public, the
> same moment as plugin submissions. When your theme is ready,
> [submit it](CONTRIBUTING-THEMES.md); approved themes appear at
> <https://hatamoto.dev/themes> and install with one click from Admin > Settings >
> Theme > Browse registry.

A theme is data: Go `html/template` files, CSS, JavaScript and JSON schemas,
plus a `theme.json`. There is no SDK, no Go code and no build step. It lives in
your own repo. Writing a plugin instead? See [WRITING.md](WRITING.md).

The full theme reference (layouts, template funcs, sections, markers) is
`docs/THEMES.md` in the Hatamoto core repository; packaging and trust are in
`docs/PACKAGES.md` there.

## Prerequisites

- The `hatamoto` binary, for `theme check` and `theme pack` (and `theme dev`,
  which also needs a running development server, see below).
- A public git repo for your theme, or a place to host a zip over https.

## 1. Lay out the files

A theme may be partial: every file it lacks comes from the built-in default
theme. This is the smallest tree the engine accepts on its own, with the
partials the engine requires:

```
hatamoto-kumo/
  theme.json
  layouts/
    base.html
    page.html
    404.html
    error.html
  partials/
    head.html header.html nav.html footer.html section.html scripts.html
  assets/
    screenshot.webp     the registry preview, see below
    css/base.css
```

The rules for each file, the layout kinds you can add (`home.html`,
`single.html`, `archive.html`, ...), section templates in `sections/` and their
schemas in `schemas/` are in the directory layout chapter of `docs/THEMES.md`.
Read that chapter before you start; this guide does not repeat it. The quickest
start is to copy the files of the default theme that ships with Hatamoto and
change them.

A theme submitted to the registry must be self-contained. Ship your CSS, fonts,
images and scripts inside `assets/`; do not load anything from another host (see
[Review criteria](CONTRIBUTING-THEMES.md#review-criteria)).

Hidden files and folders (a leading dot) and links are refused in a package, so
keep `.git` out of the folder you pack, and keep to the top-level folders the
package format allows (`docs/PACKAGES.md`).

## 2. Write theme.json

```json
{
  "name": "kumo",
  "version": "0.1.0",
  "description": "One sentence a site owner will read in the theme directory.",
  "screenshot": "assets/screenshot.webp"
}
```

| Field | Meaning |
|---|---|
| `name` | `^[a-z][a-z0-9-]{1,39}$`; also the name of your manifest file when you submit. `default` is reserved |
| `version` | your theme's semver; bump it for every release |
| `description` | shown on the directory card |
| `screenshot` | **required for the registry**: path to a preview image under `assets/` |
| `settings_schema` | optional, a JSON Schema that becomes a settings form, see `docs/THEMES.md` |

## 3. Make the screenshot

The directory card shows your screenshot, so it has to be a real picture of
your theme. Only `hatamoto theme check --registry` (and the registry build)
checks the screenshot. The rules:

- A file under `assets/`, named in `theme.json` as `screenshot`.
- PNG, WebP or JPEG (`.png`, `.webp`, `.jpg`, `.jpeg`), and the contents must
  match the extension. **Never SVG.**
- At most 2 MiB.
- Between 640 and 2560 pixels wide and between 360 and 1600 pixels high, and at
  most 4,200,000 pixels in total.

Take it from the real theme running on sample content, not a mock-up. A
screenshot that does not show what a site owner will get is a reason to refuse
the submission.

## 4. Try it on a development server

`hatamoto theme dev` pushes your folder to a running development server as an
unsigned dev package, activates it, and pushes again every time a file changes:

```sh
hatamoto theme dev ./hatamoto-kumo --dev
```

It needs the same `DATABASE_URL` as the server (so a local Hatamoto and its
PostgreSQL must be set up) and refuses anything that looks like production:
`--dev` (or `ENVIRONMENT=development`) is required and `ENVIRONMENT=production`
refuses. Add `--no-activate` to install without switching the live theme. If a
push fails (a layout that does not parse, a partial called with the wrong
argument) the command prints `NOT PUSHED` with the reason and keeps watching.
Dev packages are for development only, never for deployment.

## 5. Check it for the registry

```sh
hatamoto theme check ./hatamoto-kumo --registry
```

This needs no key and no database, and writes nothing. It parses the folder as a
theme package (name, semver version, the package safety rules in
`docs/PACKAGES.md` and the screenshot rules above) and, with `--registry`, also
requires a valid screenshot and refuses the name `default`. On success it prints
`ok: theme kumo v0.1.0`. This is the same check the registry runs, so if it
passes here it passes there.

`theme check` does not render your templates; step 4 does. Run both.

If you will submit a zip instead of a git repo, check the zip too:

```sh
hatamoto theme check --archive theme.zip --sha256 "$(sha256sum theme.zip | cut -d' ' -f1)" --registry
```

Add `--expect-name kumo` to either form to fail when `theme.json` names a
different theme.

## 6. Pack and try it as a package

```sh
hatamoto keys generate --name mykey      # mykey.key (secret) + mykey.pub
hatamoto theme pack ./hatamoto-kumo --key mykey.key --out kumo.hmp
```

Keep `mykey.key` out of git. This key is only for your own trials: the registry
repacks your theme and signs it with the Hatamoto key, so your signature is never
shipped. To install the package on a development server, trust your key with
`HATAMOTO_TRUSTED_KEYS` or allow unsigned packages, as described in
`docs/THEMES.md` and `docs/PACKAGES.md`.

## 7. Publish your repo and submit

Push your theme to a public git host, copy the 40 character commit id you want
reviewed (or build the zip and its sha256), and follow
[CONTRIBUTING-THEMES.md](CONTRIBUTING-THEMES.md).
