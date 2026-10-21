#!/usr/bin/env bash
# Print the JSON payload of one repository ruleset of a mirror repo.
# Usage: mirror-rulesets.sh tag|branch
#
#   tag     "archive-tags": no update, no deletion of refs/tags/src/* and refs/tags/v*
#   branch  "archive-main": no deletion, no non-fast-forward of refs/heads/main
#
# Repository rulesets work on a free organization (organization rulesets do not).
# Used by mirror-plugin.sh; kept apart so the payloads can be tested offline.
set -euo pipefail
case "${1:-}" in
  tag)
    jq -n '{name: "archive-tags", target: "tag", enforcement: "active",
      conditions: {ref_name: {include: ["refs/tags/src/*", "refs/tags/v*"], exclude: []}},
      rules: [{type: "update"}, {type: "deletion"}]}' ;;
  branch)
    jq -n '{name: "archive-main", target: "branch", enforcement: "active",
      conditions: {ref_name: {include: ["refs/heads/main"], exclude: []}},
      rules: [{type: "deletion"}, {type: "non_fast_forward"}]}' ;;
  *) echo "usage: $0 tag|branch" >&2; exit 2 ;;
esac
