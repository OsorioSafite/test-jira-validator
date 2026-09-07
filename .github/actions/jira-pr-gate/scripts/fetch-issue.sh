#!/usr/bin/env bash
# Step 3 · Fetch the issue from Jira.
#
# NEVER fails. Jira being down, a rotated token or a missing permission must
# not block a merge, so every problem becomes a step output plus a message.
#
# Set FIXTURE to a local JSON file to skip the API entirely — that is how the
# label logic is tested without credentials.
#
# In:  KEY, JIRA_BASE_URL, JIRA_USER_EMAIL, JIRA_API_TOKEN, ISSUE_FILE, FIXTURE
# Out: step output `status` = ok | unauthorized | forbidden | not-found |
#                             unreachable | no-credentials | http-<code>

set -uo pipefail
source "$(dirname "$0")/lib.sh"

ISSUE_FILE="${ISSUE_FILE:-issue.json}"

finish() {
  set_output status "$1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 0
}

if [[ -n "${FIXTURE:-}" ]]; then
  cp "$FIXTURE" "$ISSUE_FILE"
  finish ok "Using fixture $FIXTURE (no API call)"
fi

if [[ -z "${JIRA_BASE_URL:-}" || -z "${JIRA_USER_EMAIL:-}" || -z "${JIRA_API_TOKEN:-}" ]]; then
  finish no-credentials "Jira credentials not configured; skipping lookup."
fi

CODE="$(curl -sS -o "$ISSUE_FILE" -w '%{http_code}' \
  -u "$JIRA_USER_EMAIL:$JIRA_API_TOKEN" \
  -H "Accept: application/json" \
  "$JIRA_BASE_URL/rest/api/3/issue/$KEY?fields=summary,labels,issuetype,status" \
  2>/dev/null || echo 000)"

case "$CODE" in
200) finish ok "Issue $KEY fetched." ;;
401) finish unauthorized "Jira returned 401." ;;
403) finish forbidden "Jira returned 403." ;;
404) finish not-found "Issue $KEY not found or not visible." ;;
000) finish unreachable "Could not reach $JIRA_BASE_URL." ;;
*) finish "http-$CODE" "Jira returned HTTP $CODE." ;;
esac
