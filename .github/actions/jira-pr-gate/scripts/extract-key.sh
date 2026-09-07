#!/usr/bin/env bash
# Step 1 · Find a Jira key in the branch name or the PR title.
#
# Pure format check: no network, no credentials. Always exits 0 — deciding
# what to do about a missing key belongs to apply-gate.sh.
#
# In:  BRANCH, TITLE, PATTERN
# Out: step output `key` (empty when nothing matched)

set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_env PATTERN

KEY="$(printf '%s %s' "${BRANCH:-}" "${TITLE:-}" |
  grep -oE "$PATTERN" | head -1 || true)"

set_output key "$KEY"

if [[ -n "$KEY" ]]; then
  echo "Jira key found: $KEY"
else
  echo "No Jira key in branch '${BRANCH:-}' or title '${TITLE:-}'"
fi
