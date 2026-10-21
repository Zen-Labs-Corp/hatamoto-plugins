# Write a Hatamoto plugin in your own GitHub repo

> **Status:** the Hatamoto SDK (`hatamoto.dev/sdk`) becomes fetchable with
> `go get` when Hatamoto core goes public. Submissions to this registry open at the
> same time. The steps below are the path you will follow then.

A plugin is a WebAssembly module built with the standard Go toolchain, plus a
`plugin.json` that declares what it needs. It lives in your own repo. When it is
ready, [submit it](CONTRIBUTING.md); approved plugins appear at
<https://hatamoto.dev/plugins>.

The full plugin reference (hooks, payloads, host functions, permissions) is
`docs/PLUGIN_API.md` in the Hatamoto core repository.

## Prerequisites

- Go 1.27 or newer.
- The `hatamoto` binary, for `keys generate` and `plugin pack`.
- A public GitHub repo for your plugin.

## 1. Create the module

```sh
mkdir hatamoto-acme-seo && cd hatamoto-acme-seo
git init
go mod init github.com/acme/hatamoto-acme-seo
go get hatamoto.dev/sdk@v0.10.0
```

Your `go.mod` must resolve the SDK from the network. Do **not** add a `replace`
line for `hatamoto.dev/sdk` (to any target), no local-path `replace` and no
`go.work` file; the registry build runs in a clean checkout and refuses a plugin
that has any of them. It also builds with the Hatamoto team's pinned Go toolchain
(currently go1.27.2) and never downloads a newer one, so a plugin whose `go.mod`
requires a newer Go than that toolchain fails to build. After `go mod tidy` it
looks like this:

```
module github.com/acme/hatamoto-acme-seo

go 1.27

require hatamoto.dev/sdk v0.10.0

require github.com/extism/go-pdk v1.1.3 // indirect
```

## 2. Lay out the files

Copy the split used by the first-party `gtm` plugin. It keeps the code that only
makes sense inside WebAssembly apart from the code you can unit test on your
machine:

```
hatamoto-acme-seo/
  go.mod
  go.sum
  plugin.json         what the plugin is and needs
  plugin.go           your logic (all platforms)
  host.go             the host call seam (all platforms)
  host_wasip1.go      //go:build wasip1: wires the seam to the real host
  exports_wasip1.go   //go:build wasip1: the //go:wasmexport lines
  main_other.go       //go:build !wasip1: an empty main so tests and vet run
  plugin_test.go      host tests
  assets/             optional: plugin.js / plugin.css linked on every public page
  migrations/         optional: SQL for your own tables
  ui/                 optional: admin UI files
```

`host.go`: the seam your logic calls instead of calling the SDK directly.

```go
package main

// callHost is the host API seam: guest.Call inside the wasm module, a fake in tests.
var callHost func(fn string, args, out any) error
```

`host_wasip1.go`:

```go
//go:build wasip1

package main

import "hatamoto.dev/sdk/guest"

func init() { callHost = guest.Call }
```

`main_other.go`:

```go
//go:build !wasip1

package main

// main exists so the package vets and tests on the host; the plugin itself is
// only ever built for wasip1.
func main() {}
```

`exports_wasip1.go`: one `//go:wasmexport` line per hook you handle. The
directive only works on a function in `package main`.

```go
//go:build wasip1

package main

import (
	"hatamoto.dev/sdk"
	"hatamoto.dev/sdk/guest"
)

//go:wasmexport filter_render_head
func filterRenderHead() int32 { return guest.Run(sdk.RenderHead.Export()) }

// main is never called: a c-shared wasm module is a reactor.
func main() {}
```

`plugin.go`: register handlers in `init`. This one adds a meta tag to every
page head and reads a setting from the host.

```go
package main

import (
	"strings"

	"hatamoto.dev/sdk"
	"hatamoto.dev/sdk/guest"
)

func init() {
	guest.OnFilter(sdk.RenderHead, addTag)
}

// addTag never fails the render: a missing setting just means no tag.
func addTag(c sdk.HeadContext) (sdk.HeadContext, error) {
	var s struct {
		SiteName string `json:"site_name"`
	}
	if err := callHost("settings.get", struct{}{}, &s); err != nil {
		return c, nil
	}
	name := strings.TrimSpace(s.SiteName)
	if name == "" {
		return c, nil
	}
	c.Tags = append(c.Tags, sdk.HeadTag{
		Kind:  "meta",
		Attrs: map[string]string{"name": "acme-site", "content": name},
	})
	return c, nil
}
```

The `hello` plugin in the core repo (`examples/plugins/hello/main.go`) shows the
other hook kind: an action (`guest.OnAction(sdk.EntityPublished, ...)`) next to
a filter. If you only need one file, put the logic, the `//go:wasmexport` lines
and an empty `func main() {}` in `main.go`, as `hello` does; you then cannot unit
test on the host without building for wasip1, which is why the split is
recommended.

## 3. Write plugin.json

```json
{
  "name": "acme-seo",
  "version": "0.1.0",
  "sdk": "^0.10",
  "description": "One sentence a site owner will read on the directory page.",
  "permissions": ["settings"],
  "limits": { "memory_pages": 256, "max_instances": 4 },
  "settings_schema": {
    "type": "object",
    "properties": {
      "site_name": { "type": "string", "title": "Site name", "maxLength": 80 }
    }
  }
}
```

| Field | Meaning |
|---|---|
| `name` | `^[a-z][a-z0-9-]{1,39}$`; also the name of your manifest file here |
| `version` | your plugin's semver; bump it for every release |
| `sdk` | SDK range you built against, for example `^0.10` |
| `description` | shown on the directory page |
| `permissions` | capabilities you ask for (`settings`, `kv`, `db`, `http.fetch`, ...). Ask for the least you need; reviewers check each one |
| `allowed_hosts` | the hosts `http.fetch` may call; list them exactly |
| `routes`, `cron`, `funcs`, `cookies`, `limits`, `settings_schema` | optional, see the plugin reference |

Site owners grant permissions at install time, and a plugin only ever gets what
they grant.

## 4. Build

```sh
rm -rf build
GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o build/plugin.wasm .
cp plugin.json build/plugin.json
for d in migrations ui assets; do if [ -d "$d" ]; then cp -r "$d" "build/$d"; fi; done
```

`build/` is exactly what gets packed. This is also the recipe the registry
uses, so if it works here it works there. Add `build/` to `.gitignore`.

Only Go plugins can be listed today. A plugin written in another language can
be packed and installed on your own server, but the registry builder runs the Go
recipe above and does not build other toolchains.

## 5. Test on your machine

Because of the `!wasip1` split, `go test` runs natively and no WebAssembly
runtime is needed. `guest.Handle` runs a registered handler without the PDK and
`callHost` is replaced with a fake:

```go
package main

import (
	"encoding/json"
	"testing"

	"hatamoto.dev/sdk"
	"hatamoto.dev/sdk/guest"
)

func TestAddsTag(t *testing.T) {
	callHost = func(fn string, _, out any) error {
		if fn != "settings.get" {
			t.Fatalf("unexpected host call %q", fn)
		}
		return json.Unmarshal([]byte(`{"site_name":"Acme"}`), out)
	}
	in, _ := json.Marshal(sdk.HeadContext{Path: "/"})
	out, err := guest.Handle(sdk.RenderHead.Export(), in)
	if err != nil {
		t.Fatal(err)
	}
	var c sdk.HeadContext
	if err := json.Unmarshal(out, &c); err != nil {
		t.Fatal(err)
	}
	if len(c.Tags) != 1 || c.Tags[0].Attrs["content"] != "Acme" {
		t.Fatalf("tags = %+v", c.Tags)
	}
}
```

```sh
go vet ./... && go test ./...
```

Test the failure paths too: a plugin should fail open (return its input
unchanged) rather than break a page render.

## 6. Pack and try it on a server

Make a signing key for yourself and pack the build folder:

```sh
hatamoto keys generate --name mykey      # mykey.key (secret) + mykey.pub
hatamoto plugin pack ./build --key mykey.key --out acme-seo.hmp
```

Keep `mykey.key` out of git. This key is only for your own trials: the registry
re-builds your plugin from source and signs it with the Hatamoto key, so your
signature is never shipped.

To try the package on a development server, pick one:

- **Trust your key.** Put the base64 public key that `keys generate` prints into
  `HATAMOTO_TRUSTED_KEYS` on the server (several keys may be separated by commas
  or spaces) and restart. Then install the package:
  `hatamoto package install acme-seo.hmp --grant settings`.
- **Allow unsigned packages.** An unsigned package (pack without `--key`) installs
  only after the owner switches on "Allow unsigned packages" in Admin > Settings >
  Plugins. It is off by default and needs an acknowledgement tick; an unsigned
  package can run any code its author wrote, so use it only for your own code.
- **Dev override.** `HATAMOTO_PLUGIN_DIR=./plugins` loads
  `./plugins/<name>/plugin.json` and `plugin.wasm` as an unsigned in-memory
  package, replacing an installed one of the same name. Nothing is stored and a
  restart reloads it. It is for development only, never for deployment.

## 7. Publish your repo and submit

Push your code to GitHub, tag a release if you like, copy the 40 character commit
id you want reviewed, and follow [CONTRIBUTING.md](CONTRIBUTING.md).

The directory card heads with your plugin's `name` (for example `acme-seo`). To show
a friendlier heading such as "Acme SEO Helper", add the optional manifest field
`"title"` (1 to 60 characters, no control characters, no leading or trailing space); the `name` and version stay on the line
below it.

Every manifest also needs `"archive_grant": true` (your grant to archive, build,
sign and redistribute the source at the pinned commit) and a `license` from the
allowlist in [CONTRIBUTING.md](CONTRIBUTING.md). After the merge a copy of your
source is kept at `github.com/<archive>/<name>`.
