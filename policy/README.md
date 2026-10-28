# Listing policy

Plain-text word lists behind the plugin listing rules. One entry per line;
lines starting with `#` and blank lines are ignored; matching is
case-insensitive.

| File | Entries |
|---|---|
| `reserved-names.txt` | plugin names nobody may take |
| `banned-tokens.txt` | words a hyphen-separated part of a name may not be |
| `banned-words.txt` | words a title (and, except `free` and `plugin`, a description) may not contain |
| `brands.txt` | `brand [owner ...]`: the brand may not start a name or title unless the repo owner is listed |
| `placeholders.txt` | descriptions that are unfilled templates (whole line) |

The validator reads these files from the base branch in CI, and the registry
build reads the same files from a checkout of this repository. A missing file
makes validation fail. Change policy in its own pull request, separate from
manifest changes.
