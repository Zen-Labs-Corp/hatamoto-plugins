# Listing policy

Plain-text word lists behind the plugin listing rules. One entry per line;
blank lines and comment lines are ignored, so `#1` is an entry; matching is
case-insensitive. A comment is a `#` alone or `# ` (hash and space) followed by
text, on a line of its own. There are no inline comments: in `stripe # payments`
both `#` and `payments` would be read as brand owners. Every list except
`placeholders.txt` must keep at least one entry.

| File | Entries |
|---|---|
| `reserved-names.txt` | plugin names nobody may take |
| `banned-tokens.txt` | words a hyphen-separated part of a name may not be |
| `banned-words.txt` | words a title (and, except `free` and `plugin`, a description) may not contain |
| `brands.txt` | `brand [owner ...]`: the brand may not start a name or title unless the repo owner is listed |
| `placeholders.txt` | descriptions that are unfilled templates (whole line) |

The validator reads these files from the base branch in CI. The Hatamoto registry
build (`registry/build-community.sh` and `build-community-themes.sh` in the Hatamoto
core repository) reads the same files from a checkout of this repository. A missing,
unreadable or empty list makes validation fail and stops that build, so a bad policy
change breaks publishing, not just PR checks. The theme validator reads
`reserved-names.txt` too, and its look-alike check (one character apart, or the same
after folding hyphens and digit swaps) applies to theme names against plugin names,
other themes and reserved names. The matching rules in the core build land in the
Hatamoto repository as a follow-up; until then these validators are the stricter side. The look-alike check
of a name against `reserved-names.txt` (one character apart) can reject ordinary
words, for example `auto` (close to `auth`) or `logic` (close to `login`). Change policy in its own pull request, separate from
manifest changes.
